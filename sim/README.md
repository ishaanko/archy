# Insole pressure simulation

Browser-only demo of: pressure sensors -> heatmap -> arch indices -> printable insole -> orbit it in 3D. No server, nothing uploaded.

## Run

```
cd sim && bun install && bun run dev      # http://localhost:5173
bun run build                             # type-check + production build
bun scripts/export-stl.ts flat /tmp/x.stl # headless STL (normal | flat | "high arch", optional left|right)
```

Deep links for screenshots: `?source=p4-left&map=diff&surface=terrain&patterns=1&cmap=cividis&frame=40`.

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

`src/core` has no DOM or three.js imports, so it can be ported to Swift. The viewer renders on demand (animation frames run only while playing or while camera damping settles). Canvas keys: arrows rotate, +/- zoom. Patterns default on under `prefers-contrast: more` or forced colors (the web stand-in for iOS `shouldDifferentiateWithoutColor`).

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
