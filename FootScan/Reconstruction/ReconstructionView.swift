//
//  ReconstructionView.swift
//  FootScan
//

import SwiftUI

/// Progress screen while the photos are turned into a 3D model.
@MainActor
struct ReconstructionView: View {
    @Environment(ScanFlowModel.self) private var model
    let reconstructor: Reconstructor

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "cube.transparent")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)

            VStack(spacing: 6) {
                Text("Building 3D Model")
                    .font(.title.bold())
                Text("\(reconstructor.imageCount) photos · keep the app open")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ProgressView(value: reconstructor.fractionComplete)
                HStack {
                    Text(reconstructor.isCancelling ? "Cancelling…" : reconstructor.stageText)
                    Spacer()
                    Text(reconstructor.fractionComplete, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                if let remaining = reconstructor.estimatedRemainingTime, remaining > 0 {
                    Text("About \(Duration.seconds(remaining).formatted(.units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 1))) left")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 32)

            Spacer()

            Button("Cancel", role: .cancel) { model.cancelReconstruction() }
                .buttonStyle(.bordered)
                .disabled(reconstructor.isCancelling)
        }
        .padding(.bottom, 24)
    }
}
