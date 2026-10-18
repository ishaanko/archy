import type { Point } from "./types"

/** Control points of a generic adult insole outline (about 257 mm long, size US 8),
 *  sized so all 48 sensors fall inside. Medial side first, heel to toe, then lateral back. */
const CONTROL: readonly Point[] = [
  { x: 3, y: -18 }, { x: 22, y: -14 }, { x: 32, y: 0 }, { x: 35, y: 25 }, { x: 31, y: 55 },
  { x: 27, y: 82 }, { x: 27, y: 105 }, { x: 32, y: 130 }, { x: 46, y: 155 }, { x: 56, y: 180 },
  { x: 58, y: 205 }, { x: 52, y: 225 }, { x: 38, y: 236 }, { x: 18, y: 240 }, { x: 2, y: 238 },
  { x: -18, y: 230 }, { x: -33, y: 212 }, { x: -42, y: 185 }, { x: -43, y: 160 }, { x: -38, y: 135 },
  { x: -34, y: 105 }, { x: -32, y: 75 }, { x: -33, y: 45 }, { x: -30, y: 15 }, { x: -22, y: -8 },
  { x: -10, y: -16 },
]

/** Closed Catmull-Rom spline through the control points, as a dense counter-clockwise polygon. */
export function footOutline(stepsPerSegment = 12): Point[] {
  const n = CONTROL.length
  const out: Point[] = []
  for (let i = 0; i < n; i++) {
    const p0 = CONTROL[(i + n - 1) % n], p1 = CONTROL[i], p2 = CONTROL[(i + 1) % n], p3 = CONTROL[(i + 2) % n]
    for (let s = 0; s < stepsPerSegment; s++) {
      const t = s / stepsPerSegment, t2 = t * t, t3 = t2 * t
      const f = (a: number, b: number, c: number, d: number) =>
        0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
      out.push({ x: f(p0.x, p1.x, p2.x, p3.x), y: f(p0.y, p1.y, p2.y, p3.y) })
    }
  }
  return out
}

/** Even-odd point-in-polygon test. */
export function inside(poly: readonly Point[], x: number, y: number): boolean {
  let c = false
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const a = poly[i], b = poly[j]
    if (a.y > y !== b.y > y && x < ((b.x - a.x) * (y - a.y)) / (b.y - a.y) + a.x) c = !c
  }
  return c
}

/** Where a ray from `from` in direction (dx, dy) leaves the polygon (assumes `from` is inside). */
export function rayExit(poly: readonly Point[], from: Point, dx: number, dy: number): Point {
  let best = Infinity
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length]
    const ex = b.x - a.x, ey = b.y - a.y
    const den = dx * ey - dy * ex
    if (Math.abs(den) < 1e-12) continue
    const t = ((a.x - from.x) * ey - (a.y - from.y) * ex) / den
    const u = ((a.x - from.x) * dy - (a.y - from.y) * dx) / den
    if (t > 1e-9 && u >= 0 && u < 1 && t < best) best = t
  }
  return { x: from.x + dx * best, y: from.y + dy * best }
}

/** Largest x of the polygon on the horizontal line at y (the medial edge for a canonical foot). */
export function medialEdgeX(poly: readonly Point[], y: number): number {
  let best = -Infinity
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length]
    if (a.y > y !== b.y > y) best = Math.max(best, a.x + ((y - a.y) / (b.y - a.y)) * (b.x - a.x))
  }
  return best
}

/** Shortest distance from (x, y) to the polygon boundary. */
export function edgeDistance(poly: readonly Point[], x: number, y: number): number {
  let best = Infinity
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length]
    const ex = b.x - a.x, ey = b.y - a.y
    const t = Math.max(0, Math.min(1, ((x - a.x) * ex + (y - a.y) * ey) / (ex * ex + ey * ey)))
    best = Math.min(best, Math.hypot(x - a.x - t * ex, y - a.y - t * ey))
  }
  return best
}
