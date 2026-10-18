#if DEBUG
import SwiftUI

/// DEBUG-only stand-in for the camera screen (no session needed): the real overlay over a dark backdrop.
/// Reached with `-ArchyRoute scan.capture.preview` or `scan.capture.lap.preview`.
struct CapturePreview: View {
    let isLapComplete: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [.surface4, .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            CaptureScrims()
            CaptureOverlay(phase: .capturing, lap: 1, shots: 64, shotLimit: 250,
                           instruction: FootGuidance.instruction(for: .capturing, lap: 1, detectionFailed: false),
                           banner: isLapComplete ? nil : "Slow down",
                           canShowHelp: true, canFinish: true, isPassComplete: isLapComplete)
        }
        .environment(\.colorScheme, .dark)
    }
}
#endif
