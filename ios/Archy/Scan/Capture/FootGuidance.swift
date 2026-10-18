//
//  FootGuidance.swift
//  archy
//

import RealityKit
import SwiftUI

/// Foot-specific wording for each scan step and for the session's live warnings.
/// Setup: the person stands barefoot; a helper circles the foot twice (knee height, then near the floor).
@MainActor
enum FootGuidance {
    /// Laps we ask for. More are allowed; the second (low) lap is what sees the inner arch.
    static let plannedLaps = 2

    static func lapLabel(_ lap: Int) -> String {
        lap <= plannedLaps ? "Lap \(lap) of \(plannedLaps)" : "Lap \(lap)"
    }

    /// One short line for the bottom of the camera.
    static func instruction(for phase: ScanPhase, lap: Int, detectionFailed: Bool) -> String {
        switch phase {
        case .ready:
            detectionFailed
                ? "Can't find the foot. Step closer and put the dot on top of it."
                : "About 50 cm away, tilted down. Dot on top of the foot, then Continue."
        case .detecting:
            "Box should cover toes to heel. Drag its top down to the ankle bone."
        case .capturing:
            lap == 1
                ? "Walk slowly around at knee height until the ring is full."
                : "Go around again, phone near the floor. Slow down at the inner arch."
        case .finishing:
            "Saving your photos"
        default:
            ""
        }
    }

    /// Title and body of the card shown when a lap's ring is complete.
    static func lapCompleteText(lap: Int) -> (title: String, body: String) {
        lap < plannedLaps
            ? ("Lap \(lap) done", "Now once more with the phone near the floor, aimed at the inner arch.")
            : ("Both laps done", "Finish to build your 3D model.")
    }

    /// The most important live problem right now, or nil if capture is going fine. Priority: tracking,
    /// problems to fix right away, the "keep moving" nudge, then lighting hints. Low light can stay on
    /// for a whole scan in a dim room, so it must not hide the nudge.
    static func warning(feedback: Set<ObjectCaptureSession.Feedback>,
                        tracking: ObjectCaptureSession.Tracking,
                        isStalled: Bool,
                        tooBright: Bool) -> String? {
        switch tracking {
        case .notAvailable:
            return "Tracking lost. Move slowly back to the foot."
        case .limited(let reason):
            switch reason {
            case .excessiveMotion: return "Slow down"
            case .insufficientFeatures: return "Point the camera at the foot and floor"
            default: return "Hold steady…"
            }
        default:
            break
        }

        let urgent: [(ObjectCaptureSession.Feedback, String)] = [
            (.environmentTooDark, "Too dark. Turn on more lights."),
            (.outOfFieldOfView, "Point the camera back at the foot"),
            (.objectNotDetected, "Can't see the foot. Aim the camera at it."),
            (.movingTooFast, "Slow down"),
            (.objectTooClose, "Too close. Step back a little."),
            (.objectTooFar, "Too far. Move closer to the foot."),
        ]
        if let message = urgent.first(where: { feedback.contains($0.0) })?.1 {
            return message
        }
        if isStalled {
            return keepMoving
        }
        if feedback.contains(.environmentLowLight) {
            return "More light would help"
        }
        // The session has no "too bright" feedback; BrightnessMonitor estimates it.
        return tooBright ? "Too bright. Move out of direct sunlight." : nil
    }

    /// Shown when no new photo has been taken for a while.
    static let keepMoving = "Keep moving around the foot"

    /// Shown while aiming, before the first photo. A smudged lens makes hazy photos and a blurry model.
    static let cleanLens = "Wipe the camera lens for sharper photos"
}
