import type { Grid } from "./pressure"

export type ArchClass = "flat" | "normal" | "high arch"

/** Footprint arch indices from a peak-pressure map, with the per-index classification. */
export interface Indices {
  /** Cavanagh arch index: midfoot area / (hind + mid + fore) area, toes excluded. */
  archIndex: number
  /** Staheli: midfoot width / widest heel width. */
  staheli: number
  /** Chippaux-Smirak, percent: midfoot width / widest forefoot width. */
  chippauxSmirak: number
  archIndexClass: ArchClass
  staheliClass: ArchClass
  chippauxSmirakClass: "flat" | "normal"
  /** How many of the 3 indices suggest flat. */
  flatVotes: number
  verdict: ArchClass | "inconclusive"
}

const CONTACT_FRACTION = 0.05 // of the map's peak; "above noise"
// Midfoot width is the median row width of the middle third, not the minimum: with 48 sparse sensors
// one unsensed row would otherwise read as zero width.
const TOE_FRACTION = 0.2 // distal share of foot length treated as toes

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b)
  return s[Math.floor(s.length / 2)]
}

/** Segments the contact area, drops toes, splits into thirds along y (the canonical long axis) and computes the indices.
 *  Returns null when there is too little contact to measure. */
export function computeIndices(grid: Grid, peak: Float32Array): Indices | null {
  let max = 0
  for (const v of peak) max = Math.max(max, v)
  if (max <= 0) return null
  const threshold = CONTACT_FRACTION * max
  // Per-row contact: cell count and horizontal span.
  const count = new Float32Array(grid.ny), span = new Float32Array(grid.ny)
  let first = -1, last = -1
  for (let j = 0; j < grid.ny; j++) {
    let lo = Infinity, hi = -Infinity
    for (let i = 0; i < grid.nx; i++)
      if (peak[j * grid.nx + i] > threshold) {
        count[j]++
        lo = Math.min(lo, i)
        hi = Math.max(hi, i)
      }
    if (count[j] > 0) {
      span[j] = (hi - lo + 1) * grid.cell
      if (first < 0) first = j
      last = j
    }
  }
  if (first < 0 || last - first < 12) return null
  const length = last - first + 1
  const footEnd = last - Math.round(length * TOE_FRACTION) // exclusive of toes
  const third = (footEnd - first + 1) / 3
  const bounds = [first, first + third, first + 2 * third, footEnd + 1].map(Math.round)
  const areaOf = (a: number, b: number) => count.slice(a, b).reduce((s, v) => s + v, 0)
  const hind = areaOf(bounds[0], bounds[1]), mid = areaOf(bounds[1], bounds[2]), fore = areaOf(bounds[2], bounds[3])
  const total = hind + mid + fore
  const widths = (a: number, b: number) => Array.from(span.slice(a, b))
  const midWidth = median(widths(bounds[1], bounds[2]))
  const heelWidth = Math.max(...widths(bounds[0], bounds[1]))
  const foreWidth = Math.max(...widths(bounds[2], bounds[3]))
  if (total === 0 || heelWidth === 0 || foreWidth === 0) return null

  const archIndex = mid / total
  const staheli = midWidth / heelWidth
  const chippauxSmirak = (100 * midWidth) / foreWidth
  const archIndexClass: ArchClass = archIndex > 0.26 ? "flat" : archIndex < 0.21 ? "high arch" : "normal"
  const staheliClass: ArchClass = staheli > 0.89 ? "flat" : staheli < 0.44 ? "high arch" : "normal"
  const chippauxSmirakClass = chippauxSmirak > 45 ? "flat" : "normal"
  const flatVotes = [archIndexClass, staheliClass, chippauxSmirakClass].filter((c) => c === "flat").length
  const verdict =
    flatVotes >= 2 ? "flat" : archIndexClass === "high arch" && staheliClass === "high arch" ? "high arch" : flatVotes === 0 && archIndexClass !== "high arch" ? "normal" : "inconclusive"
  return { archIndex, staheli, chippauxSmirak, archIndexClass, staheliClass, chippauxSmirakClass, flatVotes, verdict }
}
