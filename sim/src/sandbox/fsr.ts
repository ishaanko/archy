import { adcToKPa, DIVIDER_OHMS } from "../hardware/calibrate"

/** Approximate electronics model of one FSR in the kit's divider (supply -> FSR -> pin -> 10k -> GND).
 *
 *  APPROXIMATE: shaped after the Interlink FSR 402 datasheet curves, not measured. Real parts differ by 20-30%
 *  between units, drift, and react to bending. The point is the shape of the signal chain, not exact numbers:
 *    force on the 12.7 mm active disc  ->  resistance (conductance ~ force^0.95, ~100 uS per newton)
 *    -> open circuit (~10 Mohm) under ~0.1 N  ->  softly saturates above ~12 N
 *    -> divider voltage  ->  ADC count (quantized, plus a little noise).
 *  The "seen" kPa goes back through hardware/calibrate.ts (the same conversion the real app uses), so
 *  saturation and the assumed linear curve show up as honest reading errors. */

export interface Board {
  label: string
  bits: number
  vcc: number
  /** Gaussian ADC noise, in counts (1 sigma). The ESP32 ADC is noticeably noisier than an AVR. */
  noiseLsb: number
}

export const BOARDS = {
  uno: { label: "Arduino Nano", bits: 10, vcc: 5, noiseLsb: 0.7 },
  esp32: { label: "ESP32", bits: 12, vcc: 3.3, noiseLsb: 3 },
} as const satisfies Record<string, Board>

export type BoardId = keyof typeof BOARDS

export const ACTIVE_AREA_MM2 = 127 // 12.7 mm round active area
const ACTIVE_RADIUS_MM = 6.35
const THRESHOLD_N = 0.1 // below this the FSR reads as open circuit
const OPEN_OHMS = 10e6
const US_PER_N = 100
const EXPONENT = 0.95
const SATURATION_N = 12

export interface FsrReading {
  /** Mean true pressure over the active area, kPa. */
  kPa: number
  newtons: number
  /** Infinity is never returned; open circuit reads as OPEN_OHMS. */
  ohms: number
  volts: number
  adc: number
  /** kPa the app would compute from `adc` (hardware/calibrate.ts). */
  seenKPa: number
}

/** Sample offsets (mm) that approximate the mean of a field over the active disc: center plus a ring. */
export const DISC_SAMPLES: readonly (readonly [number, number])[] = [
  [0, 0],
  ...Array.from({ length: 8 }, (_, i): [number, number] => [
    0.6 * ACTIVE_RADIUS_MM * Math.cos((i * Math.PI) / 4),
    0.6 * ACTIVE_RADIUS_MM * Math.sin((i * Math.PI) / 4),
  ]),
]

export function fsrOhms(newtons: number): number {
  if (newtons < THRESHOLD_N) return OPEN_OHMS
  const effective = SATURATION_N * Math.tanh(newtons / SATURATION_N)
  return Math.min(OPEN_OHMS, 1e6 / (US_PER_N * effective ** EXPONENT))
}

const randn = () => Math.sqrt(-2 * Math.log(1 - Math.random())) * Math.cos(2 * Math.PI * Math.random())

/** One sensor, one sample. `gain` is that unit's sensitivity (1 = nominal). */
export function readFsr(kPa: number, gain: number, board: Board): FsrReading {
  const newtons = kPa * ACTIVE_AREA_MM2 * 1e-3 * gain
  const ohms = fsrOhms(newtons)
  const max = 2 ** board.bits - 1
  const ideal = (board.vcc * DIVIDER_OHMS) / (DIVIDER_OHMS + ohms)
  const adc = Math.min(max, Math.max(0, Math.round((ideal / board.vcc) * max + randn() * board.noiseLsb)))
  return { kPa, newtons, ohms, volts: (adc / max) * board.vcc, adc, seenKPa: adcToKPa(adc, max) }
}

/** What the firmware prints for one frame (see hardware/README.md, serial protocol). */
export function serialText(board: Board, adcs: readonly number[]): string {
  return `I,foot_sensor,${adcs.length},${2 ** board.bits - 1}\nP,${adcs.join(",")}`
}
