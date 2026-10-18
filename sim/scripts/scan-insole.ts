// Own-scan insole for checking: bun scripts/scan-insole.ts <scan.stl> <out.stl> [weightKg]
import { readFileSync, writeFileSync } from "node:fs"
import { analyzeScan, parseScanFile } from "../src/core/scan"
import { estimateScan } from "../src/core/scanEstimate"
import { toBinaryStl } from "../src/core/stl"

const [path, out = "/tmp/archy-insole-my-scan.stl", kg = "70"] = process.argv.slice(2)
const buf = readFileSync(path)
const scan = analyzeScan(parseScanFile(path, buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength)))
const template = JSON.parse(readFileSync(new URL("../public/data/mun104.json", import.meta.url), "utf8"))
const t0 = performance.now()
const est = estimateScan(scan, template, Number(kg))
const max = (a: Float32Array) => a.reduce((m, v) => Math.max(m, v), 0)
console.log(`estimate ${Math.round(performance.now() - t0)}ms, arch ${est.mesh.archHeight.toFixed(1)} mm, peak ${max(est.before.peak).toFixed(0)} -> ${max(est.withInsole.peak).toFixed(0)} kPa (-${est.peakDropPercent}%)`)
writeFileSync(out, Buffer.from(toBinaryStl(est.mesh)))
