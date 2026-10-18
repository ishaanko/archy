import type { Indices } from "./indices"

export type ArchLevel = "lower" | "typical" | "higher"

/** Plain-language reading of the arch indices. `position` places a marker on a lower | typical | higher scale (0..1). */
export interface Reading {
  level: ArchLevel
  headline: string
  meaning: string
  position: number
}

const TEXT: Record<ArchLevel, Pick<Reading, "headline" | "meaning">> = {
  lower: {
    headline: "Your arch looks lower than typical",
    meaning: "More of your foot touches the ground. Lower arches are common and often painless. Arch support can spread the load more evenly.",
  },
  typical: {
    headline: "Your arch looks typical",
    meaning: "Pressure is spread the way we expect. A cushioned insole with light arch support keeps it that way.",
  },
  higher: {
    headline: "Your arch looks higher than typical",
    meaning: "Less of your foot touches the ground, so heel and ball take more load. Cushioning and a snug arch fit can help.",
  },
}

export const DISCLAIMER = "This is a screening, not a diagnosis. See a clinician if you have pain."

const clamp01 = (x: number) => Math.min(1, Math.max(0, x))

/** Folds the three indices into one of three levels (majority vote, ties fall back to the Cavanagh arch index)
 *  and places the marker inside that level's third of the scale, by arch index. Low arch index means high arch. */
export function readArch(i: Indices): Reading {
  const level: ArchLevel =
    i.verdict === "flat" ? "lower" : i.verdict === "high arch" ? "higher" : i.verdict === "normal" ? "typical"
    : i.archIndexClass === "flat" ? "lower" : i.archIndexClass === "high arch" ? "higher" : "typical"
  const ai = i.archIndex
  const within = level === "lower" ? clamp01((0.36 - ai) / 0.1) : level === "typical" ? clamp01((0.26 - ai) / 0.05) : clamp01((0.21 - ai) / 0.08)
  const third = level === "lower" ? 0 : level === "typical" ? 1 : 2
  return { level, ...TEXT[level], position: (third + 0.05 + 0.9 * within) / 3 }
}

/** Plain-language reading of the Arch Height Index (Butler 2008: <= 0.315 lower, >= 0.365 higher). Marker placement mirrors
 *  `readArch`: inside the level's third of the scale, by AHI. */
export function readAhi(ahi: number, lower = 0.315, higher = 0.365): Reading {
  const level: ArchLevel = ahi <= lower ? "lower" : ahi >= higher ? "higher" : "typical"
  const within = level === "lower" ? clamp01((ahi - (lower - 0.06)) / 0.06) : level === "typical" ? clamp01((ahi - lower) / (higher - lower)) : clamp01((ahi - higher) / 0.06)
  const third = level === "lower" ? 0 : level === "typical" ? 1 : 2
  return { level, ...TEXT[level], position: (third + 0.05 + 0.9 * within) / 3 }
}
