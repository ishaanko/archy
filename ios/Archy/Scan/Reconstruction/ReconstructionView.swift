import SwiftUI

/// Progress screen while the photos are turned into a 3D model.
@MainActor
struct ReconstructionView: View {
    @Environment(ScanFlowModel.self) private var model
    let reconstructor: Reconstructor

    var body: some View {
        ReconstructionProgressView(
            fraction: reconstructor.fractionComplete,
            stage: reconstructor.isCancelling ? "Cancelling" : reconstructor.stageText,
            remaining: reconstructor.estimatedRemainingTime,
            photos: reconstructor.imageCount,
            isCancelling: reconstructor.isCancelling,
            onCancel: { model.cancelReconstruction() }
        )
    }
}

/// A determinate ring with the percent in the middle. Plain values in, so DEBUG routes can render it.
@MainActor
struct ReconstructionProgressView: View {
    let fraction: Double
    let stage: String
    let remaining: TimeInterval?
    let photos: Int
    var isCancelling = false
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Building your model")
                .display(.title)
                .accessibilityAddTraits(.isHeader)
                .reveal(0)

            Spacer()

            VStack(spacing: Space.xl) {
                ring
                    .frame(maxWidth: 260)
                VStack(spacing: Space.xs) {
                    Text(stage)
                        .font(.body.weight(.medium))
                        .contentTransition(.opacity)
                        .animation(Motion.smooth.reduced(reduceMotion), value: stage)
                    Text(timeLeft)
                        .font(.subheadline)
                        .foregroundStyle(.inkSecondary)
                        .contentTransition(.numericText())
                        .animation(Motion.snappy.reduced(reduceMotion), value: timeLeft)
                }
            }
            .frame(maxWidth: .infinity)
            .reveal(1)

            Spacer()

            VStack(spacing: Space.xs) {
                Text("\(photos) photos. Keep archy open.")
                    .font(.footnote)
                    .foregroundStyle(.inkTertiary)
                Button("Cancel") { onCancel() }
                    .buttonStyle(.archyGhost)
                    .disabled(isCancelling)
                    .accessibilityIdentifier("scan.cancelProcessing")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.lg)
        .padding(.bottom, Space.sm)
    }

    private var ring: some View {
        let clamped = min(max(fraction, 0), 1)
        return ZStack {
            Circle().stroke(Color.line2, lineWidth: 10)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Color.brand, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.smooth.reduced(reduceMotion), value: clamped)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                MetricText(value: (clamped * 100).rounded())
                Text("%")
                    .display(.headline)
                    .foregroundStyle(.inkSecondary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Building your model")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }

    private var timeLeft: String {
        guard let remaining, remaining > 0 else { return " " }
        let time = Duration.seconds(remaining).formatted(.units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 1))
        return "About \(time) left"
    }
}
