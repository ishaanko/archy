"""Picks example feet from the Schuster et al. 2024 scans (CC0, doi 10.5061/dryad.g4f4qrfwt).

For every full-weight scan: orient the foot (floor = lowest points, PCA for the heel-toe axis), take vertices
within 3 mm of the floor as a "virtual footprint", rasterize it, drop the toes (distal 20%), and compute the
Cavanagh arch index (midfoot contact area / total, >0.26 flat, <0.21 high). Writes sim/public/data/feet.json
and exports the flattest, median and highest-arch feet as decimated GLBs in the sim's canonical foot frame
(mm, x medial, y heel->toe, z up, sole on z=0, left-foot orientation; right feet are mirrored).

Run: uv run --with trimesh --with numpy --with scipy --with fast-simplification python sim/scripts/pick_feet.py
"""
import json
import re
from pathlib import Path

import numpy as np
import trimesh
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SCANS = ROOT / "datasets/raw/zenodo-10360304"
OUT_DATA = ROOT / "sim/public/data/feet.json"
OUT_MODELS = ROOT / "sim/public/models"

FLOOR_BAND = 3.0  # mm above the lowest point counted as contact
PIXEL = 1.5  # mm
TOE_FRACTION = 0.2
FOOT_LENGTH = 240.0  # mm, scans are scaled to this so they fit the generic insole outline
HEEL_Y = -8.0  # mm, rear of the heel contact in the sim frame
INSOLE_X_CENTER = 5.0
TARGET_FACES = 20000
SHANK_TOP = 85.0  # mm above the sole, after scaling


def orient(mesh: trimesh.Trimesh, side: str):
    """Returns vertices in the canonical frame plus whether the winding must flip, and the medial-guess check."""
    v = mesh.vertices - np.array([0, 0, mesh.vertices[:, 2].min()])
    sole = v[v[:, 2] < 5][:, :2]
    leg = v[v[:, 2] > 80][:, :2]
    c = sole.mean(axis=0)
    w, vecs = np.linalg.eigh(np.cov((sole - c).T))
    u = vecs[:, np.argmax(w)]
    if np.dot(c - leg.mean(axis=0), u) < 0:  # leg stands over the heel, so toes point away from it
        u = -u
    left = np.array([-u[1], u[0]])  # z cross u
    medial = -left if side == "L" else left  # right foot: medial is toward the walker's left
    rel = v[:, :2] - c
    x, y = rel @ medial, rel @ u
    out = np.column_stack([x, y, v[:, 2]])
    return out, side != "L"  # reflection for right feet


def arch_index(pts: np.ndarray):
    """Cavanagh arch index from canonical vertices (x medial, y heel->toe). Returns (AI, image, extents) or None."""
    foot = pts[pts[:, 2] < FLOOR_BAND]
    x0, y0 = foot[:, 0].min() - 5, foot[:, 1].min() - 5
    nx = int((foot[:, 0].max() + 5 - x0) / PIXEL) + 1
    ny = int((foot[:, 1].max() + 5 - y0) / PIXEL) + 1
    img = np.zeros((ny, nx), bool)
    img[((foot[:, 1] - y0) / PIXEL).astype(int), ((foot[:, 0] - x0) / PIXEL).astype(int)] = True
    img = ndimage.binary_closing(img, iterations=2)
    img = ndimage.binary_fill_holes(img)
    labels, n = ndimage.label(img)
    if n > 1:  # keep the largest blob
        img = labels == (np.argmax(np.bincount(labels.ravel())[1:]) + 1)
    rows = np.where(img.any(axis=1))[0]
    first, last = rows[0], rows[-1]
    foot_end = last - round((last - first + 1) * TOE_FRACTION)
    bounds = np.round(np.linspace(first, foot_end + 1, 4)).astype(int)
    counts = img.sum(axis=1)
    thirds = [counts[bounds[i] : bounds[i + 1]].sum() for i in range(3)]
    return thirds[1] / sum(thirds), img, (x0, y0)


def main():
    files = sorted(SCANS.glob("*_fBW_*.ply"))
    rows = []
    for f in files:
        m = re.match(r"(\d+)_fBW_(L|Lr|R)\.ply", f.name)
        side = "L" if m.group(2) == "L" else "R"  # "Lr" was already reflected to a right foot by the authors
        mesh = trimesh.load(f, process=False)
        pts, flip = orient(mesh, side)
        ai, img, _ = arch_index(pts)
        # Medial sanity check: midfoot contact should sit lateral of the heel/forefoot centers.
        foot = pts[pts[:, 2] < FLOOR_BAND]
        ylo, yhi = foot[:, 1].min(), foot[:, 1].max()
        mid = foot[(foot[:, 1] > ylo + 0.35 * (yhi - ylo)) & (foot[:, 1] < ylo + 0.55 * (yhi - ylo))]
        ends = foot[(foot[:, 1] < ylo + 0.2 * (yhi - ylo)) | ((foot[:, 1] > ylo + 0.6 * (yhi - ylo)) & (foot[:, 1] < ylo + 0.8 * (yhi - ylo)))]
        medial_ok = bool(mid[:, 0].mean() < ends[:, 0].mean())
        rows.append({"id": m.group(1), "file": f.name, "side": side, "ai": float(ai), "length_mm": float(yhi - ylo), "medial_ok": medial_ok})
    ais = np.array([r["ai"] for r in rows])
    order = np.argsort(ais)
    picks = {"flatter": int(order[-1]), "typical": int(order[len(order) // 2]), "higher": int(order[0])}
    stats = {
        "n": len(rows),
        "mean": float(ais.mean()), "sd": float(ais.std()),
        "percentiles": {str(p): float(np.percentile(ais, p)) for p in (0, 5, 25, 50, 75, 95, 100)},
        "flat_gt_0.26": int((ais > 0.26).sum()), "normal": int(((ais >= 0.21) & (ais <= 0.26)).sum()), "high_lt_0.21": int((ais < 0.21).sum()),
        "medial_check_failed": [r["id"] for r in rows if not r["medial_ok"]],
    }
    OUT_MODELS.mkdir(parents=True, exist_ok=True)
    chosen = {}
    for key, i in picks.items():
        r = rows[i]
        mesh = trimesh.load(SCANS / r["file"], process=False)
        pts, flip = orient(mesh, r["side"])
        foot = pts[pts[:, 2] < FLOOR_BAND]
        s = FOOT_LENGTH / (foot[:, 1].max() - foot[:, 1].min())
        pts = pts * s
        foot = pts[pts[:, 2] < FLOOR_BAND * s]
        pts[:, 1] += HEEL_Y - foot[:, 1].min()
        pts[:, 0] += INSOLE_X_CENTER - (foot[:, 0].min() + foot[:, 0].max()) / 2
        faces = mesh.faces[:, ::-1] if flip else mesh.faces
        small = trimesh.Trimesh(pts, faces, process=False)
        small = small.slice_plane([0, 0, SHANK_TOP], [0, 0, -1], cap=True)  # keep the ankle, drop the lower leg
        small = trimesh.Trimesh(small.vertices, small.faces).simplify_quadric_decimation(face_count=TARGET_FACES)
        small.merge_vertices()
        small.export(OUT_MODELS / f"foot-{key}.glb")
        size = (OUT_MODELS / f"foot-{key}.glb").stat().st_size
        chosen[key] = {"id": r["id"], "ai": r["ai"], "scale": float(s), "faces": len(small.faces), "glb_bytes": size}
        print(key, r["id"], f"AI={r['ai']:.3f}", len(small.faces), "faces", size // 1024, "KB")
    OUT_DATA.parent.mkdir(parents=True, exist_ok=True)
    OUT_DATA.write_text(json.dumps({
        "source": "Schuster et al. 2024 Proc R Soc B, doi 10.5061/dryad.g4f4qrfwt, CC0",
        "thresholds": {"flat": 0.26, "high": 0.21}, "stats": stats, "picks": chosen,
        "feet": [{"id": r["id"], "side": r["side"], "ai": round(r["ai"], 4)} for r in rows],
    }, separators=(",", ":")))
    print(json.dumps(stats, indent=1))


if __name__ == "__main__":
    main()
