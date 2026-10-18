import { edgeDistance, medialEdgeX, rayExit } from "./outline"
import type { Grid } from "./pressure"
import { sampleGrid } from "./pressure"
import type { Indices } from "./indices"
import type { Point } from "./types"

/** Closed, printable insole mesh. Vertices [0, topCount) are the top surface (positions + `topXY`),
 *  the rest are the flat bottom. Triangles [0, topTriangles) are the top surface. Units mm, z up, bottom at z = 0. */
export interface InsoleMesh {
  positions: Float32Array
  indices: Uint32Array
  topCount: number
  topTriangles: number
  /** xy of each top vertex (the sampling positions for heatmaps and terrain). */
  topXY: Float32Array
  /** 0 at the outer rim rising to 1 three rings inboard; terrain displacement is scaled by it so the rim stays attached to the wall. */
  rimFade: Float32Array
  /** Arch support height used, mm. */
  archHeight: number
  /** Designed top-surface height at (x, y), mm. */
  heightAt: (x: number, y: number) => number
}

export interface InsoleParams {
  base: number
  heelCupHeight: number
  heelCupWidth: number
  minThickness: number
  /** Max thinning under pressure hotspots. */
  reliefDepth: number
}

export const DEFAULT_INSOLE: InsoleParams = { base: 3, heelCupHeight: 9, heelCupWidth: 14, minThickness: 1.8, reliefDepth: 1.2 }

const RINGS = 40
const SEGMENTS = 240
const smoothstep = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}

/** Arch support height from the arch index: 6 mm at AI 0.21, rising 8 mm per 0.1 AI, clamped to 4-18 mm. */
export function archHeightFor(archIndex: number | undefined): number {
  if (archIndex === undefined) return 6
  return Math.min(18, Math.max(4, 6 + 80 * (archIndex - 0.21)))
}

/** Generates the insole from the outline: base plate, heel cup, medial arch support sized from the arch index,
 *  and thinned relief under peak-pressure hotspots (softer zones when printed in TPU).
 *  `side: "right"` mirrors the canonical (left, medial = +x) mesh for export. */
export function buildInsole(
  outline: readonly Point[],
  grid: Grid,
  peak: Float32Array,
  indices: Indices | null,
  side: "left" | "right" = "left",
  params: InsoleParams = DEFAULT_INSOLE,
): InsoleMesh {
  const archHeight = archHeightFor(indices?.archIndex)
  let peakMax = 0
  for (const v of peak) peakMax = Math.max(peakMax, v)
  const edgeCache = new Map<number, number>()
  const medialAt = (y: number) => {
    const key = Math.round(y)
    let v = edgeCache.get(key)
    if (v === undefined) edgeCache.set(key, (v = medialEdgeX(outline, key)))
    return v
  }

  const heightAt = (x: number, y: number): number => {
    // Medial longitudinal arch: a ridge hugging the medial edge, centered under the navicular.
    const inboard = Math.max(0, medialAt(y) - x)
    const arch = archHeight * Math.exp(-((y - 88) ** 2) / (2 * 26 ** 2)) * Math.exp(-((inboard - 8) ** 2) / (2 * 15 ** 2))
    // Heel cup: a rim rising toward the outline edge over the rear of the foot.
    const cup = y < 80 ? params.heelCupHeight * smoothstep(80, 50, y) * (1 - smoothstep(0, params.heelCupWidth, edgeDistance(outline, x, y))) ** 2 : 0
    // Relief under hotspots (not under the arch support).
    const load = peakMax > 0 ? sampleGrid(grid, peak, x, y) / peakMax : 0
    const relief = params.reliefDepth * smoothstep(0.55, 0.9, load) * (1 - Math.min(1, arch / 3))
    return Math.max(params.minThickness, params.base + arch + cup - relief)
  }

  // Polar mesh around an interior center: ring i is the outline scaled by i / RINGS.
  const center = { x: 3, y: 105 }
  const rim = Array.from({ length: SEGMENTS }, (_, j) => {
    const a = (2 * Math.PI * j) / SEGMENTS
    return rayExit(outline, center, Math.cos(a), Math.sin(a))
  })
  const topCount = 1 + RINGS * SEGMENTS
  const positions = new Float32Array(topCount * 2 * 3)
  const topXY = new Float32Array(topCount * 2)
  const put = (v: number, x: number, y: number) => {
    topXY[v * 2] = x
    topXY[v * 2 + 1] = y
    positions.set([x, y, heightAt(x, y)], v * 3)
    positions.set([x, y, 0], (topCount + v) * 3)
  }
  put(0, center.x, center.y)
  for (let i = 1; i <= RINGS; i++)
    for (let j = 0; j < SEGMENTS; j++) {
      const s = i / RINGS
      put(1 + (i - 1) * SEGMENTS + j, center.x + s * (rim[j].x - center.x), center.y + s * (rim[j].y - center.y))
    }

  const tris: number[] = []
  const v = (i: number, j: number) => (i === 0 ? 0 : 1 + (i - 1) * SEGMENTS + (j % SEGMENTS))
  // Top surface, counter-clockwise seen from +z.
  for (let j = 0; j < SEGMENTS; j++) tris.push(0, v(1, j), v(1, j + 1))
  for (let i = 1; i < RINGS; i++)
    for (let j = 0; j < SEGMENTS; j++) {
      tris.push(v(i, j), v(i + 1, j), v(i + 1, j + 1), v(i, j), v(i + 1, j + 1), v(i, j + 1))
    }
  const topTriangles = tris.length / 3
  // Bottom (reversed winding) and outer wall.
  for (let j = 0; j < SEGMENTS; j++) tris.push(topCount, topCount + v(1, j + 1), topCount + v(1, j))
  for (let i = 1; i < RINGS; i++)
    for (let j = 0; j < SEGMENTS; j++) {
      const b = topCount
      tris.push(b + v(i, j), b + v(i + 1, j + 1), b + v(i + 1, j), b + v(i, j), b + v(i, j + 1), b + v(i + 1, j + 1))
    }
  for (let j = 0; j < SEGMENTS; j++) {
    const a = v(RINGS, j), b = v(RINGS, j + 1)
    tris.push(a, topCount + a, topCount + b, a, topCount + b, b)
  }

  const rimFade = new Float32Array(topCount).fill(1)
  for (let i = 1; i <= RINGS; i++)
    for (let j = 0; j < SEGMENTS; j++) rimFade[v(i, j)] = Math.min(1, (RINGS - i) / 3)
  const mesh: InsoleMesh = { positions, indices: Uint32Array.from(tris), topCount, topTriangles, topXY, rimFade, archHeight, heightAt }
  return side === "right" ? mirrored(mesh) : mesh
}

/** Mirrors a mesh across x = 0 (left <-> right insole), flipping winding to keep normals outward. */
function mirrored(mesh: InsoleMesh): InsoleMesh {
  const positions = mesh.positions.slice()
  for (let i = 0; i < positions.length; i += 3) positions[i] = -positions[i]
  const indices = mesh.indices.slice()
  for (let i = 0; i < indices.length; i += 3) [indices[i + 1], indices[i + 2]] = [indices[i + 2], indices[i + 1]]
  return { ...mesh, positions, indices }
}
