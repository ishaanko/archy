//
//  FootGuidance.swift
//  FootScan
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

    static func instruction(for phase: ScanPhase, lap: Int, detectionFailed: Bool) -> String {
        switch phase {
        case .ready:
            detectionFailed
                ? "Can't find the foot. Step a little closer, keep the whole foot in view, and put the dot on top of it."
                : "Hold the phone about 50 cm from the foot, tilted down. Put the dot on top of the foot, then tap Continue."
        case .detecting:
            "Check the box covers the whole foot, toes to heel. Drag its top edge down to the ankle bone, then tap Start Capture."
        case .capturing:
            lap == 1
                ? "Walk slowly all the way around, phone at knee height. The ring fills in as you go; gaps show where you still need to go."
                : "Go around again with the phone low, near the floor. Take extra time on the inner side of the arch."
        case .finishing:
            "Saving photos…"
        default:
            ""
        }
    }

    /// Title and body of the card shown when a lap's ring is complete.
    static func lapCompleteText(lap: Int, photos: Int) -> (title: String, body: String) {
        if lap < plannedLaps {
            ("Lap \(lap) done", "\(photos) photos so far. Now go around once more with the phone low, near the floor, aimed at the inner arch.")
        } else {
            ("All done!", "\(photos) photos. Tap Finish to build the 3D model.")
        }
    }

    /// The most important live problem right now, or nil if capture is going fine.
    static func warning(feedback: Set<ObjectCaptureSession.Feedback>,
                        tracking: ObjectCaptureSession.Tracking) -> String? {
        switch tracking {
        case .notAvailable:
            return "Tracking lost. Move slowly back toward the foot."
        case .limited(let reason):
            switch reason {
            case .excessiveMotion: return "Slow down"
            case .insufficientFeatures: return "Point the camera at the foot and floor"
            default: return "Hold steady…"
            }
        default:
            break
        }

        let messages: [(ObjectCaptureSession.Feedback, String)] = [
            (.environmentTooDark, "Too dark. Turn on more lights."),
            (.outOfFieldOfView, "Point the camera back at the foot"),
            (.objectNotDetected, "Can't see the foot. Aim the camera at it."),
            (.movingTooFast, "Slow down"),
            (.objectTooClose, "Too close. Step back a little."),
            (.objectTooFar, "Too far. Move closer to the foot."),
            (.environmentLowLight, "More light would help"),
        ]
        return messages.first { feedback.contains($0.0) }?.1
    }

    /// Shown when no new photo has been taken for a while and nothing else explains why.
    static let keepMoving = "Keep moving around the foot. No new photos for a few seconds."
}
