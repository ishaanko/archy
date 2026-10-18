# datasets

Open foot datasets for the flat-foot screening app. Raw data is gitignored (`datasets/raw/`, about 7.6 GB extracted); everything is reproducible.

Start here:
- What we found: `analysis/REPORT.md` (arch measurements on 100 scans, CAD WALK healthy vs hallux valgus, Takata flat vs normal). Results as CSV in `analysis/out/`.
- What each dataset contains and what's broken: `reports/validation.md`.
- Reference implementation of the arch indices (port this to Swift): `analysis/footprint.py`.

```
uv run --project datasets python datasets/fetch.py list
uv run --project datasets python datasets/fetch.py get all            # add --include-large for treadmill_data.mat (281 MB)
uv run --project datasets python datasets/validate.py                 # writes datasets/reports/validation.{json,md}
uv run --project datasets python datasets/analysis/scan_measure.py    # likewise pressure_indices.py, takata_regions.py
```

Needs `uv`. `.rar` extraction uses `bsdtar` (built into macOS); `7zz` 26.04 cannot read this archive's RAR v6 method.
Downloads are idempotent: checksums (Zenodo md5, Mendeley sha256) are verified, HTML responses rejected, and existing good files skipped.
Sources and statuses live in `registry.py`. Latest numbers are in `reports/validation.md`.

## Downloaded automatically

| key | what | license (per API) | use |
|---|---|---|---|
| `schuster-scans` | Zenodo 10360304: 100 people, 200 PLY foot scans (mBW + fBW), mm units | CC0 | mesh measurement + insole surface |
| `pressure-images` | Zenodo 14621923: 400 plantar pressure PNGs | CC BY 4.0 | pressure heatmap classifier |
| `fsr-rectus-valgus` | Zenodo 19872222: 307 CSVs, 32x32 FSR grids | CC BY 4.0 | FSR mat simulation, rearfoot alignment |
| `cadwalk-healthy` / `cadwalk-hallux-valgus` | Zenodo 1265420 / 3406523: RSscan pressure videos (.nii) | CC BY 4.0 | validate arch-index code |
| `pesplanus-xray` | Mendeley sss89tjddy: 842 lateral X-rays, flat vs normal | CC BY 4.0 | X-ray ground-truth idea |
| `takata-flatfoot` | Mendeley vv3zgwwpk3: regional pressure, 20 flat vs 21 normal women | CC BY 4.0 | sanity check cutoffs |
| `mun104` | GitHub 0todd0000/mun104: mean L/R pressure of 104 healthy subjects | MIT | heatmap demo |

Zenodo 21743536 (48-FSR insole) is fetched by `sim/`, not here.

## Manual / gated (not downloaded)

Kaggle photos-of-foots (login), Kaggle pesplanus mirror (redundant), Foot3D and SynFoot (Google Form, emailed link), UNB StepUP-P150 (very large, no arch labels), Frontiers 2023 pressure images (request-only). See `registry.py` for URLs.

## Caveats

- No dataset pairs phone photos or 3D scans with clinical flat-foot labels. Treat any end-to-end accuracy as unvalidated.
- `pressure-images` ships **no labels** (400 timestamp-named PNGs, one flat folder) and **198 of the 400 PNGs are zero bytes in the upstream zip** (checksum matches Zenodo). 202 are usable.
- `pesplanus-xray`: Mendeley folders are unnamed; labels come from folder file counts matching the description (402 pes planus, 440 normal). Only 540 of 842 files are unique by hash, and filenames do not identify patients, so dedupe before splitting.
- `schuster-scans`: all healthy, no arch labels. `_Lr` = left-dominant participant, mirrored to look right; `001_*_L` is an unmirrored left foot the README does not explain.
- `fsr-rectus-valgus` labels are rearfoot alignment (rectus/valgus), not arch type.
- CAD WALK license conflict: Zenodo lists CC BY 4.0, but the bundled `Readme.pdf` says CC BY-NC-SA. Fine for the demo; keep it out of anything paid until resolved.
- `mun104` has no published checksum; sha256 is recorded in the manifest and report on first fetch.
