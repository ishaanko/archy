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
    /// When the last photo was taken (or capture last resumed); drives the "keep moving" nudge.
    private(set) var lastPhotoDate = Date.now

    /// The "Before You Scan" sheet is up. On the first scan of a launch it shows before the camera exists;
    /// from the "?" button it shows over the paused camera.
    private(set) var isShowingTips = false
    private var hasShownTips = false

    /// The running reconstruction, for the progress screen.
    private(set) var reconstructor: Reconstructor?
    /// Bounding-box size of the finished model in meters (width, height, depth).
    private(set) var modelSize: SIMD3<Float>?
    /// Flat vs. normal arch for the finished model; nil if it couldn't be measured (see `archError`).
    private(set) var archAnalysis: FootArchAnalysis?
    private(set) var archError: String?
    /// The last failure happened while processing saved photos, so they can be processed again.
    private(set) var canRetryProcessing = false

    /// The session needs at least this many images to finish (same as Apple's sample).
    nonisolated static let minimumShots = 10

    let isSupported = ObjectCaptureSession.isSupported
    /// "Too bright" check for the capture screens.
    let brightness = BrightnessMonitor()

    private var sessionTasks: [Task<Void, Never>] = []

    /// Set when another app embeds the scanner through `FootScannerView`; nil in the standalone app.
    private let onComplete: ((FootScanResult) -> Void)?
    private let onClose: (() -> Void)?
    /// The host app closed the scanner; nothing may start a new scan after this.
    private var isClosed = false

    /// Embedded scanners show Done and Close buttons that hand control back to the host app.
    var isEmbedded: Bool { onComplete != nil }
    /// Startup cleanup of `Documents/Scans` has run in this app launch.
    private static var hasCleanedUp = false

    init(onComplete: ((FootScanResult) -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self.onComplete = onComplete
        self.onClose = onClose
        Log.flow.notice("Scanner launched (\(onComplete == nil ? "standalone" : "embedded", privacy: .public)). ObjectCaptureSession.isSupported = \(self.isSupported)")
        // No file cleanup here: a host app's FootScannerView can build (and discard) a model on every
        // redraw, and cleanup deletes empty scan folders, including the folder of a scan in progress.
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
            let mesh = try FootMesh.load(from: folder.modelURL)
            modelSize = mesh.size
            analyzeArch(mesh)
            self.folder = folder
            phase = .viewing
            Log.flow.notice("Opened saved scan \(name, privacy: .public) from launch argument")
        } catch {
            Log.flow.error("Couldn't open saved scan \(name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
    #endif

    // MARK: - Actions

    /// Starts a new scan. It checks free space first, then either shows the tips (first scan of
    /// this launch; the camera starts in `tipsDismissed()`) or starts the camera right away.
    /// Does nothing while a scan or the tips are already under way, so repeated calls are harmless.
    func begin() {
        guard isSupported else {
            Log.capture.error("Not starting a session: this device doesn't support Object Capture")
            return
        }
        guard session == nil, phase == .ready, !isShowingTips, !isClosed else { return }

        // Once per app launch, before any scan folder of this launch exists.
        if !Self.hasCleanedUp {
            Self.hasCleanedUp = true
            ScanFolder.cleanUp()
        }

        // Before the tips and before creating a folder: the session fails right away below 4 GB free.
        let freeBytes = ScanFolder.freeBytes()
        Log.files.notice("Free space: \(freeBytes.map(ScanFolder.formatted) ?? "unknown", privacy: .public)")
        if let freeBytes, freeBytes < ScanFolder.requiredFreeBytes {
            fail(ScanFolder.storageMessage())
            return
        }

        if !hasShownTips {
            hasShownTips = true
            isShowingTips = true
            Log.capture.notice("Tips sheet shown; camera starts after it closes")
            return
        }
        startCaptureSession()
    }

    /// Creates a fresh scan folder and capture session.
    private func startCaptureSession() {
        guard session == nil, phase == .ready, !isClosed else { return }

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
        lastPhotoDate = .now
        Log.capture.notice("Beginning scan pass \(self.passNumber)")
        // A foot can't be flipped, so the next pass keeps the same bounding box.
        session.beginNewScanPass()
        session.resume()
    }

    /// The "?" button. The camera stays on screen under the sheet, so the session is paused by hand
    /// (as Apple's sample does for its sheets). CaptureControls only offers "?" once the session is
    /// past `.initializing`: pausing a session that hasn't finished starting can leave the camera stuck.
    func showTips() {
        guard !isShowingTips else { return }
        isShowingTips = true
        session?.pause()
        Log.capture.notice("Tips sheet shown, session paused")
    }

    /// The sheet's binding setter. It only records the state; the work waits for `tipsDismissed()`.
    func setTipsPresented(_ presented: Bool) {
        isShowingTips = presented
    }

    /// Runs once the tips sheet has finished closing, and from the "Start Camera" fallback button.
    /// Resumes the paused camera, or starts it after the first-launch sheet.
    func tipsDismissed() {
        isShowingTips = false
        if let session {
            lastPhotoDate = .now
            session.resume()
            Log.capture.notice("Tips sheet closed, session resumed")
        } else {
            Log.capture.notice("Tips sheet closed, starting the camera")
            startCaptureSession()
        }
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

    /// Starts a new scan from the result or failure screen. Earlier scans stay on disk.
    func startOver() {
        Log.flow.notice("Start over")
        tearDownSession()
        reconstructor = nil
        modelSize = nil
        archAnalysis = nil
        archError = nil
        canRetryProcessing = false
        folder = nil
        phase = .ready
        begin()
    }

    func cancelReconstruction() {
        reconstructor?.cancel()
    }

    // MARK: - Embedded in another app

    /// Done on the viewer: hands the finished scan to the host app.
    func complete() {
        guard let onComplete, let folder, let modelSize, phase == .viewing else { return }
        let result = FootScanResult(folder: folder, size: modelSize, arch: archAnalysis, archError: archError)
        Log.flow.notice("Done: returning \(result.stlURL.path, privacy: .public) (arch: \(result.archType?.rawValue ?? "not measured", privacy: .public)) to the host app")
        onComplete(result)
    }

    /// Close button: stops any capture or processing, discards an unfinished capture, and hands control back.
    func close() {
        guard let onClose, !isClosed else { return }
        Log.flow.notice("Scanner closed during \(String(describing: self.phase), privacy: .public)")
        isClosed = true
        reconstructor?.cancel()
        if let session {
            session.cancel()
            tearDownSession()
            // Same as Cancel: a capture that never became a model isn't kept.
            if let folder, !FileManager.default.fileExists(atPath: folder.modelURL.path) {
                folder.delete()
            }
        }
        onClose()
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
        archAnalysis = nil
        archError = nil
        let reconstructor = Reconstructor(folder: folder)
        self.reconstructor = reconstructor
        phase = .reconstructing
        // Owned by the model, not a view, so screen changes can't cancel it.
        Task {
            do {
                try await reconstructor.run()
                try exportSTL(from: folder)
                folder.removeCheckpoint()
                self.reconstructor = nil
                phase = .viewing
            } catch is CancellationError {
                failProcessing("Processing was cancelled. Your photos are still saved.")
            } catch {
                Log.reconstruction.error("Reconstruction failed: \(String(describing: error), privacy: .public)")
                failProcessing(describe(error, as: "Building the model failed"))
            }
        }
    }

    /// Reads the mesh back from `foot.usdz`, logs its size (a scale check), writes `foot.stl`, and measures the arch.
    private func exportSTL(from folder: ScanFolder) throws {
        let mesh = try FootMesh.load(from: folder.modelURL)
        let cm = mesh.size * 100
        Log.reconstruction.notice("Mesh: \(mesh.vertices.count) vertices, \(mesh.triangleCount) triangles, size \(cm.x, format: .fixed(precision: 1)) × \(cm.y, format: .fixed(precision: 1)) × \(cm.z, format: .fixed(precision: 1)) cm (x × y × z, y up)")
        modelSize = mesh.size
        try STLExporter.write(mesh, to: folder.stlURL)
        Log.files.notice("foot.stl written: \(ScanFolder.sizeInMB(of: folder.stlURL), format: .fixed(precision: 1)) MB at \(folder.stlURL.path, privacy: .public)")
        analyzeArch(mesh)
    }

    /// A failed measurement doesn't fail the scan: the model and STL are still good, the viewer just says so.
    private func analyzeArch(_ mesh: FootMesh) {
        do {
            let arch = try FootArchAnalyzer.analyze(mesh)
            archAnalysis = arch
            archError = nil
            Log.analysis.notice("Arch height \(arch.archHeightMM, format: .fixed(precision: 1)) mm → \(arch.archType.rawValue, privacy: .public) (Arch Index \(arch.archIndex, format: .fixed(precision: 3))); sole tilt \(arch.soleTiltDegrees, format: .fixed(precision: 1))°\(arch.isSoleUneven ? " UNEVEN" : "", privacy: .public); foot \(arch.footLengthCM, format: .fixed(precision: 1)) × \(arch.footWidthCM, format: .fixed(precision: 1)) cm")
        } catch {
            archAnalysis = nil
            archError = error.localizedDescription
            Log.analysis.error("Arch analysis failed: \(String(describing: error), privacy: .public)")
        }
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
        sessionTasks.append(Task { [weak self] in
            for await count in session.numberOfShotsTakenUpdates {
                self?.lastPhotoDate = .now
                Log.capture.info("Photos taken: \(count)")
            }
        })
        sessionTasks.append(Task {
            for await feedback in session.feedbackUpdates {
                Log.capture.info("Feedback: \(String(describing: feedback), privacy: .public)")
            }
        })
        sessionTasks.append(Task { [weak self] in
            while !Task.isCancelled {
                self?.brightness.sample()
                try? await Task.sleep(for: .seconds(1))
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
            if phase != .capturing { lastPhotoDate = .now }
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
            // Don't leave an empty folder behind when the session fails before taking any photos.
            if let folder, folder.imageCount() == 0 {
                folder.delete()
                self.folder = nil
            }
            fail(describe(error, as: "Capture failed"))
        }
    }

    /// User-facing text for a framework error. Calls the concrete types' own descriptions, because
    /// `any Error` falls back to "The operation couldn't be completed (… error 1)".
    private func describe(_ error: Error, as context: String) -> String {
        if let captureError = error as? ObjectCaptureSession.Error {
            if case .insufficientStorage(let required) = captureError {
                return ScanFolder.storageMessage(requiredBytes: required)
            }
            return "\(context): \(captureError.localizedDescription)"
        }
        if let photogrammetryError = error as? PhotogrammetrySession.Error {
            if case .insufficientStorage(let required) = photogrammetryError {
                return ScanFolder.storageMessage(requiredBytes: required)
            }
            return "\(context): \(photogrammetryError.localizedDescription)"
        }
        return "\(context): \(error.localizedDescription)"
    }

    private func fail(_ message: String) {
        Log.flow.error("Failing: \(message, privacy: .public)")
        phase = .failed(message)
    }

    private func tearDownSession() {
        sessionTasks.forEach { $0.cancel() }
        sessionTasks.removeAll()
        brightness.reset()
        session = nil
        detectionFailed = false
        isPassComplete = false
        isShowingTips = false
        passNumber = 1
    }
}
