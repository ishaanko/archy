// Headless export for checking the pipeline: bun sim/scripts/export-stl.ts <normal|flat|high arch> <out.stl> [left|right]
import { readFileSync, writeFileSync } from "node:fs"
import { computeIndices } from "../src/core/indices"
import { buildInsole } from "../src/core/insole"
import { footOutline } from "../src/core/outline"
import { createPressureModel, frameMaps, peakMap } from "../src/core/pressure"
import { toBinaryStl } from "../src/core/stl"
import { synthTrial } from "../src/core/synth"
import type { FootType, Point } from "../src/core/types"

const [type = "flat", out = "/tmp/insole.stl", side = "left"] = process.argv.slice(2)
const data: { sensors: Record<"left" | "right", Point[]> } = JSON.parse(readFileSync(new URL("../public/data/insole.json", import.meta.url), "utf8"))
const sensors = data.sensors.left
const template = JSON.parse(readFileSync(new URL("../public/data/mun104.json", import.meta.url), "utf8"))
const trial = synthTrial(type as FootType, sensors, template)
const outline = footOutline()
const model = createPressureModel(sensors, outline)
const peak = peakMap(model, frameMaps(model, trial), trial.nFrames)
const idx = computeIndices(model.grid, peak)
const mesh = buildInsole(outline, model.grid, peak, idx, side === "right" ? "right" : "left")
writeFileSync(out, Buffer.from(toBinaryStl(mesh)))
console.log(type, side, idx?.archIndex.toFixed(3), "arch", mesh.archHeight.toFixed(1), "mm,", mesh.indices.length / 3, "tris ->", out)
