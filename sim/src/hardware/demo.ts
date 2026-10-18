import type { FootType } from "../core/types"
import { SENSOR_NAMES, SENSOR_POSITIONS } from "./layout"
import type { LiveSensor } from "./types"

const HZ = 50
const CYCLE_S = 1.2

/** One sensor's load over a stride: Gaussian bump at phase `at` (0..1 of the stride, stance is 0..0.62), width `w`, peak kPa. */
interface Bump { at: number; w: number; kPa: number }

/** Peak kPa per sensor, in layout order: Heel, Outer midfoot, Inner arch, Big toe joint, Little toe joint, Big toe. */
const ARCH_KPA: Record<FootType, number> = { flat: 230, normal: 25, "high arch": 0 }

function bumps(type: FootType): Bump[] {
  return [
    { at: 0.06, w: 0.06, kPa: 380 }, // heel strike
    { at: 0.24, w: 0.1, kPa: type === "high arch" ? 90 : 150 }, // outer midfoot, midstance
    { at: 0.3, w: 0.1, kPa: ARCH_KPA[type] }, // inner arch
    { at: 0.46, w: 0.07, kPa: 300 }, // 1st metatarsal head, push off
    { at: 0.4, w: 0.07, kPa: 250 }, // 5th metatarsal head
    { at: 0.54, w: 0.05, kPa: 200 }, // big toe, toe off
  ]
}

/** Emulates the real device: 50 Hz frames from a repeating walk cycle (swing phase ~0 kPa), no hardware needed. */
export function connectDemoDevice(side: "left" | "right", footType: FootType): LiveSensor {
  const curve = bumps(footType)
  const subs = new Set<(kPa: Float32Array, tMs: number) => void>()
  const t0 = performance.now()

  const timer = setInterval(() => {
    const tMs = performance.now() - t0
    const phase = (tMs / 1000 / CYCLE_S) % 1
    const kPa = new Float32Array(curve.length)
    curve.forEach((b, i) => {
      const d = (phase - b.at) / b.w
      const v = b.kPa * Math.exp(-0.5 * d * d)
      kPa[i] = v < 1 ? 0 : v * (1 + 0.04 * (Math.random() - 0.5))
    })
    for (const cb of subs) cb(kPa, tMs)
  }, 1000 / HZ)

  return {
    name: `Demo device (${footType})`,
    kind: "demo",
    side,
    sensors: SENSOR_POSITIONS,
    sensorNames: SENSOR_NAMES,
    onFrame(cb) {
      subs.add(cb)
      return () => subs.delete(cb)
    },
    async disconnect() {
      clearInterval(timer)
      subs.clear()
    },
  }
}
