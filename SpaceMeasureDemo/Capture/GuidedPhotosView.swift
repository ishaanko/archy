import SwiftUI
import PhotosUI
import OSLog

private enum PhotoAngle: String, CaseIterable, Identifiable {
    case innerSide, top, rear
    var id: String { rawValue }
    var title: String { switch self { case .innerSide: "Inner side"; case .top: "Top view"; case .rear: "Rear view" } }
    var icon: String { switch self { case .innerSide: "shoeprints.fill"; case .top: "viewfinder"; case .rear: "camera.viewfinder" } }
    var instruction: String {
        switch self {
        case .innerSide: "Frame the inside of your foot at floor level. Include the heel and all toes."
        case .top: "Photograph straight down from above. Keep your heel and longest toe in the frame."
        case .rear: "Frame the heel from behind, with the camera level and the ankle visible. Ask a helper if needed."
        }
    }
}
private struct LocalPhotoSet: Codable {
    let savedAt: Date
    let images: [String: Data]
}

struct GuidedPhotosView: View {
    @State private var side: FootSide = .left
    @State private var images: [String: Data] = [:]
    @State private var loaded = false
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var voice = GuidanceVoice()
    @AppStorage("accessibility.voiceGuidance") private var automaticNarration = false
    private let logger = Logger(subsystem: "SpaceMeasureDemo", category: "PhotoDraft")
    private var file: URL { URL.applicationSupportDirectory.appending(path: "SpaceMeasureDemo/photo-draft.json") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("A clear view,\none angle at a time.").font(.largeTitle.weight(.medium)).tracking(-0.7)
                Text("Use good light and a plain background. Photos save as a draft on this iPhone. Nothing is uploaded.").foregroundStyle(.secondary)
                HStack { Label("\(images.count) of 6 photos", systemImage: "photo.stack"); Spacer(); Text("Stored on this iPhone").font(.caption).foregroundStyle(.secondary) }.font(.callout.weight(.medium))
                ProgressView(value: Double(images.count), total: 6).tint(.journeyAccent)
                Picker("Foot to photograph", selection: $side) { ForEach(FootSide.allCases) { Text("\($0.title) foot").tag($0) } }.pickerStyle(.segmented)
                ForEach(PhotoAngle.allCases) { angle in
                    PhotoCaptureRow(side: side, angle: angle, data: images[key(side, angle)]) { data in
                        images[key(side, angle)] = data
                        save(confirm: false)
                    }.id(key(side, angle))
                }
                if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout) }
                Button { save(confirm: true) } label: { Label("Save photo set on this iPhone", systemImage: "lock.shield").frame(maxWidth: .infinity).frame(minHeight: 42) }.buttonStyle(ArchyPrimaryButtonStyle()).disabled(images.count != 6)
                Text("Photo collection only. Scan analysis is not connected. Ordinary photos cannot provide footprint Arch Index, and no classification is generated from this set.").font(.footnote).foregroundStyle(.secondary)
                NavigationLink { MeasurementHome() } label: { Label("Use manual measurements for results", systemImage: "ruler").font(.callout.weight(.semibold)) }
            }.padding(24)
        }.background(Color.journeyBackground).navigationTitle("Guided photos").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { readGuide() } label: { Image(systemName: "speaker.wave.2") }.accessibilityLabel("Read photo instructions") } }
            .onAppear {
                if !loaded { load(); loaded = true }
                if automaticNarration { readGuide() }
            }
            .onChange(of: side) { _, _ in if automaticNarration { readGuide() } }
            .onDisappear { voice.stop() }
            .alert("Photo set saved locally", isPresented: $saved) { Button("Done", role: .cancel) {} } message: { Text("All six photos are saved in this app on your iPhone. Nothing was sent for analysis. Use manual measurements for calculated results.") }
    }
    private func key(_ side: FootSide, _ angle: PhotoAngle) -> String { side.rawValue + "." + angle.rawValue }
    private func readGuide() {
        voice.readScript("photos." + side.rawValue, fallback: "Photographing the \(side.title.lowercased()) foot. " + PhotoAngle.allCases.map { $0.title + ". " + $0.instruction }.joined(separator: ". ") + ". Switch feet to add the other three photos. Photos are stored locally. Analysis is not connected.")
    }
    private func load() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { images = try JSONDecoder().decode(LocalPhotoSet.self, from: Data(contentsOf: file)).images }
        catch { errorMessage = "The saved photo draft could not be opened. Your existing file is unchanged."; logger.error("Photo draft could not be loaded") }
    }
    private func save(confirm: Bool) {
        guard !images.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(LocalPhotoSet(savedAt: .now, images: images))
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            errorMessage = nil; saved = confirm
            logger.info("Photo set saved on device")
        } catch { errorMessage = "The photos could not be saved. Please try again."; logger.error("Photo set save failed") }
    }
}

private struct PhotoCaptureRow: View {
    let side: FootSide
    let angle: PhotoAngle
    let data: Data?
    let onImport: (Data) -> Void
    @State private var selection: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(angle.title, systemImage: angle.icon).font(.headline)
                Spacer()
                if data != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.journeyAccent).accessibilityLabel("Photo added") }
            }
            Text(angle.instruction).font(.callout).foregroundStyle(.secondary)
            if let preview { Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 160).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityLabel("Selected \(side.title) foot \(angle.title) photo") }
            PhotosPicker(selection: $selection, matching: .images) {
                Label(loading ? "Opening photo…" : data == nil ? "Choose photo" : "Change photo", systemImage: "photo.badge.plus").font(.callout.weight(.semibold)).frame(maxWidth: .infinity).frame(minHeight: 44)
            }.buttonStyle(.bordered).disabled(loading).accessibilityLabel("\(data == nil ? "Choose" : "Change") \(side.title) foot \(angle.title) photo")
                .accessibilityIdentifier("photo.\(side.rawValue).\(angle.rawValue)")
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }.padding(20).background(Color.archyCard, in: RoundedRectangle(cornerRadius: 12))
            .onAppear { if let data { preview = UIImage(data: data) } }
            .task(id: selection) { await importSelection() }
    }
    private func importSelection() async {
        guard let selection else { return }
        loading = true
        defer { loading = false }
        do {
            guard let bytes = try await selection.loadTransferable(type: Data.self) else { throw PhotoImportError.unreadable }
            try Task.checkCancellation()
            guard bytes.count <= 25_000_000, let original = UIImage(data: bytes),
                  let resized = original.preparingThumbnail(of: CGSize(width: 1600, height: 1600)),
                  let compressed = resized.jpegData(compressionQuality: 0.82) else { throw PhotoImportError.unreadable }
            preview = resized
            onImport(compressed)
            errorMessage = nil
        } catch is CancellationError { }
        catch { errorMessage = "This photo couldn’t be opened. Try a different image under 25 MB." }
    }
    private enum PhotoImportError: Error { case unreadable }
}
