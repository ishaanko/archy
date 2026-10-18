"""Convert the Zenodo 21743536 insole dataset into compact JSON for the web app.

Run: uv run --with nptdms --with numpy --with openpyxl python sim/scripts/convert_insole.py
Reads sim/data/raw/ex/<participant>/Walking/{LEFT|IZQUIERDO|RIGHT}.tdms and
sim/data/raw/zip/TableS1.xlsx (sensor coordinates, cm). Writes sim/public/data/insole.json:
  sensors[side]: [{x, y}] in mm, canonical frame (x medial-positive, y heel->toe)
  trials: one representative stance per participant and side, 125 Hz, pressure in kPa.
"""
import glob
import json
import os
import re

import numpy as np
import openpyxl
from nptdms import TdmsFile

ROOT = os.path.join(os.path.dirname(__file__), "..")
RAW = os.path.join(ROOT, "data", "raw")
OUT = os.path.join(ROOT, "public", "data", "insole.json")
FS = 125  # Hz, per dataset description
AREA_MM2 = 56.25  # per-FSR area, per dataset description
KG_TO_KPA = 9.80665 / (AREA_MM2 * 1e-6) / 1000  # readings are in kg
PAD = 6  # samples kept either side of the stance


def read_layout() -> dict[str, list[dict[str, float]]]:
    wb = openpyxl.load_workbook(os.path.join(RAW, "zip", "TableS1.xlsx"))
    out: dict[str, list[dict[str, float]]] = {}
    for side, sheet in (("left", "Left Foot"), ("right", "Right Foot")):
        pts = []
        for n, _region, xy in list(wb[sheet].iter_rows(min_row=3, values_only=True)):
            x, y = (float(v) for v in re.findall(r"-?\d+\.?\d*", xy))
            pts.append((int(n), x, y))
        pts.sort()
        sign = 1.0 if side == "left" else -1.0  # canonical frame: medial = +x
        out[side] = [{"x": round(sign * x * 10, 1), "y": round((y + 20.2) * 10, 1)} for _, x, y in pts]
    return out


def read_frames(path: str) -> np.ndarray:
    """(samples, 48) kPa. Each sample is 12 consecutive rows of 4 sensors."""
    g = TdmsFile.read(path)["time"]
    rows = np.stack([g[f"Sensor {i}"][:] for i in range(1, 5)], axis=1)
    assert np.all(g["Row"][:] == np.tile(np.arange(1, 13), len(g["Row"]) // 12))
    return rows.reshape(-1, 48) * KG_TO_KPA


def best_stance(frames: np.ndarray) -> np.ndarray | None:
    """The stance whose duration and peak load are closest to the median step."""
    kernel = np.ones(5) / 5
    total = np.convolve(frames.sum(1), kernel, mode="same")
    on = total > 0.12 * np.percentile(total, 95)
    d = np.diff(on.astype(int))
    starts, ends = np.where(d == 1)[0] + 1, np.where(d == -1)[0] + 1
    if len(ends) and len(starts) and ends[0] < starts[0]:
        ends = ends[1:]
    steps = [(s, e) for s, e in zip(starts, ends) if 0.45 * FS <= e - s <= 0.9 * FS and s > PAD]
    if len(steps) < 3:
        return None
    peaks = np.array([total[s:e].max() for s, e in steps])
    s, e = steps[int(np.argmin(np.abs(peaks - np.median(peaks))))]
    return frames[s - PAD : e + PAD]


def main() -> None:
    trials = []
    for pdir in sorted(glob.glob(os.path.join(RAW, "ex", "[Pp]articipant *")), key=lambda p: int(p.split()[-1])):
        pid = int(pdir.split()[-1])
        for side, names in (("left", ("LEFT", "IZQUIERDO")), ("right", ("RIGHT",))):
            path = next((p for n in names if os.path.exists(p := os.path.join(pdir, "Walking", n + ".tdms"))), None)
            if path is None:
                continue
            frames = read_frames(path)
            stance = best_stance(frames)
            if stance is None:
                print("skip", pid, side)
                continue
            stance = np.where(stance < 0.02 * KG_TO_KPA, 0, stance)  # clip sensor noise floor
            print(pid, side, "samples", len(frames), "stance frames", len(stance), "peak kPa", int(stance.max()))
            trials.append({"participant": pid, "side": side, "frames": np.rint(stance).astype(int).tolist()})
    layout = read_layout()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump({"fs": FS, "unit": "kPa", "sensors": layout, "trials": trials}, f, separators=(",", ":"))
    print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
