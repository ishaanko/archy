"""Convert the MUN104 left-foot template CSV to JSON for the web app.

Run: python3 sim/scripts/convert_mun104.py
Input:  sim/data/raw/mun104/MUN104L.csv (from MUN104.csv.zip, github.com/0todd0000/mun104, MIT)
Output: sim/public/data/mun104.json {rows, cols, data}: row 0 = heel, last row = toes, column index grows medially
        (hallux on the right for the left foot), values = mean peak pressure of 104 healthy adults, kPa.
"""
import csv
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
rows = [[int(float(v)) for v in r] for r in csv.reader(open(os.path.join(ROOT, "data", "raw", "mun104", "MUN104L.csv")))]
out = os.path.join(ROOT, "public", "data", "mun104.json")
with open(out, "w") as f:
    json.dump({"rows": len(rows), "cols": len(rows[0]), "unit": "kPa", "data": rows}, f, separators=(",", ":"))
print("wrote", out, os.path.getsize(out), "bytes", len(rows), "x", len(rows[0]), "max", max(map(max, rows)))
