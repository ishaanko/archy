# AGENTS.md: using the foot datasets

All paths are relative to the repo root. Every `python` block below is executed by a verification script against the local data; copy them as written.

## 1. Purpose and the honest limit

- The app is low-cost flat-foot **screening**: an iPhone scan or DIY FSR pressure sensors give arch indices, which drive a 3D-printed insole. It is not diagnosis.
- No open dataset pairs phone photos or 3D scans with clinical flat-foot labels. Do not claim end-to-end accuracy.
- Design consequence: classify with rule-based, cited indices (section 5); use ML only for measuring the foot (keypoints, depth), never for the flat/normal verdict.

## 2. Setup

```
uv run --project datasets python datasets/fetch.py list
uv run --project datasets python datasets/fetch.py get all            # add --include-large for treadmill_data.mat (281 MB)
uv run --project datasets python datasets/validate.py                 # writes datasets/reports/validation.{json,md}
```

| item | value |
|---|---|
| Tooling | `uv` (deps in `datasets/pyproject.toml`: requests, trimesh, numpy, pillow, pandas, openpyxl, nibabel, scipy, matplotlib, scikit-image). Python >= 3.12 |
| Download size | about 1.26 GB (Schuster scans 920 MB, CAD WALK 124.5 + 157.7 MB, rest under 31 MB each) |
| On disk after extraction | about 7.6 GB (`datasets/raw/`; CAD WALK NIfTI expands to 5.0 GB + 1.3 GB) |
| Runtime | bandwidth bound, not timed here. Re-runs are fast |
| Idempotent | yes. Zenodo md5 / Mendeley sha256 verified, HTML responses rejected, good files skipped, archives only extracted into an empty `extracted/<name>/` |
| `.rar` (FSR set) | extracted with `bsdtar` (macOS built-in). `7zz` 26.04 fails on this RAR v6 archive |
| MUN104 | no published checksum; sha256 recorded in `manifest.json` on first fetch |
| Layout | `datasets/raw/<type>-<id>/` + `manifest.json`; archives under `extracted/<zip stem>/` |

Gated or manual (not downloaded by `fetch.py`; `fetch.py get <key>` exits with the reason): Kaggle photos-of-foots (login), Kaggle pesplanus (redundant mirror), Foot3D and SynFoot (Google Form, link arrives by email), UNB StepUP-P150 (very large, no arch labels), Frontiers 2023 1,573 pressure images (request-only, email the corresponding author of PMC10519788). URLs in `datasets/registry.py`.

The 48-FSR insole set (Zenodo 21743536) is **not** fetched by `datasets/fetch.py` and the repo has no fetch script for it. `sim/scripts/convert_insole.py` expects it by hand under `sim/data/raw/` (gitignored): `zip/DATASET.zip` (MD5 545e356099f7bd21f97998b24448cdda), `zip/TableS1.xlsx`, and `DATASET.zip` unzipped into `ex/`. You do not need it unless you rerun that converter; `sim/public/data/insole.json` is the committed result.

Imports for all blocks below:

```python
import sys, re, hashlib, json
from pathlib import Path
import numpy as np
import pandas as pd

RAW = Path("datasets/raw")
sys.path.insert(0, "datasets/analysis")  # for footprint.py
```

## 3. Datasets

Registry keys: `schuster-scans`, `pressure-images`, `fsr-rectus-valgus`, `cadwalk-healthy`, `cadwalk-hallux-valgus`, `pesplanus-xray`, `takata-flatfoot`, `mun104`. Per-file results: `datasets/reports/validation.md`.

### 3.1 Schuster 3D scans (`schuster-scans`)

- What: Zenodo 10360304 (Dryad doi 10.5061/dryad.g4f4qrfwt), Schuster et al. 2024, Proc R Soc B. 100 healthy people, 2 PLY scans each (mBW = minimal weight bearing, fBW = full body weight), dominant foot only. IDs 001-103 with 021, 030, 064 missing.
- License: CC0.
- Path: `datasets/raw/zenodo-10360304/NNN_{mBW|fBW}_{R|Lr|L}.ply` (200 files; `README.md` and, with `--include-large`, `treadmill_data.mat` joint angles and moments).
- Format and units: PLY triangle mesh, **mm**, z up, sole near z = 0 (tilt under 0.45 deg on every scan). About 30-36k vertices, 200 of 200 watertight. The leg is included, cut at about 125 mm height and sitting over the heel half. Length runs along x in all 200 files, but heel vs toe direction is not fixed: use PCA plus the leg position (see `datasets/analysis/scan_measure.py::_aligned_frame` and `sim/scripts/pick_feet.py::orient`).
- Left/right: suffix `R` = right foot as scanned (93 people). `Lr` = left-dominant participant whose scan was **reflected about its length axis to look like a right foot** (6 people: 028, 075, 078, 096, 097, 098). Plain `L` appears only for participant 001 and is an unmirrored left foot the README does not explain (`scan_measure.py` flips it). Mirror 001 before pooling.
- Labels: none. All healthy. Use mBW vs fBW as an arch-drop-under-load measure (median 5.9 mm in our proxy).
- Breakage: none in the files. Participant 51 mBW yields no usable footprint in our pipeline.

```python
SCANS = RAW / "zenodo-10360304"

def load_scan(path: Path):
    """(participant id, 'mBW'|'fBW', trimesh in mm) with every foot mirrored to look like a right foot."""
    import trimesh
    m = re.fullmatch(r"(\d{3})_(mBW|fBW)_(R|Lr|L)\.ply", path.name)
    mesh = trimesh.load(path, force="mesh")
    if m.group(3) == "L":  # participant 001 only: unmirrored left foot. Length is along x, so reflect y.
        mesh.vertices[:, 1] *= -1
        mesh.invert()  # restore outward face winding after the reflection
    return m.group(1), m.group(2), mesh

pid, cond, mesh = load_scan(SCANS / "002_fBW_R.ply")
print(pid, cond, mesh.vertices.shape, mesh.extents.round(0), mesh.is_watertight)
files = sorted(SCANS.glob("*_*BW_*.ply"))  # 200
```

### 3.2 Pressure images, Footbird (`pressure-images`)

- What: Zenodo 14621923, "Plantar pressure dataset for foot health assessment" (Zhang and Liang, Putian Univ.). 400 rendered heatmap PNGs from a Footbird 3.0 shoe-store scanner. The Zenodo description names 5 classes (normal, high arch, flat, inward heel tilt, outward heel tilt).
- License: CC BY 4.0.
- Path: `datasets/raw/zenodo-14621923/extracted/Dataset-plantarImages/Dataset/YYYYMMDDHHMMSS.png` (flat folder).
- Format: RGBA PNG, about 640-720 px square, rendered colormap. **No pressure units, no calibration**, not raw sensor values.
- Labels: **none shipped**. No label file, no class folders, no metadata. Labels must come from the authors or hand annotation.
- Breakage: **198 of the 400 PNGs are zero bytes in the upstream zip** (the checksum matches Zenodo, so this is upstream data loss). 202 are loadable.
- Do not train a supervised classifier on this without hand labels.

```python
IMGS = RAW / "zenodo-14621923/extracted/Dataset-plantarImages/Dataset"
usable = [p for p in sorted(IMGS.glob("*.png")) if p.stat().st_size > 0]  # 202 of 400
from PIL import Image
img = Image.open(usable[0]).convert("RGB")
print(len(usable), img.size)
```

### 3.3 FSR 32x32 rectus vs valgus (`fsr-rectus-valgus`)

- What: Zenodo 19872222, high-density plantar pressure from a custom 32x32 FSR mat, 307 samples (one standing capture of both feet per file).
- License: CC BY 4.0.
- Path: `datasets/raw/zenodo-19872222/extracted/PLANTAR PRESSURE DIST/PLANTAR PRESSURE DIST/<left>-<right>_<tcaL>_<tcaR>_<id>.csv` (note the doubled folder and the spaces). The record root also has 4 example PNG maps (`Rectus_Rectus.png`, etc.).
- CSV grid (164 rows x 128 cols per file, 1-based spreadsheet coordinates):
  - Row 1: map timestamp string in column B. Row 2: `tca_left, label_left, tca_right, label_right`, where tca is the tibio-calcaneal angle in degrees and label is `Rectus` or `Valgus`.
  - Row 3 `INTERPOLATIONS`, rows 4-131: a 128x128 interpolated map (4x upsampling).
  - Row 132 `MEASUREMENTS`, **rows 133-164, columns A-AF: the raw 32x32 grid**. Left foot = columns A-P (16 wide), right foot = Q-AF. Toes are at the top of the image (the analysis flips rows to get heel first).
- Units and pitch: **undocumented** (values are about 0.4-2.2 at the file maximum). The analysis assumes 3 mm per pixel on the 4x block; indices are ratios so only length filters depend on it.
- Labels: rearfoot **alignment** (rectus or valgus), not arch type. Counts (left,right): rectus/rectus 47, rectus/valgus 62, valgus/rectus 49, valgus/valgus 149. Filename labels match the cell labels in all files.
- Breakage: one file is truncated (`valgus-valgus_5.58_7.83_0001.csv`, under 124 columns); skip it. Some valid files are 124 columns wide instead of 128 (the interpolated block is then 124 wide; the raw grid is still A-AF). Our AI on these maps goes the opposite way to the pronation hypothesis (rectus reads flatter), so do not use this set for flat-foot claims. It is useful as a low-resolution FSR-mat stand-in.

```python
FSR = RAW / "zenodo-19872222/extracted/PLANTAR PRESSURE DIST/PLANTAR PRESSURE DIST"

def load_fsr(path: Path):
    """(raw 32x32 left, raw 32x32 right, header dict). Returns None for the truncated file."""
    df = pd.read_csv(path, header=None, encoding="utf-8-sig")
    if df.shape[1] < 124:  # truncated upload; some valid files are 124 wide, grid is still A-AF
        return None
    grid = df.iloc[132:164, 0:32].apply(pd.to_numeric, errors="coerce").to_numpy(float)  # rows 133-164, cols A-AF
    head = dict(tca_left=float(df.iloc[1, 0]), label_left=df.iloc[1, 1], tca_right=float(df.iloc[1, 2]), label_right=df.iloc[1, 3])
    return grid[:, :16], grid[:, 16:], head

left, right, head = load_fsr(sorted(FSR.glob("rectus-rectus_*.csv"))[0])
print(left.shape, right.shape, head)
```

### 3.4 CAD WALK healthy and hallux valgus (`cadwalk-healthy`, `cadwalk-hallux-valgus`)

- What: Booth et al., IEEE ISBI 2019. Dynamic barefoot walking on an RSscan footscan plate (0.5 m, 48.8 x 32.5 cm), exported to NIfTI. Healthy: Zenodo 1265420, 55 Dutch adults (C01-C55), 24 trials per foot, 500 Hz. Hallux valgus pre-surgery: Zenodo 3406523, 50 patients (HV01-HV50), 8-15 trials per foot, 200 Hz.
- **License conflict**: the Zenodo API says CC BY 4.0, but the bundled `Readme.pdf` in both sets says CC BY-NC-SA. Fine for the hackathon demo; keep it out of anything commercial until resolved.
- Path: `datasets/raw/zenodo-1265420/extracted/CAD_WALK_Healthy_Controls_Dataset/HealthyControls/Cxx/{left|right}_foot_trial_NN.nii` and `datasets/raw/zenodo-3406523/extracted/CAD_WALK_Hallux_Valgus_PreSurgery/HalluxValgus_PreSugery/HVxx/...` (same file names; note the upstream typo `PreSugery`). Per subject: `walking_speeds_<ID>.xlsx`. Per set: `metadata.xlsx` (Subject ID, height, weight, age, sex, EU shoe size, handedness, leg dominance) and `Readme.pdf`. Healthy has 2640 NIfTI files, HV has 1466.
- Format: NIfTI, array shape `(rows along foot, cols across foot, frames)`. Header zooms are `(7.62, 5.08, dt_ms)`: mm per row, mm per column, ms per frame (2.0 healthy, 5.0 HV). The sensors are non-square and **no geometric correction is applied**, so pass `px_mm=(7.62, 5.08)` to `footprint_indices`. Typical frame 34-38 x 19-22 pixels, 204-433 frames per healthy trial. HV has partial steps (a minimum of 5 frames).
- Units: **undocumented in the Readme**. Values peak around 50-100, read as N/cm2 (sim multiplies by 10 for kPa). Treat as relative.
- Orientation: the heel is **not** always at row 0. Detect it per trial from contact timing (first-contact centroid vs last-contact centroid; `pressure_indices.py::_heel_first`). Mediolateral direction is undocumented; `sim/scripts/convert_cadwalk.py` infers it per side by a vote on where midfoot contact sits.
- Labels: cohort only (healthy vs hallux valgus). There are no arch labels. HV is a forefoot deformity used as a clinical contrast group.
- Breakage: one HV trial is a partial step and is excluded (1 of 4106 trials).

```python
import nibabel as nib
CAD = {
    "healthy": RAW / "zenodo-1265420/extracted/CAD_WALK_Healthy_Controls_Dataset/HealthyControls",
    "hallux_valgus": RAW / "zenodo-3406523/extracted/CAD_WALK_Hallux_Valgus_PreSurgery/HalluxValgus_PreSugery",
}

def load_trial(path: Path):
    """(peak image heel-first, (mm per row, mm per col), ms per frame, frames) for one NIfTI trial."""
    im = nib.load(path)
    vol = np.asarray(im.dataobj, dtype=float)  # (rows, cols, frames)
    px_row, px_col, dt_ms = (float(z) for z in im.header.get_zooms()[:3])
    load = vol.sum((0, 1))
    active = np.flatnonzero(load > 0.1 * load.max())
    k = max(len(active) // 8, 1)
    rows = np.arange(vol.shape[0])
    def centroid(frames):
        f = vol[:, :, frames].sum((1, 2))
        return (f * rows).sum() / f.sum()
    peak = vol.max(2)
    if centroid(active[:k]) > centroid(active[-k:]):  # heel loads first, so it must sit at row 0
        peak = peak[::-1]
    return peak, (px_row, px_col), dt_ms, vol.shape[2]

peak, px, dt_ms, n_frames = load_trial(CAD["healthy"] / "C01" / "left_foot_trial_01.nii")
meta = pd.read_excel(CAD["healthy"] / "metadata.xlsx").dropna(subset=["Subject ID"])  # first sheet row is blank
speeds = pd.read_excel(CAD["healthy"] / "C01" / "walking_speeds_C01.xlsx", header=None)  # km/h, stride length, stride time per trial
print(peak.shape, px, dt_ms, n_frames, len(meta))
```

### 3.5 Pesplanus X-rays (`pesplanus-xray`)

- What: Mendeley sss89tjddy (Gul et al., Diagnostics 2023). 842 weight-bearing lateral foot X-rays, 14-47 y, labeled by calcaneal inclination (**under 18 deg = pes planus**; two radiologists, a third for disagreements).
- License: CC BY 4.0.
- Path: `datasets/raw/mendeley-sss89tjddy/{pes_planus|normal}/<name>.JPG` (402 pes planus, 440 normal). Filenames look like `10L.JPG`, `100R.JPG`, `75L - (139).JPG`; the letter is the side.
- Labels: Mendeley's API gives **unnamed folders**; `fetch.py` names them by file count matching the description (402 -> `pes_planus`, 440 -> `normal`). Spot-check a few images before trusting.
- Format: RGB JPEG, sizes vary (e.g. 995x661). No pixel spacing, no calibration.
- Breakage and leakage: only **540 of 842 files are unique by sha256** (byte-identical duplicates). Filenames do not identify patients (numeric prefixes repeat across classes). No duplicate group spans both classes, so labels are consistent. **Dedupe by hash before any split.**
- Use: validates the X-ray ground-truth idea only. Not usable for a phone-camera product.

```python
PES = RAW / "mendeley-sss89tjddy"
manifest = json.loads((PES / "manifest.json").read_text())  # {"files": [{"name": "normal/10L.JPG", "digest": sha256, ...}]}
first_by_hash: dict[str, str] = {}
for f in manifest["files"]:
    first_by_hash.setdefault(f["digest"], f["name"])
unique = sorted(first_by_hash.values())  # 540 files; split on this list
label = {n: n.split("/")[0] for n in unique}  # 'pes_planus' | 'normal'
from PIL import Image
img = Image.open(PES / unique[0])
print(len(unique), img.size, img.mode)
```

### 3.6 Takata flat vs normal (`takata-flatfoot`)

- What: Mendeley vv3zgwwpk3. 20 flat-arch ("LOW") vs 21 normal women on a Footscan plate. **Group-level regional summaries per person, not pressure frames.**
- License: CC BY 4.0.
- Path: `datasets/raw/mendeley-vv3zgwwpk3/data on foot and plantar pressure and gait cycle.xlsx`.
- Sheets: `MAXP` (peak pressure), `CA` (contact area), `GC` (gait-phase times: ICP, FFCP, FFP, FFPOP). Layout: row 0 = region name over its LOW column only (needs `ffill`), row 1 = `LOW`/`NORMAL`, rows 2+ = one woman per row (col 0 = id). Regions: Toe1, Toe2-5, Meta1-Meta5, Midfoot, Heel medial, Heel lateral. Group n is 20 flat and 21 normal in every column pair.
- Units: **none stated**; assumed N/cm2, cm2, ms.
- Label meaning: LOW = low arch (flat). The one strong effect is midfoot contact area (49.6 vs 35.6, +39%, d = 1.21, p < 0.001); results in `datasets/analysis/out/takata_regions.csv`.

```python
TAKATA = RAW / "mendeley-vv3zgwwpk3/data on foot and plantar pressure and gait cycle.xlsx"
raw = pd.read_excel(TAKATA, sheet_name="CA", header=None)
regions, groups, body = raw.iloc[0].ffill(), raw.iloc[1], raw.iloc[2:]
col = next(c for c in range(1, raw.shape[1]) if regions[c] == "Midfoot" and groups[c] == "LOW")
flat = pd.to_numeric(body[col], errors="coerce").dropna().to_numpy()
normal = pd.to_numeric(body[col + 1], errors="coerce").dropna().to_numpy()
print(len(flat), len(normal), flat.mean().round(1), normal.mean().round(1))
```

### 3.7 MUN104 template (`mun104`)

- What: github.com/0todd0000/mun104, Pataky et al. 2011, Gait & Posture 33(3):418-422. **Mean** plantar pressure template of 104 healthy people (Munster), one 63 x 27 map per foot. Not per-subject.
- License: MIT.
- Path: `datasets/raw/github_raw-0todd0000-mun104/extracted/MUN104.csv/MUN104{L|R}.csv` (also `extracted/MUN104.h5/MUN104{L|R}.h5`).
- Format: integer-valued CSV grid, 63 rows x 27 cols, max 402 (L) and 392 (R), about 660 nonzero pixels. Rows run heel to toe (row 0 = heel, last = toes). In the left foot the column index grows medially (hallux on the right); the right foot is its mirror. Pixel pitch undocumented (the analysis assumes 5 mm). Units are read as kPa by `sim/` (not stated in the CSV).
- Use: heatmap template and a sanity reference. The footprint AI of the template is 0.160 (L) and 0.168 (R), far below 0.26, because it is a dynamic mean.

```python
MUN = RAW / "github_raw-0todd0000-mun104/extracted/MUN104.csv"
mun_l = np.loadtxt(MUN / "MUN104L.csv", delimiter=",")
mun_r = np.loadtxt(MUN / "MUN104R.csv", delimiter=",")
print(mun_l.shape, mun_l.max(), mun_r.max())
```

### 3.8 48-FSR insole set (Zenodo 21743536, not in `datasets/raw/`)

- What: Trujillo-Hernandez et al., "Dataset of Plantar Pressure Insoles". 14 healthy adults, 48 FSRs per insole (12 rows x 4), 125 Hz, walking.
- License: CC BY 4.0. Raw data lives in `sim/data/raw/` (see section 2). `sim/public/data/insole.json` is the processed output; use that unless you must reconvert.
- Path: `sim/data/raw/ex/<Participant N>/Walking/{LEFT|IZQUIERDO|RIGHT}.tdms`. Folder case varies (`participant 3`), and the left file is `LEFT.tdms` for most people but `IZQUIERDO.tdms` for participant 13; `DERECHO.tdms_index` / `*.tdms_index` files are index sidecars. Glob `[Pp]articipant *`.
- TDMS layout: group `time`, channels `Measurement`, `Row`, `Timestamp`, `Sensor 1`..`Sensor 4`. **12 consecutive rows make one sample** (`Row` cycles 1-12, 4 sensor columns per row = 48 sensors). `reshape(-1, 48)` on the stacked sensor columns gives `(samples, sensor)` with sensor number n = 4 * (row - 1) + column, matching Table S1 numbering.
- Units: **kg per sensor**, each FSR 56.25 mm2. kPa = kg * 9.80665 / 56.25e-6 / 1000 (about 174.3 kPa per kg).
- **`Timestamp` is broken** (non-monotonic, jumps of tens of thousands of seconds between samples). Ignore it and use the nominal 125 Hz.
- Sensor coordinates: `sim/data/raw/zip/TableS1.xlsx`, sheets `Left Foot` / `Right Foot`, header on rows 1-2, columns (sensor number, region, text `"(x, y)"`) in **cm**. `convert_insole.py` converts to the sim frame: mm, x medial-positive (right x sign flipped), y heel to toe with +20.2 cm offset.
- Labels: none (healthy, with height, weight, shoe size only).

```python
INSOLE_RAW = Path("sim/data/raw")
KG_TO_KPA = 9.80665 / (56.25e-6) / 1000

def read_insole(path: Path):
    """(samples, 48) in kPa from one TDMS file. Needs `nptdms` (uv run --with nptdms)."""
    from nptdms import TdmsFile
    g = TdmsFile.read(path)["time"]
    rows = np.stack([g[f"Sensor {i}"][:] for i in range(1, 5)], axis=1)
    assert np.all(g["Row"][:] == np.tile(np.arange(1, 13), len(g["Row"]) // 12))
    return rows.reshape(-1, 48) * KG_TO_KPA

def read_layout_cm(side: str):
    """(48, 2) sensor (x, y) in cm for 'Left Foot' or 'Right Foot', ordered by sensor number."""
    import openpyxl
    ws = openpyxl.load_workbook(INSOLE_RAW / "zip/TableS1.xlsx")[side]
    pts = sorted((int(n), *map(float, re.findall(r"-?\d+\.?\d*", xy))) for n, _r, xy in ws.iter_rows(min_row=3, values_only=True))
    return np.array([[x, y] for _, x, y in pts])

frames = read_insole(INSOLE_RAW / "ex/Participant 1/Walking/LEFT.tdms")
layout = read_layout_cm("Left Foot")
print(frames.shape, frames.max().round(0), layout.shape)
```

## 4. Which dataset for which task

| task | use | why / caveat |
|---|---|---|
| Insole surface design, mesh measurement code (length, width, AHI, arch drop) | Schuster scans | Only real 3D feet; healthy, mBW/fBW pairs, CC0 |
| Validate pressure-index code on real plate data | CAD WALK healthy + HV | Realistic dynamic maps; HV is the only pathology contrast; license caveat |
| Flat vs normal ground-truth targets (synthetic generator, cutoffs sanity) | Takata | Only labeled flat vs normal pressure data; regional means, n = 20 vs 21 |
| Pressure heatmap template / demo | MUN104 | Clean mean map of 104 healthy people |
| Sensor-layout simulation (48 FSRs, 125 Hz) | 48-FSR insole | Real sensor timing and coordinates; healthy only, unlabeled |
| Low-resolution FSR mat stand-in | FSR rectus/valgus | Alignment labels only, units unknown |
| X-ray ground-truth idea (calcaneal inclination < 18 deg) | Pesplanus | Dedupe first; no relation to phone photos |
| Photos, segmentation, keypoints | none here (Kaggle photos-of-foots is manual, no arch labels) | |
| Supervised flat-foot classifier from Footbird images | **do not** | No labels, 198 empty files; hand labels required |

## 5. Arch indices

All cutoffs are population specific and the indices disagree. Show each index with its cutoff and citation, and report agreement, not one verdict.

| index | formula | cutoff | source |
|---|---|---|---|
| Cavanagh Arch Index (AI) | mid-third contact area / toeless total area | > 0.26 flat, < 0.21 high arch (older adults: > 0.28, Menz 2012) | Cavanagh and Rodgers 1987, J Biomech 20:547 (quartiles of 107 young adults, ink prints) |
| Staheli | min midfoot width / max heel width | > 0.89 flat, < 0.44 cavus | Staheli 1987 |
| Chippaux-Smirak (CSI) | min midfoot width / max forefoot width | > 0.45 flat (children; 0.627 in some adult cohorts) | Forriol and Pascual 1990 |
| Arch Height Index (AHI) | dorsum height at 50% foot length / truncated foot length (heel to 1st MTP) | standing mean 0.340 +/- 0.030; <= 0.315 planus | Butler 2008 |
| Navicular drop | seated neutral minus relaxed standing navicular height | >= 10 mm excessive | Mueller 1993 |
| Calcaneal inclination (X-ray) | radiographic angle | < 18 deg pes planus | Pesplanus labeling rule |

Empirical caveats from `datasets/analysis/REPORT.md` (read it before quoting any number):

- **The indices disagree.** On 100 healthy scans the share called flat is 2% by AHI, 50% by AI, 15% by Staheli, 57% by CSI. AHI vs AI Spearman is only -0.46; AI vs Staheli 0.92.
- **Scan footprint AI reads flat for 50% of a healthy cohort** (mean 0.265 +/- 0.033 at the 0.26 cutoff). Contact tolerance moves it: mean AI 0.279 / 0.258 / 0.265 / 0.284 at 1 / 2 / 3 / 5 mm, flat share 64 / 43 / 50 / 76%. (`sim/scripts/pick_feet.py` uses a different rasterizer and gets 56 of 100 above 0.26.) Use rank order, or calibrate cutoffs per modality.
- **Dynamic plate AI runs far below the 0.26 static cutoff**: CAD WALK healthy 0.145 +/- 0.070 (2.7% of feet flat), HV 0.190 +/- 0.086 (22% of feet, 30% of people with either foot flat; Mann-Whitney p = 2e-5). MUN104 gives 0.160 / 0.168. Set any pressure cutoff from healthy plate data, not from ink prints. Group differences and ranks are the robust part.
- Staheli and CSI collapse on dynamic plate data (midfoot width near zero); AI is the usable pressure index there.
- **AHI from scans: 0.369 +/- 0.027 vs Butler 0.340 +/- 0.030**, about 1 SD high with matching spread. Close, not exact.
- Arch drop (mBW to fBW) median 5.9 mm, IQR 4.7 to 7.4 mm; 3 of 100 reach 10 mm. It is an underside-height proxy, not the bony navicular landmark.
- Takata targets for synthetic flat feet: about 1.4x normal midfoot contact area, about 1.15x midfoot peak pressure, forefoot and heel unchanged.

**Reference implementation to port: `datasets/analysis/footprint.py`** (pure numpy and scipy). Input: a 2D contact or pressure image; row 0 must be the heel side (left/right irrelevant).

```python
from footprint import footprint_indices, FootprintIndices, AI_FLAT, AI_HIGH, STAHELI_FLAT, STAHELI_CAVUS, CSI_FLAT, AHI_MEAN, AHI_SD, AHI_PLANUS, ARCH_DROP_EXCESSIVE_MM
# footprint_indices(img: np.ndarray, px_mm: tuple[float, float] = (1.0, 1.0), *, threshold_frac: float = 0.05,
#                   toe_frac: float = 0.20, align: bool = True, length_mm: float | None = None) -> FootprintIndices | None
# FootprintIndices(ai, staheli, csi, length_mm, area_mm2, heel_width_mm, mid_width_mm, fore_width_mm)
#   .flat_flags() -> dict[str, bool]   # keys ai, staheli, csi at the cutoffs above
#   .as_dict() -> dict[str, float]
# Returns None for an empty or degenerate print. px_mm is (mm per row, mm per col).
ix = footprint_indices(peak, px)  # peak, px from the CAD WALK block above
print(ix.as_dict() if ix else None, ix.flat_flags() if ix else None)
ix_mun = footprint_indices(mun_l, (5.0, 5.0))  # MUN104 pitch is assumed, not documented
print(ix_mun.ai.round(3), AI_FLAT)
```

Algorithm in one line: contact = pixels above 5% of max (speckle under 10% of the largest blob dropped), PCA foot axis (heel to toe), toes = distal 20%, rear/mid/fore thirds, widths from 4 mm slices. Other scripts: `scan_measure.py` (`measure(path, contact_mm=3.0)` on a PLY, AHI and arch drop), `pressure_indices.py` (CAD WALK, MUN104, FSR), `takata_regions.py` (`tidy()`).

## 6. Derived artifacts you can use without raw data

`datasets/analysis/out/` (regenerate with the three analysis scripts, see `REPORT.md`):

| file | rows | columns |
|---|---|---|
| `scan_measurements.csv` | 100 (one per person) | `id, side`, then `fBW_*` and `mBW_*` sets: `mirrored_by_me, floor_tilt_deg, foot_length, ball_width, trunc_length, dorsum_h, ahi, medial_arch_h, lateral_arch_h, heel_width, ai, staheli, csi, print_area`; plus `arch_drop_mm, ahi_drop`. mm and mm2; participant 51 mBW is blank |
| `scan_contact_sensitivity.csv` | 3 | `contact_mm, ai_mean, ai_sd, pct_ai_flat, pct_csi_flat` (1, 2, 5 mm) |
| `pressure_indices.csv` | 4720 (4106 CAD WALK trials, 2 MUN104, 612 FSR feet) | `dataset, group, subject, foot, trial, frames, ok, ai, staheli, csi, length_mm, flat_ai, flat_staheli, flat_csi, tca_deg` (`tca_deg` only for FSR). Filter `ok == True` |
| `takata_regions.csv` | 24 (10 MAXP + 10 CA + 4 GC) | `metric, unit, region, n_flat, n_normal, flat_mean, flat_sd, normal_mean, normal_sd, pct_diff, cohens_d, welch_p` |
| `pressure_summary.json` | | CAD WALK per-group means, flat percentages, sensitivity to threshold and toe cut, MUN104 and FSR summaries |
| `cadwalk_ai.png`, `fsr_ai.png`, `footprints.png` | | Figures (AI histograms, example prints) |

`sim/public/data/` (canonical frame: mm, x medial-positive, y heel to toe; right-foot data mirrored):

| file | holds |
|---|---|
| `insole.json` | `{fs: 125, unit: "kPa", sensors: {left, right}: 48 x {x, y} mm, trials: [{participant, side, frames: [T][48] int kPa}]}`. 28 trials, one representative stance per participant and side, from the 48-FSR set |
| `cadwalk.json` | `{source, steps: [{id, title, cohort, subject, side, ai, fs: 50, qstep, grid: {nx: 26, ny: 54, cell: 5, x0, y0}, frames: [T][nx*ny]}]}`. 5 real plate steps (3 healthy, 2 HV), footprint scaled to 240 mm. kPa = frame value * `qstep`; the flat array is row-major with y (heel to toe) outer, x inner |
| `mun104.json` | `{rows: 63, cols: 27, unit: "kPa", data}`: left-foot MUN104, row 0 heel, column grows medially |
| `feet.json` | `{source, thresholds, stats, picks, feet: [{id, side, ai}]}`: the footprint AI of all 100 fBW scans by `pick_feet.py` (flat share 56 of 100) and the three chosen examples |

`sim/public/models/foot-{flatter,typical,higher}.glb`: scans 077 (AI 0.351), 058 (0.264), 101 (0.191), 20k faces, scaled to a 240 mm foot, sole on z = 0, left-foot orientation in the canonical frame. Scan 077 failed the automatic medial-side check; its orientation follows the file label.

## 7. Gotchas checklist

- [ ] Never commit `datasets/raw/` or `sim/data/raw/` (both gitignored, 7.6 GB).
- [ ] Pesplanus: dedupe by sha256 before splitting (540 unique of 842); folder labels were inferred from file counts.
- [ ] Mirror left feet before pooling: Schuster `001_*_L` is an unmirrored left, `_Lr` is already mirrored; CAD WALK has separate `left_`/`right_` files whose mediolateral direction is undocumented.
- [ ] Units differ everywhere: kPa (MUN104 as read by sim, insole after conversion), N/cm2 (CAD WALK, Takata, assumed), kg per sensor (48-FSR raw), mm (scans), uncalibrated (Footbird images, FSR 32x32). Normalize before pooling.
- [ ] Heel direction is not fixed in CAD WALK; detect it per trial. Pixels are non-square (7.62 x 5.08 mm).
- [ ] 14621923 has 198 zero-byte PNGs and no labels. One FSR CSV is truncated. One CAD WALK HV trial is a partial step. Participant 51 mBW has no footprint.
- [ ] The 48-FSR `Timestamp` column is broken; assume 125 Hz.
- [ ] All cohorts are healthy except Takata, HV (forefoot deformity) and Pesplanus (X-ray). Flat-call rates on healthy cohorts are false-positive rates by construction.
- [ ] Cutoffs are population and modality specific (ink prints, children, one lab). Do not copy 0.26 onto pressure plates or phone scans.
- [ ] Wording: "screening" and "suggests", never "diagnoses". Show per-index results and agreement.
- [ ] CAD WALK license is CC BY 4.0 on Zenodo and CC BY-NC-SA in the bundled Readme.pdf: demo only until resolved.

## 8. Repo conventions for agents

- Commit only on a `test/<topic>` branch (currently `test/data-sim`). Never commit or push to `main`.
- Commit through the Cursor CLI headless mode so Cursor is the coauthor (`Co-authored-by: Cursor <cursoragent@cursor.com>`, no other AI trailer). Stage only your owned paths by explicit path; never `git add -A`, stash, reset, checkout or rebase, because the working tree is shared. Full rules and the command template: `docs/agent-workflow.md`.
- Conventional commits: `<type>(scope): description`.
- Further reading: `datasets/README.md`, `datasets/reports/validation.md`, `datasets/analysis/REPORT.md`, `docs/data-dossier.md` (sections A-F), `docs/pressure-datasets.md`.
