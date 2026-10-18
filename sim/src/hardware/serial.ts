import { createCalibrator, type Calibrator } from "./calibrate"
import { SENSOR_NAMES, SENSOR_POSITIONS } from "./layout"
import type { LiveSensor } from "./types"

const BAUD = 115200
/** Full-scale ADC counts: Uno/Nano are 10-bit, ESP32 is 12-bit. The firmware's "I," header says which. */
const AVR_ADC_MAX = 1023
const ESP32_ADC_MAX = 4095
/** Boards that don't reset on open never print the header unprompted, so we ask for it after this long.
 *  Waiting first keeps the byte away from an AVR bootloader that is still running after the reset. */
const HEADER_WAIT_MS = 1500

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
  let adcMax = AVR_ADC_MAX
  let headerSeen = false
  let calibrator = createCalibrator(adcMax, n)
  const subs = new Set<(kPa: Float32Array, tMs: number) => void>()
  const t0 = performance.now()
  let closed = false

  const setAdcMax = (max: number) => {
    if (max === adcMax) return
    adcMax = max
    const prev = calibrator
    calibrator = createCalibrator(max, n)
    calibrator.normalize = prev.normalize
  }

  // Keep the pipe's promise so disconnect() can wait for it to release port.readable.
  const decoder = new TextDecoderStream()
  const piped = port.readable.pipeTo(decoder.writable).catch(() => {})
  const reader = decoder.readable.getReader()
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
            const max = Number(line.split(",")[3])
            if (max > 0) {
              headerSeen = true
              setAdcMax(max)
            }
            continue
          }
          const raw = parseFrame(line, n)
          if (!raw) continue
          // No header yet: a 10-bit board can't read above 1023, so a higher count means a 12-bit ESP32.
          if (!headerSeen && raw.some((v) => v > AVR_ADC_MAX)) setAdcMax(ESP32_ADC_MAX)
          const kPa = calibrator.convert(raw)
          const t = performance.now() - t0
          for (const cb of subs) cb(kPa, t)
        }
      }
    } catch {
      // Device unplugged or stream cancelled: fall through to cleanup.
    }
  })()

  // The firmware re-sends its header on any byte. Best effort: the range check above covers a failed write.
  let headerRequest = Promise.resolve()
  const headerTimer = setTimeout(() => {
    if (headerSeen || !port.writable) return
    const writer = port.writable.getWriter()
    headerRequest = writer.write(new Uint8Array([10])).catch(() => {}).finally(() => writer.releaseLock())
  }, HEADER_WAIT_MS)

  // Calibrator is swapped when the full scale changes, so expose a stable proxy.
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
      clearTimeout(headerTimer)
      subs.clear()
      // close() rejects while either stream is locked, so unwind the pipe and any pending write first.
      await reader.cancel().catch(() => {})
      await Promise.all([piped, pump, headerRequest])
      await port.close()
    },
  }
}
