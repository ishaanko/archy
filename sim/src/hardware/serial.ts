import { createCalibrator, type Calibrator } from "./calibrate"
import { SENSOR_NAMES, SENSOR_POSITIONS } from "./layout"
import type { LiveSensor } from "./types"

const BAUD = 115200
const DEFAULT_ADC_MAX = 1023

/** A serial device plus its calibrator (call `calibrator.tare()` with the foot off, toggle `normalize`). */
export interface SerialSensor extends LiveSensor {
  calibrator: Calibrator
}

/** True in Chrome/Edge (Web Serial needs a secure context: https or localhost). */
export function isSerialSupported(): boolean {
  return typeof navigator !== "undefined" && "serial" in navigator
}

/** Parses "P,a,b,..." into raw numbers; null for anything else (junk, partial lines, header). */
function parseFrame(line: string, n: number): number[] | null {
  if (!line.startsWith("P,")) return null
  const vals = line.slice(2).split(",").map(Number)
  return vals.length === n && vals.every(Number.isFinite) ? vals : null
}

/** Asks the user to pick a port, opens it at 115200 baud and streams frames (see hardware/README.md for the protocol).
 *  Must be called from a user gesture (button click). Rejects if the user cancels the picker. */
export async function connectSerial(side: "left" | "right"): Promise<SerialSensor> {
  if (!navigator.serial) throw new Error("Web Serial not supported; use Chrome or Edge")
  const port = await navigator.serial.requestPort()
  await port.open({ baudRate: BAUD })
  if (!port.readable) throw new Error("Port is not readable")

  const n = SENSOR_POSITIONS.length
  let calibrator = createCalibrator(DEFAULT_ADC_MAX, n)
  const subs = new Set<(kPa: Float32Array, tMs: number) => void>()
  const t0 = performance.now()
  let closed = false

  const reader = port.readable.pipeThrough(new TextDecoderStream()).getReader()
  const pump = (async () => {
    let buf = ""
    try {
      for (;;) {
        const { value, done } = await reader.read()
        if (done) break
        buf += value
        const lines = buf.split(/\r?\n/)
        buf = lines.pop() ?? ""
        for (const line of lines) {
          if (line.startsWith("I,")) {
            const adcMax = Number(line.split(",")[3])
            if (adcMax > 0) {
              const prev = calibrator
              calibrator = createCalibrator(adcMax, n)
              calibrator.normalize = prev.normalize
            }
            continue
          }
          const raw = parseFrame(line, n)
          if (!raw) continue
          const kPa = calibrator.convert(raw)
          const t = performance.now() - t0
          for (const cb of subs) cb(kPa, t)
        }
      }
    } catch {
      // Device unplugged or stream cancelled: fall through to cleanup.
    }
  })()

  // Calibrator is swapped when the header arrives, so expose a stable proxy.
  const proxy: Calibrator = {
    get normalize() { return calibrator.normalize },
    set normalize(v) { calibrator.normalize = v },
    convert: (raw) => calibrator.convert(raw),
    tare: (f) => calibrator.tare(f),
    resetMax: () => calibrator.resetMax(),
  }

  return {
    name: "Foot sensor (USB)",
    kind: "serial",
    side,
    sensors: SENSOR_POSITIONS,
    sensorNames: SENSOR_NAMES,
    calibrator: proxy,
    onFrame(cb) {
      subs.add(cb)
      return () => subs.delete(cb)
    },
    async disconnect() {
      if (closed) return
      closed = true
      subs.clear()
      await reader.cancel().catch(() => {})
      await pump
      await port.close().catch(() => {})
    },
  }
}
