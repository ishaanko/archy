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
