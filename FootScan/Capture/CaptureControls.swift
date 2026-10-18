//
//  CaptureControls.swift
//  FootScan
//

import RealityKit
import SwiftUI

/// Buttons, instructions and live warnings over the camera feed, switched on the scan phase.
@MainActor
struct CaptureControls: View {
    @Environment(ScanFlowModel.self) private var model
    let session: ObjectCaptureSession

    /// Seconds without a new photo before nudging the helper to keep moving.
    private let stallSeconds: TimeInterval = 5

    var body: some View {
        VStack(spacing: 12) {
            topBar
            warningBanner
            Spacer()
            if model.isPassComplete {
                lapCompleteCard
            } else {
                if model.phase == .detecting {
                    BoxTrimDiagram()
                        .frame(maxWidth: 200)
                }
                Text(FootGuidance.instruction(for: model.phase, lap: model.passNumber,
                                              detectionFailed: model.detectionFailed))
                    .font(.callout.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                bottomButtons
            }
        }
        .padding()
        .onAppear { model.showTipsIfFirstScan() }
        .sheet(isPresented: Binding(get: { model.isShowingTips }, set: { model.setShowingTips($0) })) {
            ScanTipsSheet { model.setShowingTips(false) }
        }
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
            switch model.phase {
            case .ready, .detecting:
                Button {
                    model.setShowingTips(true)
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                }
                .tint(.white)
                .accessibilityLabel("How to scan")
            case .capturing, .finishing:
                Text("\(FootGuidance.lapLabel(model.passNumber)) · \(session.numberOfShotsTaken) photos")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            default:
                EmptyView()
            }
        }
    }

    /// The session's most important warning, a nudge when no photo has been taken for a while,
    /// or, while aiming with nothing wrong, a reminder to clean the lens.
    private var warningBanner: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let text = warningText(now: context.date) {
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.yellow, in: Capsule())
                    .transition(.opacity)
            } else if model.phase == .ready, !model.isShowingTips {
                Label(FootGuidance.cleanLens, systemImage: "sparkles")
                    .font(.callout.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: warningText(now: .now))
    }

    private func warningText(now: Date) -> String? {
        guard [.ready, .detecting, .capturing].contains(model.phase),
              !session.isPaused, !model.isPassComplete, !model.isShowingTips else { return nil }
        // "Move out of the sun" can only be acted on before capture starts; mid-lap it would ruin the scan.
        let tooBright = model.brightness.isTooBright && model.phase != .capturing
        if let warning = FootGuidance.warning(feedback: session.feedback, tracking: session.cameraTracking,
                                              tooBright: tooBright) {
            return warning
        }
        if model.phase == .capturing, now.timeIntervalSince(model.lastPhotoDate) > stallSeconds {
            return FootGuidance.keepMoving
        }
        return nil
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

    private var lapCompleteCard: some View {
        let text = FootGuidance.lapCompleteText(lap: model.passNumber, photos: session.numberOfShotsTaken)
        let moreLapsPlanned = model.passNumber < FootGuidance.plannedLaps
        return VStack(spacing: 12) {
            Label(text.title, systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(text.body)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                if moreLapsPlanned {
                    Button("Finish Now") { model.finish() }
                        .buttonStyle(.bordered)
                    Button("Start Lap \(model.passNumber + 1)") { model.beginNewPass() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Another Lap") { model.beginNewPass() }
                        .buttonStyle(.bordered)
                    Button("Finish") { model.finish() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
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
