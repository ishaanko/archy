import { archRidge, buildInsole, DEFAULT_INSOLE, type InsoleLayout, type InsoleMesh, type InsoleParams } from "./insole"
import { footOutline, lateralEdgeX, medialEdgeX } from "./outline"
import { SENSOR_POSITIONS } from "../hardware/layout"
import { makeGrid, sampleGrid, type Grid } from "./pressure"
import { AHI_HIGHER, AHI_LOWER, type ScanResult } from "./scan"
import { archShape, gauss, PEAK_KPA, peakTime, STANCE_SECONDS } from "./synth"
import { templateAt, type Template } from "./template"
import type { Point } from "./types"

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
  /** A plain flat insole of the same outline: what the foot stands on in the "before" view. */
  flatMesh: InsoleMesh
  /** How much the estimated peak pressure drops with the insole, percent. */
  peakDropPercent: number
  /** The 6-sensor kit's spots (hardware/layout.ts order and names) moved onto this foot's outline. */
  spots: Point[]
}

export interface PressureWalk {
  /** nFrames x grid size, kPa. */
  maps: Float32Array
  peak: Float32Array
  /** nFrames x spots, kPa: what a sensor at each spot would read (small patch average). */
  spotFrames: Float32Array
  /** Highest reading per spot over the step, kPa. */
  spotPeaks: Float32Array
}

const FS = 125
const REF_WEIGHT_KG = 70
/** Inset of the warped template from the outline edge, mm (the outline is the footprint plus a margin). */
const EDGE_INSET = 3

/** Arch support height, mm, built like a full-contact custom orthotic: fill the standing gap under the medial arch, then add
 *  the rise that would bring the arch to a typical AHI (mid-band, 0.34): (0.34 - AHI) x truncated length, since
 *  AHI = dorsum height / truncated length. Clamped to 8-25 mm. */
export function archHeightFromScan(scan: Pick<ScanResult, "ahi" | "medialArchHeight" | "truncLength">): number {
  const correction = Math.max(0, (AHI_LOWER + AHI_HIGHER) / 2 - scan.ahi) * scan.truncLength
  return Math.min(25, Math.max(8, scan.medialArchHeight + correction))
}

/** Scan insoles get a deeper heel cup than the generic one, to hold the heel over the taller arch support. */
export const SCAN_INSOLE: InsoleParams = { ...DEFAULT_INSOLE, heelCupHeight: 14 }

/** Insole feature positions for the scan's own outline (heel at y = 0). */
export function scanInsoleLayout(scan: ScanResult): InsoleLayout {
  const L = scan.length
  let cx = 0, cy = 0
  for (const p of scan.outline) (cx += p.x, cy += p.y)
  return {
    center: { x: cx / scan.outline.length, y: cy / scan.outline.length },
    archY: scan.medialArchY, archSigma: 32 * (L / 257),
    cupStart: 0.31 * L, cupEnd: 0.19 * L,
    archHeight: archHeightFromScan(scan),
  }
}

/** Generic-frame contact extent of MUN104 (core/template.ts), used to map between the generic foot and a scan. */
const Y0 = -14, Y1 = 236

/** Moves generic-frame points onto the scan outline: the inverse of the warp in `estimateScan` (heel-to-toe position by
 *  foot length, medial-lateral position by the inset row width), so a spot lands on the same part of every foot. */
function toScanFrame(scan: ScanResult, points: readonly Point[]): Point[] {
  const generic = footOutline()
  return points.map((p) => {
    const y = ((p.y - Y0) / (Y1 - Y0)) * scan.length
    const gl = lateralEdgeX(generic, p.y) + EDGE_INSET, gm = medialEdgeX(generic, p.y) - EDGE_INSET
    const sl = lateralEdgeX(scan.outline, y) + EDGE_INSET, sm = medialEdgeX(scan.outline, y) - EDGE_INSET
    return { x: sl + ((p.x - gl) / Math.max(1, gm - gl)) * (sm - sl), y }
  })
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
  const spots = toScanFrame(scan, SENSOR_POSITIONS)
  const before = walk(grid, spots, maps, nFrames)

  const mesh = buildInsole(outline, grid, before.peak, null, "left", SCAN_INSOLE, layout)
  const flatMesh = buildInsole(outline, grid, before.peak, null, "left", { ...DEFAULT_INSOLE, heelCupHeight: 0, reliefDepth: 0 }, { ...layout, archHeight: 0 })
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
  const withInsole = walk(grid, spots, out, nFrames)
  const max = (a: Float32Array) => a.reduce((m, v) => Math.max(m, v), 0)
  return {
    grid, cells, fs: FS, nFrames, reference, before, withInsole, mesh, flatMesh,
    peakDropPercent: Math.max(0, Math.round(100 * (1 - max(withInsole.peak) / max(before.peak)))),
    spots,
  }
}

const PATCH = [[0, 0], [5, 0], [-5, 0], [0, 5], [0, -5]] as const

function walk(grid: Grid, spots: readonly Point[], maps: Float32Array, nFrames: number): PressureWalk {
  const size = grid.nx * grid.ny, n = spots.length
  const peak = new Float32Array(size)
  const spotFrames = new Float32Array(nFrames * n), spotPeaks = new Float32Array(n)
  for (let f = 0; f < nFrames; f++) {
    const frame = maps.subarray(f * size, (f + 1) * size)
    for (let c = 0; c < size; c++) peak[c] = Math.max(peak[c], frame[c])
    spots.forEach((s, k) => {
      const v = PATCH.reduce((sum, [dx, dy]) => sum + sampleGrid(grid, frame, s.x + dx, s.y + dy), 0) / PATCH.length
      spotFrames[f * n + k] = v
      spotPeaks[k] = Math.max(spotPeaks[k], v)
    })
  }
  return { maps, peak, spotFrames, spotPeaks }
}
