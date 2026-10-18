//
//  CaptureControls.swift
//  FootScan
//

import RealityKit
import SwiftUI
import os

/// Buttons, instructions and live warnings over the camera feed, switched on the scan phase.
@MainActor
struct CaptureControls: View {
    @Environment(ScanFlowModel.self) private var model
    let session: ObjectCaptureSession

    /// The warning on screen. Updated by `updateBanner(now:)`, not straight from the session.
    @State private var banner: String?
    @State private var bannerShownAt = Date.distantPast

    /// Seconds without a new photo before nudging the helper to keep moving.
    private let stallSeconds: TimeInterval = 5
    /// The session's feedback and tracking flip several times a second while the phone moves,
    /// so a warning stays up at least this long to be readable.
    private let minimumBannerSeconds: TimeInterval = 2

    var body: some View {
        // Text sits at the top: the middle and bottom of the feed are where the foot, the box,
        // and Apple's coverage ring and point cloud are drawn.
        VStack(spacing: 12) {
            topBar
            if !model.isPassComplete {
                instructionCard
            }
            warningBanner
            Spacer()
            if model.isPassComplete {
                lapCompleteCard
            } else {
                bottomButtons
            }
        }
        .padding()
        .task {
            while !Task.isCancelled {
                updateBanner(now: .now)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Pieces

    private var instructionCard: some View {
        HStack(spacing: 12) {
            if model.phase == .detecting {
                BoxTrimDiagram()
                    .frame(maxWidth: 110)
            }
            Text(FootGuidance.instruction(for: model.phase, lap: model.passNumber,
                                          detectionFailed: model.detectionFailed))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(model.phase == .detecting ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 380)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

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
                // Hidden while the session is still initializing: pausing it then can leave the camera stuck.
                if session.state != .initializing {
                    Button {
                        model.showTips()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.title2)
                    }
                    .tint(.white)
                    .accessibilityLabel("How to scan")
                }
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
        VStack {
            if let banner {
                Label(banner, systemImage: "exclamationmark.triangle.fill")
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
        .animation(.easeInOut(duration: 0.2), value: banner)
    }

    /// Called twice a second. A new warning shows right away, but one that's already up stays for at
    /// least `minimumBannerSeconds`. When warnings don't apply (lap card, tips, paused), it clears at once.
    private func updateBanner(now: Date) {
        let latest = bannersApply ? warningText(now: now) : nil
        guard latest != banner else { return }
        if bannersApply, banner != nil, now.timeIntervalSince(bannerShownAt) < minimumBannerSeconds { return }
        banner = latest
        bannerShownAt = now
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
