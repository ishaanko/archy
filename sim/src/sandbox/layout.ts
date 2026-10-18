import { medialEdgeX } from "../core/outline"
import type { Point } from "../core/types"
import { BOARDS, type BoardId } from "./fsr"

export interface SensorDef extends Point {
  name: string
  /** This unit's sensitivity, 1 = nominal (real FSRs vary about +-10%). */
  gain: number
}

export function insoleBounds(outline: readonly Point[]): { minY: number; length: number } {
  const ys = outline.map((p) => p.y)
  const minY = Math.min(...ys)
  return { minY, length: Math.max(...ys) - minY }
}

/** JSON for the "Copy layout" button: sim-frame mm plus the two measurements you can take on a real insole
 *  (mm from the back of the heel, mm from the inner edge at that height). `wire` is the order of the P line. */
export function layoutJson(sensors: readonly SensorDef[], outline: readonly Point[], board: BoardId): string {
  const { minY, length } = insoleBounds(outline)
  const r = (v: number) => Math.round(v * 10) / 10
  return JSON.stringify(
    {
      board: BOARDS[board].label,
      units: "mm",
      insoleLengthMm: Math.round(length),
      sensors: sensors.map((s, i) => ({
        wire: i + 1,
        name: s.name,
        fromHeelMm: r(s.y - minY),
        fromInnerEdgeMm: r(medialEdgeX(outline, s.y) - s.x),
        simX: r(s.x),
        simY: r(s.y),
      })),
    },
    null,
    2,
  )
}
