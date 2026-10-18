"""Tidy Takata flat vs normal regional values (20 flat/'LOW' vs 21 normal women).

Usage: uv run --project datasets python datasets/analysis/takata_regions.py
Writes out/takata_regions.csv: one row per (metric, region) with group means/SDs, Welch t-test
and Cohen's d. MAXP = peak pressure, CA = contact area, GC = gait-cycle phase times; units are
assumed N/cm2, cm2, ms (the workbook states no units).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats

SRC = Path(__file__).resolve().parents[1] / "raw/mendeley-vv3zgwwpk3/data on foot and plantar pressure and gait cycle.xlsx"
OUT = Path(__file__).resolve().parent / "out"
UNITS = {"MAXP": "N/cm2", "CA": "cm2", "GC": "ms"}


def tidy() -> pd.DataFrame:
    rows = []
    for sheet in ("MAXP", "CA", "GC"):
        raw = pd.read_excel(SRC, sheet_name=sheet, header=None)
        regions = raw.iloc[0].ffill()  # region name sits over its LOW column only
        groups = raw.iloc[1]
        body = raw.iloc[2:]
        for col in range(1, raw.shape[1], 2):
            flat = pd.to_numeric(body[col], errors="coerce").dropna().to_numpy()
            norm = pd.to_numeric(body[col + 1], errors="coerce").dropna().to_numpy()
            assert groups[col] == "LOW" and groups[col + 1] == "NORMAL"
            t = stats.ttest_ind(flat, norm, equal_var=False)
            pooled = np.sqrt(((len(flat) - 1) * flat.var(ddof=1) + (len(norm) - 1) * norm.var(ddof=1)) / (len(flat) + len(norm) - 2))
            rows.append({
                "metric": sheet, "unit": UNITS[sheet], "region": regions[col],
                "n_flat": len(flat), "n_normal": len(norm),
                "flat_mean": flat.mean(), "flat_sd": flat.std(ddof=1),
                "normal_mean": norm.mean(), "normal_sd": norm.std(ddof=1),
                "pct_diff": 100 * (flat.mean() - norm.mean()) / norm.mean(),
                "cohens_d": (flat.mean() - norm.mean()) / pooled, "welch_p": t.pvalue,
            })
    return pd.DataFrame(rows)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    df = tidy()
    df.round(4).to_csv(OUT / "takata_regions.csv", index=False)
    print(df.round(3).to_string())
