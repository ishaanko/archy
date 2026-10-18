import type { Grid } from "./pressure"

/** MUN104 mean peak pressure of 104 healthy adults (Pataky et al. 2011), left foot, kPa.
 *  Row 0 = heel, last row = toes, columns grow medially. */
export interface Template {
  rows: number
  cols: number
  data: number[][]
}

// The template's contact bounding box (rows 4-57, columns 3-22) is fitted to the generic insole outline.
const ROW_RANGE = [4, 57] as const
const COL_CENTER = 13
const Y_RANGE = [-14, 236] as const // mm, contact extent inside the outline
const X_CENTER = 5 // mm

const MM_PER_PX = (Y_RANGE[1] - Y_RANGE[0]) / (ROW_RANGE[1] - ROW_RANGE[0] + 1)

/** Template pressure (kPa) at a point of the canonical foot frame, bilinear. */
export function templateAt(t: Template, x: number, y: number): number {
  const fr = (y - Y_RANGE[0]) / MM_PER_PX + ROW_RANGE[0] - 0.5
  const fc = (x - X_CENTER) / MM_PER_PX + COL_CENTER - 0.5
  const r = Math.floor(fr), c = Math.floor(fc), tr = fr - r, tc = fc - c
  const at = (i: number, j: number) => (i < 0 || j < 0 || i >= t.rows || j >= t.cols ? 0 : t.data[i][j])
  return at(r, c) * (1 - tr) * (1 - tc) + at(r + 1, c) * tr * (1 - tc) + at(r, c + 1) * (1 - tr) * tc + at(r + 1, c + 1) * tr * tc
}

/** Resamples the template onto a pressure grid (outside cells included; callers mask). */
export function templateOnGrid(t: Template, grid: Grid): Float32Array {
  const out = new Float32Array(grid.nx * grid.ny)
  for (let j = 0; j < grid.ny; j++)
    for (let i = 0; i < grid.nx; i++)
      if (grid.mask[j * grid.nx + i]) out[j * grid.nx + i] = templateAt(t, grid.x0 + (i + 0.5) * grid.cell, grid.y0 + (j + 0.5) * grid.cell)
  return out
}

/** Difference of load shares: peak / sum(peak) - template / sum(template) over the masked cells.
 *  Positive = this foot carries a larger share of load there than the healthy population. */
export function differenceMap(grid: Grid, peak: Float32Array, template: Float32Array): Float32Array {
  let sp = 0, st = 0
  for (let k = 0; k < peak.length; k++)
    if (grid.mask[k]) {
      sp += peak[k]
      st += template[k]
    }
  const out = new Float32Array(peak.length)
  if (sp > 0 && st > 0) for (let k = 0; k < peak.length; k++) if (grid.mask[k]) out[k] = peak[k] / sp - template[k] / st
  return out
}
