# Measurement validation on open data

Rule-based, cited indices only, no training. Everything regenerates with:

```
uv run --project datasets python datasets/analysis/scan_measure.py
uv run --project datasets python datasets/analysis/pressure_indices.py
uv run --project datasets python datasets/analysis/takata_regions.py
```

`footprint.py` is the single reference implementation of AI, Staheli and Chippaux-Smirak (cutoffs and citations in its docstring). It is what the iOS app should port. Outputs are in `out/`.

## Headline

- The scan pipeline reproduces the published standing AHI on 100 healthy people: **0.369 +/- 0.027** against Butler 2008 **0.340 +/- 0.030**. That is about 1 SD high, with the spread matching. Close, not exact.
- On clinical pressure-plate data the same footprint code separates hallux valgus from healthy: Cavanagh AI **0.190 vs 0.145** (p = 2e-5), AI-flat **22% of HV feet vs 2.7% of healthy feet** (30% vs 3.6% of people with either foot flat).
- The absolute AI cutoff (0.26) does not transfer between sources. A healthy scan cohort lands at 0.265 (50% "flat") and healthy walking plates at 0.145 (3% "flat"). Cutoffs need calibration to the sensing modality; ranks and group differences are the robust part.
- Staheli and CSI are fragile on dynamic plate data (midfoot width collapses to near zero). AI is the usable pressure index.
- Arch drop under load (minimal to full body weight) is measurable: median **5.9 mm**, IQR 4.7 to 7.4 mm, on a healthy cohort.

## 1. 3D scans (Schuster, 100 people, 200 meshes)

`scan_measure.py` -> `out/scan_measurements.csv` (one row per person; `fBW_*` and `mBW_*` columns), `out/footprints.png`, `out/scan_contact_sensitivity.csv`.

Method. Floor plane = trimmed least-squares fit to the lowest 2% of vertices (tilt was already below 0.45 deg on every scan, so the scans arrive leveled). Heel-toe axis = PCA of the plan view below 40 mm. Heel end = the end away from the leg stump (cut at 125 mm height, sits over the heel half). Medial side = left of travel for right feet; the one unmirrored left foot (`001_*_L`) is flipped; `_Lr` files are treated as right feet. Foot length and ball width come from vertices below 50 mm. Truncated length = **0.73 x foot length** (heel to 1st MTP; fixed anthropometric fraction chosen over a widest-medial-point rule because the latter is noisy on soft scans). Dorsum height = highest surface in a 6 mm slab at 50% length. Virtual footprint = underside height map (downward-facing triangles rasterized at 1 mm) under 3 mm; toes removed as the distal 20% of true foot length; AI/Staheli/CSI from `footprint.py`. Medial arch height = max underside height in a band 5 to 30 mm inside the medial outline, 40 to 55% of length, median over rows (navicular proxy, not the bony landmark). Arch drop = mBW minus fBW medial arch height.

Orientation self-checks, all 100 of 100 feet in both conditions: ball width exceeds heel width (heel/toe correct), and underside is higher on the medial than lateral side (medial side correct, including the mirrored foot).

fBW results (n = 100):

| measure | mean +/- SD | range |
|---|---|---|
| foot length (mm) | 257.7 +/- 15.6 | 222 to 306 |
| ball width (mm) | 97.0 +/- 6.1 | 85 to 114 |
| AHI | **0.369 +/- 0.027** | 0.306 to 0.447 |
| Cavanagh AI | 0.265 +/- 0.033 | 0.186 to 0.360 |
| Staheli | 0.725 +/- 0.159 | 0.34 to 1.02 |
| CSI | 0.463 +/- 0.108 | 0.20 to 0.79 |
| medial arch height (mm) | 15.7 +/- 3.5 | 4.4 to 25.0 |

Share of this healthy cohort called flat at the published cutoffs: AHI <= 0.315: **2%**; AI > 0.26: **50%**; Staheli > 0.89: **15%**; CSI > 0.45: **57%**. Votes among the four indices: 0 flat 39 people, 1 flat 15, 2 flat 31, 3 flat 13, 4 flat 2.

Arch drop (mBW to fBW): mean 6.2 +/- 2.2 mm, median 5.9, 10th to 90th percentile 3.9 to 8.9 mm. **3 of 100** reach the 10 mm "excessive" mark, 67 reach 5 mm. AHI rises from 0.369 (fBW) to 0.417 (mBW). Medial arch height rises 15.7 to 21.8 mm.

Honest read.
- AHI agrees with Butler on spread and sits about 0.03 high. Plausible causes: scans are a young healthy cohort, foot length is cut at 50 mm height, the 0.73 truncation is a fixed fraction, and "full body weight" in a scanner is not relaxed bilateral standing.
- The indices disagree strongly. AI, Staheli and CSI correlate well (Spearman 0.92 between AI and Staheli) because they share a footprint, but AHI correlates only -0.46 with AI. The app should show per-index results and agreement, not one verdict (as the dossier proposes).
- Footprint AI depends on the contact tolerance: mean AI 0.279 / 0.258 / 0.265 / 0.284 at 1 / 2 / 3 / 5 mm, and AI-flat share 64 / 43 / 50 / 76%. A phone scan or soft-tissue footprint will not match ink-print cutoffs without calibration.
- Arch drop here is an underside-height proxy, so the 10 mm navicular-drop cutoff does not map onto it directly. Use it as a relative load-response measure.
- Visual check of segmentation: `out/footprints.png` shows lowest, 25th, median, 75th, highest AI prints. Prints are clean, heel and forefoot are right, toe prints are separate lobes.

## 2. Pressure indices

`pressure_indices.py` -> `out/pressure_indices.csv` (every trial or foot), `out/pressure_summary.json`, `out/cadwalk_ai.png`, `out/fsr_ai.png`.

Method. Each recording is reduced to a peak-pressure image (max over frames), oriented heel first, and sent to `footprint_indices` (contact = pixels above 5% of the image maximum, toes = distal 20%). CAD WALK heel direction comes from contact timing (first-contact centroid versus last-contact centroid). Trials under 30 frames or with a print under 150 mm are excluded (1 of 4106 trials). Per-foot value = median over its trials (10 to 12 per foot).

### CAD WALK, healthy (55) vs hallux valgus (50, pre-surgery)

| | healthy | hallux valgus |
|---|---|---|
| feet | 110 | 100 |
| AI mean +/- SD (per foot) | 0.145 +/- 0.070 | 0.190 +/- 0.086 |
| feet AI > 0.26 | **2.7%** | **22.0%** |
| people with either foot AI > 0.26 | 3.6% | **30.0%** |
| single trials AI > 0.26 | 4.8% | 24.0% |
| feet Staheli > 0.89 / CSI > 0.45 | 0% / 0% | 0% / 1% |

Mann-Whitney on per-foot AI: p = 2.0e-5 (medians 0.151 vs 0.208). Staheli and CSI differ in rank but almost never cross their cutoffs.

PAPPI (PLOS ONE 2020) reports about 35% of HV cases with a pes-planus midfoot pattern. Our 30% of HV people (22% of feet) is the same order and 8 to 10 times the healthy rate, but this is a different test, so treat it as consistent, not as a replication. It is sensitive to the toe cut (share of HV feet flat: 15% at 15% toe cut, 22% at 20%, 36% at 25%; healthy 2.7 / 2.7 / 3.6%) and to the contact threshold (HV 19 / 22 / 16% at 2 / 5 / 10%; healthy 1.8 / 2.7 / 0.9%). Across every setting HV is at least 5 times the healthy rate.

Why absolute AI is low on plates: the peak image of a walking foot has a heel blob and a forefoot blob joined by a thin lateral strip, and the plate quantizes pressure at about 3 units, so light midfoot contact falls below 5% of peak. Dynamic AI sits well under the static 0.26 cutoff (healthy mean 0.145). MUN104 (mean of 104 healthy people) agrees: AI 0.160 (left) and 0.168 (right), Staheli 0.0 and 0.09. A pressure-based cutoff for this app should be set from healthy plate data, not copied from ink prints.

### FSR 32x32 maps, rearfoot rectus vs valgus (306 files, 612 feet)

Pixel pitch is not documented, so pixels are assumed 3 mm on the 4x interpolated block; indices are ratios and only the length filter depends on it.

| | rectus (205 feet) | valgus (407 feet) |
|---|---|---|
| AI mean +/- SD | 0.261 +/- 0.077 | 0.239 +/- 0.086 |
| AI > 0.26 | 62% | 49% |
| CSI > 0.45 | 37% | 22% |
| Staheli > 0.89 | 0% | 0% |

AI differs between groups (p = 0.002) but in the **opposite direction** to the pronation hypothesis: rectus feet score flatter. AI vs the numeric tibiocalcaneal angle is also weakly negative (Spearman -0.16). Labels are rearfoot alignment, not arch type, and the map is a few sensor cells wide, so this dataset should not be used to claim flat-foot detection. It does show the code runs on low-resolution FSR grids (like the DIY 6-FSR kit after interpolation) and produces broadly spread values.

## 3. Takata flat vs normal (20 flat vs 21 normal women)

`takata_regions.py` -> `out/takata_regions.csv` (flat and normal mean, SD, percent difference, Cohen d, Welch p for 10 regions of peak pressure and contact area, plus 4 gait phase times). Units are assumed (N/cm2, cm2, ms); the workbook states none.

Regions that differ:
- **Midfoot contact area: 49.6 vs 35.6 (+39%), d = 1.21, p < 0.001.** The one strong effect.
- Midfoot peak pressure: 5.15 vs 4.46 (+15%), d = 0.54, p = 0.095 (suggestive).
- Hallux (Toe1) peak pressure: 6.43 vs 5.33 (+21%), d = 0.68, p = 0.037.
- Meta5 contact area +17% (p = 0.098, not significant).
- No meaningful difference in Meta1 to Meta4 pressure, heel pressure or contact area, lesser toes, or gait phase times.

Targets for the synthetic generator: flat feet should have roughly 1.4x the normal midfoot contact area and about 1.15x the midfoot peak pressure, with forefoot and heel left unchanged and a modest hallux pressure increase.

## Limitations

- Scans are all healthy and carry no clinical labels, so these numbers validate measurement consistency, not diagnostic accuracy. Flat-call rates on this cohort are false-positive rates by construction, and they vary from 2% to 57% across indices.
- Cutoffs are population and modality specific (Cavanagh quartiles from 107 young adults, CSI from children, AHI from one lab study). Report agreement across indices, not one label.
- AHI and arch drop depend on landmarks approximated with fixed fractions (73% truncated length, 40 to 55% of length for the arch). Real phone-scan landmarks will add noise.
- CAD WALK has no arch labels; HV is a forefoot deformity used here only as a clinical contrast group. The healthy group is healthy, not "flat versus normal".
- Foot length from this pipeline (median 258 mm) differs from the validation report (267 mm), which used PCA over the full mesh including the leg.
- Data problems: one FSR file is truncated (`valgus-valgus_5.58_7.83_0001.csv`, skipped, 1 of 307); one mBW scan (participant 51) produced no usable footprint; one CAD WALK HV trial was a partial step; the `pressure-images` set (no labels, 198 empty PNGs) was not used.
