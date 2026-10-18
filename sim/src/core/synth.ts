import { templateAt, type Template } from "./template"
import type { FootType, Point, Trial } from "./types"

export const STANCE_SECONDS = 0.65

export const gauss = (x: number, c: number, s: number) => Math.exp(-((x - c) ** 2) / (2 * s * s))

/** Spatial scale on the MUN104 mean peak map. `flatness` 0 is the template itself; toward +1 it adds medial midfoot
 *  loading (flat), toward -1 it suppresses the midfoot band (high arch). */
export function archShape(flatness: number, template: Template, peakRef: number) {
  return (x: number, y: number): number => {
    const base = templateAt(template, x, y)
    if (flatness > 0) return base + 0.4 * flatness * peakRef * gauss(x, 17, 9) * gauss(y, 92, 24)
    return base * (1 - -flatness * 0.9 * gauss(y, 92, 28))
  }
}

const footShape = (type: FootType, template: Template, peakRef: number) => archShape(type === "flat" ? 1 : type === "high arch" ? -1 : 0, template, peakRef)

/** Typical peak pressure of the synthetic examples at 70 kg, close to the FSR data. */
export const PEAK_KPA = 180

/** Time (0..1 of stance) at which a spot at distance y from the heel is loaded most: heel strike, midstance, push-off, toe off. */
export function peakTime(y: number): number {
  const knots: [number, number][] = [[0, 0.15], [25, 0.17], [95, 0.45], [160, 0.65], [205, 0.84], [260, 0.86]]
  for (let i = 1; i < knots.length; i++)
    if (y <= knots[i][0]) {
      const [y0, t0] = knots[i - 1], [y1, t1] = knots[i]
      return t0 + ((Math.max(y, y0) - y0) / (y1 - y0)) * (t1 - t0)
    }
  return knots[knots.length - 1][1]
}

/** Small seeded PRNG so the synthetic trials are repeatable. */
function mulberry32(seed: number): () => number {
  let a = seed
  return () => {
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/** Parametric stance (heel strike -> midstance -> toe off) at the given sensor layout. Each sensor's peak is the
 *  foot-type map (MUN104 template, modified for flat / high arch) at its position; its time course is a Gaussian
 *  bump centered at the moment that region of the foot is loaded. */
export function synthTrial(type: FootType, sensors: readonly Point[], template: Template, fs = 125): Trial {
  const peakRef = Math.max(...template.data.flat())
  const shape = footShape(type, template, peakRef)
  const scale = PEAK_KPA / peakRef
  const nFrames = Math.round(STANCE_SECONDS * fs)
  const rand = mulberry32(type.length * 7919)
  const peaks = sensors.map((s) => shape(s.x, s.y) * scale * (0.95 + 0.1 * rand())) // per-sensor FSR gain scatter
  const times = sensors.map((s) => peakTime(s.y))
  const frames = new Float32Array(nFrames * sensors.length)
  for (let f = 0; f < nFrames; f++) {
    const t = f / (nFrames - 1)
    const env = Math.min(1, t / 0.05, (1 - t) / 0.05) // ramp in at heel strike, out at toe off
    for (let k = 0; k < sensors.length; k++)
      frames[f * sensors.length + k] = peaks[k] * Math.max(0, env) * gauss(t, times[k], 0.16) * (1 + 0.03 * (rand() - 0.5))
  }
  return { id: `synthetic-${type}`, label: `Synthetic ${type} foot`, source: "synthetic", side: "left", fs, sensors, frames, nFrames }
}
