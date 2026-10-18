import { inside } from "./outline"
import type { Point, Trial } from "./types"

/** Regular dense grid. Cell (i, j) is centered at (x0 + (i + .5) * cell, y0 + (j + .5) * cell); index = j * nx + i. */
export interface Grid {
  nx: number
  ny: number
  cell: number
  x0: number
  y0: number
  /** 1 inside the insole outline. */
  mask: Uint8Array
}

/** Precomputed sparse-to-dense interpolation: dense = weights * sensors for the cells inside the outline. */
export interface PressureModel {
  grid: Grid
  nSensors: number
  cells: Int32Array
  weights: Float32Array
}

const SIGMA = 11 // mm, Gaussian kernel width (about 0.6 sensor spacing)
const FADE_DIST = 20 // mm, cells farther than this from every sensor fade toward zero

/** Builds the Gaussian-RBF interpolator (normalized weights with a fade term, so unsensed areas decay to 0). */
export function createPressureModel(sensors: readonly Point[], outline: readonly Point[], cell = 2.5): PressureModel {
  const xs = outline.map((p) => p.x), ys = outline.map((p) => p.y)
  const x0 = Math.min(...xs) - cell, y0 = Math.min(...ys) - cell
  const nx = Math.ceil((Math.max(...xs) + cell - x0) / cell), ny = Math.ceil((Math.max(...ys) + cell - y0) / cell)
  const mask = new Uint8Array(nx * ny)
  const cellList: number[] = []
  for (let j = 0; j < ny; j++)
    for (let i = 0; i < nx; i++)
      if (inside(outline, x0 + (i + 0.5) * cell, y0 + (j + 0.5) * cell)) {
        mask[j * nx + i] = 1
        cellList.push(j * nx + i)
      }
  const cells = Int32Array.from(cellList)
  const n = sensors.length
  const weights = new Float32Array(cells.length * n)
  const w0 = Math.exp(-(FADE_DIST * FADE_DIST) / (2 * SIGMA * SIGMA))
  cells.forEach((c, k) => {
    const cx = x0 + ((c % nx) + 0.5) * cell, cy = y0 + (Math.floor(c / nx) + 0.5) * cell
    let sum = w0
    for (let s = 0; s < n; s++) {
      const d2 = (cx - sensors[s].x) ** 2 + (cy - sensors[s].y) ** 2
      const w = Math.exp(-d2 / (2 * SIGMA * SIGMA))
      weights[k * n + s] = w
      sum += w
    }
    for (let s = 0; s < n; s++) weights[k * n + s] /= sum
  })
  return { grid: { nx, ny, cell, x0, y0, mask }, nSensors: n, cells, weights }
}

/** Interpolates one sensor reading (length nSensors, starting at `offset`) into `out` (grid-sized, outside cells set to 0). */
export function interpolate(model: PressureModel, reading: Float32Array, offset: number, out: Float32Array): Float32Array {
  const { cells, weights, nSensors: n } = model
  out.fill(0)
  for (let k = 0; k < cells.length; k++) {
    let v = 0
    for (let s = 0; s < n; s++) v += weights[k * n + s] * reading[offset + s]
    out[cells[k]] = v
  }
  return out
}

/** Dense maps for every frame, as one nFrames x gridSize array. */
export function frameMaps(model: PressureModel, trial: Trial): Float32Array {
  const size = model.grid.nx * model.grid.ny
  const out = new Float32Array(trial.nFrames * size)
  const tmp = new Float32Array(size)
  for (let f = 0; f < trial.nFrames; f++) {
    interpolate(model, trial.frames, f * model.nSensors, tmp)
    out.set(tmp, f * size)
  }
  return out
}

/** Per-cell maximum over all frame maps. */
export function peakMap(model: PressureModel, maps: Float32Array, nFrames: number): Float32Array {
  const size = model.grid.nx * model.grid.ny
  const peak = new Float32Array(size)
  for (let f = 0; f < nFrames; f++)
    for (let c = 0; c < size; c++) peak[c] = Math.max(peak[c], maps[f * size + c])
  return peak
}

/** Center of pressure per frame as [x0, y0, x1, y1, ...]; NaN when the frame carries no load. */
export function copTrajectory(model: PressureModel, maps: Float32Array, nFrames: number): Float32Array {
  const { grid } = model
  const size = grid.nx * grid.ny
  const out = new Float32Array(nFrames * 2)
  for (let f = 0; f < nFrames; f++) {
    let sw = 0, sx = 0, sy = 0
    for (const c of model.cells) {
      const w = maps[f * size + c]
      sw += w
      sx += w * (grid.x0 + ((c % grid.nx) + 0.5) * grid.cell)
      sy += w * (grid.y0 + (Math.floor(c / grid.nx) + 0.5) * grid.cell)
    }
    out[f * 2] = sw > 1e-3 ? sx / sw : NaN
    out[f * 2 + 1] = sw > 1e-3 ? sy / sw : NaN
  }
  return out
}

/** Bilinear lookup of a grid-sized map at (x, y) in mm. */
export function sampleGrid(grid: Grid, map: Float32Array, x: number, y: number): number {
  const fx = (x - grid.x0) / grid.cell - 0.5, fy = (y - grid.y0) / grid.cell - 0.5
  const i = Math.floor(fx), j = Math.floor(fy), tx = fx - i, ty = fy - j
  const at = (a: number, b: number) =>
    a < 0 || b < 0 || a >= grid.nx || b >= grid.ny ? 0 : map[b * grid.nx + a]
  return (
    at(i, j) * (1 - tx) * (1 - ty) + at(i + 1, j) * tx * (1 - ty) + at(i, j + 1) * (1 - tx) * ty + at(i + 1, j + 1) * tx * ty
  )
}
