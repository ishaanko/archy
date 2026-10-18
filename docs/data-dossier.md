# Flat-Foot App Data & Model Dossier (DubHacks 2026): What Actually Works This Weekend

The Dryad foot-scan dataset is usable after all. Its Zenodo mirror (zenodo.org/records/10360304, CC0) lists every PLY file with its own direct download link and MD5 checksum. That makes it the strongest 3D asset you have. For training a flat-foot classifier, the best open data is the small Zenodo "Plantar pressure dataset for foot health assessment" (400 labeled pressure images, CC BY 4.0, 10.1 MB). The best large labeled set is the Kaggle/Mendeley weight-bearing X-ray "Pesplanus" set (842 images labeled by radiologists). No open dataset links phone photos or 3D scans to clinical flat-foot labels. So the sensible design is rule-based classification on measurements (indices you can cite), with ML only for measuring the foot.

## TL;DR

- **Use these now:** Dryad/Zenodo foot scans (100 people, about 200 PLY files, CC0, per-file MD5). Zenodo 14621923 (400 pressure images, 5 classes including flat and high arch, CC BY 4.0). Mendeley/Kaggle Pesplanus X-rays (842 images, flat vs normal by calcaneal inclination angle <18°). For a big unlabeled pressure corpus, use CAD WALK (55 healthy + 50 hallux valgus, Zenodo) and UNB StepUP-P150 (150 people, >200,000 footsteps). None of these has phone-photo arch labels.
- **Pipeline:** do everything on-device. Capture with Object Capture (iOS 17+, needs a LiDAR iPhone with A14 or later). Get measurements from the mesh and from MediaPipe/RTMW foot keypoints, then classify with published cutoffs:
  - Cavanagh arch index >0.26 means flat.
  - Staheli index >0.89 means flat.
  - Navicular drop ≥10 mm means excessive.
  - Arch height index ≤~0.315 suggests planus.

  Use cloud only for an opt-in, on-demand Grok voice session. Unite.AI reported that xAI announced Grok Voice 3.0 on October 14, 2026 "at $0.08 per minute, or $4.80 per hour, the same price as Grok Voice 2.0."
- **Space tie-in:** cite peer-reviewed work, not anecdotes:
  - Lowrey CR, Perry SD, Strzalkowski NDJ, Williams DR, Wood SJ, Bent LR, *J Appl Physiol* 2014;116(6):683–692 (doi:10.1152/japplphysiol.01200.2013): foot-sole sensitivity in 11 astronauts after 12–16-day missions; 6 had heel hypersensitivity linked to worse balance (the CSA "Hypersole" experiment).
  - Layne et al. (Acta Astronautica 1998; Aviat Space Environ Med 2008): plantar-pressure boots as an in-flight countermeasure.
  - NASA KC-135 Foot Restraint Equipment Device (FRED) evaluation (1998).

  The "baby feet"/callus-loss story comes only from astronaut interviews (Scott Kelly, Leroy Chiao). Present it as anecdote.

## How to read the "verified" labels

I could not run `curl`/`md5sum` from this environment. **"Verified"** below means I fetched the repository page myself and confirmed three things: a public, login-free download link per file, a stated license, and (where shown) a per-file MD5 checksum you can check locally. **"Listed / unverified"** means the dataset is described in a paper or search result, but I did not confirm the file page, the license, or open access. **"Gated"** means it needs a form, a login, or an emailed link. Run the MD5 checks yourself before training. That is the only real test for corruption.

---

## Key Findings

### 1. The Dryad scan problem is solved: download from the Zenodo mirror

- **What it is:** "Foot shape-function model data," Robert Schuster (Griffith University), DOI 10.5061/dryad.g4f4qrfwt. Dryad automatically mirrors it to Zenodo as record **10360304** under **CC0 1.0**. It supports Schuster et al., *Proc. R. Soc. B* 2024, "Human foot form and function: variable and versatile, yet sufficiently related to predict function from form" (PMC10777145). That paper builds a statistical shape-function model from **100 healthy participants**.
- **Contents (verified from the Zenodo file table):**
  - Two PLY scans per participant: `NNN_mBW_R.ply` (minimal weight-bearing) and `NNN_fBW_R.ply` (full body-weight). Each is about 4.2–4.9 MB.
  - IDs run 001–103, with 021, 030 and 064 missing, so 100 participants and about 200 meshes.
  - Some files end in `_Lr` (e.g., 028, 075, 078, 096, 097, 098), and 001 is `_L`. These look like left feet, probably mirrored to right ("r"). Check the README before mixing them in.
  - `treadmill_data.mat` (281.3 MB) holds foot and ankle joint angles and moments for level, incline and decline walking and running.
  - `README.md` (2.0 kB).
  - The record totals 1.2 GB; the README says the scans alone are about 920 MB.
- **Why your earlier downloads looked "corrupted":** Dryad's download endpoints often return HTML (bot-check or redirect pages) to scripts. Saved with a `.ply` name, those look like broken meshes. The Zenodo mirror exposes plain links of the form `https://zenodo.org/records/10360304/files/001_fBW_L.ply?download=1`, each with an MD5 (e.g., `001_fBW_L.ply` → `706ef4a0806e30be0edbe6dfa2cee1f3`). Two other routes: the Zenodo REST API (`/api/records/10360304`), or downloading by hand in a browser.
- **Labels:** none for arch type. The participants are all healthy. But each person has a minimal-weight and a full-weight scan, so you can compute arch-height-index-style ratios and the **arch drop under load** (a 3D "navicular drop"). You can then label the feet yourself with published cutoffs. This is the best real 3D data for designing the insole surface and for testing your measurement code.
- **Download status:** **Verified** (public per-file links and MD5s on the Zenodo page). The Zenodo record showed 4,793 recorded downloads when I fetched it; an earlier indexed snapshot of the same page showed 4,394 downloads, 26.0 GB total data volume and a 1.12 GB record size, so the count changes over time and is best rechecked live.

### 2. Labeled flat-foot data is small, and almost none of it is photo- or scan-based

The only open datasets with explicit flat/normal/high-arch labels are:
- (a) 400 plantar-pressure images from one Chinese shoe store's scanner;
- (b) 842 weight-bearing lateral X-rays;
- (c) a few small tables of regional pressure values.

**I found no open dataset that pairs smartphone RGB, LiDAR or 3D foot scans with clinical arch labels.** This is the most important limitation to state honestly in your pitch.

### 3. Do the computer vision on-device

Every component you need has an iPhone-ready path:
- Object Capture runs on-device on iOS 17+.
- Depth Anything V2 Small has an official Apple Core ML package; Apple's Hugging Face model card (apple/coreml-depth-anything-v2-small) lists 33.90 ms on iPhone 15 Pro Max (iOS 17.4, Neural Engine, F16 variant, 49.8 MB).
- MediaPipe Pose exposes heel and toe landmarks.
- RTMW has ONNX exports.

This fits your "client owns everything" promise. The heavy 3D foot-fitting models (FOUND, FIND, FOCUS) are PyTorch research code. Their best use is an optional, self-hostable "pro" path, not the demo you show this weekend.

---

## Details

### A. Plantar-pressure datasets

| Dataset | Link | License | Subjects / size | Format | Labels | Access | Status |
|---|---|---|---|---|---|---|---|
| **Plantar pressure dataset for foot health assessment** (Zhang & Liang, Putian Univ.) | zenodo.org/records/14621923 | CC BY 4.0 | 400 images (subject count not stated); 10.1 MB zip | Images in `Dataset-plantarImages.zip` (MD5 2572b288fee0f97c59855586bbf9cd88) | 5 classes: normal, high arch, flat, inward heel tilt, outward heel tilt; some mixed | Open | **Verified** (page, license, MD5; 178 downloads). Labeling method not documented |
| **CAD WALK Healthy Controls** | zenodo.org/records/1265420 | Not confirmed (check record) | 55 healthy Dutch adults, 24 dynamic measurements each (2,640 steps) | Raw RSscan footscan pressure videos | Healthy only | Open (Zenodo) | **Listed / partially verified** (record exists; files and license not opened) |
| **CAD WALK Hallux Valgus (pre-surgery)** | zenodo.org/records/3406523 (pre-release of 16 patients: 1441309) | Not confirmed | 50 patients, 8–15 measurements each; plus FFI-5pt and Manchester-Oxford questionnaires | Raw pressure videos | Hallux valgus diagnosis | Open (Zenodo) | **Listed / partially verified.** Post-surgery set "not yet available" per project site |
| **UNB StepUP-P150** | FRDR doi:10.20383/103.01285 (earlier figshare 10.6084/m9.figshare.28143686); paper *Sci Data* s41597-025-05792-1 | Not confirmed | 150 people, >200,000 footsteps; 4 sensors/cm² (5×5 mm), 100 Hz, 1.2 × 3.6 m walkway | Raw trials plus preprocessed footsteps (75×40 px, normalized to 101 frames); per-step metadata including foot length and width | Identity, speed, footwear, sex, age; **no arch labels** | Open (FRDR) | **Listed** (very large; not downloaded) |
| **High-Density Plantar Pressure Dataset for Foot Alignment Classification (Rectus and Valgus)** | zenodo.org/records/19872222 | Not confirmed | 307 samples | 32×32 FSR grid as CSV inside a **.rar** (16.5 MB, MD5 2c1dc99402f5f3f17fadcaaa58102291) | Rectus vs valgus (foot alignment) | Open | **Listed with MD5** (needs `unrar`/`7z`; label definitions should be checked) |
| **Dataset of Plantar Pressure Insoles** (Trujillo-Hernández et al., Aug 2026) | zenodo.org/records/21743536 | Not confirmed | 14 healthy adults, 48 FSRs per insole, 125 Hz; 26.5 MB zip | `.tdms` (NI LabVIEW; read with Python `npTDMS`) plus sensor XY coordinates | None (healthy) | Open | **Listed with MD5** (545e356099f7bd21f97998b24448cdda). Ideal template for simulating an insole sensor |
| **Takata flatfoot plantar pressure data** | data.mendeley.com/datasets/vv3zgwwpk3/1 | Not confirmed (Mendeley default is often CC BY 4.0) | 20 flat-foot + 21 normal-foot women; Footscan plate | Probably tabular regional pressure and contact area (10 regions) plus gait-phase timing | **Flat vs normal** | Open (Mendeley) | **Listed** (file format not opened) |
| **Frontiers 2023 foot-type DL dataset** | Paper PMC10519788 | n/a | 1,573 pressure images from 125 people (748 flat, 774 normal, 51 single-flat) | FeetMapping plate images | Flat vs normal (X-ray and exam confirmed) | Not posted publicly as far as I found | **Problematic:** paper only; probably request-only |
| **PhysioNet gaitpdb** (Gait in Parkinson's) | physionet.org | ODC-BY (from prior knowledge) | PD patients + controls; 8 insole VGRF sensors per foot | Text time series | Parkinson's vs control, not arch | Open | **Not re-checked this session.** Force sensors only; not pressure maps |
| CASIA-D, SFootBD, UoM-Gait-69 | Listed in the StepUP-P150 comparison table | — | — | — | Biometrics | Mostly request/registration | **Unverified** |

**Takeaways:**
1. Train or demo your heatmap classifier on **Zenodo 14621923**. It is labeled, CC BY 4.0, and a tiny download, but treat the labels as unvalidated shop-floor labels.
2. Use **CAD WALK** to validate your index code. In the PAPPI analysis, **24 of 69 hallux-valgus cases (35%) showed the pes-planus pressure pattern** (raised midfoot peak pressure). It is a good realistic test set.
3. Use the **Zenodo insole set (21743536)** to give your three.js mat or insole simulation a realistic 48-sensor layout and 125 Hz timing.

### B. Footprint, photo and X-ray datasets

| Dataset | Link | License | Size / subjects | Labels | Access | Status |
|---|---|---|---|---|---|---|
| **Pesplanus Dataset (weight-bearing lateral X-ray)**, Gül et al., *Diagnostics* 2023 | Mendeley: data.mendeley.com/datasets/sss89tjddy/1; Kaggle: kaggle.com/datasets/suleyman32/pesplanus-two-class-dataset | Not confirmed | 842 JPGs from 421 patients aged 14–47 (Elazığ Fethi Sekin City Hospital) | Pes planus (402) vs normal (440); **calcaneal inclination <18° = pes planus**; two radiologists plus a third for disagreements | Mendeley open; Kaggle needs a free login | **Listed** (used by at least 4 follow-up papers, so it is evidently downloadable). Not usable for a phone-camera product, but it validates the X-ray ground-truth idea |
| **Photos of Foots** (Aydemir) | kaggle.com/datasets/emrahaydemr/photos-of-foots | Kaggle-listed (check) | 6,944 photos from multiple angles, left and right; age and gender only | **No arch labels** | Kaggle login | **Listed.** Useful for fine-tuning foot segmentation and keypoints |
| **Footprint Image Database** | kaggle.com/datasets/hellorahulk/footprintdatabase (mirror of github.com/goodrahstar/footprint-database) | Check repo | 21 people (flatbed scans) + 32 (dactyloscopic prints) | Identity only | Open | **Listed.** Can test your Cavanagh/CSI/Staheli code on real inked prints, but not for arch-label training |
| Roboflow foot datasets | — | — | — | — | — | **Not verified** this session |

### C. 3D foot scans and parametric models

| Asset | Link | License | Contents | Access | Status |
|---|---|---|---|---|---|
| **Schuster foot shape-function data** | zenodo.org/records/10360304 | **CC0** | 100 people × {minimal, full weight-bearing} PLY + treadmill .mat | Open, direct links + MD5 | **Verified** |
| **Foot3D** (Boyne, Charles, Cipolla, Cambridge) | github.com/OllieBoyne/Foot3D | MIT (repo) | 118 high-res foot meshes (FIND) + multiview set of 474 calibrated images over 14 scans (FOUND) | **Google Form → emailed link** | **Gated.** Allow a day or more; may not arrive during the hackathon |
| **SynFoot** | github.com/OllieBoyne/SynFoot | MIT (repo; data terms not separately confirmed) | V1: 50K synthetic RGB with normals, masks, keypoints. V2: 100K with normals, masks, dense correspondences | Google Form | **Gated;** download size not published |
| **FIND** (implicit articulated foot model, BMVC 2022) | github.com/OllieBoyne/FIND | Sidebar says MIT; README shows only a copyright/disclaimer | Pretrained models on Google Drive | Open (Drive) | **Listed.** The closest thing to a "SMPL for feet." Needs PyTorch + PyTorch3D |
| **SUPR** (body model with articulated foot) | arXiv 2210.13861 | Not confirmed (likely research-only) | Foot trained on 7,000 ANSUR II foot scans + 356 dynamic sequences | Registration | **Unverified** |
| **ANSUR II / CAESAR / SizeUSA raw scans** | — | Restricted / commercial | — | Not freely downloadable | **Problematic** for a hackathon |
| Size Korea, Volumental, Aetrex data | — | Proprietary | — | — | **No public data found** |

### D. Pretrained models

| Model | Use | License | Weights | iPhone path | Notes |
|---|---|---|---|---|---|
| **MediaPipe Pose Landmarker** | Heel (29/30) and foot-index/toe (31/32) landmarks out of 33 | Apache 2.0 commonly stated (official page not confirmed) | Lite/full/heavy `.task` bundles | Native iOS SDK | Only 2 points per foot: enough for foot length and heel-to-toe axis, not the arch |
| **RTMW / RTMPose wholebody** (MMPose) | COCO-WholeBody 133 keypoints incl. 6 foot (big toe, small toe, heel ×2) | Apache 2.0 | Official ONNX at download.openmmlab.com; `rtmlib` runs without mmcv | ONNX Runtime iOS; community Core ML fork `Kinetix-ML/rtmlib-coreml` (maturity unchecked) | RTMW-l 384×288: whole-body AP 70.1, **foot AP 79.3** |
| **Depth Anything V2 Small** | Monocular relative depth for non-LiDAR phones | Apache 2.0 for Small (larger variants differ) | `apple/coreml-depth-anything-v2-small` on Hugging Face; Apple Core ML gallery | **Official Core ML:** F16 49.8 MB, F16P6 19 MB; 33.90 ms on iPhone 15 Pro Max (iOS 17.4, Neural Engine, F16) per Apple's Hugging Face model card | Relative depth only; needs a scale reference (A4 sheet or credit card) |
| **Apple Depth Pro** | Metric monocular depth | Apple sample-code license for code; HF metadata disagrees (apple-ascl vs apple-amlr) | `apple/DepthPro`; Core ML `coreml-projects/DepthPro-coreml` (1.9 GB), pruned ~745 MB | Possible but heavy | **Check license before commercial use;** too large for a casual app |
| **FOCUS** (3DV 2025) | Multi-view foot reconstruction via dense correspondences | MIT | TOC model on Google Drive and HF `OllieBoyne/FOCUS` | Server/Mac (PyTorch; COLMAP for `--method sfm`); "can run without a GPU" | Foot3D benchmark: chamfer RMSE 2.7 mm vs COLMAP 3.1 mm, FOUND 3.3 mm |
| **FOUND** (WACV 2024) | Fit FIND to few views using predicted surface normals + uncertainty | **Not confirmed** (no LICENSE seen) | Uses FIND weights | Server only | Beats photogrammetry with few views; treat as unlicensed until checked |
| **FIND** | Generative foot shape model | See above | Google Drive | Server only | Good for fitting a full foot to sparse measurements |
| **Apple Object Capture** | Photogrammetric mesh (USDZ) | Apple SDK | Built in | On-device, iOS 17+ | See section E |

**Tracking foot shape over time:**
1. Save each scan as a dated, user-owned mesh plus a JSON of measurements.
2. Align successive meshes with ICP (e.g., Open3D, or a simple Swift/Metal implementation).
3. Track scalar indices (AHI, arch-drop under load, footprint AI from the mesh's contact patch) instead of raw vertices.

FIND/FOCUS latent codes would allow shape-space tracking, but they need a server.

### E. iOS specifics and accuracy

- **Object Capture requirements:** Apple's WWDC23 sample requires **iOS/iPadOS 17+ on an iPhone or iPad with a LiDAR Scanner and an A14 Bionic or later**. Apple's own wording in the developer forums: Object Capture is "available on select iOS devices with LiDAR capabilities." Apple engineers explain that LiDAR, while not strictly needed for photogrammetry, "significantly improves results" and is therefore required. An iPhone XS failed with `CPGSessionCreate failed!`. Always check `PhotogrammetrySession.isSupported` and `ObjectCaptureSession.isCurrentDeviceSupported`. On-device reconstruction quality is limited compared with sending the same images to `PhotogrammetrySession` on a Mac (Apple silicon, or a GPU with ≥4 GB and ray tracing).
- **Raw LiDAR is too coarse for feet:** in "A comparison of lidar accuracy across iPhone models" (Taylor & Francis, 2026, doi:10.1080/2150704X.2026.2720055), point-cloud RMSE on 14 boxes and 1 cylinder "were nearly identical between the iPhone 15 (2.06 cm) and the iPhone 12 Pro (2.05 cm)." That is fine for rooms, not for arches. Use LiDAR for scale and pose only, and photogrammetry or the camera for millimetre detail.
- **Validated phone foot measurement:**
  - *OptiFit* (iOS, peer-reviewed, PMC9739363) reported accuracy of **95.23% for length, 96.54% for width, 89.14% for arch height, 95.27% for instep girth**. Arch height is the hardest to measure.
  - Volumental's mobile-scanning page reports that "in our internal validation on barefoot adults, median absolute error was 1.1 millimetres for foot length and 1.3 millimetres for ball width," and that nine in ten scans were within 3.2 mm (length) and 3.5 mm (ball width) of its in-store scanner (revalidated September 2026). This is *internal company validation*, not peer-reviewed.
  - FOCUS and FOUND reach about 2–3 mm chamfer error on Foot3D.
- **TrueDepth (front camera):** good at close range for depth, but awkward to point at your own foot. Use it only for an "assistant holds the phone" mode.
- **On-device vs cloud — recommendation: on-device by default.** Reasons:
  - It matches the "client owns everything" promise: meshes, measurements and STL stay in the app sandbox or Files.
  - The required models already exist in Core ML or native form.
  - It avoids HIPAA-adjacent data handling.

  Offer an **opt-in "export & self-host"** path (a Docker image of FOCUS/FIND) for power users. Never upload by default.

### F. Validated thresholds for the Tape Measure Interpreter

| Measure | Formula | Cutoffs | Source / caveat |
|---|---|---|---|
| **Cavanagh Arch Index (AI)** | Midfoot area / total footprint area (toes excluded) | <0.21 high; 0.21–0.26 normal; **>0.26 flat** | Cavanagh & Rodgers, *J Biomech* 1987 (quartiles of 107 young adults). For older adults, Menz et al. 2012 use >0.28 |
| **Chippaux-Smirak Index (CSI)** | Min midfoot width / max forefoot width | <25% cavus; 25–45% normal; **>45% flat** (children) | IJERPH 2021 (10.3390/ijerph18105196). Another study uses >62.7%, so cutoffs differ by population |
| **Staheli Index** | Min midfoot width / max heel width | 0.44–0.89 normal; **>0.89 flat**; <0.44 cavus | Same source. A 2026 trial splits 0.90–1.00 flexible vs ≥1.01 rigid (with Jack's test) |
| **Clarke's angle** | Angle between medial footprint tangent and the line to the arch apex | Commonly quoted: <~31° flat, >~45° cavus | **Not verified this session.** Concordance with CSI is poor (ICC −0.42 to −0.45, PMC5438225) |
| **Arch Height Index (AHI)** | Dorsum height at 50% foot length / truncated foot length (heel → 1st MTP joint) | Mean standing 0.340 ± 0.030 (Butler et al. 2008). Studies citing Butler: **≤0.315 planus**, 0.315–0.365 rectus, ≥0.365 cavus. Older stricter cutoff ≤0.275 planus; adolescents <0.30 planus | Population-specific; standing-AHI reliability is weaker (ICC 0.674–0.789) |
| **Normalized truncated navicular height (NTNH)** | Navicular height / truncated foot length | **≤0.195 = flatfoot** (children/adolescents, validated against X-ray) | Aboelnasr et al. Adult cutoffs not established |
| **Navicular drop (ND)** | Seated (neutral) navicular height − relaxed standing height | 5–9 mm normal; **≥10 mm excessive**; historical upper limits 10 (Mueller), 13 (Beckett), 15 mm (Brody) | Nielsen et al. 2009: dynamic ND rises with foot length (+0.40 mm per 10 mm in men, +0.31 in women); 95% upper limit 7.25–9.50 mm (men) and 7.8–10 mm (women) for 22–28 cm feet. Implement a length- and sex-adjusted option |
| **Foot Posture Index (FPI-6)** | 6 observational items, −2 to +2 each | ≥6 pronated (used as a trial inclusion criterion); Redmond normative bands 0–5 normal, 6–9 pronated, ≥10 highly pronated | Bands from prior knowledge; voice-guidable but subjective |
| **Feiss line** | Navicular position relative to the medial malleolus → 1st MTP line | Qualitative grading (1st–3rd degree) | **No validated numeric cutoff found;** show as qualitative |
| **Calcaneal inclination (X-ray)** | Radiographic angle | **<18° = pes planus** | Labeling rule for the Pesplanus dataset |

**Interpreter design:**
1. Compute every index the user's inputs allow.
2. Show each result with its cutoff and citation.
3. Report agreement ("3 of 4 indices suggest flat arch") instead of one verdict.

The indices are known to disagree, and none of them is a diagnosis.

### G. Pressure-heatmap arch classification algorithms

- **Geometric baseline (what you already have):** segment the footprint from the pressure map with a threshold above noise. Then remove the toes, split into thirds along the principal axis, and compute AI, CSI and Staheli. This is fully explainable and fits the "cite everything" story.
- **Deep learning:**
  - The Frontiers 2023 study combined YOLO-v5 midfoot localization with ResNet-50 multilabel classification on 1,573 images. Its Grad-CAM maps highlighted the metatarsal and midfoot regions.
  - ViT, CNN–ViT ensembles and CNN-SVM pipelines exist for the X-ray set (Gül 2023; *J Clin Med* 2024; *Diagnostics* 2025).
  - **I did not confirm public GitHub code for these papers.** A ResNet-18 or MobileNetV3 fine-tuned on Zenodo 14621923 and exported with `coremltools` is a realistic weekend replacement.
- **Statistical:** PAPPI (PLOS ONE 2020) does personalized statistical parametric mapping on CAD WALK and flags abnormal regional pressures, including the pes-planus midfoot pattern.

### H. Low-cost orthotics: molds, printing, recycled material, evidence

- **Capture options:** (1) phone scan of the plantar surface; (2) foam impression box (scan the box impression with Object Capture, then invert); (3) plaster slipper cast. With a foam box, take semi-weight-bearing impressions in subtalar neutral. Scanning the foam gives a clean negative that is easy to photograph.
- **Printing:** TPU 95A with gyroid infill. Use variable density: firmer under the medial arch, softer under the heel and metatarsal heads. Use PETG only for a rigid shell or arch post.
- **Recycled filaments:**
  - **Recreus Reciflex:** 100% recycled TPU from footwear-industry waste, Shore 96A–98A. A good story fit.
  - **GreenGate3D:** 100% recycled PETG, USA.
  - **IC3D R-PETG:** 100% recycled, about $32.99/kg.
  - **taulman3D Enviro PETG.**
  - **BigRep rPETG.**
  - **Recyclers:** RepRapable Recyclebot (GPL, HardwareX 2018); Precious Plastic extruder (open source); Artme3D MK2 (partly open kit); Filabot EX6 (proprietary, professional).
- **Evidence (3D-printed vs conventional):**
  - RCT, Siriraj Hospital (ASEAN J Rehabil Med): 3D-printed vs conventional custom insoles for flat feet. Insole deformation was similar in both groups.
  - RCT, 63 patients (*Am J Phys Med Rehabil* 2024, PMID 38958259): 3D-printed insoles cut VAS pain significantly at 4 weeks (P < 0.001); prefabricated insoles did not.
  - 12 men with flexible flatfoot (PMID 39330623): both conventional and 3D-printed orthoses reduced dynamic navicular drop and peak rearfoot eversion compared with a flat insole.
  - A 2024/25 review (PMC11831857) reports greater comfort with 3D-printed insoles, but only 4 studies qualified.
  - **Bottom line:** 3D-printed insoles perform about as well as conventional custom ones in small, short trials. Long-term data are thin.

### I. Pressure-mat hardware (pitch / future work)

- **DIY Velostat matrices:**
  - **WiReSens Toolkit** (MIT, arXiv 2412.00247): wireless readout for up to 32×32 Velostat arrays, with visualization software.
  - Kobakant's Arduino matrix tutorial.
  - Instructables "O-mat" (15×15).
  - `haardhiko/velostat-pressure-viz` (ESP32 + JS visualizer for shoe soles).
  - A validated 16×16 Velostat mat (32×32 cm, 7 mm cells, 10 Hz; IJERPH 2021, 10.3390/ijerph18115958) for centre-of-pressure measurement.
- **Three.js demo:** I found no ready-made foot-pressure three.js demo. Build one: map a 32×32 (or 48-sensor insole) grid onto a `PlaneGeometry` or the insole mesh. Set vertex colours with a colour-blind-safe map (viridis/cividis) and displace vertices by pressure. Drive it with MUN104's mean maps, Zenodo 14621923 images, or the 48-FSR insole time series.

### J. Accessibility and Grok voice

- **xAI Grok voice:**
  - The Voice Agent API launched at **$0.05/min**. It is "compatible with the OpenAI Realtime API specification" and has an xAI LiveKit plugin.
  - **Grok Voice 3.0 is the current flagship.** Unite.AI reported on Oct 14, 2026 that "xAI announced Grok Voice 3.0 on October 14, 2026 ... at $0.08 per minute, or $4.80 per hour, the same price as Grok Voice 2.0," and that "agents using grok-voice-latest have been switched over automatically." xAI's pricing also lists $0.004 per text input. It streams audio both ways over WebSocket and does tool calling.
  - One blog calls the company "SpaceXSI (formerly xAI)." I could not confirm that rename from a primary source.
  - **Integration:** never ship the API key in the app. Run a tiny relay (e.g., Cloudflare Worker) that opens or authorizes sessions. Define tools such as `start_timer`, `log_measurement(name, mm)` and `next_test_step` so Grok can drive the flow while measurements stay on-device.
  - **Offline/privacy fallback:** `AVSpeechSynthesizer` plus on-device speech recognition.
- **Apple accessibility APIs:**
  - VoiceOver labels and hints on every control, plus `accessibilityValue` for live measurements.
  - Dynamic Type.
  - Respect `UIAccessibility.shouldDifferentiateWithoutColor` with patterns or labels on heatmaps.
  - Default to viridis/cividis palettes.
  - Haptics (`UIImpactFeedbackGenerator`) for "hold still" and "capture done."
  - Large-target capture buttons and audio progress cues for Object Capture.
- **Voice-guidable at-home tests:**
  - Wet footprint test (feeds AI/CSI/Staheli via a photo of the print on paper).
  - Navicular drop (≥10 mm).
  - Too-many-toes sign.
  - Jack's (great-toe extension) test: arch reappears = flexible flatfoot.
  - Single-leg heel raise: heel inverts and the arch forms = flexible, functioning tibialis posterior.

  The last three are qualitative clinical signs. Present results as "screening, see a clinician if painful." Have the voice script tell users to hold a chair for balance tests.

### K. Space connection (cite these)

- **Lowrey CR, Perry SD, Strzalkowski NDJ, Williams DR, Wood SJ, Bent LR, "Selective skin sensitivity changes and sensory reweighting following short-duration space flight," *J Appl Physiol* 2014;116(6):683–692 (doi:10.1152/japplphysiol.01200.2013):**
  - Measured vibration perception at the great toe, fifth metatarsal and heel in **11 astronauts** after **12–16-day** Shuttle/ISS missions.
  - **6 showed hypersensitivity**, significantly increased sensitivity to 250 Hz at the heel.
  - This is the Canadian Space Agency's **Hypersole** experiment (PI Leah Bent, University of Guelph). It was prompted by astronaut Dave Williams' foot tingling after his 1998 Columbia flight. The CSA Hypersole page states that "eleven astronauts participated," that data were collected "during four Space Shuttle missions between 2010 and 2011," and that "the astronauts with increased sensitivity had more problems balancing their weight correctly."
- **Layne CS et al., "The use of in-flight foot pressure as a countermeasure to neuromuscular degradation," *Acta Astronautica* 42:231–246 (1998):** foot-pressure boots restored the preparatory leg-muscle activation that microgravity removes.
- **Layne CS & Forth KE, "Plantar stimulation as a possible countermeasure to microgravity-induced neuromotor degradation," *Aviat Space Environ Med* 79:787–794 (2008).**
- **Kyparos et al., *J Appl Physiol* (2005):** with NASA JSC co-authors, dynamic foot stimulation (an air-bladder boot) reduced soleus atrophy in hindlimb-unloaded rats.
- **NASA "Ergonomic Evaluation of the Foot Restraint Equipment Device (FRED)":** KC-135 flights, July 22–23, 1998; Whitmore et al. with F. Mount, NASA JSC; NTRS 20000026310. Microgravity workstation restraint research.
- **NASA NTRS 20220019245, "Gecko Mobility Aids for a Common Habitat Architecture" (2023 HRP IWS):** notes ISS crew "risks of breaking ankles and wrists when using handrails." It proposes gecko-gripper uniforms to replace handrails and foot restraints.
- **Skin review:** "Effects of Spaceflight on Human Skin," *Skin Pharmacol Physiol* 34(5):239. Notes that "foot calluses simply float" and must be handled by ISS ventilation.
- **"Baby feet":**
  - Scott Kelly (Reddit AMA via Space.com): calluses fall off and the soles become "very soft like newborn baby feet." The tops of the feet develop "rough alligator skin" from foot rails.
  - Leroy Chiao (NewsNation): "you kind of have baby feet when you come back."
  - Baylor College of Medicine's space-medicine page agrees.
  - **No peer-reviewed measurement of callus loss was found.** Label it anecdotal.
- **Pitch angle:** astronauts use the *tops* of their feet as anchors (foot loops, FRED). Their soles lose load and recalibrate their sensitivity. That links plantar loading, sensation and balance, which is exactly what a pressure-mapping insole measures.

---

## Recommendations (what to build this weekend)

1. **Data pull (first hour):**
   - Script the Zenodo API for record 10360304 and check every MD5.
   - Download Zenodo 14621923, the Pesplanus set from Mendeley, and one CAD WALK record.
   - Submit the Foot3D and SynFoot Google Forms now, in case links arrive.
2. **Tape Measure Interpreter:** implement the section F table as pure Swift with citations shown in the UI. Add a length/sex-adjusted navicular-drop option (Nielsen 2009).
3. **Footprint/pressure classifier:**
   - Keep the geometric AI/CSI/Staheli as the primary output.
   - Fine-tune MobileNetV3 on Zenodo 14621923 (5-class, or collapse to flat/normal/high). Export to Core ML and show it as a "second opinion."
   - Report a held-out confusion matrix honestly.
4. **3D capture:**
   - Object Capture on LiDAR iPhones → USDZ/OBJ → measure in-app: length, ball width, dorsum height at 50% length, AHI.
   - On non-LiDAR phones: a photo on an A4 sheet plus MediaPipe/RTMW heel and toe keypoints for length, and Depth Anything V2 Small for a rough arch profile.
   - Validate your mesh-measurement code on the Schuster scans first.
5. **Insole generator:** take the plantar surface from the scan (or the foam-box scan). Offset it, add a medial arch post sized by AHI deficit, and export STL/3MF for TPU gyroid printing. Everything is saved in the user's Files.
6. **Demo extras:** a three.js heatmap driven by the 48-sensor insole dataset; Grok voice guiding the navicular drop and wet-footprint tests; and a slide on the Hypersole and Layne studies.

## Caveats

- **No dataset here links phone images or scans to clinical flat-foot diagnoses.** Any "accuracy" you quote for the full pipeline would be unvalidated. Frame the app as screening and education, not diagnosis.
- **Licenses still unconfirmed:** CAD WALK, StepUP-P150, the Zenodo alignment and insole sets, the Kaggle/Mendeley X-rays, FOUND, and Depth Pro's Hugging Face weights. Check each record's license field before redistributing.
- **Label quality:** Zenodo 14621923's labels come from a shoe-store scanner workflow with undocumented criteria. The X-ray labels are radiologist-grade but use a different modality.
- **Cutoffs depend on population** (children vs adults vs older adults; AHI varies by study). Show the source population next to each result.
- **Integrity:** I verified repository listings and checksums, not file contents. Run MD5 checks and open a sample of meshes (e.g., `trimesh.load`) before training.
- **Fast-moving facts:** Grok Voice pricing and versions changed within days of this report (Oct 2026). Recheck x.ai/api/voice before the demo.