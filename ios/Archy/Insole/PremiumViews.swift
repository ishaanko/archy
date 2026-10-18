import SwiftUI

@MainActor @Observable
final class InsoleRequestStore {
    private(set) var requests: [InsoleRequest] = []
    var error: String?
    private let folder = URL.applicationSupportDirectory.appending(path: "archy/requests", directoryHint: .isDirectory)
    init() { reload() }
    func reload() {
        do {
            guard FileManager.default.fileExists(atPath: folder.path) else { return }
            requests = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { try JSONDecoder().decode(InsoleRequest.self, from: Data(contentsOf: $0)) }.sorted { $0.createdAt > $1.createdAt }
            error = nil
        } catch { self.error = "Saved requests could not be opened. Existing files have been kept." }
    }
    func save(_ request: InsoleRequest) -> URL? {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(request).write(to: url(request), options: [.atomic, .completeFileProtection])
            reload(); return url(request)
        } catch { self.error = "The request could not be saved. Please try again."; return nil }
    }
    func url(_ request: InsoleRequest) -> URL { folder.appending(path: "AstroFit-\(request.id.uuidString).json") }
    func delete(_ request: InsoleRequest) {
        do { try FileManager.default.removeItem(at: url(request)); reload() }
        catch { self.error = "The request could not be deleted." }
    }
}

struct PremiumHome: View {
    @Environment(InsoleRequestStore.self) private var requests
    @State private var accessibility = false
    @State private var voice = GuidanceVoice()
    @AppStorage("accessibility.voiceGuidance") private var narration = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { ArchyWordmark(); Spacer(); Text("PREMIUM PREVIEW").font(.caption2.monospaced()).foregroundStyle(Color.archyAccent) }
                Text("One small step.\nMade yours.").font(.largeTitle.weight(.medium)).tracking(-1)
                Text("Guided movement. A fit of your own.").font(.title3).foregroundStyle(Color.archySecondary)
                NavigationLink { ExerciseLibraryView() } label: {
                    Panel {
                        HStack { Image(systemName: "figure.mind.and.body").font(.largeTitle).foregroundStyle(Color.archyAccent); Spacer(); Image(systemName: "arrow.up.right") }
                        Eyebrow(text: "01 / Movement studio")
                        Text("Find your footing.").font(.title2.weight(.medium))
                        Text("Short-foot and balance practice, with optional voice guidance.").foregroundStyle(Color.archySecondary)
                        Label("Open movement studio", systemImage: "play.circle").font(.headline)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("premium.exercises")
                NavigationLink { AstroFitView() } label: {
                    Panel {
                        HStack { Image(systemName: "shoeprints.fill").font(.largeTitle).foregroundStyle(Color.archyAccent); Spacer(); Text("ASTROFIT").font(.caption.monospaced()); Image(systemName: "arrow.up.right") }
                        Text("A fit beyond ordinary.").font(.title2.weight(.medium))
                        Text("Use your measurements to prepare a custom-insole quote request.").foregroundStyle(Color.archySecondary)
                        Label("Explore AstroFit", systemImage: "ruler").font(.headline)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("premium.astrofit")
                NavigationLink { InsoleRequestView(initialEnvironment: nil) } label: {
                    Panel {
                        HStack { Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Color.archyAccent); Spacer(); Image(systemName: "arrow.up.right") }
                        Eyebrow(text: "02 / The long shot")
                        Text("Your next orbit.").font(.title2.weight(.medium))
                        Text("An insole concept for your SpaceLab environment.").foregroundStyle(Color.archySecondary)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("premium.spaceInsole")
                Panel {
                    Label("Open for the demo", systemImage: "lock.open").font(.headline)
                    Text("Free to explore. Orders and billing are coming later.").font(.callout).foregroundStyle(Color.archySecondary)
                }
                NavigationLink { RequestHistoryView() } label: { Label("Saved requests · \(requests.requests.count)", systemImage: "tray.full").frame(minHeight: 44) }.accessibilityIdentifier("premium.requests")
                Button { accessibility = true } label: { Label("Accessibility · always included", systemImage: "accessibility").frame(minHeight: 44) }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.archyBackground).navigationTitle("Premium").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $accessibility) { GuidanceSettingsView() }
            .onAppear { if narration { voice.readScript("premium", fallback: "Welcome to Premium. Explore the exercise coach, AstroFit custom insole concepts, and Space Insole requests. Accessibility settings are always included.") } }
            .onDisappear { voice.stop() }
    }
}

private struct RequestPhotos: Decodable { let images: [String: Data] }
struct InsoleRequestView: View {
    @EnvironmentObject private var assessments: AssessmentStore
    @Environment(InsoleRequestStore.self) private var requests
    var initialEnvironment: GravityMode? = .earth
    @AppStorage("space.selectedEnvironment") private var selectedEnvironment = "Earth"
    @State private var environment: GravityMode = .earth
    @State private var recordID: UUID?
    @State private var side: FootSide = .left
    @State private var material: InsoleMaterial = .lunar
    @State private var useExample = false
    @State private var exampleAssessment = Assessment.synthetic
    @State private var includePhotos = false
    @State private var consent = false
    @State private var photos: [String: Data] = [:]
    @State private var photoError: String?
    @State private var scan: InsoleScan?
    @State private var exportURL: URL?
    @State private var preparedRequest: InsoleRequest?
    @State private var loaded = false
    private var assessment: Assessment? { useExample ? exampleAssessment : assessments.records.first { $0.id == recordID } }
    private var foot: FootMeasurements? { assessment?.measurements(for: side) }
    private var selectedPhotos: [String: Data] { photos.filter { $0.key.hasPrefix(side.rawValue + ".") } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: "AstroFit / Request studio")
                Text(environment == .earth ? "A foundation\nall your own." : "Designed for\na different world.").font(.largeTitle.weight(.medium)).tracking(-1)
                Text("Prepare a quote request. Share it when you’re ready.").foregroundStyle(Color.archySecondary)
                Panel {
                    Text("01 / Choose your foundation").font(.headline)
                    Toggle("Try sample measurements", isOn: $useExample).accessibilityIdentifier("request.example")
                    if !useExample {
                        if assessments.records.isEmpty { Text("No saved measurements yet. Add an assessment in the + tab, or try the labeled sample.").foregroundStyle(Color.archySecondary) }
                        else { Picker("Assessment", selection: $recordID) { Text("Select a record").tag(nil as UUID?); ForEach(assessments.records) { Text($0.date.formatted(date: .abbreviated, time: .shortened)).tag(Optional($0.id)) } } }
                    }
                    Picker("Foot", selection: $side) { ForEach(FootSide.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    if let foot {
                        Text(useExample ? "SYNTHETIC DEMO · NOT YOUR MEASUREMENTS" : "Saved assessment · \(assessment?.date.formatted(date: .abbreviated, time: .shortened) ?? "")").font(.caption.weight(.semibold)).foregroundStyle(Color.archyAccent)
                        ForEach(MeasurementField.allCases) { field in
                            HStack(alignment: .firstTextBaseline) { Text(field.title); Spacer(); Text("\(foot[field], specifier: "%.1f") mm").monospacedDigit() }.font(.callout)
                        }
                        Text("AHI \((try? MeasurementMath.archHeightIndex(foot)) ?? 0, specifier: "%.3f") · Not footprint Arch Index").font(.caption).foregroundStyle(Color.archySecondary)
                    }
                }
                Panel {
                    Text("02 / Imagine the design").font(.headline)
                    Picker("Environment", selection: $environment) { ForEach(GravityMode.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                    Text("\(environment.g, specifier: "%.3f") g · \(environment == .earth ? "Everyday fit review" : "Space Insole concept")").font(.caption.monospaced()).foregroundStyle(Color.archyAccent)
                    HStack(spacing: 24) {
                        InsoleShape().fill(LinearGradient(colors: [material.color, Color.archyGreen.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)).overlay(InsoleShape().stroke(Color.archyAccent, lineWidth: 1)).frame(width: previewWidth, height: 185).scaleEffect(x: side == .left ? 1 : -1, y: 1).rotationEffect(.degrees(12)).accessibilityLabel("\(side.title) insole silhouette based on length and width; no manufactured fit")
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: environment.symbol).font(.largeTitle).foregroundStyle(Color.archyAccent)
                            Text(environment == .earth ? "Fit + cushioning" : "Retention + adjustable cushioning").font(.headline)
                            Text(environment == .earth ? "Ask a fitter to review arch support and heel stability." : "Explore heel retention when loading is reduced. This is a design question for a specialist.").font(.caption).foregroundStyle(Color.archySecondary)
                        }
                    }.padding(.vertical, 14)
                    Picker("Material concept", selection: $material) { ForEach(InsoleMaterial.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Text("Gravity changes the concept, not your measurements. Specialist review is needed before manufacture or spaceflight use.").font(.footnote).foregroundStyle(Color.archySecondary)
                }
                Panel {
                    Text("03 / Review attachments").font(.headline)
                    if selectedPhotos.isEmpty { Text("No \(side.title.lowercased())-foot photos saved. Add them in + → Guided photos. You can attach a separate scan file below.").font(.callout).foregroundStyle(Color.archySecondary) }
                    else {
                        Toggle("Include \(selectedPhotos.count) reviewed foot photos", isOn: $includePhotos)
                        Text("This photo draft was collected separately. Check it matches this foot and assessment. Photos are not calibrated scans.").font(.caption).foregroundStyle(Color.archySecondary)
                        ForEach(selectedPhotos.keys.sorted(), id: \.self) { key in
                            if let data = selectedPhotos[key], let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 130).frame(maxWidth: .infinity).accessibilityLabel(key)
                                Text(key).font(.caption)
                            }
                        }
                    }
                    Divider()
                    ScanAttachmentPicker(side: side, attachment: $scan)
                    if let photoError { Text(photoError).font(.caption).foregroundStyle(.red) }
                }
                Panel {
                    Text("04 / Your data, your choice").font(.headline)
                    Text("The export contains the six measurements above for one foot, record date and ID, selected material, environment and design brief\(includePhotos ? ", plus the reviewed photos" : ", without photos"). Quiz answers and pain history are excluded.").font(.callout)
                    if let scan { Text("Scan included: \(scan.filename), \(ByteCountFormatter.string(fromByteCount: Int64(scan.bytes.count), countStyle: .file)). Calibration is unverified.").font(.callout) }
                    else { Text("No scan file included.").font(.callout) }
                    Text("Recipient: whoever you select in the iOS share sheet. Verify their identity and privacy terms before sending. Once shared, the recipient may retain a copy; deleting a local draft cannot recall it.").font(.footnote).foregroundStyle(Color.archySecondary)
                    Text("Health-data privacy: consent does not establish HIPAA compliance. The future service must assess applicable obligations before accepting health data.").font(.footnote).foregroundStyle(Color.archySecondary)
                    Toggle("I consent to preparing this data for sharing", isOn: $consent).accessibilityIdentifier("request.consent")
                    Button { prepare() } label: { Label("Prepare request on this iPhone", systemImage: "doc.badge.plus").frame(maxWidth: .infinity) }.buttonStyle(ArchyPrimaryButtonStyle()).disabled(!consent || assessment == nil || exportURL != nil).accessibilityIdentifier("request.prepare")
                    if let exportURL, let preparedRequest, consent {
                        Label("Draft saved · not sent", systemImage: "checkmark.circle").foregroundStyle(Color.archyGreen).accessibilityIdentifier("request.saved")
                        Text(preparedRequest.synthetic ? "Synthetic measurements. Any attached photos or scans are your selected files; they may contain real personal data." : "Ready for your review. Nothing has left this iPhone.").font(.caption)
                        ShareLink(item: exportURL) { Label("Share request for a quote", systemImage: "square.and.arrow.up").frame(minHeight: 44) }.accessibilityIdentifier("request.share")
                    }
                    if let error = requests.error { Text(error).foregroundStyle(.red).font(.callout) }
                    Text("No order placed or payment taken. Provider, price, turnaround and checkout will be added when a manufacturing partner is available.").font(.caption).foregroundStyle(Color.archySecondary)
                }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.archyBackground).navigationTitle("Insole request").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !loaded else { return }; loaded = true
                environment = initialEnvironment ?? GravityMode(rawValue: selectedEnvironment) ?? .earth
                recordID = assessments.records.first?.id
                loadPhotos()
            }
            .onChange(of: environment) { _, _ in invalidate() }.onChange(of: material) { _, _ in invalidate() }
            .onChange(of: side) { _, _ in includePhotos = false; scan = nil; invalidate() }.onChange(of: recordID) { _, _ in invalidate() }
            .onChange(of: scan) { _, _ in invalidate() }
            .onChange(of: useExample) { _, _ in includePhotos = false; invalidate() }.onChange(of: includePhotos) { _, _ in invalidate() }
    }
    private var previewWidth: CGFloat { guard let foot else { return 78 }; return CGFloat(min(105, max(65, 185 * foot.width / foot.fullLength))) }
    private func invalidate() { consent = false; exportURL = nil; preparedRequest = nil }
    private func prepare() {
        guard let assessment, consent else { return }
        do {
            let request = try InsoleRequest(assessment: assessment, side: side, material: material.rawValue, environment: environment.rawValue, gravity: environment.g, photos: includePhotos ? selectedPhotos : [:], consent: consent, scan: scan)
            if let url = requests.save(request) { preparedRequest = request; exportURL = url }
        } catch { requests.error = "Check your measurements and sharing consent, then try again." }
    }
    private func loadPhotos() {
        let file = URL.applicationSupportDirectory.appending(path: "archy/photo-draft.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { photos = try JSONDecoder().decode(RequestPhotos.self, from: Data(contentsOf: file)).images }
        catch { photoError = "The photo draft could not be opened. It will not be attached." }
    }
}

struct RequestHistoryView: View {
    @Environment(InsoleRequestStore.self) private var store
    @State private var toDelete: InsoleRequest?
    var body: some View {
        List {
            Section { Text("Requests are saved on this iPhone. No orders have been placed. Sharing requires a fresh review of each saved export.").font(.callout).foregroundStyle(.secondary) }
            if store.requests.isEmpty { ContentUnavailableView("No saved requests", systemImage: "tray", description: Text("Prepare a request in AstroFit to keep it here.")) }
            ForEach(store.requests) { request in
                NavigationLink { SavedRequestView(request: request) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(request.kind).font(.headline)
                        Text("\(request.side.title) · \(request.environment) · \(request.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                        Text(request.synthetic ? "Demo draft · not sent" : "Local draft · not sent").font(.caption).foregroundStyle(Color.archyAccent)
                    }
                }.swipeActions { Button("Delete", role: .destructive) { toDelete = request } }
            }
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Saved requests").confirmationDialog("Delete this local request?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Delete local request", role: .destructive) { if let request = toDelete { store.delete(request) }; toDelete = nil }
        } message: { Text("This cannot recall any copies you previously shared.") }
    }
}
private struct SavedRequestView: View {
    @Environment(InsoleRequestStore.self) private var store
    let request: InsoleRequest
    @State private var consent = false
    var body: some View {
        Form {
            Section(request.kind) {
                Text("\(request.side.title) foot · \(request.environment) · \(request.material)")
                Text(request.synthetic ? "Synthetic demo measurements" : "Saved assessment measurements")
                ForEach(MeasurementField.allCases) { field in LabeledContent(field.title, value: String(format: "%.1f mm", request.measurementsMM[field])) }
                Text(request.designIntent)
                Text("\(request.photos.count) photos included")
                if let scan = request.scan { Text("Scan file: \(scan.filename) · \(ByteCountFormatter.string(fromByteCount: Int64(scan.bytes.count), countStyle: .file)) · Unverified calibration") }
                ForEach(request.photos.keys.sorted(), id: \.self) { key in
                    if let data = request.photos[key], let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 170).accessibilityLabel(key) }
                }
            }
            Section("Review before sharing") {
                Text("Contains the selected foot measurements, assessment date and ID, design preferences, any photos shown above and the named scan file, if attached. Quiz answers and pain history are excluded. Choose and verify the recipient yourself. They may retain the export; local deletion cannot recall it. Consent does not establish HIPAA compliance.")
                Toggle("I consent to sharing this reviewed export", isOn: $consent)
                if consent { ShareLink(item: store.url(request)) { Label("Share request for a quote", systemImage: "square.and.arrow.up") } }
                Text("Draft only. No payment or order placed.").font(.footnote)
            }
        }.navigationTitle("Review request")
    }
}

