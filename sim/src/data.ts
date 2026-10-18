import type { Template } from "./core/template"
import type { Point, Trial } from "./core/types"

interface InsoleJson {
  fs: number
  sensors: Record<"left" | "right", Point[]>
  trials: { participant: number; side: "left" | "right"; frames: number[][] }[]
}

/** Loads the converted real recordings (sim/public/data/insole.json) and the two sensor layouts. */
export async function loadInsoleData(): Promise<{ sensors: InsoleJson["sensors"]; trials: Trial[] }> {
  const res = await fetch(`${import.meta.env.BASE_URL}data/insole.json`)
  const json: InsoleJson = await res.json()
  const trials = json.trials.map((t): Trial => {
    const sensors = json.sensors[t.side]
    return {
      id: `p${t.participant}-${t.side}`,
      label: `Participant ${t.participant}, ${t.side} foot`,
      source: "real",
      side: t.side,
      fs: json.fs,
      sensors,
      frames: Float32Array.from(t.frames.flat()),
      nFrames: t.frames.length,
    }
  })
  return { sensors: json.sensors, trials }
}

/** Loads the MUN104 left-foot mean peak pressure template (sim/public/data/mun104.json). */
export async function loadTemplate(): Promise<Template> {
  const res = await fetch(`${import.meta.env.BASE_URL}data/mun104.json`)
  return res.json()
}

export interface FeetInfo {
  stats: { n: number; percentiles: Record<string, number> }
  picks: Record<"flatter" | "typical" | "higher", { id: string; ai: number }>
}

/** Loads the scanned-foot summary (sim/public/data/feet.json, written by scripts/pick_feet.py). */
export async function loadFeet(): Promise<FeetInfo> {
  const res = await fetch(`${import.meta.env.BASE_URL}data/feet.json`)
  return res.json()
}

/** One real walking step from the CAD WALK clinical pressure plate (sim/public/data/cadwalk.json, scripts/convert_cadwalk.py). */
export interface CadStep {
  id: string
  title: string
  cohort: string
  subject: string
  side: "left" | "right"
  ai: number
  fs: number
  /** kPa per quantization level. */
  qstep: number
  grid: { nx: number; ny: number; cell: number; x0: number; y0: number }
  /** Per frame, nx * ny levels (row-major, row 0 = heel). */
  frames: number[][]
}

/** Loads the plate steps; an empty list if the file is missing so the rest of the app still works. */
export async function loadCadwalk(): Promise<CadStep[]> {
  try {
    const res = await fetch(`${import.meta.env.BASE_URL}data/cadwalk.json`)
    return res.ok ? (await res.json()).steps : []
  } catch {
    return []
  }
}
