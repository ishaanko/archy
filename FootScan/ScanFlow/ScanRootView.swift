//
//  ScanRootView.swift
//  FootScan
//

import SwiftUI
import UIKit

/// Picks the screen for the current scan phase.
@MainActor
struct ScanRootView: View {
    @Environment(ScanFlowModel.self) private var model

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
                case .reconstructing, .viewing:
                    // Milestone 1 stops after capture; reconstruction and the viewer come next.
                    CaptureSavedView()
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

/// Temporary end of Milestone 1: confirms the images are on disk.
private struct CaptureSavedView: View {
    @Environment(ScanFlowModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Capture Saved", systemImage: "checkmark.circle")
        } description: {
            if let folder = model.folder {
                Text("\(folder.imageCount()) images saved to\nScans/\(folder.root.lastPathComponent)/Images")
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
            Button("Start Over") { model.startOver() }
                .buttonStyle(.borderedProminent)
        }
    }
}
