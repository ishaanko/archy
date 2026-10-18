import { peakTime } from "./synth"

/** Rigid-ish foot pose through one step, in the canonical frame (mm, radians).
 *  `pitch` > 0 lifts the toes, < 0 lifts the heel (rotation about the medial x axis through a pivot on the sole). */
export interface FootPose {
  pitch: number
  /** Pivot along the foot: 0 = rear of the heel contact, 1 = ball of the foot. */
  pivot: number
  /** Whole-foot lift off the insole, mm (swing phase). */
  lift: number
}

export const FLAT_POSE: FootPose = { pitch: 0, pivot: 0, lift: 0 }

const HEEL = 0
const BALL = 1
const HEEL_STRIKE_PITCH = 0.32 // rad, toes up at first contact
const PUSH_OFF_PITCH = -0.5 // rad, heel up at toe off

const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}

/** Pose at stance fraction t in [0, 1): heel strike (pivot about the heel, toes up), foot flat through midstance,
 *  push-off (pivot about the ball, heel up), then a short swing back to the next heel strike. Matches the
 *  timing of core/synth.ts (heel loaded at ~0.15, forefoot at ~0.84). */
export function stancePose(t: number): FootPose {
  if (t < 0.28) return { pitch: HEEL_STRIKE_PITCH * (1 - smooth(0, 0.28, t)), pivot: HEEL, lift: 0 }
  if (t < 0.5) return FLAT_POSE
  if (t < 0.9) return { pitch: PUSH_OFF_PITCH * smooth(0.5, 0.88, t), pivot: BALL, lift: 0 }
  // Swing: lift off, rotate from heel-up to toes-up, return to the heel-strike pose at t = 1.
  const s = smooth(0.9, 1, t)
  return { pitch: PUSH_OFF_PITCH + (HEEL_STRIKE_PITCH - PUSH_OFF_PITCH) * s, pivot: BALL * (1 - s) + HEEL * s, lift: 14 * Math.sin(Math.PI * s) }
}

/** Live pose from the center of pressure along the foot (mm from heel): the loaded region tells where in the step we are.
 *  NaN (no load) means the foot is in the air. */
export function poseFromCop(copY: number): FootPose {
  if (Number.isNaN(copY)) return { ...FLAT_POSE, lift: 10 }
  return stancePose(Math.min(0.89, Math.max(0, peakTime(copY) - 0.04)))
}
