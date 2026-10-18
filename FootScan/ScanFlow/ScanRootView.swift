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
        // A ZStack, not a Group: a Group passes its modifiers to whichever child is showing, so the
        // sheet's presenter and onAppear would be replaced on every screen change.
        ZStack {
            screen
        }
        .onAppear {
            // Keep the screen awake during capture and processing.
            UIApplication.shared.isIdleTimerDisabled = true
            model.begin()
        }
        // Here rather than on the capture screen: on the first scan it shows before the camera exists.
        // The camera starts or resumes in onDismiss, after the sheet has finished animating away.
        .sheet(isPresented: Binding(get: { model.isShowingTips }, set: { model.setTipsPresented($0) }),
               onDismiss: { model.tipsDismissed() }) {
            ScanTipsSheet { model.setTipsPresented(false) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // iOS may suspend processing in the background; this shows up in the logs if it happens.
            Log.flow.notice("App scene phase \(String(describing: newPhase), privacy: .public) during \(String(describing: model.phase), privacy: .public)")
        }
    }

    @ViewBuilder
    private var screen: some View {
        if !model.isSupported && model.phase == .ready {
            UnsupportedDeviceView()
        } else {
            switch model.phase {
            case .ready, .detecting, .capturing, .finishing:
                if let session = model.session {
                    CaptureView(session: session)
                } else {
                    CameraNotStartedView()
                }
            case .reconstructing:
                if let reconstructor = model.reconstructor {
                    ReconstructionView(reconstructor: reconstructor)
                } else {
                    ProgressView("Saving model…")
                }
            case .viewing:
                if let folder = model.folder {
                    ModelViewerView(folder: folder)
                }
            case .failed(let message):
                FailedView(message: message)
            }
        }
    }
}

/// Behind the first-launch tips sheet, and a way out if the camera ever fails to start after it closes.
private struct CameraNotStartedView: View {
    @Environment(ScanFlowModel.self) private var model

    var body: some View {
        if model.isShowingTips {
            Color.clear
        } else {
            ContentUnavailableView {
                Label("Camera Not Started", systemImage: "camera")
            } description: {
                Text("Tap Start Camera to begin scanning.")
            } actions: {
                Button("Start Camera") { model.tipsDismissed() }
                    .buttonStyle(.borderedProminent)
            }
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
