"""Open every downloaded file and prove it is usable, not just checksummed.

Writes reports/validation.json (machine-readable) and reports/validation.md (summary).
Run: uv run --project datasets python datasets/validate.py
"""

import json
import re
import warnings
from collections import Counter
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from statistics import median

import nibabel as nib
import numpy as np
import pandas as pd
import trimesh
from PIL import Image

from fetch import RAW, hash_file, source_dir
from registry import SOURCES, Source

REPORTS = Path(__file__).parent / "reports"
warnings.filterwarnings("ignore")


@dataclass
class Result:
    loadable: int = 0
    total: int = 0
    failures: list[str] = field(default_factory=list)
    labels: dict[str, int] = field(default_factory=dict)
    stats: dict = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)
    per_file: list[dict] = field(default_factory=list)  # only where useful (meshes)

    def try_each(self, paths: list[Path], fn: Callable[[Path], object], base: Path) -> list:
        """Run fn on each path; count successes, record failures; return successful outputs."""
        outs = []
        for p in paths:
            self.total += 1
            try:
                outs.append(fn(p))
                self.loadable += 1
            except Exception as e:  # noqa: BLE001
                self.failures.append(f"{p.relative_to(base)}: {type(e).__name__}: {e}"[:200])
        return outs


def summarize(values: list[float]) -> dict:
    return {"min": round(min(values), 2), "median": round(median(values), 2), "max": round(max(values), 2)} if values else {}


# ---------- per-dataset validators ----------

def check_ply(p: Path) -> dict:
    """Load a scan; report counts, axis-aligned and PCA extents (mm), watertightness."""
    m = trimesh.load(p, force="mesh")
    v = np.asarray(m.vertices)
    ext = v.max(0) - v.min(0)
    c = v - v.mean(0)
    _, vecs = np.linalg.eigh(np.cov(c.T))
    pca = np.ptp(c @ vecs, axis=0)[::-1]  # longest first
    return {
        "file": p.name, "vertices": len(v), "faces": len(m.faces),
        "extents_aabb": [round(float(x), 2) for x in ext],
        "extents_pca": [round(float(x), 2) for x in pca],
        "watertight": bool(m.is_watertight),
    }


def v_schuster(d: Path, src: Source) -> Result:
    r = Result()
    plys = sorted(d.glob("*.ply"))
    with ThreadPoolExecutor(4) as pool:
        r.per_file = []
        r.total = len(plys)
        for p, out in zip(plys, pool.map(lambda p: _safe(check_ply, p), plys)):
            if isinstance(out, dict):
                r.loadable += 1
                r.per_file.append(out)
            else:
                r.failures.append(f"{p.name}: {out}"[:200])
    longest = [f["extents_pca"][0] for f in r.per_file]
    unit = "mm" if longest and median(longest) > 100 else "m" if longest and median(longest) < 1 else "unknown"
    r.stats = {
        "units_guess": unit,
        "foot_length_pca": summarize(longest),
        "vertices": summarize([f["vertices"] for f in r.per_file]),
        "faces": summarize([f["faces"] for f in r.per_file]),
        "watertight": sum(f["watertight"] for f in r.per_file),
        "in_220_300mm": sum(220 <= x <= 300 for x in longest),
        "participants": len({f["file"][:3] for f in r.per_file}),
    }
    r.labels = dict(Counter(re.sub(r"^\d+_", "", f["file"][:-4]) for f in r.per_file))
    r.notes = [
        "Filename suffix: R = right foot as scanned; Lr = LEFT-dominant participant's scan, reflected about its "
        "length axis so it looks like a right foot (per README); L (only 001_*) = a left foot that README does not "
        "explain and which is NOT mirrored. Mirror 001 before pooling with the others.",
        "No arch labels: all participants healthy. mBW vs fBW pairs give an arch-drop-under-load measure.",
    ]
    return r


def _safe(fn: Callable, p: Path):
    try:
        return fn(p)
    except Exception as e:  # noqa: BLE001
        return f"{type(e).__name__}: {e}"


def check_image(p: Path) -> tuple[tuple[int, int], str]:
    with Image.open(p) as im:
        im.load()
        return im.size, im.mode


def image_stats(outs: list) -> dict:
    return {"sizes": dict(Counter(f"{s[0]}x{s[1]}" for s, _ in outs).most_common(5)),
            "modes": dict(Counter(m for _, m in outs))}


def v_pressure(d: Path, src: Source) -> Result:
    r = Result()
    imgs = sorted((d / "extracted").rglob("*.png"))
    r.stats = image_stats(r.try_each(imgs, check_image, d))
    r.stats["zero_byte_pngs"] = sum(p.stat().st_size == 0 for p in imgs)
    r.labels = {"unlabeled": len(imgs)}
    r.notes = [
        "UPSTREAM DATA LOSS: the zip itself (MD5 matches Zenodo) contains zero-byte PNGs, so only the non-empty "
        "files are usable (see zero_byte_pngs / loadable).",
        "NO CLASS LABELS SHIPPED: 400 PNGs named by timestamp (YYYYMMDDHHMMSS) in one flat folder; no label file, "
        "no class folders, no metadata in the zip or the Zenodo record. The 5 classes are only named in the "
        "description. Labels must be obtained from the authors or assigned by hand before supervised training.",
        "Collected at a shoe store with a Footbird 3.0 scanner; some images may be mixed types.",
    ]
    return r


def v_pesplanus(d: Path, src: Source) -> Result:
    r = Result()
    imgs = sorted(p for p in d.rglob("*") if p.suffix.lower() == ".jpg")
    outs = r.try_each(imgs, check_image, d)
    r.stats = image_stats(outs)
    r.labels = dict(Counter(p.parent.name for p in imgs))
    by_hash: dict[str, set[str]] = {}
    for f in json.loads((d / "manifest.json").read_text())["files"]:
        by_hash.setdefault(f["digest"], set()).add(f["name"].split("/")[0])
    r.stats["name_patterns"] = dict(Counter(re.sub(r"\d+", "#", p.name).lower() for p in imgs).most_common(5))
    r.stats["unique_images_by_sha256"] = len(by_hash)
    r.stats["duplicate_groups_spanning_both_classes"] = sum(len(c) > 1 for c in by_hash.values())
    r.notes = [
        "Mendeley's API gives unnamed class folders; labels are inferred from folder file counts matching the "
        "dataset description (402 pes planus, 440 normal). Spot-check before trusting.",
        "Labels: calcaneal inclination <18 deg = pes planus (2 radiologists + a third for conflicts).",
        "LEAKAGE RISK: the 842 files are only as many unique images as 'unique_images_by_sha256' (byte-identical "
        "duplicates, apparently from re-exporting); numeric filename prefixes are reused across classes and "
        "'N L (k)' names are a separate series, so filenames do NOT identify patients. Dedupe by hash before "
        "splitting (no duplicate group spans both classes, so labels are consistent).",
    ]
    return r


def read_fsr(p: Path) -> dict:
    """Parse one rectus/valgus CSV: labels from rows 1-2, raw 32x32 block at rows 133-164."""
    df = pd.read_csv(p, header=None, low_memory=False)
    grid = df.iloc[132:164, :32].to_numpy(dtype=float)
    assert grid.shape == (32, 32) and df.iloc[2, 0] == "INTERPOLATIONS" and df.iloc[131, 0] == "MEASUREMENTS"
    return {"left": df.iloc[1, 1], "right": df.iloc[1, 3], "max": grid.max(), "nonzero": int((grid > 0).sum()),
            "name_label": p.name.split("_")[0], "rows": len(df)}


def v_fsr(d: Path, src: Source) -> Result:
    r = Result()
    csvs = sorted((d / "extracted").rglob("*.csv"))
    outs = r.try_each(csvs, read_fsr, d)
    r.labels = dict(Counter(f"left={o['left']},right={o['right']}" for o in outs))
    mismatch = sum(o["name_label"].lower() != f"{o['left']}-{o['right']}".lower() for o in outs)
    r.stats = {"grid": "32x32 raw + 128-row interpolated block", "max_value": summarize([o["max"] for o in outs]),
               "nonzero_cells_per_sample": summarize([o["nonzero"] for o in outs]), "filename_vs_cell_label_mismatch": mismatch}
    r.notes = [
        "Labels per file: left and right REARFOOT alignment (rectus/valgus) from Tibial-Calcaneal Angle, not arch "
        "type. Useful for alignment, not flat-foot, classification.",
        ".rar uses the RAR v6 method: 7zz 26.04 fails ('Unsupported Method'), bsdtar extracts it.",
        "Zenodo record also holds 4 example PNG intensity maps (Rectus_Rectus.png etc.).",
    ]
    return r


def v_cadwalk(label: str) -> Callable[[Path, Source], Result]:
    def run(d: Path, src: Source) -> Result:
        r = Result()
        ex = d / "extracted"
        niis = sorted(ex.rglob("*.nii"))
        outs = r.try_each(niis, lambda p: (np.asanyarray(nib.load(p).dataobj).shape), d)
        xl = sorted(ex.rglob("*.xlsx"))
        r.try_each(xl, lambda p: pd.read_excel(p, sheet_name=None, header=None), d)
        subjects = {p.relative_to(ex).parts[2] for p in niis if len(p.relative_to(ex).parts) > 3}
        r.labels = {label: len(subjects)}
        r.stats = {"nii_files": len(niis), "xlsx_files": len(xl), "subjects": len(subjects),
                   "frame_shapes": dict(Counter(f"{s[0]}x{s[1]}" for s in outs).most_common(4)),
                   "frames_per_trial": summarize([s[2] for s in outs if len(s) == 3])}
        r.notes = ["Pressure videos as NIfTI (rows x cols x frames), left_foot_trial_N / right_foot_trial_N per subject; "
                   "per-subject xlsx plus metadata.xlsx and Readme.pdf. Labels are cohort-level only."]
        return r
    return run


def v_takata(d: Path, src: Source) -> Result:
    r = Result()
    x = d / "data on foot and plantar pressure and gait cycle.xlsx"
    sheets = r.try_each([x], lambda p: pd.read_excel(p, sheet_name=None, header=None), d)[0]
    r.stats = {name: list(df.shape) for name, df in sheets.items()}
    maxp = sheets["MAXP"]
    # Row 1 holds LOW / NORMAL group headers; count non-empty subject rows under the first of each.
    r.labels = {"LOW (flat arch group)": int(maxp.iloc[2:, 1].notna().sum()), "NORMAL": int(maxp.iloc[2:, 2].notna().sum())}
    r.notes = ["Sheets MAXP (peak pressure), CA (contact area), GC (gait-phase times); columns are foot regions x "
               "{LOW, NORMAL}. Group means per row, not raw frames. Flat group = 'LOW' (arch), per paper: 20 FF vs 21 NF women."]
    return r


def v_mun104(d: Path, src: Source) -> Result:
    r = Result()
    csvs = sorted(p for p in (d / "extracted").rglob("*.csv") if p.is_file())
    outs = r.try_each(csvs, lambda p: (p.stem, np.loadtxt(p, delimiter=",")), d)
    r.stats = {n: {"shape": list(a.shape), "min": float(a.min()), "max": float(a.max()),
                   "nonzero_contact_pixels": int((a > 0).sum()), "all_finite": bool(np.isfinite(a).all())} for n, a in outs}
    h5 = sorted(p for p in (d / "extracted").rglob("*.h5") if p.is_file())
    r.try_each(h5, lambda p: p.read_bytes()[:8] == b"\x89HDF\r\n\x1a\n" or (_ for _ in ()).throw(ValueError("not HDF5")), d)
    r.labels = {"healthy mean map": len(outs)}
    r.notes = ["Mean of 104 healthy subjects per foot; integer-valued grid, rows = long axis. Not per-subject. "
               "No published checksum: sha256 recorded by fetch.py on first download (see hashes in manifest)."]
    return r


VALIDATORS: dict[str, Callable[[Path, Source], Result]] = {
    "schuster-scans": v_schuster,
    "pressure-images": v_pressure,
    "fsr-rectus-valgus": v_fsr,
    "cadwalk-healthy": v_cadwalk("healthy"),
    "cadwalk-hallux-valgus": v_cadwalk("hallux_valgus"),
    "pesplanus-xray": v_pesplanus,
    "takata-flatfoot": v_takata,
    "mun104": v_mun104,
}


# ---------- driver ----------

def check_hashes(d: Path) -> tuple[int, int, int, list[str]]:
    """Re-hash manifest files. Returns (passed, failed, bytes, failure messages)."""
    man = json.loads((d / "manifest.json").read_text())
    files = man["files"]

    def one(f: dict) -> tuple[bool, str]:
        p = d / f["name"]
        if not p.exists():
            return False, f"{f['name']}: missing"
        got = hash_file(p, f["algo"])
        return got == f["digest"], f"{f['name']}: {f['algo']} mismatch"

    with ThreadPoolExecutor(6) as pool:
        res = list(pool.map(one, files))
    ok = sum(a for a, _ in res)
    return ok, len(res) - ok, sum(f["size"] for f in files), [m for a, m in res if not a], man.get("skipped_large", []), files[0]["algo"] if files else ""


def validate_source(src: Source) -> dict:
    d = source_dir(src)
    if not (d / "manifest.json").exists():
        return {"key": src.key, "status": "not downloaded"}
    ok, bad, nbytes, hash_fail, skipped, algo = check_hashes(d)
    res = VALIDATORS[src.key](d, src)
    out = {
        "key": src.key, "title": src.title, "license": src.license, "doi": src.doi,
        "files": ok + bad, "bytes": nbytes, "hash_algo": algo, "hash_pass": ok, "hash_fail": bad,
        "hash_failures": hash_fail[:10], "skipped_large": skipped,
        "loadable": res.loadable, "loadable_of": res.total, "load_failures": res.failures[:10],
        "labels": res.labels, "stats": res.stats, "notes": res.notes,
    }
    if src.type == "github_raw":
        out["observed_sha256"] = {Path(f["name"]).name: f["digest"] for f in json.loads((d / "manifest.json").read_text())["files"]}
    if res.per_file:
        out["per_file"] = res.per_file
    return out


def to_markdown(reports: list[dict]) -> str:
    lines = ["# Dataset validation", "", "Generated by `datasets/validate.py`. Hash = re-computed against the repository's checksum "
             "(sha256 observed on first fetch for GitHub raw files). Loadable = opened with trimesh / Pillow / pandas / nibabel.", "",
             "| source | files | MB | hash pass/fail | loadable | license |", "|---|---|---|---|---|---|"]
    for r in reports:
        if "title" not in r:
            lines.append(f"| {r['key']} | - | - | not downloaded | - | - |")
            continue
        lines.append(f"| {r['key']} | {r['files']} | {r['bytes'] / 1e6:.1f} | {r['hash_algo']} {r['hash_pass']}/{r['hash_fail']} "
                     f"| {r['loadable']}/{r['loadable_of']} | {r['license']} |")
    for r in reports:
        if "title" not in r:
            continue
        lines += ["", f"## {r['key']}: {r['title']}", ""]
        if r["skipped_large"]:
            lines.append(f"- Skipped large files: {', '.join(r['skipped_large'])} (use `--include-large`)")
        if r["hash_failures"] or r["load_failures"]:
            lines += [f"- FAILURE: {m}" for m in r["hash_failures"] + r["load_failures"]]
        lines.append(f"- Labels: {json.dumps(r['labels'])}")
        lines.append(f"- Stats: {json.dumps(r['stats'])}")
        if r.get("observed_sha256"):
            lines.append(f"- Observed sha256: {json.dumps(r['observed_sha256'])}")
        lines += [f"- Note: {n}" for n in r["notes"]]
    return "\n".join(lines) + "\n"


def main() -> None:
    reports = []
    for src in SOURCES:
        if src.type == "manual":
            continue
        print(f"validating {src.key} ...", flush=True)
        reports.append(validate_source(src))
    REPORTS.mkdir(exist_ok=True)
    (REPORTS / "validation.json").write_text(json.dumps(reports, indent=1))
    (REPORTS / "validation.md").write_text(to_markdown(reports))
    print((REPORTS / "validation.md").read_text())


if __name__ == "__main__":
    main()
