import RealityKit
import SwiftUI
import os

/// What the viewer shows: a finished scan on disk, or the bundled sample.
enum ViewerSource {
    case scan(ScanFolder, size: SIMD3<Float>?, arch: FootArchAnalysis?)
    case sample(SampleScan)

    /// The model as an entity in meters: the reconstructed USDZ, or the sample's mesh.
    func loadEntity() async throws -> Entity {
        switch self {
        case .scan(let folder, _, _): try await Entity(contentsOf: folder.modelURL)
        case .sample(let sample): try sample.makeEntity()
        }
    }

    /// Bounding box in meters, Y up.
    var size: SIMD3<Float>? {
        switch self {
        case .scan(_, let size, _): size
        case .sample(let sample): sample.size
        }
    }

    var title: String {
        switch self {
        case .scan: "Your foot"
        case .sample: "Sample scan"
        }
    }

    var closeTitle: String {
        switch self {
        case .scan: "New scan"
        case .sample: "Back"
        }
    }

    /// Where the files ended up, for real scans only.
    var filesNote: String? {
        switch self {
        case .scan(let folder, _, _): "Also in Files › archy › Scans › \(folder.root.lastPathComponent)"
        case .sample: nil
        }
    }

    /// Flat or normal arch, measured from the sole; nil when the scan's footprint couldn't be read.
    var arch: FootArchAnalysis? {
        switch self {
        case .scan(_, _, let arch): arch
        case .sample(let sample): sample.arch
        }
    }

    var isRealScan: Bool {
        if case .scan = self { true } else { false }
    }
}

/// The finished scan: an interactive 3D view, its three dimensions, and sharing.
@MainActor
struct ModelViewerView: View {
    let source: ViewerSource
    let onClose: () -> Void

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

            if let arch = source.arch {
                archCard(arch)
                    .reveal(4)
            } else if source.isRealScan {
                Text("Couldn't measure the arch on this scan. The model and STL are fine.")
                    .font(.footnote)
                    .foregroundStyle(.inkTertiary)
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

    /// Length, width and height in cm. Length and width come from the sole when the arch was measured, since the
    /// bounding box can include the lower leg. Otherwise: Y is up, and Object Capture doesn't line the foot up
    /// with x or z consistently, so the longer horizontal side is the length.
    private func dimensions(for size: SIMD3<Float>) -> some View {
        let values: [(label: String, cm: Double)] = [
            ("Length", source.arch?.footLengthCM ?? Double(max(size.x, size.z)) * 100),
            ("Width", source.arch?.footWidthCM ?? Double(min(size.x, size.z)) * 100),
            ("Height", Double(size.y) * 100),
        ]
        return HStack(alignment: .top, spacing: Space.lg) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        MetricText(value: revealed ? item.cm : 0, fractionDigits: 1, style: .title)
                        Text("cm")
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
                .accessibilityLabel("\(item.label) \(item.cm.formatted(.number.precision(.fractionLength(1)))) centimeters")
            }
        }
    }

    /// Flat or normal, with the footprint it was read from and how far the inner arch lifts.
    private func archCard(_ arch: FootArchAnalysis) -> some View {
        HStack(alignment: .center, spacing: Space.lg) {
            FootprintView(footprint: arch.footprint)
                .frame(width: 96, height: 136)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(arch.archType == .flat ? "Flat arch" : "Normal arch")
                    .display(.headline)
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    MetricText(value: revealed ? arch.archHeightMM : 0, fractionDigits: 1, style: .title)
                    Text("mm lift")
                        .font(.footnote)
                        .foregroundStyle(.inkTertiary)
                }
                Text("Arch Index \(arch.archIndex, format: .number.precision(.fractionLength(2)))")
                    .font(.footnote)
                    .foregroundStyle(.inkSecondary)
                Text("A screening estimate, not a diagnosis.")
                    .font(.caption)
                    .foregroundStyle(.inkTertiary)
            }
            Spacer(minLength: 0)
        }
        .surface(padding: Space.md)
        .accessibilityElement(children: .combine)
    }

    /// Zips the photos (once per scan) so the share sheet can AirDrop STL, USDZ and photos together.
    /// The sample only offers its STL.
    private func prepareShareItems() async {
        guard case .scan(let folder, _, _) = source else {
            if case .sample(let sample) = source { shareItems = [sample.stlURL] }
            return
        }
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
