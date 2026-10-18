import type { Point } from "../core/types"

/** Sensor placement in the canonical foot frame (mm; x medial-positive, y heel -> toe),
 *  matched to core/outline.ts: heel edge near y = 0, toe tip near y = 240, x from about -43 (lateral) to 58 (medial).
 *  Order is the wire order of the firmware (P,<s0>..<s5>) and the numbering in hardware/README.md. */
export const FOOT_LENGTH_MM = 240
export const FOOT_WIDTH_MM = 100
/** x of the lateral edge at the ball of the foot. */
const LATERAL_X_MM = -43

/** Fractions of foot length (fy, heel = 0) and width (fx, lateral = 0, medial = 1). */
const SPOTS = [
  { name: "Heel", fx: 0.45, fy: 0.1 },
  { name: "Outer midfoot", fx: 0.19, fy: 0.375 },
  { name: "Inner arch", fx: 0.63, fy: 0.4 },
  { name: "Big toe joint", fx: 0.79, fy: 0.67 },
  { name: "Little toe joint", fx: 0.11, fy: 0.63 },
  { name: "Big toe", fx: 0.83, fy: 0.88 },
] as const

export const SENSOR_NAMES: readonly string[] = SPOTS.map((s) => s.name)

export const SENSOR_POSITIONS: readonly Point[] = SPOTS.map((s) => ({
  x: Math.round(LATERAL_X_MM + s.fx * FOOT_WIDTH_MM),
  y: Math.round(s.fy * FOOT_LENGTH_MM),
}))

/** Index of the Inner arch sensor (the flat-foot sensor). */
export const INNER_ARCH_INDEX = SENSOR_NAMES.indexOf("Inner arch")
