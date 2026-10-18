//
//  Reconstructor.swift
//  archy
//

import Foundation
import Observation
import RealityKit
import os

/// Runs `PhotogrammetrySession` on a scan's images and writes `foot.usdz`. Exposes progress for the UI.
@MainActor
@Observable
final class Reconstructor {
    enum Failure: LocalizedError {
        case notSupported
        case tooFewImages(Int)
        case noModelWritten

        var errorDescription: String? {
            switch self {
            case .notSupported: "This device can't build 3D models."
            case .tooFewImages(let count): "Only \(count) photos were saved. Scan again and take at least \(ScanFlowModel.minimumShots)."
            case .noModelWritten: "Processing finished but no model file was written."
            }
        }
    }

    let folder: ScanFolder
    let imageCount: Int

    private(set) var fractionComplete: Double = 0
    private(set) var stageText = "Starting…"
    private(set) var estimatedRemainingTime: TimeInterval?
    private(set) var isCancelling = false

    private var session: PhotogrammetrySession?

    init(folder: ScanFolder) {
        self.folder = folder
        imageCount = folder.imageCount()
    }

    /// Builds `foot.usdz`. Throws `CancellationError` if the user cancels.
    func run() async throws {
        guard PhotogrammetrySession.isSupported else { throw Failure.notSupported }
        guard imageCount >= ScanFlowModel.minimumShots else { throw Failure.tooFewImages(imageCount) }

        var configuration = PhotogrammetrySession.Configuration()
        // Reuses the capture session's checkpoint so processing starts faster.
        // Object masking (on by default) keeps the floor out of the model.
        configuration.checkpointDirectory = folder.checkpoint
        let session = try PhotogrammetrySession(input: folder.images, configuration: configuration)
        self.session = session
        defer { self.session = nil }

        let start = Date.now
        Log.reconstruction.notice("Starting reconstruction: \(self.imageCount) images → \(self.folder.modelURL.path, privacy: .public)")
        try session.process(requests: [.modelFile(url: folder.modelURL)])

        var requestError: Error?
        var lastLoggedDecile = -1
        outputs: for try await output in session.outputs {
            switch output {
            case .inputComplete:
                Log.reconstruction.notice("Input complete")
            case .requestProgress(_, let fraction):
                fractionComplete = fraction
                let decile = Int(fraction * 10)
                if decile != lastLoggedDecile {
                    lastLoggedDecile = decile
                    Log.reconstruction.notice("Progress \(decile * 10)%")
                }
            case .requestProgressInfo(_, let info):
                estimatedRemainingTime = info.estimatedRemainingTime
                if let stage = info.processingStage?.displayText, stage != stageText {
                    stageText = stage
                    Log.reconstruction.notice("Stage: \(stage, privacy: .public)")
                }
            case .requestComplete(_, let result):
                Log.reconstruction.notice("Request complete: \(String(describing: result), privacy: .public)")
            case .requestError(_, let error):
                Log.reconstruction.error("Request error: \(String(describing: error), privacy: .public)")
                requestError = error
            case .processingComplete:
                break outputs
            case .processingCancelled:
                Log.reconstruction.notice("Processing cancelled")
                throw CancellationError()
            case .invalidSample(let id, let reason):
                Log.reconstruction.warning("Invalid sample \(id): \(reason, privacy: .public)")
            case .skippedSample(let id):
                Log.reconstruction.warning("Skipped sample \(id)")
            case .automaticDownsampling:
                Log.reconstruction.notice("Automatic downsampling (low memory)")
            case .stitchingIncomplete:
                Log.reconstruction.warning("Stitching incomplete: some photos didn't connect to the rest")
            @unknown default:
                Log.reconstruction.warning("Unknown output: \(String(describing: output), privacy: .public)")
            }
        }

        if let requestError { throw requestError }
        guard FileManager.default.fileExists(atPath: folder.modelURL.path) else { throw Failure.noModelWritten }
        let seconds = Int(Date.now.timeIntervalSince(start))
        let megabytes = ScanFolder.sizeInMB(of: folder.modelURL)
        Log.reconstruction.notice("foot.usdz written in \(seconds)s, \(megabytes, format: .fixed(precision: 1)) MB")
    }

    func cancel() {
        Log.reconstruction.notice("Cancel requested")
        isCancelling = true
        session?.cancel()
    }
}

private extension PhotogrammetrySession.Output.ProcessingStage {
    var displayText: String {
        switch self {
        case .preProcessing: "Preparing photos…"
        case .imageAlignment: "Aligning photos…"
        case .pointCloudGeneration: "Building point cloud…"
        case .meshGeneration: "Building mesh…"
        case .textureMapping: "Adding color…"
        case .optimization: "Optimizing…"
        @unknown default: "Processing…"
        }
    }
}
