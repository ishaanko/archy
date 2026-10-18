"""Converts a few real CAD WALK steps (clinical RSscan plate) to sim/public/data/cadwalk.json.

Source: Booth et al., CAD WALK Healthy Controls (Zenodo 1265420) and Hallux Valgus pre-surgery (Zenodo 3406523), IEEE ISBI 2019.
Each NIfTI is (length, width, frames) with 7.62 x 5.08 mm sensors, 500 Hz (healthy) or 200 Hz (hallux valgus).
Pressure units are not documented in the Readme; the values (peaks ~50-100) are read as N/cm2 and stored as kPa (x10).

Steps: ranks every subject by arch index (Cavanagh, toes dropped) on one trial per foot, then keeps a flatter,
a typical and a higher-arch healthy foot, plus the two highest-arch-index (flattest midfoot) hallux valgus feet.
Each step is cropped to its contact frames, aligned to the sim's canonical foot frame (x medial, y heel->toe, mm,
scaled so the footprint is 240 mm long like core/outline.ts), resampled to a 5 mm grid at 50 Hz and quantized to 8 bits.

Run: uv run --with nibabel --with numpy --with scipy python -I sim/scripts/convert_cadwalk.py
"""
import json
from pathlib import Path

import nibabel as nib
import numpy as np
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
HEALTHY = ROOT / "datasets/raw/zenodo-1265420/extracted/CAD_WALK_Healthy_Controls_Dataset/HealthyControls"
HV = ROOT / "datasets/raw/zenodo-3406523/extracted/CAD_WALK_Hallux_Valgus_PreSurgery/HalluxValgus_PreSugery"
OUT = ROOT / "sim/public/data/cadwalk.json"

PIX_L, PIX_W = 7.62, 5.08  # mm
KPA_PER_UNIT = 10.0  # N/cm2 -> kPa
OUT_FS = 50
CELL = 5.0
X0, Y0, NX, NY = -60.0, -20.0, 26, 54  # canonical grid, covers the insole outline
FOOT_LENGTH, HEEL_Y, X_CENTER = 240.0, -8.0, 5.0
TRIAL = 5


def load(path: Path):
    im = nib.load(path)
    return np.asarray(im.dataobj, dtype=np.float32) * KPA_PER_UNIT, 500 if "Healthy" in str(path) else 200


def heel_first(video: np.ndarray) -> np.ndarray:
    """Flips the length axis so the heel (loaded first) is at index 0."""
    total = video.sum(axis=1)  # (L, T)
    t = np.arange(video.shape[2])
    w = total.sum(axis=0) + 1e-9
    early = t < np.searchsorted(np.cumsum(w) / w.sum(), 0.25)
    late = t > np.searchsorted(np.cumsum(w) / w.sum(), 0.75)
    idx = np.arange(video.shape[0])[:, None]
    cop_early = (total[:, early] * idx).sum() / (total[:, early].sum() + 1e-9)
    cop_late = (total[:, late] * idx).sum() / (total[:, late].sum() + 1e-9)
    return video if cop_early < cop_late else video[::-1]


def arch_index(peak: np.ndarray) -> float:
    """Cavanagh arch index from a heel-first peak map (L, W)."""
    img = peak > 0.05 * peak.max()
    rows = np.where(img.any(axis=1))[0]
    first, last = rows[0], rows[-1]
    foot_end = last - round((last - first + 1) * 0.2)
    b = np.round(np.linspace(first, foot_end + 1, 4)).astype(int)
    counts = img.sum(axis=1)
    thirds = [counts[b[i] : b[i + 1]].sum() for i in range(3)]
    return thirds[1] / max(1, sum(thirds))


def lateral_sign(peak: np.ndarray) -> int:
    """+1 if the midfoot contact sits toward higher width indices than the heel and forefoot (so that is lateral)."""
    img = peak > 0.05 * peak.max()
    rows = np.where(img.any(axis=1))[0]
    n = rows[-1] - rows[0] + 1
    def centroid(a, b):
        sub = img[rows[0] + int(a * n) : rows[0] + int(b * n)]
        cols = np.nonzero(sub)[1]
        return cols.mean() if len(cols) else np.nan
    mid = centroid(0.35, 0.55)
    ends = (centroid(0, 0.2) + centroid(0.6, 0.8)) / 2
    return 0 if np.isnan(mid - ends) else int(np.sign(mid - ends))  # 0 = no vote


def feet_of(root: Path, prefix: str, ids):
    out = []
    for i in ids:
        d = root / f"{prefix}{i:02d}"
        for side in ("left", "right"):
            f = d / f"{side}_foot_trial_{TRIAL:02d}.nii"
            if not f.exists():
                continue
            video, fs = load(f)
            video = heel_first(video)
            peak = video.max(axis=2)
            if peak.max() <= 0 or (peak > 0.05 * peak.max()).sum() < 100:
                continue
            out.append({"path": f, "subject": f"{prefix}{i:02d}", "side": side, "ai": float(arch_index(peak)), "lat": lateral_sign(peak)})
    return out


def canonical_step(path: Path, lateral: int):
    video, fs = load(path)
    video = heel_first(video)
    load_t = video.sum(axis=(0, 1))
    on = np.where(load_t > 0.05 * load_t.max())[0]
    video = video[:, :, on[0] : on[-1] + 1]
    if lateral > 0:  # make width index grow medially
        video = video[:, ::-1]
    peak = video.max(axis=2)
    img = peak > 0.05 * peak.max()
    rows, cols = np.where(img.any(axis=1))[0], np.where(img.any(axis=0))[0]
    s = FOOT_LENGTH / ((rows[-1] - rows[0] + 1) * PIX_L)  # mm in sim per mm on the plate
    cx = (cols[0] + cols[-1] + 1) / 2 * PIX_W
    # Block-average to OUT_FS.
    block = max(1, round(fs / OUT_FS))
    nT = video.shape[2] // block
    video = video[:, :, : nT * block].reshape(video.shape[0], video.shape[1], nT, block).mean(axis=3)
    gy, gx = np.meshgrid(Y0 + (np.arange(NY) + 0.5) * CELL, X0 + (np.arange(NX) + 0.5) * CELL, indexing="ij")
    src_l = ((gy - HEEL_Y) / s + rows[0] * PIX_L) / PIX_L - 0.5
    src_w = ((gx - X_CENTER) / s + cx) / PIX_W - 0.5
    frames = np.stack([ndimage.map_coordinates(video[:, :, t], [src_l, src_w], order=1, cval=0.0) for t in range(nT)])
    return frames, OUT_FS


def main():
    healthy = feet_of(HEALTHY, "C", range(1, 56))
    hv = feet_of(HV, "HV", range(1, 51))
    for name, group in (("healthy", healthy), ("hv", hv)):
        for side in ("left", "right"):
            votes = [f["lat"] for f in group if f["side"] == side]
            print(name, side, "lateral votes (+1/-1):", votes.count(1), votes.count(-1))
    # Per-side orientation is fixed by the plate setup: take the majority vote over all feet of that side.
    lat = {s: int(np.sign(sum(f["lat"] for f in healthy + hv if f["side"] == s)) or 1) for s in ("left", "right")}
    ais = np.array([f["ai"] for f in healthy])
    # Dynamic plate footprints read lower than the static-footprint cutoffs (healthy median is below 0.21), so "typical" is the
    # foot closest to the middle of the normal band (0.235) and "higher" the one closest to 0.15 rather than the degenerate AI = 0.
    near = lambda target: healthy[int(np.argmin(np.abs(ais - target)))]
    picks = [("healthy-flatter", "Healthy, flatter midfoot", healthy[int(np.argmax(ais))]), ("healthy-typical", "Healthy, typical", near(0.235)),
             ("healthy-higher", "Healthy, higher arch", near(0.15))]
    best = {}
    for f in sorted(hv, key=lambda f: -f["ai"]):
        best.setdefault(f["subject"], f)  # one foot per patient
    for k, f in enumerate(list(best.values())[:2]):
        picks.append((f"hv-{k + 1}", f"Hallux valgus patient {k + 1}", f))
    steps = []
    for sid, title, f in picks:
        frames, fs = canonical_step(f["path"], lat[f["side"]])
        q = float(frames.max() / 255)
        steps.append({"id": sid, "title": title, "cohort": "healthy" if sid.startswith("healthy") else "hallux valgus", "subject": f["subject"],
                      "side": f["side"], "ai": round(f["ai"], 3), "fs": fs, "qstep": round(q, 3),
                      "grid": {"nx": NX, "ny": NY, "cell": CELL, "x0": X0, "y0": Y0},
                      "frames": [np.round(fr.ravel() / q).astype(int).tolist() for fr in frames]})
        print(sid, f["subject"], f["side"], f"AI={f['ai']:.3f}", len(frames), "frames", f"peak {frames.max():.0f} kPa")
    print("healthy AI percentiles 0/25/50/75/100:", np.percentile(ais, [0, 25, 50, 75, 100]).round(3), " hv AI median:", np.median([f["ai"] for f in hv]).round(3))
    OUT.write_text(json.dumps({"source": "CAD WALK, Booth et al. 2019 (Zenodo 1265420, 3406523)", "steps": steps}, separators=(",", ":")))
    print(OUT, OUT.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
