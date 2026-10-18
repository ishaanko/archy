//
//  CaptureControls.swift
//  FootScan
//

import RealityKit
import SwiftUI

/// Buttons and instructions over the camera feed, switched on the scan phase.
@MainActor
struct CaptureControls: View {
    @Environment(ScanFlowModel.self) private var model
    let session: ObjectCaptureSession

    var body: some View {
        VStack(spacing: 16) {
            topBar
            Spacer()
            if model.isPassComplete {
                passCompleteCard
            } else {
                Text(instruction)
                    .font(.callout.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                bottomButtons
            }
        }
        .padding()
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            if model.phase == .detecting || model.phase == .capturing {
                Button("Cancel", role: .cancel) { model.cancel() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
            Spacer()
            if model.phase == .capturing || model.phase == .finishing {
                Text("Pass \(model.passNumber) · \(session.numberOfShotsTaken)/\(session.maximumNumberOfInputImages)")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var bottomButtons: some View {
        switch model.phase {
        case .ready:
            Button("Continue") { model.startDetecting() }
                .buttonStyle(PrimaryCaptureButtonStyle())
        case .detecting:
            HStack(spacing: 16) {
                Button("Reset Box") { model.resetBox() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                Button("Start Capture") { model.startCapturing() }
                    .buttonStyle(PrimaryCaptureButtonStyle())
            }
        case .capturing:
            Button("Finish") { model.finish() }
                .buttonStyle(PrimaryCaptureButtonStyle())
                .disabled(session.numberOfShotsTaken < ScanFlowModel.minimumShots)
        case .finishing:
            ProgressView()
                .tint(.white)
                .controlSize(.large)
        default:
            EmptyView()
        }
    }

    private var passCompleteCard: some View {
        VStack(spacing: 12) {
            Text("Pass \(model.passNumber) complete")
                .font(.headline)
            Text("\(session.numberOfShotsTaken) images so far. Do another pass from a different height, or finish.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button("Another Pass") { model.beginNewPass() }
                    .buttonStyle(.bordered)
                Button("Finish") { model.finish() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var instruction: String {
        switch model.phase {
        case .ready:
            model.detectionFailed
                ? "Can't find the foot. Move closer and center the dot on it, then tap Continue."
                : "Center the dot on the foot, then tap Continue."
        case .detecting:
            "Make sure the whole foot is inside the box. Drag the top handle down to the ankle."
        case .capturing:
            "Move slowly around the foot."
        case .finishing:
            "Saving images…"
        default:
            ""
        }
    }
}

/// The big blue capsule button used for the main action in each phase.
private struct PrimaryCaptureButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(isEnabled ? Color.blue : Color.gray, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
