import RealityKit
import SwiftUI
import os

/// What the viewer shows: the scan just made, a saved or imported scan, or the bundled sample.
enum ViewerSource {
    case scan(ScanFolder, size: SIMD3<Float>?, arch: Result<FootArchAnalysis, any Error>?)
    case saved(OpenedScan)
    case sample(SampleScan)

    /// The model as a faded clay entity in meters, from the reconstructed USDZ or the mesh already in memory,
    /// stood level on the floor the arch analysis found.
    func loadEntity() async throws -> Entity {
        let floorNormal = analysis?.floorNormal
        return switch self {
        case .scan(let folder, _, _): try FootModel.entity(for: FootMesh.load(from: folder.modelURL), floorNormal: floorNormal)
        case .saved(let opened): try FootModel.entity(for: opened.mesh, floorNormal: floorNormal)
        case .sample(let sample): try FootModel.entity(for: sample.mesh, floorNormal: floorNormal)
        }
    }

    /// Bounding box in meters, Y up.
    var size: SIMD3<Float>? {
        switch self {
        case .scan(_, let size, _): size
        case .saved(let opened): opened.mesh.size
        case .sample(let sample): sample.size
        }
    }

    var title: String {
        switch self {
        case .scan: "Your foot"
        case .saved: "Saved scan"
        case .sample: "Sample scan"
        }
    }

    var closeTitle: String {
        switch self {
        case .scan: "New scan"
        case .saved, .sample: "Back"
        }
    }

    /// The scan's folder on disk; nil for the bundled sample.
    var folder: ScanFolder? {
        switch self {
        case .scan(let folder, _, _): folder
        case .saved(let opened): opened.folder
        case .sample: nil
        }
    }

    /// Where the files ended up, for scans on disk only.
    var filesNote: String? {
        folder.map { "Also in Files › archy › Scans › \($0.root.lastPathComponent)" }
    }

    /// Flat or normal arch measured from the sole, or why it couldn't be measured.
    var arch: Result<FootArchAnalysis, any Error>? {
        switch self {
        case .scan(_, _, let arch): arch
        case .saved(let opened): opened.arch
        case .sample(let sample): sample.arch
        }
    }

    /// The arch measurement, when it succeeded.
    var analysis: FootArchAnalysis? { try? arch?.get() }

    var isRealScan: Bool {
        if case .sample = self { false } else { true }
    }
}

/// The finished scan: an interactive 3D view, its three dimensions, and sharing.
@MainActor
struct ModelViewerView: View {
    let source: ViewerSource
    let onClose: () -> Void

    @AppStorage(MeasurementUnit.storageKey) private var unit = MeasurementUnit.localeDefault()
    @State private var loadError: String?
    @State private var shareItems: [URL] = []
    @State private var isPreparingShare = false
    @State private var isShowingShareSheet = false
    /// Flips once after the screen settles: the numbers roll up and a real scan gets its success haptic.
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(source.title)
                .display(.title)
                .accessibilityAddTraits(.isHeader)
                .reveal(0)

            stage
                .reveal(1)

            if let size = source.size {
                dimensions(for: size)
            }

            switch source.arch {
            case .success(let arch):
                archCard(arch)
                    .reveal(4)
            case .failure(let error):
                archFailure(error)
                    .reveal(4)
            case nil:
                EmptyView()
            }

            HStack(spacing: Space.md) {
                Button(isPreparingShare ? "Preparing" : "Share") { isShowingShareSheet = true }
                    .buttonStyle(.archyPrimary)
                    .disabled(shareItems.isEmpty)
                    .accessibilityIdentifier("scan.share")
                Button(source.closeTitle, action: onClose)
                    .buttonStyle(.archySecondary)
                    .accessibilityIdentifier("scan.new")
            }
            .reveal(5)

            if let note = source.filesNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.inkTertiary)
                    .reveal(5)
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.lg)
        .padding(.bottom, Space.sm)
        .sensoryFeedback(.success, trigger: revealed) { _, shown in shown && source.isRealScan }
        .task { await prepareShareItems() }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            revealed = true
        }
        .sheet(isPresented: $isShowingShareSheet) {
            ShareSheet(items: shareItems) { isShowingShareSheet = false }
                .presentationDetents([.medium, .large])
        }
    }

    private var stage: some View {
        ZStack {
            FootStage(source: source) { loadError = $0 }
            if let loadError {
                Text(loadError)
                    .font(.subheadline)
                    .foregroundStyle(.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(Space.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous).strokeBorder(Color.line2))
        .accessibilityLabel("3D model of your foot. Drag to rotate, pinch to zoom.")
    }

    /// Length, width and height in the preferred unit. Length and width come from the sole when the arch was measured, since the
    /// bounding box can include the lower leg. Otherwise: Y is up, and Object Capture doesn't line the foot up
    /// with x or z consistently, so the longer horizontal side is the length.
    private func dimensions(for size: SIMD3<Float>) -> some View {
        let values: [(label: String, millimeters: Double)] = [
            ("Length", source.analysis.map { $0.footLengthCM * 10 } ?? Double(max(size.x, size.z)) * 1000),
            ("Width", source.analysis.map { $0.footWidthCM * 10 } ?? Double(min(size.x, size.z)) * 1000),
            ("Height", Double(size.y) * 1000),
        ]
        let digits = unit.fractionDigits(fine: false)
        return HStack(alignment: .top, spacing: Space.lg) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        MetricText(value: revealed ? unit.fromMillimeters(item.millimeters) : 0, fractionDigits: digits, style: .title)
                        Text(unit.symbol)
                            .font(.footnote)
                            .foregroundStyle(.inkTertiary)
                    }
                    Text(item.label)
                        .font(.footnote)
                        .foregroundStyle(.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .reveal(2 + index)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.label) \(unit.format(millimeters: item.millimeters, symbol: false)) \(unit.spokenName)")
            }
        }
    }

    /// Flat or normal, with the footprint it was read from and how far the inner arch lifts. No Arch Index:
    /// on 3D scans it can disagree with the verdict (a normal foot read 0.29).
    private func archCard(_ arch: FootArchAnalysis) -> some View {
        HStack(alignment: .center, spacing: Space.lg) {
            FootprintView(footprint: arch.footprint)
                .frame(width: 96, height: 136)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(arch.archType == .flat ? "Flat arch" : "Normal arch")
                    .display(.headline)
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    MetricText(value: revealed ? unit.fromMillimeters(arch.archHeightMM) : 0, fractionDigits: unit.fractionDigits(fine: true), style: .title)
                    Text("\(unit.symbol) lift")
                        .font(.footnote)
                        .foregroundStyle(.inkTertiary)
                }
                if arch.isSoleUneven {
                    Text("You weren't standing flat, so this is less certain.")
                        .font(.footnote)
                        .foregroundStyle(.inkSecondary)
                }
                Text("A screening estimate, not a diagnosis.")
                    .font(.caption)
                    .foregroundStyle(.inkTertiary)
            }
            Spacer(minLength: 0)
        }
        .surface(padding: Space.md)
        .accessibilityElement(children: .combine)
    }

    /// The analyzer's reason the arch has no reading. The model and STL are fine either way.
    private func archFailure(_ error: any Error) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Arch not measured")
                .display(.headline)
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(.inkSecondary)
        }
        .surface(padding: Space.md)
        .accessibilityElement(children: .combine)
    }

    /// Zips the photos (once per scan) so the share sheet can AirDrop STL, USDZ and photos together.
    /// Imported scans have no photos, so they share just their file; the sample only offers its STL.
    private func prepareShareItems() async {
        guard let folder = source.folder else {
            if case .sample(let sample) = source { shareItems = [sample.stlURL] }
            return
        }
        let models = [folder.stlURL, folder.modelURL].filter { FileManager.default.fileExists(atPath: $0.path) }
        guard folder.imageCount() > 0 else {
            shareItems = models
            return
        }
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

/// The orbitable 3D model. Loads the USDZ, centers it on the camera's pivot and reports a load failure.
@MainActor
private struct FootStage: View {
    let source: ViewerSource
    let onError: (String) -> Void

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            do {
                let foot = try await source.loadEntity()
                // Display only: shift the model so its center sits at the origin, where the camera orbits.
                // The file on disk keeps its real-world meter coordinates.
                let bounds = foot.visualBounds(relativeTo: nil)
                foot.position -= bounds.center
                let pivot = Entity()
                pivot.addChild(foot)
                // Also display only: lay the long side across the screen, then tilt the toes toward the camera.
                let yaw = bounds.extents.z > bounds.extents.x
                    ? simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) : simd_quatf(angle: 0, axis: [0, 1, 0])
                pivot.orientation = simd_quatf(angle: 0.35, axis: [1, 0, 0]) * yaw
                content.add(pivot)
                content.cameraTarget = pivot
                Log.viewer.notice("Showing \(source.title, privacy: .public), visual extents \(String(describing: bounds.extents), privacy: .public) m")
            } catch {
                Log.viewer.error("Couldn't load \(source.title, privacy: .public): \(String(describing: error), privacy: .public)")
                onError("Couldn't show the model.")
            }
        }
        .realityViewCameraControls(.orbit)
    }
}
