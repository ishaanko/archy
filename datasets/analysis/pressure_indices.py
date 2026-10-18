"""Arch indices from pressure data: CAD WALK (healthy vs hallux valgus), MUN104 template, FSR 32x32 maps.

Usage: uv run --project datasets python datasets/analysis/pressure_indices.py
Writes out/pressure_indices.csv, out/pressure_summary.json, out/cadwalk_ai.png, out/fsr_ai.png.

Every map is reduced to a peak-pressure image, oriented heel-first, and passed to
footprint.footprint_indices. CAD WALK heel direction is detected per trial from contact
timing (first-contact centroid vs last-contact centroid).
"""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import nibabel as nib
import numpy as np
import pandas as pd
from scipy import stats

from footprint import AI_FLAT, CSI_FLAT, STAHELI_FLAT, footprint_indices

RAW = Path(__file__).resolve().parents[1] / "raw"
OUT = Path(__file__).resolve().parent / "out"
CAD = {
    "healthy": RAW / "zenodo-1265420/extracted/CAD_WALK_Healthy_Controls_Dataset/HealthyControls",
    "hallux_valgus": RAW / "zenodo-3406523/extracted/CAD_WALK_Hallux_Valgus_PreSurgery/HalluxValgus_PreSugery",
}
MUN = RAW / "github_raw-0todd0000-mun104/extracted/MUN104.csv"
FSR = RAW / "zenodo-19872222/extracted/PLANTAR PRESSURE DIST/PLANTAR PRESSURE DIST"
MIN_FRAMES = 30  # shorter CAD WALK trials are partial steps
MIN_LENGTH_MM = 150.0  # shorter prints are partial steps / noise


def _heel_first(vol: np.ndarray) -> bool:
    """True if the heel is at low row index: first-contact centroid row < last-contact centroid row."""
    load = vol.sum((0, 1))
    active = np.flatnonzero(load > 0.1 * load.max())
    rows = np.arange(vol.shape[0])[:, None]

    def centroid(frames: np.ndarray) -> float:
        f = vol[:, :, frames].sum((1, 2))
        return float((f * rows[:, 0]).sum() / f.sum())

    k = max(len(active) // 8, 1)
    return centroid(active[:k]) < centroid(active[-k:])


def _row(dataset: str, group: str, subject: str, foot: str, trial: str, frames: int, img: np.ndarray,
         px: tuple[float, float], **extra: float) -> dict[str, object]:
    out: dict[str, object] = dict(dataset=dataset, group=group, subject=subject, foot=foot, trial=trial,
                                  frames=frames, **extra)
    ix = footprint_indices(img, px)
    ok = ix is not None and ix.length_mm >= MIN_LENGTH_MM and frames >= MIN_FRAMES
    out["ok"] = ok
    if ix:
        out |= {k: round(v, 4) for k, v in ix.as_dict().items() if k in ("ai", "staheli", "csi", "length_mm")}
        out |= {f"flat_{k}": v for k, v in ix.flat_flags().items()}
    return out


def cadwalk() -> tuple[pd.DataFrame, dict[str, np.ndarray]]:
    rows, peaks = [], {}
    for group, root in CAD.items():
        for subj in sorted(p for p in root.iterdir() if p.is_dir()):
            for f in sorted(subj.glob("*_foot_trial_*.nii")):
                im = nib.load(f)
                vol = np.asarray(im.dataobj, dtype=float)
                px = (float(im.header.get_zooms()[0]), float(im.header.get_zooms()[1]))
                if vol.shape[2] < 5 or vol.max() <= 0:
                    continue
                peak = vol.max(2)
                if not _heel_first(vol):
                    peak = peak[::-1]
                foot = f.name.split("_")[0]
                row = _row("cadwalk", group, subj.name, foot, f.stem.split("_")[-1], vol.shape[2], peak, px)
                rows.append(row)
                peaks[f"{group}/{subj.name}/{f.stem}"] = peak
    return pd.DataFrame(rows), peaks


def mun104() -> pd.DataFrame:
    """Mean healthy template per foot; rows run heel -> toe (checked by eye); 5 mm pixels assumed."""
    rows = []
    for side in "LR":
        img = np.loadtxt(MUN / f"MUN104{side}.csv", delimiter=",")
        rows.append(_row("mun104", "healthy_mean", "mean104", side, "template", 999, img, (5.0, 5.0)))
    return pd.DataFrame(rows)


def fsr() -> tuple[pd.DataFrame, dict[str, np.ndarray]]:
    """32x32 FSR maps: left foot in the left half, right foot in the right half, toes at the top.

    Uses the file's 128x(124 or 128) interpolated block (clipped at 0, split into left/right halves), heel flipped to the
    top. The sensor pitch is unknown, so pixels are set to 3 mm (~12 mm cells / 4x upsampling); all
    indices are ratios, only the length filter is affected.
    """
    rows, imgs = [], {}
    for f in sorted(FSR.glob("*.csv")):
        lines = [ln.split(",") for ln in f.read_text(encoding="utf-8-sig").splitlines()]
        start = next(i for i, ln in enumerate(lines) if ln[0] == "INTERPOLATIONS") + 1
        end = next(i for i, ln in enumerate(lines) if ln[0] == "MEASUREMENTS")
        block = np.array([[float(x) if x else 0.0 for x in ln] for ln in lines[start:end]])
        if block.shape[1] < 124:  # one truncated file (valgus-valgus_..._0001.csv)
            continue
        cols = 128 if block.shape[1] >= 128 else 124
        block = np.clip(block, 0, None)[:, :cols]
        half = cols // 2
        head = lines[1]
        for foot, sl, tca, label in (("L", slice(0, half), head[0], head[1]), ("R", slice(half, cols), head[2], head[3])):
            img = block[::-1, sl]
            row = _row("fsr", label.lower(), f.stem, foot, "map", 999, img, (3.0, 3.0), tca_deg=float(tca))
            rows.append(row)
            imgs[f"{label.lower()}/{f.stem}/{foot}"] = img
    return pd.DataFrame(rows), imgs


def _flat_pct(df: pd.DataFrame) -> dict[str, float]:
    return {k: round(100 * float(df[f"flat_{k}"].mean()), 1) for k in ("ai", "staheli", "csi")} | {"n": len(df)}


def _mw(a: pd.Series, b: pd.Series) -> dict[str, float]:
    u = stats.mannwhitneyu(a, b)
    return {"p": float(u.pvalue), "median_a": float(a.median()), "median_b": float(b.median())}


def _plot_cad(feet: pd.DataFrame, peaks: dict[str, np.ndarray], trials: pd.DataFrame) -> None:
    fig = plt.figure(figsize=(10, 6), facecolor="black")
    ax = fig.add_subplot(2, 1, 1, facecolor="black")
    bins = np.linspace(0, 0.5, 41)
    for g, c in (("healthy", "#7fd1ff"), ("hallux_valgus", "#ffb347")):
        ax.hist(feet[feet.group == g].ai, bins=bins, alpha=0.7, color=c, label=f"{g} (n={int((feet.group == g).sum())} feet)")
    ax.axvline(AI_FLAT, color="white", ls="--", lw=1)
    ax.text(AI_FLAT + 0.003, ax.get_ylim()[1] * 0.9, "AI 0.26 flat", color="white", fontsize=8)
    ax.set(xlabel="Cavanagh AI (per-foot median over trials)")
    ax.legend(facecolor="black", labelcolor="white", fontsize=8)
    ax.tick_params(colors="white")
    ax.xaxis.label.set_color("white")
    ok = trials[trials.ok].copy()
    picks = []
    for g in ("healthy", "hallux_valgus"):
        t = ok[ok.group == g].sort_values("ai")
        picks += [(g, "lowest", t.iloc[0]), (g, "median", t.iloc[len(t) // 2]), (g, "highest", t.iloc[-1])]
    for i, (g, tag, r) in enumerate(picks):
        a = fig.add_subplot(2, 6, 7 + i, facecolor="black")
        a.imshow(peaks[f"{g}/{r.subject}/{r.foot}_foot_trial_{r.trial}"], cmap="inferno", aspect=7.62 / 5.08)
        a.set_title(f"{g[:2]} {tag}\nAI {r.ai:.2f}", color="white", fontsize=7)
        a.axis("off")
    fig.tight_layout()
    fig.savefig(OUT / "cadwalk_ai.png", dpi=80, facecolor="black")


def _plot_fsr(df: pd.DataFrame, imgs: dict[str, np.ndarray]) -> None:
    fig, axes = plt.subplots(1, 4, figsize=(10, 3.4), facecolor="black")
    ax = axes[0]
    ax.set_facecolor("black")
    data = [df[(df.group == g) & df.ok].ai for g in ("rectus", "valgus")]
    bp = ax.boxplot(data, tick_labels=["rectus", "valgus"], patch_artist=True)
    for b in bp["boxes"]:
        b.set(facecolor="#333", edgecolor="white")
    for k in ("whiskers", "caps", "medians"):
        for ln in bp[k]:
            ln.set_color("white")
    ax.axhline(AI_FLAT, color="white", ls="--", lw=1)
    ax.set_title("FSR map AI by rearfoot alignment", color="white", fontsize=8)
    ax.tick_params(colors="white")
    ok = df[df.ok].sort_values("ai")
    for a, (tag, r) in zip(axes[1:], (("lowest", ok.iloc[0]), ("median", ok.iloc[len(ok) // 2]), ("highest", ok.iloc[-1]))):
        a.imshow(imgs[f"{r.group}/{r.subject}/{r.foot}"], cmap="inferno")
        a.set_title(f"{tag} AI {r.ai:.2f} ({r.group})", color="white", fontsize=8)
        a.axis("off")
    fig.tight_layout()
    fig.savefig(OUT / "fsr_ai.png", dpi=80, facecolor="black")


def main() -> None:
    OUT.mkdir(exist_ok=True)
    cad, peaks = cadwalk()
    fs, fsr_imgs = fsr()
    mun = mun104()
    allrows = pd.concat([cad, mun, fs], ignore_index=True)
    allrows.to_csv(OUT / "pressure_indices.csv", index=False)

    ok = cad[cad.ok]
    feet = ok.groupby(["group", "subject", "foot"]).agg(
        ai=("ai", "median"), staheli=("staheli", "median"), csi=("csi", "median"), n=("ai", "size")).reset_index()
    feet["flat_ai"], feet["flat_staheli"], feet["flat_csi"] = feet.ai > AI_FLAT, feet.staheli > STAHELI_FLAT, feet.csi > CSI_FLAT
    subj = feet.groupby(["group", "subject"])[["flat_ai", "flat_staheli", "flat_csi"]].any().reset_index()
    summary: dict[str, object] = {
        "cadwalk_trials": {g: {"total": int((cad.group == g).sum()), "ok": int(((cad.group == g) & cad.ok).sum())} for g in CAD},
    }
    for g in CAD:
        fg = feet[feet.group == g]
        summary[f"cadwalk_{g}"] = {
            "feet": len(fg),
            "ai_mean_sd": [round(fg.ai.mean(), 3), round(fg.ai.std(), 3)],
            "staheli_mean_sd": [round(fg.staheli.mean(), 3), round(fg.staheli.std(), 3)],
            "csi_mean_sd": [round(fg.csi.mean(), 3), round(fg.csi.std(), 3)],
            "pct_feet_flat": _flat_pct(fg),
            "pct_subjects_any_foot_flat": _flat_pct(subj[subj.group == g]),
            "trial_level_pct_flat_ai": round(100 * float(ok[ok.group == g].flat_ai.mean()), 1),
        }
    h, v = feet[feet.group == "healthy"], feet[feet.group == "hallux_valgus"]
    summary["cadwalk_healthy_vs_hv"] = {m: _mw(h[m], v[m]) for m in ("ai", "staheli", "csi")}

    # Sensitivity of the flat fraction to the contact threshold and toe cut (re-runs on stored peaks).
    sens = {}
    for thr, toe in ((0.05, 0.20), (0.02, 0.20), (0.10, 0.20), (0.05, 0.15), (0.05, 0.25)):
        res: dict[str, list[float]] = {"healthy": [], "hallux_valgus": []}
        tmp = []
        for key, peak in peaks.items():
            g, s, t = key.split("/")
            ix = footprint_indices(peak, (7.62, 5.08), threshold_frac=thr, toe_frac=toe)
            r = cad[(cad.group == g) & (cad.subject == s) & (cad.foot == t.split("_")[0]) & (cad.trial == t.split("_")[-1])]
            if ix and ix.length_mm >= MIN_LENGTH_MM and bool(r.ok.iloc[0]):
                tmp.append((g, s, t.split("_")[0], ix.ai))
        d = pd.DataFrame(tmp, columns=["group", "subject", "foot", "ai"]).groupby(["group", "subject", "foot"]).ai.median().reset_index()
        sens[f"thr{thr}_toe{toe}"] = {g: round(100 * float((d[d.group == g].ai > AI_FLAT).mean()), 1) for g in res}
    summary["cadwalk_sensitivity_pct_feet_flat_ai"] = sens

    summary["mun104"] = mun[["foot", "ai", "staheli", "csi", "length_mm"]].to_dict("records")
    fok = fs[fs.ok]
    summary["fsr"] = {
        "feet_total": len(fs), "feet_ok": len(fok),
        **{g: {"n": int((fok.group == g).sum()), "ai_mean_sd": [round(fok[fok.group == g].ai.mean(), 3), round(fok[fok.group == g].ai.std(), 3)],
               "pct_flat": _flat_pct(fok[fok.group == g])} for g in ("rectus", "valgus")},
        "rectus_vs_valgus_ai": _mw(fok[fok.group == "rectus"].ai, fok[fok.group == "valgus"].ai),
        "spearman_ai_vs_tca": [round(x, 3) for x in stats.spearmanr(fok.ai, fok.tca_deg)],
    }
    (OUT / "pressure_summary.json").write_text(json.dumps(summary, indent=1, default=float))
    _plot_cad(feet, peaks, cad)
    _plot_fsr(fs, fsr_imgs)
    print(json.dumps(summary, indent=1, default=float))


if __name__ == "__main__":
    main()
