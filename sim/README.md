# archy: insole pressure simulation

Browser-only foot arch screening demo: pressure sensors -> heatmap -> arch result in plain words -> printable insole, with a scanned 3D foot walking on it. No server, nothing uploaded.

Guided flow: Start -> Watch -> Result -> Insole. Technical controls, indices, cutoffs and citations sit under "Details". The start screen has three paths: Scan your foot (bundled scans or an upload), Walk on sensors (demo sensor, which walks like a flatter arch, or a live sensor over Web Serial) and the Sensor sandbox. "More demos" holds the rest: 3 arch types (scanned feet with matching synthetic walking pressure), a hospital pressure plate walk (real CAD WALK step, toggle between the full plate and what the 6-sensor kit would read) and the lab 48-sensor insole walk. Live input keeps a rolling mean of per-sensor peaks over the last 4 steps and shows the result after 3 steps (6 sensors: arch index only, since contact widths saturate). `src/core/gait.ts` rolls the foot through heel strike, flat, push-off; skipped under `prefers-reduced-motion`.

## Run

```
cd sim && bun install && bun run dev      # http://localhost:5173
bun run build                             # type-check + production build
bun scripts/export-stl.ts flat /tmp/x.stl # headless STL (normal | flat | "high arch", optional left|right)
```

Deep links for screenshots: `?ex=1|2|3`, `?plate=healthy-flatter&variant=kit`, `?source=p4-left`, `?live=demo&foot=flat&side=left`, plus `screen=watch|result|insole`, `frame=40` (pauses), `details=1`, `map=diff`, `surface=terrain`, `cmap=cividis`, `patterns=1`, `theme=light|dark` (default follows the system).

Foot models: `uv run --with trimesh --with numpy --with scipy --with fast-simplification --with mapbox_earcut --with networkx --with shapely python sim/scripts/pick_feet.py`. Plate steps: `uv run --with nibabel --with numpy --with scipy python sim/scripts/convert_cadwalk.py`.

## Pipeline

```
sensor frames (48 FSR, kPa)        src/core/synth.ts  (or real TDMS via scripts/convert_insole.py)
   -> pressure.ts   Gaussian-RBF interpolation onto a 2.5 mm grid inside the outline.
                    Per-frame maps, peak map, center-of-pressure trail.
   -> indices.ts    contact segmentation (5% of peak), drop toes (distal 20%), thirds along the long axis:
                    Cavanagh AI (>0.26 flat, <0.21 high), Staheli (>0.89 flat, <0.44 high), Chippaux-Smirak (>45% flat)
   -> template.ts   MUN104 healthy-mean map on the same grid; difference of load shares
   -> insole.ts     3 mm base, heel cup, medial arch support (6 mm + 80 mm x (AI - 0.21), clamped 4-18 mm),
                    1.2 mm relief under hotspots; closed polar mesh -> stl.ts (binary STL, mm)
   -> colormap.ts   viridis / cividis, blue-orange diverging for differences, contour + hatch "patterns" mode
   -> view/scene.ts three.js: heatmap texture, optional pressure terrain, sensors, CoP trail, OrbitControls
```

`src/core` has no DOM or three.js imports, so it can be ported to Swift. The viewer renders on demand (animation frames run only while playing or while camera damping settles). Canvas keys: arrows rotate, +/- zoom. Styling uses the cursor.com tokens in `src/theme.css`; the 3D background is read from `--bg` at runtime. The scanned foot is scaled to 93% of the insole length, centered, with its open leg cut domed over (`view/foot.ts`), and the camera refits to insole plus posed foot on resize and example change. Patterns default on under `prefers-contrast: more` or forced colors (the web stand-in for iOS `shouldDifferentiateWithoutColor`).

Canonical frame: mm, x medial-positive (right-foot data is mirrored on load), y heel to toe. Right-foot STLs are mirrored on export. 3MF export is not implemented.

## Data

Real (insole.json, 330 KB), `scripts/convert_insole.py`:
Zenodo 10.5281/zenodo.21743536, "Dataset of Plantar Pressure Insoles", CC BY 4.0. 14 healthy adults, 48 FSRs per insole (12 rows x 4), 125 Hz, readings in kg (56.25 mm2 per sensor, converted to kPa), sensor coordinates from Table S1 (cm). The converter keeps one representative stance (closest to the median step) per participant and side. Raw files live in `data/raw/` (gitignored); the zip MD5 is 545e356099f7bd21f97998b24448cdda.

MUN104 template (mun104.json, 4 KB), `scripts/convert_mun104.py`:
Mean peak plantar pressure of 104 healthy adults, MIT license, https://github.com/0todd0000/mun104.
Pataky TC, Bosch K, Mu T, Keijsers NLW, Segers V, Rosenbaum D, Goulermas JY (2011). An anatomically unbiased foot template for inter-subject plantar pressure evaluation. Gait and Posture 33(3): 418-422.
Grid 63 x 27, max 402 kPa, left foot (right is its mirror). Fitted to the generic insole outline by its contact bounding box.

## Real vs synthetic

- Real: sensor readings and their timing. The dataset is healthy-only and has no arch labels.
- Synthetic: each sensor's peak is the MUN104 map at its position (normal), plus medial midfoot loading (flat) or a suppressed midfoot band (high arch); time course is a Gaussian bump per foot region (heel strike, midstance, push-off, toe off), seeded noise.
- Insole outline is a generic adult shape (about 257 mm), not measured per user.
- Indices from 48 sparse sensors are not clinically validated. The sensors span about 6 cm of foot width, so widths saturate and most real single steps read flat-ish. Screening, not diagnosis.

## Scanned feet (3D model)

Schuster et al. 2024, Proc R Soc B, 3D foot scans, doi 10.5061/dryad.g4f4qrfwt (Zenodo 10360304), CC0. `scripts/pick_feet.py` builds a virtual footprint for each of the 100 full-weight scans (vertices within 3 mm of the floor, rasterized, toes dropped) and computes the Cavanagh arch index. Median 0.263, 5th-95th percentile 0.22-0.32, 56 of 100 above the 0.26 flat cutoff: a standing soft-tissue footprint reads flatter than the ink footprints the cutoffs came from, so use the ordering, not the cutoffs. Examples (public/models/, about 350 KB each, 20k faces, scaled to a 240 mm foot): flatter = participant 077 (0.351), typical = 058 (0.264), higher = 101 (0.191). Scan 077 failed the automatic medial-side check (very flat foot), orientation there follows the file label. Pressure for examples is synthetic (`core/synth.ts`), the scans only supply the foot shape.

## Clinic plate steps (CAD WALK)

Booth et al., "The CAD WALK Healthy Controls Dataset" (Zenodo 10.5281/zenodo.1265420) and the hallux valgus pre-surgery set (Zenodo 3406523), IEEE ISBI 2019. RSscan plate, 7.62 x 5.08 mm sensors, 500 Hz healthy / 200 Hz hallux valgus. `scripts/convert_cadwalk.py` keeps 5 steps (3 healthy, 2 hallux valgus with the flattest midfoot), aligns them to the canonical frame (orientation per side from a unanimous vote over all feet), resamples to a 5 mm grid at 50 Hz (public/data/cadwalk.json, about 550 KB). Units are undocumented; values are read as N/cm2 and stored as kPa. License note: the dataset Readme says CC BY-NC-SA, the task notes said CC BY 4.0, check before commercial use. The kit view samples the same step at the six positions in `src/hardware/layout.ts` (5-point patch mean), then reconstructs with `SPARSE_KERNEL`. Dynamic plate footprints give lower arch indices than the cutoffs (healthy median 0.15), so "typical" and "higher" steps were picked near arch index 0.235 and 0.15. Future work: UNB StepUP-P150 (50+ GB, not downloaded).

## Your own foot scan

Scan your foot: "Ishaan's foot", "Prakhar's foot" and "Pranav's foot" (bundled `public/models/scan-{ishaan,prakhar,pranav}.stl`, standing iPhone LiDAR scans shared with permission; Pranav's is a right foot, not flat, and reads typical) and "Your foot scan" (upload or drop an STL or OBJ; USDZ is not read, export STL from the scanning app). Everything runs in the browser through one path: `core/scan.ts` (parse, units from the bounding box, floor from the largest flat patch at the low end of any direction, heel/toe from the ankle height, medial side from the raised arch edge, then the canonical frame with right feet mirrored; measurements ported from `datasets/analysis/scan_measure.py`; insole outline from the silhouette below 20 mm, smoothed and offset 3 mm) and `core/scanEstimate.ts` (insole sized from the AHI and medial arch, estimated pressure, with-insole estimate; "Before" stands the foot on a flat insole, "With insole" on the custom one; and the 6-sensor kit's spots moved onto the scan so the Watch screen shows a reading per spot). `bun scripts/scan-measure.ts <scan.stl>...` prints the measurements; `bun scripts/scan-insole.ts <scan.stl> <out.stl>` exports the insole. Bundled scans also have a "Realistic" toggle: `public/models/scan-<key>-real.glb` is the scanning app's textured USDZ converted by `scripts/convert_usdz.py` (same mesh as the STL, in the STL's coordinates, 2048 px JPEG color texture), placed with `ScanResult.toCanonical`, the affine map `analyzeScan` fits from file to canonical coordinates. Deep links: `?scan=ishaan|prakhar|pranav` (`example` = ishaan), `real=1`, dev only `?scan=<url>`, plus `est=with`.

- Real (measured from the scan): outline, length, widths, dorsum height, Arch Height Index (Butler 2008 cutoffs 0.315 / 0.365; our healthy scan pipeline reads about 0.37, so "higher" is common), medial edge height. The verdict uses the AHI only.
- Sole check: a standing scan never saw the sole, so its underside is a hole fill of large flat triangles (over half of the underside area in triangles with an edge above 5 mm). Then `soleObserved` is false and the footprint indices (Cavanagh, Staheli, Chippaux-Smirak) are not used.
- Estimated, never measured: pressure. MUN104 warped onto the scan outline, arch loading from the AHI, scaled by body weight (180 kPa peak at 70 kg), and the with-insole view moves a share of heel and forefoot load onto the arch support (see the doc comment in `estimateScan`).

Fonts: Instrument Sans (headlines and logo wordmark), SIL OFL 1.1, license in `public/brand/OFL_InstrumentSans.txt`.
