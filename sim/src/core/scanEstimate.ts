import { archRidge, buildInsole, type InsoleLayout, type InsoleMesh } from "./insole"
import { footOutline, lateralEdgeX, medialEdgeX } from "./outline"
import { makeGrid, type Grid } from "./pressure"
import type { ScanResult } from "./scan"
import { archShape, gauss, PEAK_KPA, peakTime, STANCE_SECONDS } from "./synth"
import { templateAt, type Template } from "./template"

/** Everything the own-scan flow shows that is not a measurement: an insole sized from the scan, and an ESTIMATED pressure
 *  walk (never measured), before and with that insole. */
export interface ScanEstimate {
  grid: Grid
  /** Grid cells inside the insole outline. */
  cells: Int32Array
  fs: number
  nFrames: number
  /** Healthy reference (MUN104 warped onto this outline), for the difference map. */
  reference: Float32Array
  before: PressureWalk
  withInsole: PressureWalk
  mesh: InsoleMesh
  /** How much the estimated peak pressure drops with the insole, percent. */
  peakDropPercent: number
}

export interface PressureWalk {
  /** nFrames x grid size, kPa. */
  maps: Float32Array
  peak: Float32Array
}

const FS = 125
const REF_WEIGHT_KG = 70
/** Inset of the warped template from the outline edge, mm (the outline is the footprint plus a margin). */
const EDGE_INSET = 3

/** Arch support height, mm. From the AHI deficit: 6 mm at the "higher" cutoff (0.365), 8 mm more per 0.1 of AHI below it
 *  (the same slope as the footprint rule in `archHeightFor`), clamped to 4-18 mm; and never above 60% of the measured
 *  medial arch clearance, so it fits under the arch the scan actually shows. */
export function archHeightFromScan(scan: Pick<ScanResult, "ahi" | "medialArchHeight">): number {
  const fromAhi = Math.min(18, Math.max(4, 6 + 80 * (0.365 - scan.ahi)))
  return Math.max(4, Math.min(fromAhi, 0.6 * scan.medialArchHeight))
}

/** Insole feature positions for the scan's own outline (heel at y = 0). */
export function scanInsoleLayout(scan: ScanResult): InsoleLayout {
  const L = scan.length
  let cx = 0, cy = 0
  for (const p of scan.outline) (cx += p.x, cy += p.y)
  return {
    center: { x: cx / scan.outline.length, y: cy / scan.outline.length },
    archY: scan.medialArchY, archSigma: 26 * (L / 257),
    cupStart: 0.31 * L, cupEnd: 0.19 * L,
    archHeight: archHeightFromScan(scan),
  }
}

const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}

/** ILLUSTRATIVE ESTIMATE, not a measurement. Pressure is not captured by a scan, so it is modelled:
 *  1. The MUN104 healthy mean peak map is warped onto the scan outline: heel-to-toe position normalized by foot length,
 *     medial-lateral position normalized by the outline width at that row.
 *  2. Arch loading follows the AHI: at or below 0.29 the flat-foot medial midfoot load of the examples is fully added, at or
 *     above 0.39 the midfoot band is suppressed as for a high arch, linear in between (the same shapes as the examples).
 *  3. Peaks scale with body weight (180 kPa at 70 kg, as the examples), with the same stance timing as `synthTrial`.
 *  "With insole": a fraction k = 2.5% per mm of arch support (at most 30%) of the heel and forefoot load is taken off and
 *  put onto the arch support area in proportion to its ridge shape, frame by frame, so the total load is conserved.
 *  That is a rule of thumb for how contouring spreads load, not a model of tissue or a clinical result. */
export function estimateScan(scan: ScanResult, template: Template, weightKg: number): ScanEstimate {
  const outline = scan.outline
  const { grid, cellList } = makeGrid(outline)
  const cells = Int32Array.from(cellList)
  const generic = footOutline()
  const size = grid.nx * grid.ny
  const peakRef = Math.max(...template.data.flat())
  const flatness = Math.min(1, Math.max(-1, (0.34 - scan.ahi) / 0.05))
  const shaped = archShape(flatness, template, peakRef)
  const kpa = (PEAK_KPA * weightKg) / REF_WEIGHT_KG / peakRef
  const L = scan.length
  const Y0 = -14, Y1 = 236 // MUN104 contact extent in the generic frame (core/template.ts)

  const nFrames = Math.round(STANCE_SECONDS * FS)
  const maps = new Float32Array(nFrames * size)
  const reference = new Float32Array(size)
  const archMask = new Float32Array(size) // ridge shape, then normalized below
  const layout = scanInsoleLayout(scan)
  const rowEdges = new Map<number, [number, number, number, number]>()
  for (const c of cells) {
    const i = c % grid.nx, j = (c - i) / grid.nx
    const x = grid.x0 + (i + 0.5) * grid.cell, y = grid.y0 + (j + 0.5) * grid.cell
    let e = rowEdges.get(j)
    if (!e) {
      const yg = Y0 + (Math.min(1, Math.max(0, y / L))) * (Y1 - Y0)
      e = [lateralEdgeX(outline, y) + EDGE_INSET, medialEdgeX(outline, y) - EDGE_INSET, lateralEdgeX(generic, yg) + EDGE_INSET, medialEdgeX(generic, yg) - EDGE_INSET]
      rowEdges.set(j, e)
    }
    const yg = Y0 + Math.min(1, Math.max(0, y / L)) * (Y1 - Y0)
    const t = Math.min(1, Math.max(0, (x - e[0]) / Math.max(1, e[1] - e[0])))
    const xg = e[2] + t * (e[3] - e[2])
    reference[c] = templateAt(template, xg, yg)
    const peak = shaped(xg, yg) * kpa
    const tp = peakTime(yg)
    for (let f = 0; f < nFrames; f++) {
      const u = f / (nFrames - 1)
      maps[f * size + c] = peak * Math.max(0, Math.min(1, u / 0.05, (1 - u) / 0.05)) * gauss(u, tp, 0.16)
    }
    archMask[c] = archRidge(layout, medialEdgeX(outline, y), x, y)
  }
  const before = walk(maps, size, nFrames)

  const mesh = buildInsole(outline, grid, before.peak, null, "left", undefined, layout)
  const k = Math.min(0.3, 0.025 * mesh.archHeight)
  let archSum = 0
  for (const c of cells) archSum += archMask[c]
  const take = new Float32Array(size) // share of load removed at each cell
  for (const c of cells) {
    const y = grid.y0 + (Math.floor(c / grid.nx) + 0.5) * grid.cell
    const heel = 1 - smooth(0.18 * L, 0.3 * L, y)
    const fore = smooth(0.55 * L, 0.66 * L, y) * (1 - smooth(0.86 * L, 0.96 * L, y))
    take[c] = k * Math.max(heel, fore)
  }
  const out = new Float32Array(maps.length)
  for (let f = 0; f < nFrames; f++) {
    let moved = 0
    for (const c of cells) {
      const v = maps[f * size + c]
      moved += v * take[c]
      out[f * size + c] = v * (1 - take[c])
    }
    for (const c of cells) out[f * size + c] += (moved * archMask[c]) / archSum
  }
  const withInsole = walk(out, size, nFrames)
  const max = (a: Float32Array) => a.reduce((m, v) => Math.max(m, v), 0)
  return {
    grid, cells, fs: FS, nFrames, reference, before, withInsole, mesh,
    peakDropPercent: Math.max(0, Math.round(100 * (1 - max(withInsole.peak) / max(before.peak)))),
  }
}

function walk(maps: Float32Array, size: number, nFrames: number): PressureWalk {
  const peak = new Float32Array(size)
  for (let f = 0; f < nFrames; f++) for (let c = 0; c < size; c++) peak[c] = Math.max(peak[c], maps[f * size + c])
  return { maps, peak }
}
