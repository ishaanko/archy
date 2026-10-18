import type { Grid } from "../core/pressure"
import { peakTime } from "../core/synth"
import { templateAt, type Template } from "../core/template"
import type { Point } from "../core/types"

/** Foot pose controls. arch: 0 flat .. 1 high (0.5 normal). shift: -1 heel .. 1 forefoot.
 *  roll: -1 pronation (inward) .. 1 supination (outward). kg: body weight. */
export interface Pose {
  arch: number
  shift: number
  roll: number
  kg: number
}

export const DEFAULT_POSE: Pose = { arch: 0.5, shift: 0, roll: 0, kg: 70 }

/** Fingertip pushing on the insole: gaussian of radius `radius` (mm) carrying `newtons` in total. */
export interface Press extends Point {
  radius: number
  newtons: number
}

/** Two-foot standing: each foot carries half of body weight. */
const STANCE_SHARE = 0.5
/** Walking peaks above standing load. */
const WALK_PEAK = 1.3
export const WALK_SECONDS = 1.2

const gauss = (x: number, c: number, s: number) => Math.exp(-((x - c) ** 2) / (2 * s * s))
const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}
const cellX = (g: Grid, c: number) => g.x0 + ((c % g.nx) + 0.5) * g.cell
const cellY = (g: Grid, c: number) => g.y0 + (Math.floor(c / g.nx) + 0.5) * g.cell

/** Total force of a map in newtons (kPa * mm^2 = 1e-3 N). */
function totalNewtons(g: Grid, map: Float32Array): number {
  let s = 0
  for (let c = 0; c < map.length; c++) if (g.mask[c]) s += map[c]
  return s * g.cell * g.cell * 1e-3
}

/** Standing pressure field (kPa, grid-sized) for a pose, built from the MUN104 template (same recipe as core/synth.ts):
 *  low arch adds medial midfoot loading, arch > 0.5 suppresses the midfoot band; shift tilts load along the foot,
 *  roll tilts it across the foot. Rescaled so the total force equals the foot's share of body weight. */
export function standingField(g: Grid, template: Template, pose: Pose): Float32Array {
  const peakRef = Math.max(...template.data.flat())
  // The template is an average of many feet and reads slightly high-arched, so "normal" (0.5) keeps a little
  // of the medial midfoot loading; it fades out by 0.6 and the midfoot band is suppressed above 0.5.
  const flat = Math.max(0, (0.6 - pose.arch) / 0.6), high = Math.max(0, (pose.arch - 0.5) * 2)
  const out = new Float32Array(g.nx * g.ny)
  for (let c = 0; c < out.length; c++) {
    if (!g.mask[c]) continue
    const x = cellX(g, c), y = cellY(g, c)
    let v = templateAt(template, x, y)
    v += flat * 0.4 * peakRef * gauss(x, 17, 9) * gauss(y, 92, 24)
    v *= 1 - high * 0.9 * gauss(y, 92, 28)
    v *= Math.exp(pose.shift * 0.6 * ((y - 110) / 110)) * Math.exp(-pose.roll * 0.9 * ((x - 5) / 40))
    out[c] = v
  }
  const total = totalNewtons(g, out)
  const k = total > 0 ? (pose.kg * 9.81 * STANCE_SHARE) / total : 0
  for (let c = 0; c < out.length; c++) out[c] *= k
  return out
}

/** Fraction of the gait cycle (0..1) with the foot on the ground: ramps in at heel strike, out at toe off. */
export function contact(phase: number): number {
  return smooth(0, 0.05, phase) * (1 - smooth(0.82, 0.9, phase))
}

/** Writes the walking field at `phase` of the cycle into `out`: each spot is loaded when that part of the foot is
 *  (same timing as core/synth.ts). */
export function walkingField(g: Grid, stand: Float32Array, phase: number, out: Float32Array): void {
  const on = contact(phase)
  for (let c = 0; c < out.length; c++) out[c] = g.mask[c] ? stand[c] * WALK_PEAK * on * gauss(phase, peakTime(cellY(g, c)), 0.16) : 0
}

/** Adds a fingertip load to `map` in place. */
export function addPress(g: Grid, map: Float32Array, p: Press): void {
  const peak = (p.newtons / (2 * Math.PI * p.radius ** 2)) * 1000 // N/mm^2 -> kPa
  const reach = 3 * p.radius
  for (let j = Math.max(0, Math.floor((p.y - reach - g.y0) / g.cell)); j < Math.min(g.ny, Math.ceil((p.y + reach - g.y0) / g.cell)); j++)
    for (let i = Math.max(0, Math.floor((p.x - reach - g.x0) / g.cell)); i < Math.min(g.nx, Math.ceil((p.x + reach - g.x0) / g.cell)); i++) {
      const c = j * g.nx + i
      if (!g.mask[c]) continue
      const d2 = (cellX(g, c) - p.x) ** 2 + (cellY(g, c) - p.y) ** 2
      map[c] += peak * Math.exp(-d2 / (2 * p.radius ** 2))
    }
}

/** Relative L1 error of `seen` against `truth` over the insole: sum|truth - seen| / sum(truth). */
export function coverageError(g: Grid, truth: Float32Array, seen: Float32Array): number {
  let diff = 0, sum = 0
  for (let c = 0; c < truth.length; c++)
    if (g.mask[c]) {
      diff += Math.abs(truth[c] - seen[c])
      sum += truth[c]
    }
  return sum > 0 ? diff / sum : NaN
}

/** Where one more sensor would help most: the cell with the largest error that is not already within `minGap` mm of a sensor. */
export function worstSpot(g: Grid, truth: Float32Array, seen: Float32Array, sensors: readonly Point[], minGap = 12): Point | null {
  let best = -1, at: Point | null = null
  for (let c = 0; c < truth.length; c++) {
    if (!g.mask[c]) continue
    const x = cellX(g, c), y = cellY(g, c)
    if (sensors.some((s) => Math.hypot(s.x - x, s.y - y) < minGap)) continue
    const e = Math.abs(truth[c] - seen[c])
    if (e > best) {
      best = e
      at = { x, y }
    }
  }
  return at
}
