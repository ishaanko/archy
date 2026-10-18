//
//  ScanFlowModel.swift
//  FootScan
//

import Foundation
import Observation
import RealityKit
import SwiftUI  // ObjectCaptureSession lives in RealityKit's SwiftUI overlay.
import os

/// Owns the scan state machine, the current scan folder and the `ObjectCaptureSession`.
/// Views read `phase` and call the action methods; nothing else changes the phase.
@MainActor
@Observable
final class ScanFlowModel {
    private(set) var phase: ScanPhase = .ready {
        didSet {
            guard phase != oldValue else { return }
            Log.flow.notice("Phase \(String(describing: oldValue), privacy: .public) → \(String(describing: self.phase), privacy: .public)")
        }
    }

    /// The live capture session; nil once capture is over (and on devices that can't capture).
    private(set) var session: ObjectCaptureSession?
    /// The scan being captured, or the one just captured.
    private(set) var folder: ScanFolder?

    /// `startDetecting()` couldn't find an object under the dot.
    private(set) var detectionFailed = false
    /// The user just completed a scan pass; the UI offers Another Pass / Finish.
    private(set) var isPassComplete = false
    private(set) var passNumber = 1

    /// The running reconstruction, for the progress screen.
    private(set) var reconstructor: Reconstructor?
    /// Bounding-box size of the finished model in meters (width, height, depth).
    private(set) var modelSize: SIMD3<Float>?
    /// The last failure happened while processing saved photos, so they can be processed again.
    private(set) var canRetryProcessing = false

    /// The session needs at least this many images to finish (same as Apple's sample).
    nonisolated static let minimumShots = 10

    let isSupported = ObjectCaptureSession.isSupported

    private var sessionTasks: [Task<Void, Never>] = []

    init() {
        Log.flow.notice("App launched. ObjectCaptureSession.isSupported = \(self.isSupported)")
        #if DEBUG
        openScanFromLaunchArgument()
        #endif
    }

    #if DEBUG
    /// Debug builds only: launching with `-FootScanOpenScan <scan folder name>` opens that saved scan in the
    /// viewer without scanning. This is how the viewer gets checked in the Simulator.
    private func openScanFromLaunchArgument() {
        guard let name = UserDefaults.standard.string(forKey: "FootScanOpenScan") else { return }
        let folder = ScanFolder(root: ScanFolder.scansRoot.appending(path: name, directoryHint: .isDirectory))
        do {
            modelSize = try FootMesh.load(from: folder.modelURL).size
            self.folder = folder
            phase = .viewing
            Log.flow.notice("Opened saved scan \(name, privacy: .public) from launch argument")
        } catch {
            Log.flow.error("Couldn't open saved scan \(name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
    #endif

    // MARK: - Actions

    /// Creates a fresh scan folder and capture session. Safe to call repeatedly.
    func startSession() {
        guard isSupported else {
            Log.capture.error("Not starting a session: this device doesn't support Object Capture")
            return
        }
        guard session == nil, phase == .ready else { return }

        let folder: ScanFolder
        do {
            folder = try ScanFolder.createNew()
        } catch {
            fail("Couldn't create the scan folder: \(error.localizedDescription)")
            return
        }

        let session = ObjectCaptureSession()
        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = folder.checkpoint
        // Takes extra shots the iPhone doesn't use, for a higher-detail reprocess on a Mac.
        configuration.isOverCaptureEnabled = true
        session.start(imagesDirectory: folder.images, configuration: configuration)

        self.folder = folder
        self.session = session
        Log.capture.notice("Session started. Images → \(folder.images.path, privacy: .public)")

        if case .failed(let error) = session.state {
            sessionFailed(error)
            return
        }
        observe(session)
    }

    func startDetecting() {
        guard let session else { return }
        detectionFailed = !session.startDetecting()
        if detectionFailed {
            Log.capture.notice("startDetecting: no object found under the dot")
        } else {
            Log.capture.notice("startDetecting: bounding box shown")
        }
    }

    func resetBox() {
        guard let session else { return }
        let didReset = session.resetDetection()
        Log.capture.notice("resetDetection → \(didReset)")
    }

    func startCapturing() {
        Log.capture.notice("startCapturing")
        session?.startCapturing()
    }

    func beginNewPass() {
        guard let session else { return }
        passNumber += 1
        isPassComplete = false
        Log.capture.notice("Beginning scan pass \(self.passNumber)")
        // A foot can't be flipped, so the next pass keeps the same bounding box.
        session.beginNewScanPass()
        session.resume()
    }

    func finish() {
        guard let session else { return }
        isPassComplete = false
        Log.capture.notice("finish requested with \(session.numberOfShotsTaken) shots")
        session.finish()
    }

    /// Abandons the current scan. The session reports `.failed(.cancelled)`, which deletes its folder.
    func cancel() {
        Log.capture.notice("cancel requested")
        session?.cancel()
    }

    /// Returns to a fresh camera from the result or failure screen. Earlier scans stay on disk.
    func startOver() {
        Log.flow.notice("Start over")
        tearDownSession()
        reconstructor = nil
        modelSize = nil
        canRetryProcessing = false
        folder = nil
        phase = .ready
        startSession()
    }

    func cancelReconstruction() {
        reconstructor?.cancel()
    }

    /// Processes the current scan's saved photos again after a failure or cancel.
    func retryProcessing() {
        Log.flow.notice("Retry processing")
        startReconstruction()
    }

    // MARK: - Reconstruction

    private func startReconstruction() {
        guard let folder else { return }
        folder.removeOutputs()
        canRetryProcessing = false
        modelSize = nil
        let reconstructor = Reconstructor(folder: folder)
        self.reconstructor = reconstructor
        phase = .reconstructing
        // Owned by the model, not a view, so screen changes can't cancel it.
        Task {
            do {
                try await reconstructor.run()
                try exportSTL(from: folder)
                self.reconstructor = nil
                phase = .viewing
            } catch is CancellationError {
                failProcessing("Processing was cancelled. Your photos are still saved.")
            } catch {
                Log.reconstruction.error("Reconstruction failed: \(String(describing: error), privacy: .public)")
                failProcessing("Building the model failed: \(error.localizedDescription)")
            }
        }
    }

    /// Reads the mesh back from `foot.usdz`, logs its size (a scale check), and writes `foot.stl`.
    private func exportSTL(from folder: ScanFolder) throws {
        let mesh = try FootMesh.load(from: folder.modelURL)
        let cm = mesh.size * 100
        Log.reconstruction.notice("Mesh: \(mesh.vertices.count) vertices, \(mesh.triangleCount) triangles, size \(cm.x, format: .fixed(precision: 1)) × \(cm.y, format: .fixed(precision: 1)) × \(cm.z, format: .fixed(precision: 1)) cm (x × y × z, y up)")
        modelSize = mesh.size
        try STLExporter.write(mesh, to: folder.stlURL)
        Log.files.notice("foot.stl written: \(ScanFolder.sizeInMB(of: folder.stlURL), format: .fixed(precision: 1)) MB at \(folder.stlURL.path, privacy: .public)")
    }

    private func failProcessing(_ message: String) {
        reconstructor = nil
        canRetryProcessing = (folder?.imageCount() ?? 0) >= Self.minimumShots
        fail(message)
    }

    // MARK: - Session events

    private func observe(_ session: ObjectCaptureSession) {
        sessionTasks.append(Task { [weak self] in
            for await state in session.stateUpdates {
                self?.sessionStateChanged(state)
            }
        })
        sessionTasks.append(Task { [weak self] in
            for await completed in session.userCompletedScanPassUpdates where completed {
                self?.scanPassCompleted()
            }
        })
        sessionTasks.append(Task {
            for await feedback in session.feedbackUpdates {
                Log.capture.info("Feedback: \(String(describing: feedback), privacy: .public)")
            }
        })
        sessionTasks.append(Task {
            for await tracking in session.cameraTrackingUpdates {
                Log.capture.info("Camera tracking: \(String(describing: tracking), privacy: .public)")
            }
        })
    }

    private func sessionStateChanged(_ state: ObjectCaptureSession.CaptureState) {
        Log.capture.notice("Session state: \(String(describing: state), privacy: .public)")
        switch state {
        case .initializing, .ready:
            phase = .ready
        case .detecting:
            phase = .detecting
        case .capturing:
            phase = .capturing
        case .finishing:
            phase = .finishing
        case .completed:
            captureCompleted()
        case .failed(let error):
            sessionFailed(error)
        @unknown default:
            Log.capture.warning("Unknown session state: \(String(describing: state), privacy: .public)")
        }
    }

    private func scanPassCompleted() {
        guard let session else { return }
        Log.capture.notice("Scan pass \(self.passNumber) complete with \(session.numberOfShotsTaken) shots")
        // Stop taking shots while the prompt is up, like Apple's sample does under its sheets.
        session.pause()
        isPassComplete = true
    }

    private func captureCompleted() {
        guard let folder else { return }
        Log.capture.notice("Capture complete: \(folder.imageCount()) images in \(folder.images.path, privacy: .public)")
        // Release the capture session (camera, GPU memory) before reconstruction starts.
        tearDownSession()
        startReconstruction()
    }

    private func sessionFailed(_ error: Error) {
        if case ObjectCaptureSession.Error.cancelled = error {
            Log.capture.notice("Session cancelled; discarding this scan")
            folder?.delete()
            startOver()
        } else {
            Log.capture.error("Session failed: \(String(describing: error), privacy: .public)")
            tearDownSession()
            fail("Capture failed: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        Log.flow.error("Failing: \(message, privacy: .public)")
        phase = .failed(message)
    }

    private func tearDownSession() {
        sessionTasks.forEach { $0.cancel() }
        sessionTasks.removeAll()
        session = nil
        detectionFailed = false
        isPassComplete = false
        passNumber = 1
    }
}
