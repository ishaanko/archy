import type { Point } from "../core/types"

/** A live pressure device (real hardware over Web Serial, or the built-in demo emulator).
 *  Sensor positions are in the canonical foot frame (see core/types.ts), in mm.
 *  Values are approximate kPa: cheap FSRs are only roughly calibrated, so treat them as relative. */
export interface LiveSensor {
  name: string
  kind: "serial" | "demo"
  side: "left" | "right"
  sensors: readonly Point[]
  /** Human-readable sensor names, same order as `sensors` (e.g. "Heel", "Inner arch"). */
  sensorNames: readonly string[]
  /** Subscribes to frames; returns an unsubscribe function. `kPa.length === sensors.length`. */
  onFrame(cb: (kPa: Float32Array, tMs: number) => void): () => void
  disconnect(): Promise<void>
}
