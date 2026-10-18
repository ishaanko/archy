//
//  ScanRootView.swift
//  FootScan
//

import SwiftUI
import UIKit
import os

/// Picks the screen for the current scan phase.
@MainActor
struct ScanRootView: View {
    @Environment(ScanFlowModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !model.isSupported {
                UnsupportedDeviceView()
            } else {
                switch model.phase {
                case .ready, .detecting, .capturing, .finishing:
                    if let session = model.session {
                        CaptureView(session: session)
                    } else {
                        ProgressView()
                    }
                case .reconstructing:
                    if let reconstructor = model.reconstructor {
                        ReconstructionView(reconstructor: reconstructor)
                    } else {
                        ProgressView("Saving model…")
                    }
                case .viewing:
                    ModelReadyView()
                case .failed(let message):
                    FailedView(message: message)
                }
            }
        }
        .onAppear {
            // Keep the screen awake during capture and processing.
            UIApplication.shared.isIdleTimerDisabled = true
            model.startSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // iOS may suspend processing in the background; this shows up in the logs if it happens.
            Log.flow.notice("App scene phase \(String(describing: newPhase), privacy: .public) during \(String(describing: model.phase), privacy: .public)")
        }
    }
}

private struct UnsupportedDeviceView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Scanning Not Supported", systemImage: "camera.metering.unknown")
        } description: {
            Text("FootScan needs an iPhone or iPad with a LiDAR Scanner. The Simulator can't scan.")
        }
    }
}

/// Temporary end of Milestone 2: confirms the model files exist. Milestone 3 replaces it with the 3D viewer.
private struct ModelReadyView: View {
    @Environment(ScanFlowModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Model Ready", systemImage: "checkmark.circle")
        } description: {
            VStack(spacing: 8) {
                if let size = model.modelSize {
                    let cm = size * 100
                    // The model is Y up: x = width, y = height, z = length.
                    Text("\(cm.z, format: .number.precision(.fractionLength(1))) cm long × \(cm.x, format: .number.precision(.fractionLength(1))) cm wide × \(cm.y, format: .number.precision(.fractionLength(1))) cm tall")
                        .font(.headline)
                }
                if let folder = model.folder {
                    Text("Saved foot.usdz and foot.stl in\nFiles › FootScan › Scans › \(folder.root.lastPathComponent)")
                }
            }
        } actions: {
            Button("New Scan") { model.startOver() }
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct FailedView: View {
    @Environment(ScanFlowModel.self) private var model
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if model.canRetryProcessing {
                Button("Retry Processing") { model.retryProcessing() }
                    .buttonStyle(.borderedProminent)
                Button("New Scan") { model.startOver() }
                    .buttonStyle(.bordered)
            } else {
                Button("Start Over") { model.startOver() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
