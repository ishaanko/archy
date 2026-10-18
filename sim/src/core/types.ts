/** Shared plain data types. Everything is in the canonical foot frame, in mm:
 *  x points medially (right-foot data is mirrored on load), y runs heel -> toe,
 *  heel sensors sit near y = 0. */
export interface Point {
  x: number
  y: number
}

/** A pressure recording over one stance. `frames` is nFrames x sensors.length, kPa. */
export interface Trial {
  id: string
  label: string
  source: "real" | "synthetic"
  side: "left" | "right"
  fs: number
  sensors: readonly Point[]
  frames: Float32Array
  nFrames: number
}

export type FootType = "normal" | "flat" | "high arch"
