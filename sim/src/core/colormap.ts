import type { Grid } from "./pressure"
import { sampleGrid } from "./pressure"

export type ColormapName = "viridis" | "cividis"

type RGB = readonly [number, number, number]

const STOPS: Record<ColormapName, readonly string[]> = {
  viridis: ["#440154", "#472d7b", "#3b528b", "#2c728e", "#21908c", "#27ad81", "#5dc863", "#aadc32", "#fde725"],
  cividis: ["#00224e", "#123570", "#3b496c", "#575d6d", "#707173", "#8a8678", "#a59c74", "#c3b369", "#e1cc55", "#fee838"],
}

const PALETTES: Record<ColormapName, readonly RGB[]> = {
  viridis: STOPS.viridis.map(hexToRgb),
  cividis: STOPS.cividis.map(hexToRgb),
}

function hexToRgb(hex: string): RGB {
  const n = parseInt(hex.slice(1), 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

/** Colormap color at t in [0, 1] (linear interpolation between perceptual-uniform stops). */
export function colormapAt(name: ColormapName, t: number): RGB {
  const stops = PALETTES[name]
  const f = (Number.isFinite(t) ? Math.min(1, Math.max(0, t)) : 0) * (stops.length - 1)
  const i = Math.min(stops.length - 2, Math.floor(f)), u = f - i
  const a = stops[i], b = stops[i + 1]
  return [a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u]
}

/** CSS linear-gradient stops for a legend bar. */
export function colormapCss(name: ColormapName): string {
  return STOPS[name].join(", ")
}

export const PATTERN_LEVELS = 6
const EMPTY: RGB = [14, 14, 14]

export interface HeatmapImage {
  width: number
  height: number
  /** RGBA, row 0 = smallest y (heel), matching texture v = 0. */
  data: Uint8ClampedArray
}

/** Pixel size of one grid cell in the heatmap texture. */
export const HEATMAP_SCALE = 5

/** Allocates the texture buffer for a grid. */
export function createHeatmapImage(grid: Grid): HeatmapImage {
  const width = grid.nx * HEATMAP_SCALE, height = grid.ny * HEATMAP_SCALE
  return { width, height, data: new Uint8ClampedArray(width * height * 4) }
}

/** Diverging blue-orange (color-vision-safe) around a near-black center, for t in [-1, 1]. */
function divergingAt(t: number): RGB {
  const a = Math.min(1, Math.abs(t))
  const end: RGB = t < 0 ? [90, 170, 255] : [255, 140, 26]
  return [14 + (end[0] - 14) * a, 14 + (end[1] - 14) * a, 14 + (end[2] - 14) * a]
}

/** Paints a map into `img`. Sequential (default): pressure / vmax in [0, 1] through the colormap. Diverging: signed
 *  difference / vmax in [-1, 1], blue negative, orange positive. With `patterns`, value bands also get contour lines and
 *  hatching (denser = larger magnitude; diverging maps hatch "/" for positive and "\" for negative) so the map reads
 *  without color (mirrors iOS shouldDifferentiateWithoutColor). */
export function paintHeatmap(
  img: HeatmapImage,
  grid: Grid,
  map: Float32Array,
  vmax: number,
  name: ColormapName,
  patterns: boolean,
  diverging = false,
  emptyColor: readonly [number, number, number] = EMPTY,
): void {
  const { width, height, data } = img
  const level = new Int8Array(width * height)
  const value = new Float32Array(width * height)
  const bands = diverging ? 3 : PATTERN_LEVELS
  for (let py = 0; py < height; py++) {
    const y = grid.y0 + ((py + 0.5) / HEATMAP_SCALE) * grid.cell
    for (let px = 0; px < width; px++) {
      const raw = sampleGrid(grid, map, grid.x0 + ((px + 0.5) / HEATMAP_SCALE) * grid.cell, y) / vmax
      const v = diverging ? Math.max(-1, Math.min(1, raw)) : Math.min(1, raw)
      const m = Math.abs(v)
      value[py * width + px] = v
      // Level -1 = empty; diverging levels are signed band numbers so the sign flips draw a contour too.
      const band = diverging ? (m < 0.08 ? -1 : m < 0.3 ? 0 : m < 0.6 ? 1 : 2) : m < 0.02 ? -1 : Math.min(bands - 1, Math.floor(m * bands))
      level[py * width + px] = diverging && band >= 0 && v < 0 ? -2 - band : band
    }
  }
  const empty = (l: number) => l === -1
  for (let py = 0; py < height; py++)
    for (let px = 0; px < width; px++) {
      const k = py * width + px
      const v = value[k], lv = level[k]
      let [r, g, b] = empty(lv) ? emptyColor : diverging ? divergingAt(v) : colormapAt(name, v)
      if (patterns && !empty(lv)) {
        const edge = (px + 1 < width && level[k + 1] !== lv) || (py + 1 < height && level[k + width] !== lv)
        const band = diverging ? (lv <= -2 ? -2 - lv : lv) : lv
        // Hatch gets denser and heavier with the band; sequential bands 3+ are cross-hatched.
        const period = diverging ? [12, 8, 5][band] : [0, 14, 9, 10, 7, 6][band]
        const thick = diverging ? [1, 1, 2][band] : [0, 1, 2, 1, 2, 3][band]
        const flip = diverging && lv <= -2
        const diag = period > 0 && ((flip ? px - py + 4 * width : px + py) % period) < thick
        const cross = !diverging && band >= 3 && (px - py + 4 * width) % period < thick
        if (edge || diag || cross) {
          const light = 0.299 * r + 0.587 * g + 0.114 * b > 110
          ;[r, g, b] = light ? [0, 0, 0] : [255, 255, 255]
        }
      }
      data[k * 4] = r
      data[k * 4 + 1] = g
      data[k * 4 + 2] = b
      data[k * 4 + 3] = 255
    }
}
