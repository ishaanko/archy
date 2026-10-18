"""Typed registry of every dataset considered for the app, downloadable or not."""

from dataclasses import dataclass, field
from typing import Literal

SourceType = Literal["zenodo", "mendeley", "github_raw", "manual"]


@dataclass(frozen=True)
class Source:
    key: str
    title: str
    type: SourceType
    record_id: str  # Zenodo record, Mendeley dataset id, or "" for manual
    license: str  # as stated by the repository API; "unverified" for manual entries
    purpose: str  # what it is for in our app
    status: str  # human-readable fetch status / caveat
    url: str = ""
    doi: str = ""
    raw_urls: tuple[str, ...] = ()  # github_raw only: direct file URLs (no published checksum)
    large_files: tuple[str, ...] = ()  # skipped unless --include-large
    # Mendeley folders have no names in the API; map folder file-count -> label
    # (counts come from the dataset description).
    folder_labels_by_count: dict[int, str] = field(default_factory=dict)

    @property
    def dirname(self) -> str:
        return f"{self.type}-{self.record_id}"


SOURCES: tuple[Source, ...] = (
    Source(
        key="schuster-scans",
        title="Foot shape-function model data (Schuster, 100 people, PLY scans)",
        type="zenodo",
        record_id="10360304",
        doi="10.5061/dryad.g4f4qrfwt",
        license="CC0 1.0 (API: cc-zero)",
        purpose="Real 3D foot meshes: test mesh measurement code (length, width, AHI) and insole surface generation.",
        status="auto: PLY + README; treadmill_data.mat (281 MB) only with --include-large",
        large_files=("treadmill_data.mat",),
    ),
    Source(
        key="pressure-images",
        title="Plantar pressure dataset for foot health assessment (400 images, 5 classes)",
        type="zenodo",
        record_id="14621923",
        doi="10.5281/zenodo.14621923",
        license="CC BY 4.0 (API: cc-by-4.0)",
        purpose="Train/demo the pressure-heatmap arch classifier (flat / normal / high arch / heel tilt).",
        status="auto; labels are undocumented shop-scanner labels",
    ),
    Source(
        key="fsr-rectus-valgus",
        title="High-density plantar pressure, rectus vs valgus alignment (32x32 FSR CSV)",
        type="zenodo",
        record_id="19872222",
        doi="10.5281/zenodo.19872222",
        license="CC BY 4.0 (API: cc-by-4.0)",
        purpose="32x32 pressure grids for simulating a DIY FSR/Velostat mat and alignment classification.",
        status="auto; CSVs are inside a .rar, extracted with bsdtar (7zz 26.04 cannot read its RAR v6 method)",
    ),
    Source(
        key="cadwalk-healthy",
        title="CAD WALK Healthy Controls (55 adults, RSscan pressure)",
        type="zenodo",
        record_id="1265420",
        doi="10.5281/zenodo.1265420",
        license="CC BY 4.0 (API: cc-by-4.0)",
        purpose="Realistic walking pressure data to validate arch-index code on healthy feet.",
        status="auto; 124 MB, fetched in full",
    ),
    Source(
        key="cadwalk-hallux-valgus",
        title="CAD WALK Hallux Valgus, pre-surgery (50 patients)",
        type="zenodo",
        record_id="3406523",
        doi="10.5281/zenodo.3406523",
        license="CC BY 4.0 (API: cc-by-4.0)",
        purpose="Pathological pressure data (about 35% show a pes-planus midfoot pattern) as a realistic test set.",
        status="auto; 158 MB, fetched in full",
    ),
    Source(
        key="pesplanus-xray",
        title="Pesplanus Dataset (weight-bearing lateral X-rays, 842 images)",
        type="mendeley",
        record_id="sss89tjddy",
        doi="10.17632/sss89tjddy.1",
        license="CC BY 4.0 (API: data_licence)",
        purpose="Radiologist-labeled flat vs normal (calcaneal inclination <18 deg); validates the X-ray ground-truth idea.",
        status="auto via Mendeley public API (SHA-256 per file); class folders are unnamed, labeled by file count",
        url="https://data.mendeley.com/datasets/sss89tjddy/1",
        folder_labels_by_count={402: "pes_planus", 440: "normal"},
    ),
    Source(
        key="takata-flatfoot",
        title="Takata flatfoot plantar pressure and gait cycle (20 flat + 21 normal women)",
        type="mendeley",
        record_id="vv3zgwwpk3",
        doi="10.17632/vv3zgwwpk3.1",
        license="CC BY 4.0 (API: data_licence)",
        purpose="Regional pressure / contact area, flat vs normal: sanity check for midfoot pressure cutoffs.",
        status="auto via Mendeley public API (single xlsx)",
        url="https://data.mendeley.com/datasets/vv3zgwwpk3/1",
    ),
    Source(
        key="mun104",
        title="MUN104 mean plantar pressure template (104 healthy subjects, L/R)",
        type="github_raw",
        record_id="0todd0000-mun104",
        license="MIT (GitHub API: mit)",
        purpose="Realistic mean pressure map to drive the three.js mat / insole heatmap demo. Pataky et al. 2011, Gait & Posture 33(3):418-422.",
        status="auto: direct GitHub raw download; no published checksum, sha256 recorded on first fetch",
        url="https://github.com/0todd0000/mun104",
        raw_urls=(
            "https://github.com/0todd0000/mun104/raw/master/MUN104.csv.zip",
            "https://github.com/0todd0000/mun104/raw/master/MUN104.h5.zip",
        ),
    ),
    # Manual / gated: no download.
    Source(
        key="kaggle-photos-of-foots",
        title="Photos of Foots (Aydemir, 6,944 photos, no arch labels)",
        type="manual",
        record_id="",
        license="unverified (check Kaggle page)",
        purpose="Fine-tune foot segmentation / keypoints; no clinical labels.",
        status="manual: needs Kaggle login. `kaggle datasets download emrahaydemr/photos-of-foots`",
        url="https://www.kaggle.com/datasets/emrahaydemr/photos-of-foots",
    ),
    Source(
        key="kaggle-pesplanus",
        title="Pesplanus two-class dataset (Kaggle mirror of the Mendeley X-rays)",
        type="manual",
        record_id="",
        license="unverified",
        purpose="Redundant: use pesplanus-xray from Mendeley instead.",
        status="manual, not needed (Mendeley copy is fetched automatically)",
        url="https://www.kaggle.com/datasets/suleyman32/pesplanus-two-class-dataset",
    ),
    Source(
        key="foot3d",
        title="Foot3D (Boyne et al., 118 meshes + 474 multiview images)",
        type="manual",
        record_id="",
        license="MIT for the repo; data terms unverified",
        purpose="Benchmark for FOCUS/FOUND foot reconstruction and a second set of real foot meshes.",
        status="gated: Google Form linked from the repo, link arrives by email (may take a day or more)",
        url="https://github.com/OllieBoyne/Foot3D",
    ),
    Source(
        key="synfoot",
        title="SynFoot (synthetic RGB with normals, masks, keypoints; 50K v1, 100K v2)",
        type="manual",
        record_id="",
        license="MIT for the repo; data terms unverified",
        purpose="Train foot segmentation / normal estimation without real photos.",
        status="gated: Google Form linked from the repo; download size not published",
        url="https://github.com/OllieBoyne/SynFoot",
    ),
    Source(
        key="stepup-p150",
        title="UNB StepUP-P150 (150 people, >200,000 footsteps, 4 sensors/cm2)",
        type="manual",
        record_id="",
        doi="10.20383/103.01285",
        license="unverified (check FRDR record)",
        purpose="Large unlabeled pressure corpus; no arch labels. Too large for this weekend.",
        status="manual: very large (>200k steps; check FRDR for size). Not downloaded",
        url="https://doi.org/10.20383/103.01285",
    ),
    Source(
        key="frontiers-2023",
        title="Frontiers 2023 foot-type DL dataset (1,573 pressure images, 125 people)",
        type="manual",
        record_id="",
        license="n/a",
        purpose="Flat vs normal pressure images confirmed by X-ray; would be the best pressure set.",
        status="request-only: not posted publicly; email the corresponding author of PMC10519788",
        url="https://pmc.ncbi.nlm.nih.gov/articles/PMC10519788/",
    ),
)

BY_KEY: dict[str, Source] = {s.key: s for s in SOURCES}
