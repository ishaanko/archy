/** Turns a stream of sensor frames (kPa per sensor) into steps and a rolling peak reading.
 *  A step starts when the summed load rises above a threshold and ends when it stays low for a moment;
 *  the reading is the per-sensor mean of each step's peak over the last `keep` steps (robust to one odd step). */
export class StepTracker {
  /** Steps completed since connect. */
  steps = 0
  /** Latest frame and its summed load. */
  latest: Float32Array
  /** Mean per-sensor step peak over the last `keep` steps; null until the first step ends. */
  rolling: Float32Array | null = null
  /** Steps needed before the result is shown. */
  readonly needed: number
  private recent: Float32Array[] = []
  private current: Float32Array
  private inStep = false
  private stepStart = 0
  private quietSince = 0
  private maxTotal = 0

  constructor(private nSensors: number, private keep = 4, needed = 3) {
    this.needed = needed
    this.latest = new Float32Array(nSensors)
    this.current = new Float32Array(nSensors)
  }

  get ready(): boolean {
    return this.steps >= this.needed && this.rolling !== null
  }

  /** Feeds one frame. Returns true when this frame completed a step (the rolling reading changed). */
  push(kPa: Float32Array, tMs: number): boolean {
    this.latest = kPa
    const total = kPa.reduce((s, v) => s + v, 0)
    // Absolute floor for the first step, then a fraction of the biggest load seen so far.
    const on = Math.max(25, 0.2 * this.maxTotal)
    if (!this.inStep) {
      if (total > on) {
        this.inStep = true
        this.stepStart = tMs
        this.current.fill(0)
      }
    }
    if (this.inStep) {
      this.maxTotal = Math.max(this.maxTotal, total)
      for (let k = 0; k < this.nSensors; k++) this.current[k] = Math.max(this.current[k], kPa[k])
      if (total > on * 0.5) this.quietSince = tMs
      else if (tMs - this.quietSince > 80) {
        this.inStep = false
        if (this.quietSince - this.stepStart >= 150) {
          this.recent.push(this.current.slice())
          if (this.recent.length > this.keep) this.recent.shift()
          this.steps++
          const mean = new Float32Array(this.nSensors)
          for (const r of this.recent) for (let k = 0; k < this.nSensors; k++) mean[k] += r[k] / this.recent.length
          this.rolling = mean
          return true
        }
      }
    }
    return false
  }

  /** Largest single-sensor value seen in recent steps, used to scale live bars (never below `floor`). */
  scale(floor = 100): number {
    return Math.max(floor, ...(this.rolling ?? []), ...this.latest)
  }
}

/** Center of pressure y (mm from heel) for one frame of sensor readings; NaN when there is no load. */
export function copY(sensorsY: readonly number[], kPa: Float32Array): number {
  let sw = 0, sy = 0
  kPa.forEach((v, i) => { sw += v; sy += v * sensorsY[i] })
  return sw > 5 ? sy / sw : NaN
}
