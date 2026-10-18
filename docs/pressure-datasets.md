# Public Plantar Pressure Map Datasets: What Exists, What to Use, and How to Get It

Research summary (Oct 2026). On-disk status for this repo: CAD WALK (both), 48-FSR insole, rectus/valgus 32x32, Takata, Footbird images (14621923) and MUN104 are already downloaded and validated, see `datasets/reports/validation.md`.

## TL;DR
- **Best overall: UNB StepUP-P150.** 150 adults aged 19-91 on a Stepscan walkway (240x720 sensors at 4 sensors/cm², 100 Hz, kPa) at 4 speeds x 4 footwear. About 200,000 footsteps, raw frames plus preprocessed steps (75x40 px, 101 frames) in NPZ/MAT on FRDR (DOI 10.20383/103.01285). Larracy et al., Sci Data 12:1415, 2025. NPZ is about 50 GB, MAT about 118 GB. Healthy adults only.
- **Best clinical alternative: CAD WALK.** 55 healthy Dutch adults (Zenodo 1265420, 24 barefoot trials per foot, 500 Hz) and 50 hallux valgus patients (Zenodo 3406523, 8-15 trials, 200 Hz). RSscan footscan plate (sensors 7.62x5.08 mm), dynamic pressure "videos" exported to NIfTI, CC BY 4.0. Booth et al., IEEE ISBI 2019. Pressure units: check Readme.pdf.
- **Disease labels with insoles (per-sensor, not dense maps):** PhysioNet gaitpdb (93 PD + 73 controls, 8 force sensors per foot, Newtons, ODC-BY); WearGait-PD (100 PD + 85 controls, Moticon 16-sensor insoles, Synapse registration); Niemann et al. diabetic polyneuropathy (25 + 18, 8 insole regions, figshare, CC BY 4.0).

## Comparison table

| Dataset | Hardware / resolution / rate | N and population | Format / raw maps? | Units | Labels | Access |
|---|---|---|---|---|---|---|
| UNB StepUP-P150 | Stepscan, 240x720 sensors (5x5 mm), 100 Hz | 150 healthy adults, 19-91 y | NPZ + MAT, raw trial tensors + segmented footsteps | kPa (10 kPa threshold, 1,510 kPa range) | Demographics, foot length/width, speed, footwear, side | Open (FRDR) |
| CAD WALK Healthy | RSscan footscan, 7.62x5.08 mm, 500 Hz | 55 healthy adults, 18-70 y | ZIP 124.5 MB raw dynamic frames | Likely kPa (see Readme) | Age, height, weight, shoe size, sex, speed | Open, CC BY 4.0 |
| CAD WALK Hallux Valgus | Same, 200 Hz | 50 HV patients | ZIP 157.7 MB raw frames | As above | Demographics, speed, FFI, MOXFQ | Open, CC BY 4.0 |
| CASIA-D | RSscan + camera | ~88 subjects | .mat cumulative pressure images | Undocumented | Subject ID | CBSR site, unreliable |
| SFootBD | 2 mats x 88 piezo sensors | 127 users | .mat 2200x88 per foot | Raw piezo | User ID | Signed license |
| UoM-Gait-69 | Optical-fibre tomographic floor | 69 adults | Reconstructed images | Not calibrated | Task, age | Not verified |
| PhysioNet gaitpdb | Ultraflex insoles, 8 sensors/foot, 100 Hz | 93 PD + 73 controls | Text, no maps | N | Diagnosis, H&Y, UPDRS | Open, ODC-BY |
| WearGait-PD | Moticon OpenGo, 16 sensors + IMU | 100 PD + 85 controls | CSV per-sensor | N/cm² | UPDRS, FoG events | Synapse registration |
| Smart-Insole Dataset | Moticon SCIENCE, 16 sensors/foot + IMU | 29 (healthy, elderly, PD) | Per-sensor time series | N/cm² | Group, gait events | Open (authors' site) |
| Niemann diabetic | Insole, 8 regions | 25 DPN + 18 controls | ZIP 59 MB, no maps | Not verified | Group | Open, CC BY 4.0 |
| Takata flatfoot (Mendeley vv3zgwwpk3) | RSscan | 20 flat + 21 normal women | Regional summary values | Pressure per area | Foot type | Open |
| Footbird images (Zenodo 14621923) | Footbird 3.0 scanner | 400 images | Rendered heatmaps | None | 5 foot types (in description only; not shipped) | Open |
| 32x32 FSR rectus/valgus (Zenodo 19872222) | Custom 32x32 FSR | 307 samples | CSV 2D maps | Not verified | Rearfoot angle, rectus/valgus | Open |
| 48-FSR insole (Zenodo 21743536) | 12x4 FSRs per foot, 125 Hz | 14 healthy | .tdms + sensor coordinates | kg | Height, weight, shoe size | Open, CC BY 4.0 |
| Insole-GAITRite (Zenodo 19662017) | 32-channel insole + IMU | Not verified | CSV + GAITRite + video | Not verified | Cadence | Open |
| ImbalanSense (Zenodo 20924766) | Moticon OpenGo | Not verified | Per-sensor | Moticon | Condition | Open |
| PSU Taiji (arXiv 1811.12607) | Tekscan F-Scan 60x21/foot, 100 fps | 6 subjects | Pressure heatmaps | kPa | Pose, video sync | Not verified |

## Recommendations
1. General mapping or deep learning: StepUP-P150 (barefoot, preferred speed matches CAD WALK).
2. Healthy vs deformity, SPM-style regional analysis: CAD WALK, the only open high-rate clinical plate data with a pathology group.
3. Parkinson's / neuro: gaitpdb for comparability, WearGait-PD for scale. No true maps.
4. Insole mapping: open options are coarse (16-48 sensors). No open Pedar or F-Scan full-resolution walking dataset of meaningful size.
5. Children, athletes, diabetic walking maps: none open.

## Caveats
- Units differ (kPa, N, kg, N/cm², uncalibrated images); normalize before pooling.
- All high-resolution open sets are adults; StepUP and CAD WALK controls are mostly White/Dutch.
- Not public: multicenter RSscan/Zebris 460-participant set (Frontiers 2025), 1,573 flat-foot pressure images from 125 people, Win-Track diabetic images.
