import SwiftUI

/// Capture, processing or sample failure. Short title, the reason, and the way forward.
@MainActor
struct ScanFailedView: View {
    let message: String
    /// The photos are still saved, so processing can run again.
    let canRetry: Bool
    var dismissTitle = "New scan"
    let onRetry: () -> Void
    let onNewScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Spacer()
            Text("That didn't work")
                .display(.title)
                .accessibilityAddTraits(.isHeader)
                .reveal(0)
            Text(message)
                .foregroundStyle(.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(1)
            Spacer()
            VStack(spacing: Space.sm) {
                if canRetry {
                    Button("Try again", action: onRetry)
                        .buttonStyle(.archyPrimary)
                        .accessibilityIdentifier("scan.retry")
                    Button(dismissTitle, action: onNewScan)
                        .buttonStyle(.archySecondary)
                        .accessibilityIdentifier("scan.new")
                } else {
                    Button(dismissTitle, action: onNewScan)
                        .buttonStyle(.archyPrimary)
                        .accessibilityIdentifier("scan.new")
                }
            }
            .reveal(2)
        }
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.sm)
    }
}
