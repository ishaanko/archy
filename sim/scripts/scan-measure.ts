// Headless check of the own-scan pipeline: bun scripts/scan-measure.ts <file.stl|obj>...
// Prints the measurements and (with --outline=<file.json>) writes the insole outline for inspection.
import { readFileSync } from "node:fs"
import { analyzeScan, parseScanFile } from "../src/core/scan"

for (const path of process.argv.slice(2).filter((a) => !a.startsWith("--"))) {
  const buf = readFileSync(path)
  const t0 = performance.now()
  const r = analyzeScan(parseScanFile(path, buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength)))
  const f = r.footprint
  console.log(
    path.split("/").pop(), `${Math.round(performance.now() - t0)}ms`,
    JSON.stringify({
      side: r.side, unit: r.unitScale, len: +r.length.toFixed(1), ball: +r.ballWidth.toFixed(1), heel: +r.heelWidth.toFixed(1), dorsum: +r.dorsumHeight.toFixed(1),
      ahi: +r.ahi.toFixed(3), cls: r.ahiClass, archH: +r.medialArchHeight.toFixed(1), archY: Math.round(r.medialArchY), sole: r.soleObserved, fill: +r.fillShare.toFixed(2),
      ai: f ? +f.archIndex.toFixed(3) : null, sta: f ? +f.staheli.toFixed(2) : null, csi: f ? +f.chippauxSmirak.toFixed(0) : null,
      chk: { htr: +r.checks.heelToeRatio.toFixed(2), side: +r.checks.sideMargin.toFixed(1), ball: r.checks.ballWiderThanHeel },
    }),
  )
}
