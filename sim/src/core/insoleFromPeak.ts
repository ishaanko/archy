import { computeIndices, type Indices } from "./indices"
import { buildInsole, type InsoleMesh } from "./insole"
import type { Grid } from "./pressure"
import type { Point } from "./types"

/** The one peak-pressure-map -> printable insole path (main page and sensor sandbox): arch indices from the map,
 *  then the insole sized from the arch index with relief under hotspots. */
export function insoleFromPeak(
  outline: readonly Point[],
  grid: Grid,
  peak: Float32Array,
  side: "left" | "right" = "left",
): { indices: Indices | null; mesh: InsoleMesh } {
  const indices = computeIndices(grid, peak)
  return { indices, mesh: buildInsole(outline, grid, peak, indices, side) }
}
