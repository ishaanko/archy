// Headless sandbox export: bun sim/scripts/export-sandbox-stl.ts [outDir]
// Runs the sandbox's static path (standing field -> 6 FSRs -> interpolation) through the shared insoleFromPeak for
// Flat/Typical/High arch, with the real map and the sensors' map, and writes archy-insole-<preset>-<real|sensors>.stl.
import { readFileSync, writeFileSync } from "node:fs"
import { insoleFromPeak } from "../src/core/insoleFromPeak"
import { footOutline } from "../src/core/outline"
import { createPressureModel, interpolate, SPARSE_KERNEL } from "../src/core/pressure"
import { toBinaryStl } from "../src/core/stl"
import { SENSOR_POSITIONS } from "../src/hardware"
import { DEFAULT_POSE, standingField } from "../src/sandbox/field"
import { BOARDS, readSensors } from "../src/sandbox/fsr"

const out = process.argv[2] ?? "/tmp"
const template = JSON.parse(readFileSync(new URL("../public/data/mun104.json", import.meta.url), "utf8"))
const outline = footOutline()
const sensors = SENSOR_POSITIONS.map((p, i) => ({ ...p, gain: 1 + 0.1 * Math.sin(i * 7.13 + 1.7) }))
const model = createPressureModel(sensors, outline, SPARSE_KERNEL)
const { grid } = model

for (const [preset, arch] of [["flat", 0], ["typical", 0.5], ["high", 1]] as const) {
  const real = standingField(grid, template, { ...DEFAULT_POSE, arch })
  const kPa = Float32Array.from(readSensors(grid, real, sensors, BOARDS.uno), (r) => r.seenKPa)
  const seen = interpolate(model, kPa, 0, new Float32Array(real.length))
  for (const [kind, map] of [["real", real], ["sensors", seen]] as const) {
    const { mesh, indices } = insoleFromPeak(outline, grid, map)
    const file = `${out}/archy-insole-${preset}-${kind}.stl`
    writeFileSync(file, Buffer.from(toBinaryStl(mesh)))
    console.log(preset, kind, "AI", indices?.archIndex.toFixed(3), "arch", mesh.archHeight.toFixed(1), "mm", file)
  }
}
