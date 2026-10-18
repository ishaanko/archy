"""Foot measurements from the Schuster 3D scans (mBW = minimal weight, fBW = full body weight).

Usage: uv run --project datasets python datasets/analysis/scan_measure.py
Writes out/scan_measurements.csv (one row per participant) and out/footprints.png.

Frame per mesh: s = heel -> toe (mm), t = lateral -> medial (mm), z = height above floor (mm).
Method notes (see REPORT.md): foot length/ball width from vertices below 50 mm; truncated
length = 0.73 * foot length (heel to 1st MTP, anthropometric approximation); AHI = dorsum
height at 50% foot length / truncated length (Butler 2008); virtual footprint = underside
height map < 3 mm rasterized at 1 mm; medial arch height = max underside height in the
medial band (5-30 mm inside the medial outline) over 40-55% of foot length, median over rows.
"""

from __future__ import annotations

import re
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import trimesh
from skimage.draw import polygon

from footprint import footprint_indices

ROOT = Path(__file__).resolve().parents[1]
SCANS = ROOT / "raw" / "zenodo-10360304"
OUT = Path(__file__).resolve().parent / "out"

TRUNC_FRAC = 0.73  # 1st MTP head at ~73% of foot length
CONTACT_MM = 3.0  # virtual footprint: surface within 3 mm of the floor
FOOT_Z = 50.0  # vertices below this are "foot" (excludes the leg)
_NAME = re.compile(r"(\d{3})_(mBW|fBW)_(R|Lr|L)\.ply")


def _aligned_frame(path: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray, float, int]:
    """Return aligned vertices (s, t, z), per-face vertex indices, face normal z, floor tilt (deg)."""
    mesh = trimesh.load(path, process=False)
    v = np.asarray(mesh.vertices, dtype=float)
    faces = np.asarray(mesh.faces)
    nz = np.asarray(mesh.face_normals)[:, 2]
    foot_side = _NAME.match(path.name).group(3)

    # Floor: plane through the lowest 2% of vertices (trimmed fit), then z=0 at its lowest point.
    low = v[v[:, 2] <= np.percentile(v[:, 2], 2)]
    design = np.c_[low[:, :2], np.ones(len(low))]
    coef = np.linalg.lstsq(design, low[:, 2], rcond=None)[0]
    res = low[:, 2] - design @ coef
    ok = np.abs(res) < 2.0
    coef = np.linalg.lstsq(design[ok], low[ok, 2], rcond=None)[0]
    tilt = float(np.degrees(np.arctan(np.hypot(coef[0], coef[1]))))
    z = v[:, 2] - (v[:, 0] * coef[0] + v[:, 1] * coef[1])
    z -= np.percentile(z, 0.1)

    # Foot axis: PCA of the plan view of everything below 40 mm; the leg sits over the heel half.
    xy = v[z < 40, :2]
    ctr = xy.mean(0)
    axis2 = np.linalg.eigh(np.cov((xy - ctr).T))[1][:, 1]
    leg = v[z > 100, :2].mean(0)
    if (leg - ctr) @ axis2 > 0:
        axis2 = -axis2  # axis points away from the leg: heel -> toe
    u = np.r_[axis2, 0.0]
    # Medial direction: left of travel (z x u) for a right foot, right for an unmirrored left foot.
    medial = np.cross([0, 0, 1.0], u)
    if foot_side == "L":
        medial = -medial
    p = np.c_[(v - np.r_[ctr, 0]) @ u, (v - np.r_[ctr, 0]) @ medial, z]
    return p, faces, nz, tilt, int(foot_side == "L")


def _underside_heightmap(p: np.ndarray, faces: np.ndarray, nz: np.ndarray, s0: float, t0: float,
                         shape: tuple[int, int]) -> np.ndarray:
    """Lowest downward-facing surface height per 1 mm cell (nan = no surface); rows=s, cols=t."""
    h = np.full(shape, np.inf)
    sel = np.flatnonzero((nz < -0.1) & (p[faces][:, :, 2].mean(1) < 60.0))
    for f in sel:
        a, b, c = p[faces[f]]
        rr, cc = polygon(np.array([a[0], b[0], c[0]]) - s0, np.array([a[1], b[1], c[1]]) - t0, shape)
        if len(rr) == 0:
            continue
        # Barycentric interpolation of z at the cell centers.
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-9:
            continue
        ps, pt = rr + s0, cc + t0
        l1 = ((b[1] - c[1]) * (ps - c[0]) + (c[0] - b[0]) * (pt - c[1])) / d
        l2 = ((c[1] - a[1]) * (ps - c[0]) + (a[0] - c[0]) * (pt - c[1])) / d
        zz = l1 * a[2] + l2 * b[2] + (1 - l1 - l2) * c[2]
        h[rr, cc] = np.minimum(h[rr, cc], zz)
    h[np.isinf(h)] = np.nan
    return h


def measure(path: Path, contact_mm: float = CONTACT_MM) -> dict[str, float | str | int]:
    """All measurements for one scan. `contact_mm` = footprint height tolerance above the floor."""
    pid, cond, side = _NAME.match(path.name).groups()
    p, faces, nz, tilt, mirrored = _aligned_frame(path)
    foot = p[p[:, 2] < FOOT_Z]
    s_min, s_max = foot[:, 0].min(), foot[:, 0].max()
    length = s_max - s_min
    trunc = TRUNC_FRAC * length

    def rel(s: np.ndarray) -> np.ndarray:
        return (s - s_min) / length

    # Ball width: widest 5 mm slab between 60% and 78% of foot length.
    fr = rel(foot[:, 0])
    ball = 0.0
    for lo in np.arange(0.60, 0.78, 0.01):
        m = foot[(fr >= lo) & (fr < lo + 5 / length)]
        if len(m):
            ball = max(ball, np.ptp(m[:, 1]))

    # Heel width (widest 5 mm slab in 8-20% of length); orientation sanity: ball must exceed heel.
    heel = 0.0
    for lo in np.arange(0.08, 0.20, 0.01):
        m = foot[(fr >= lo) & (fr < lo + 5 / length)]
        if len(m):
            heel = max(heel, np.ptp(m[:, 1]))

    # Dorsum height at 50% foot length: highest surface point in a +-3 mm slab.
    slab = p[np.abs(p[:, 0] - (s_min + 0.5 * length)) < 3.0]
    dorsum = slab[:, 2].max()

    # Virtual footprint from the underside height map.
    t0 = foot[:, 1].min() - 2
    shape = (int(length + 10), int(np.ptp(foot[:, 1]) + 10))
    s_off = s_min - 2
    h = _underside_heightmap(p, faces, nz, s_off, t0, shape)
    contact = np.nan_to_num(h, nan=1e9) < contact_mm
    fp = footprint_indices(contact.astype(float), (1.0, 1.0), align=False, length_mm=length)

    # Medial arch height from the same height map.
    heights, lat_heights = [], []
    for r in range(shape[0]):
        s_here = r + s_off
        if not 0.40 <= rel(np.array([s_here]))[0] <= 0.55:
            continue
        row = foot[np.abs(foot[:, 0] - s_here) < 1.0]
        if not len(row):
            continue
        edge = int(row[:, 1].max() - t0)
        band = h[r, max(edge - 30, 0): max(edge - 5, 1)]
        if np.isfinite(band).any():
            heights.append(np.nanmax(band))
        # Same band on the lateral side: handedness sanity check (medial arch should be higher).
        ledge = int(row[:, 1].min() - t0)
        lband = h[r, ledge + 5: ledge + 30]
        if np.isfinite(lband).any():
            lat_heights.append(np.nanmax(lband))
    arch_h = float(np.median(heights)) if heights else np.nan

    lat_h = float(np.median(lat_heights)) if lat_heights else np.nan
    row: dict[str, float | str | int] = {
        "id": int(pid), "cond": cond, "side": side, "mirrored_by_me": mirrored,
        "floor_tilt_deg": tilt, "foot_length": length, "ball_width": ball,
        "trunc_length": trunc, "dorsum_h": dorsum, "ahi": dorsum / trunc,
        "medial_arch_h": arch_h, "lateral_arch_h": lat_h, "heel_width": heel,
    }
    if fp:
        row |= {"ai": fp.ai, "staheli": fp.staheli, "csi": fp.csi, "print_area": fp.area_mm2}
    else:
        row |= {"ai": np.nan, "staheli": np.nan, "csi": np.nan, "print_area": np.nan}
    row["_contact"] = contact  # dropped before csv; used for the figure
    return row


def _figure(rows: pd.DataFrame, contacts: dict[int, np.ndarray]) -> None:
    f = rows.dropna(subset=["ai"]).sort_values("ai")
    picks = [("lowest AI", f.iloc[0]), ("p25", f.iloc[len(f) // 4]), ("median", f.iloc[len(f) // 2]),
             ("p75", f.iloc[3 * len(f) // 4]), ("highest AI", f.iloc[-1])]
    fig, axes = plt.subplots(1, 5, figsize=(10, 3.6), facecolor="black")
    for ax, (name, r) in zip(axes, picks):
        c = contacts[int(r["id"])]
        ys, xs = np.nonzero(c)
        ax.imshow(c[ys.min() - 3: ys.max() + 4, xs.min() - 3: xs.max() + 4], cmap="gray", origin="upper")
        ax.set_title(f"{name}\nid {int(r['id'])} AI {r['ai']:.2f}", color="white", fontsize=8)
        ax.axis("off")
    fig.text(0.5, 0.02, "fBW virtual footprints (<3 mm from floor), heel at top, toes at bottom",
             color="white", ha="center", fontsize=8)
    fig.savefig(OUT / "footprints.png", dpi=90, facecolor="black")


def main() -> None:
    OUT.mkdir(exist_ok=True)
    paths = sorted(SCANS.glob("*.ply"))
    with ProcessPoolExecutor() as ex:
        results = list(ex.map(measure, paths, chunksize=4))
    # Sensitivity of the footprint AI (fBW only) to the contact tolerance.
    fpaths = [p for p in paths if "_fBW_" in p.name]
    sens = []
    with ProcessPoolExecutor() as ex:
        for mm in (1.0, 2.0, 5.0):
            for r in ex.map(measure, fpaths, [mm] * len(fpaths), chunksize=4):
                sens.append({"contact_mm": mm, "id": r["id"], "ai": r["ai"], "staheli": r["staheli"], "csi": r["csi"]})
    sens_df = pd.DataFrame(sens)
    sens_df.groupby("contact_mm").agg(ai_mean=("ai", "mean"), ai_sd=("ai", "std"), pct_ai_flat=("ai", lambda x: 100 * (x > 0.26).mean()),
                                      pct_csi_flat=("csi", lambda x: 100 * (x > 0.45).mean())).round(3).to_csv(OUT / "scan_contact_sensitivity.csv")
    contacts = {int(r["id"]): r["_contact"] for r in results if r["cond"] == "fBW"}
    df = pd.DataFrame([{k: v for k, v in r.items() if k != "_contact"} for r in results])
    f, m = df[df.cond == "fBW"].set_index("id"), df[df.cond == "mBW"].set_index("id")
    wide = f.add_prefix("fBW_").join(m.add_prefix("mBW_"))
    wide["arch_drop_mm"] = wide["mBW_medial_arch_h"] - wide["fBW_medial_arch_h"]
    wide["ahi_drop"] = wide["mBW_ahi"] - wide["fBW_ahi"]
    wide.drop(columns=["fBW_cond", "mBW_cond", "mBW_side"]).rename(columns={"fBW_side": "side"}).round(4).to_csv(
        OUT / "scan_measurements.csv")
    _figure(f.reset_index(), contacts)
    print(wide.describe().T.round(3).to_string())


if __name__ == "__main__":
    main()
