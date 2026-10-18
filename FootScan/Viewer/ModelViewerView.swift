//
//  ModelViewerView.swift
//  FootScan
//

import RealityKit
import SwiftUI
import os

/// The finished scan: an interactive 3D view of `foot.usdz`, its size, and sharing.
@MainActor
struct ModelViewerView: View {
    @Environment(ScanFlowModel.self) private var model
    let folder: ScanFolder

    @State private var loadError: String?
    @State private var shareItems: [URL] = []
    @State private var isPreparingShare = false
    @State private var isShowingShareSheet = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Your Foot Scan")
                    .font(.title2.bold())
                if let arch = model.archAnalysis {
                    // Measured on the sole; the bounding box can include part of the lower leg.
                    Text("Foot \(arch.footLengthCM, format: .number.precision(.fractionLength(1))) cm long · \(arch.footWidthCM, format: .number.precision(.fractionLength(1))) cm wide")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let size = model.modelSize {
                    // Y is up. Object Capture doesn't line the foot up with x or z consistently,
                    // so the longer horizontal side is the length.
                    let length = max(size.x, size.z) * 100
                    let width = min(size.x, size.z) * 100
                    let height = size.y * 100
                    Text("\(length, format: .number.precision(.fractionLength(1))) cm long · \(width, format: .number.precision(.fractionLength(1))) cm wide · \(height, format: .number.precision(.fractionLength(1))) cm tall")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ZStack {
                RealityView { content in
                    content.camera = .virtual
                    do {
                        let foot = try await Entity(contentsOf: folder.modelURL)
                        // Display only: shift the model so its center sits at the origin, where the camera orbits.
                        // The file on disk keeps its real-world meter coordinates.
                        let bounds = foot.visualBounds(relativeTo: nil)
                        foot.position -= bounds.center
                        let pivot = Entity()
                        pivot.addChild(foot)
                        content.add(pivot)
                        content.cameraTarget = pivot
                        Log.viewer.notice("Showing \(folder.modelURL.lastPathComponent, privacy: .public), visual extents \(String(describing: bounds.extents), privacy: .public) m")
                    } catch {
                        Log.viewer.error("Couldn't load \(folder.modelURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
                        loadError = error.localizedDescription
                    }
                }
                .realityViewCameraControls(.orbit)

                if let loadError {
                    ContentUnavailableView("Couldn't Show the Model", systemImage: "cube.transparent",
                                           description: Text(loadError))
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))

            Text("Drag to rotate · pinch to zoom")
                .font(.footnote)
                .foregroundStyle(.secondary)

            archCard

            if model.isEmbedded {
                // Hands the scan back to the app that opened the scanner.
                Button {
                    model.complete()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
            }

            HStack(spacing: 12) {
                Button {
                    isShowingShareSheet = true
                } label: {
                    if isPreparingShare {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Preparing…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(shareItems.isEmpty)

                Button {
                    model.startOver()
                } label: {
                    Label("New Scan", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)

            Text("Also in Files › FootScan › Scans › \(folder.root.lastPathComponent)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .task { await prepareShareItems() }
        .sheet(isPresented: $isShowingShareSheet) {
            ShareSheet(items: shareItems) { isShowingShareSheet = false }
                .presentationDetents([.medium, .large])
        }
    }

    /// Flat vs. normal, with the footprint it was measured from.
    @ViewBuilder
    private var archCard: some View {
        if let arch = model.archAnalysis {
            let isFlat = arch.archType == .flat
            HStack(spacing: 14) {
                FootprintView(footprint: arch.footprint)
                    .frame(width: 100, height: 150)
                VStack(alignment: .leading, spacing: 6) {
                    Label(isFlat ? "Flat arch" : "Normal arch",
                          systemImage: isFlat ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(isFlat ? .orange : .green)
                    Text("Inner arch lifts \(arch.archHeightMM, format: .number.precision(.fractionLength(1))) mm off the floor (flat is under \(Int(FootArchAnalyzer.flatArchHeight * 1000)) mm).")
                        .font(.subheadline)
                    Text("Arch Index \(arch.archIndex, format: .number.precision(.fractionLength(2)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("A screening estimate, not a medical diagnosis.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        } else if let error = model.archError {
            Label("Arch not measured: \(error)", systemImage: "questionmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Zips the photos (once per scan) so the share sheet can AirDrop STL, USDZ and photos together.
    private func prepareShareItems() async {
        let models = [folder.stlURL, folder.modelURL].filter { FileManager.default.fileExists(atPath: $0.path) }
        let images = folder.images
        let zipURL = folder.imagesZipURL

        if !FileManager.default.fileExists(atPath: zipURL.path) {
            isPreparingShare = true
            let start = Date.now
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FolderZipper.zip(images, to: zipURL)
                }.value
                let seconds = Date.now.timeIntervalSince(start)
                Log.files.notice("Images.zip ready in \(seconds, format: .fixed(precision: 1))s, \(ScanFolder.sizeInMB(of: zipURL), format: .fixed(precision: 0)) MB")
            } catch {
                Log.files.error("Zipping Images failed, sharing models only: \(String(describing: error), privacy: .public)")
            }
            isPreparingShare = false
        }

        let zip = FileManager.default.fileExists(atPath: zipURL.path) ? [zipURL] : []
        shareItems = models + zip
        Log.viewer.notice("Share ready: \(shareItems.map(\.lastPathComponent).joined(separator: ", "), privacy: .public)")
    }
}
