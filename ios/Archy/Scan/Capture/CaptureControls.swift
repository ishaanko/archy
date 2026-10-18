import RealityKit
import SwiftUI
import os

/// Connects the live `ObjectCaptureSession` to `CaptureOverlay`: picks the warning to show
/// (with a minimum display time) and wires the buttons to the scan model.
@MainActor
struct CaptureControls: View {
    @Environment(ScanFlowModel.self) private var model
    let session: ObjectCaptureSession

    /// The warning on screen. Updated by `updateBanner(now:)`, not straight from the session.
    @State private var warning: String?
    @State private var warningShownAt = Date.distantPast

    /// Seconds without a new photo before nudging the helper to keep moving.
    private let stallSeconds: TimeInterval = 5
    /// The session's feedback and tracking flip several times a second while the phone moves,
    /// so a warning stays up at least this long to be readable.
    private let minimumBannerSeconds: TimeInterval = 2

    var body: some View {
        CaptureOverlay(
            phase: model.phase,
            lap: model.passNumber,
            shots: session.numberOfShotsTaken,
            shotLimit: session.maximumNumberOfInputImages,
            instruction: FootGuidance.instruction(for: model.phase, lap: model.passNumber,
                                                  detectionFailed: model.detectionFailed),
            banner: warning ?? lensReminder,
            canShowHelp: session.state != .initializing,
            canFinish: session.numberOfShotsTaken >= ScanFlowModel.minimumShots,
            isPassComplete: model.isPassComplete,
            actions: .init(
                cancel: { model.cancel() },
                help: { model.showTips() },
                detect: { model.startDetecting() },
                resetBox: { model.resetBox() },
                startCapture: { model.startCapturing() },
                finish: { model.finish() },
                nextLap: { model.beginNewPass() }
            )
        )
        .task {
            while !Task.isCancelled {
                updateBanner(now: .now)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// While aiming with nothing wrong, a reminder to clean the lens.
    private var lensReminder: String? {
        model.phase == .ready && !model.isShowingTips ? FootGuidance.cleanLens : nil
    }

    /// Called twice a second. A new warning shows right away, but one that's already up stays for at
    /// least `minimumBannerSeconds`. When warnings don't apply (lap card, tips, paused), it clears at once.
    private func updateBanner(now: Date) {
        let latest = bannersApply ? warningText(now: now) : nil
        guard latest != warning else { return }
        if bannersApply, warning != nil, now.timeIntervalSince(warningShownAt) < minimumBannerSeconds { return }
        warning = latest
        warningShownAt = now
        Log.capture.info("Banner: \(latest ?? "none", privacy: .public)")
    }

    private var bannersApply: Bool {
        [.ready, .detecting, .capturing].contains(model.phase)
            && !session.isPaused && !model.isPassComplete && !model.isShowingTips
    }

    private func warningText(now: Date) -> String? {
        let isStalled = model.phase == .capturing && now.timeIntervalSince(model.lastPhotoDate) > stallSeconds
        // "Move out of the sun" can only be acted on before capture starts; mid-lap it would ruin the scan.
        let tooBright = model.brightness.isTooBright && model.phase != .capturing
        return FootGuidance.warning(feedback: session.feedback, tracking: session.cameraTracking,
                                    isStalled: isStalled, tooBright: tooBright)
    }
}
