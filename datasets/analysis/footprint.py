"""Footprint arch indices (Cavanagh AI, Staheli, Chippaux-Smirak) from a 2D contact image.

Reference implementation intended to be ported to Swift. Pure numpy/scipy, one public
function: `footprint_indices`. Conventions:

* Input is a 2D array (pressure, or a 0/1 contact mask). Row index runs heel -> toe
  (row 0 is the heel side). Column direction and left/right do not matter.
* Pixel size is `(dy, dx)` in mm (rows, cols); the image is resampled to square pixels.

Algorithm
1. Contact = pixels > `threshold_frac` * max(img); drop speckle components (< 10% of the largest).
2. Principal axis (PCA of contact pixels) gives the foot axis; signed so it points heel -> toe.
3. Toes are removed: only the proximal (1 - `toe_frac`) of the print length is kept
   (default 20%; toe imprints are ~18-25% of print length, a fixed approximation).
4. The toeless print is split into rear/mid/fore thirds along the axis.
5. Indices:
   * AI (Cavanagh & Rodgers 1987, J Biomech 20:547) = mid-third area / toeless total area.
     > 0.26 flat, < 0.21 high arch (quartile cutoffs from 107 young adults, ink prints).
   * Staheli (Staheli 1987) = min midfoot width / max heel width. > 0.89 flat (<0.44 cavus).
   * CSI (Forriol & Pascual 1990) = min midfoot width / max forefoot width. > 0.45 flat
     (children; adult cutoffs vary, e.g. 0.627 in some cohorts).
   Width of a slice = contact area in that slice / slice thickness (gaps do not count).

Other published cutoffs used by the callers (not computed here):
   AHI (Butler 2008): dorsum height at 50% foot length / truncated foot length, standing
   mean 0.340 +/- 0.030, <= 0.315 planus. Navicular drop >= 10 mm excessive (Mueller 1993).
All cutoffs are population specific and the indices disagree; none is a diagnosis.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass

import numpy as np
from scipy import ndimage

AI_FLAT, AI_HIGH = 0.26, 0.21
STAHELI_FLAT, STAHELI_CAVUS = 0.89, 0.44
CSI_FLAT = 0.45
AHI_MEAN, AHI_SD, AHI_PLANUS = 0.340, 0.030, 0.315
ARCH_DROP_EXCESSIVE_MM = 10.0

_SLICE_MM = 4.0  # thickness of width-profile slices


@dataclass(frozen=True)
class FootprintIndices:
    ai: float
    staheli: float
    csi: float
    length_mm: float  # full print length incl. toes (or the caller-supplied foot length)
    area_mm2: float  # toeless contact area
    heel_width_mm: float
    mid_width_mm: float
    fore_width_mm: float

    def flat_flags(self) -> dict[str, bool]:
        """Which indices call this print flat, at the cutoffs above."""
        return {
            "ai": bool(self.ai > AI_FLAT),
            "staheli": bool(self.staheli > STAHELI_FLAT),
            "csi": bool(self.csi > CSI_FLAT),
        }

    def as_dict(self) -> dict[str, float]:
        return asdict(self)


def _clean_mask(mask: np.ndarray) -> np.ndarray:
    labels, n = ndimage.label(mask)
    if n <= 1:
        return mask
    sizes = ndimage.sum(mask, labels, index=np.arange(1, n + 1))
    keep = np.flatnonzero(sizes >= 0.10 * sizes.max()) + 1
    return np.isin(labels, keep)


def footprint_indices(
    img: np.ndarray,
    px_mm: tuple[float, float] = (1.0, 1.0),
    *,
    threshold_frac: float = 0.05,
    toe_frac: float = 0.20,
    align: bool = True,
    length_mm: float | None = None,
) -> FootprintIndices | None:
    """Compute AI/Staheli/CSI. Returns None when the print is empty or degenerate.

    `length_mm`: true foot length (heel to longest toe) if known, so the toe cut does not
    depend on whether the toes touched the ground. `align=False` skips PCA rotation and
    uses the image rows as the foot axis (for already-aligned rasters).
    """
    img = np.nan_to_num(np.asarray(img, dtype=float))
    if img.max() <= 0:
        return None
    step = min(px_mm)
    zoom = (px_mm[0] / step, px_mm[1] / step)
    thr = threshold_frac * img.max()
    iso = ndimage.zoom(img, zoom, order=1) if zoom != (1.0, 1.0) else img
    mask = _clean_mask(iso > thr)
    ys, xs = np.nonzero(mask)
    if len(ys) < 30:
        return None
    pts = np.c_[ys, xs].astype(float) * step  # (row, col) in mm
    centered = pts - pts.mean(0)
    if align:
        _, vecs = np.linalg.eigh(np.cov(centered.T))
        axis = vecs[:, 1]
        if axis[0] < 0:  # point towards increasing row = heel -> toe
            axis = -axis
    else:
        axis = np.array([1.0, 0.0])
    s = centered @ axis
    s0, s1 = s.min(), s.max()
    full = length_mm if length_mm is not None else s1 - s0
    cut = s0 + (1.0 - toe_frac) * full
    keep = s <= cut
    if keep.sum() < 30 or full < 5 * _SLICE_MM:
        return None
    s = s[keep]
    edges = np.linspace(s0, cut, 4)  # rear | mid | fore
    pixel_area = step * step

    n_slices = max(int(round((cut - s0) / _SLICE_MM)), 6)
    sl_edges = np.linspace(s0, cut, n_slices + 1)
    thickness = sl_edges[1] - sl_edges[0]
    counts, _ = np.histogram(s, bins=sl_edges)
    width = counts * pixel_area / thickness
    centers = 0.5 * (sl_edges[:-1] + sl_edges[1:])
    third = np.digitize(centers, edges[1:-1])  # 0 rear, 1 mid, 2 fore
    heel_w, mid_w, fore_w = width[third == 0].max(), width[third == 1].min(), width[third == 2].max()
    if heel_w <= 0 or fore_w <= 0:
        return None

    total = len(s) * pixel_area
    mid_area = np.count_nonzero((s >= edges[1]) & (s < edges[2])) * pixel_area
    return FootprintIndices(
        ai=mid_area / total,
        staheli=mid_w / heel_w,
        csi=mid_w / fore_w,
        length_mm=full,
        area_mm2=total,
        heel_width_mm=heel_w,
        mid_width_mm=mid_w,
        fore_width_mm=fore_w,
    )
