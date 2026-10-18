import SwiftUI

enum StartupConfiguration {
    // Set an HTTPS URL to enable the website CTA. No measurements are added to the URL.
    static let websiteURL: URL? = nil
}
enum InsoleMaterial: String, CaseIterable {
    case lunar = "Lunar lattice", orbital = "Orbital foam", carbon = "Carbon weave"
    var color: Color { switch self { case .lunar: .lunar; case .orbital: .mintSignal; case .carbon: .orange } }
    var detail: String { switch self { case .lunar: "An imagined open-cell lattice for a light, sculptural feel."; case .orbital: "A soft layered-foam concept with a bold surface pattern."; case .carbon: "A woven-composite visual concept with contrasting support zones." } }
}
struct AstroFitView: View {
    @EnvironmentObject private var store: AssessmentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var side: FootSide = .left
    @State private var recordID: UUID?
    @State private var material: InsoleMaterial = .lunar
    @State private var support = 0.5
    @State private var density = 0.5
    @State private var showWebsiteInfo = false
    private var record: Assessment? { store.records.first { $0.id == recordID } }
    private var foot: FootMeasurements? { record?.measurements(for: side) }
    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Eyebrow(text: "AstroFit / Concept atelier")
                    Text("Made for\nyour orbit.").font(.system(.largeTitle, weight: .medium))
                    Text("A custom-insole vision, inspired by exploration.").foregroundStyle(.secondary)
                    insolePreview
                    Picker("Foot", selection: $side) { ForEach(FootSide.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    Panel(dark: true) {
                        Text("Personalize the foundation").font(.headline)
                        if !store.records.isEmpty {
                            Picker("Measurements", selection: $recordID) { Text("Illustrative sizing").tag(nil as UUID?); ForEach(store.records) { Text($0.date.formatted(date: .abbreviated, time: .shortened)).tag(Optional($0.id)) } }
                        }
                        if let foot {
                            Text("\(side.title) · \(foot.fullLength, specifier: "%.1f") mm length · \(foot.width, specifier: "%.1f") mm width").font(.system(.caption, design: .monospaced)).foregroundStyle(Color.mintSignal)
                            Text("AHI \((try? MeasurementMath.archHeightIndex(foot)) ?? 0, specifier: "%.3f") · Dorsum \(foot.dorsumHeight, specifier: "%.1f") mm").font(.caption).foregroundStyle(.secondary)
                        } else { Text("Illustrative sizing. Save an assessment to use your foot proportions.").font(.callout).foregroundStyle(.secondary) }
                        Text("The preview adapts its width-to-length proportions. Support and texture are visual customization only; this does not generate a manufactured or medically fitted insole.").font(.caption).foregroundStyle(.secondary)
                    }
                    Panel(dark: true) {
                        Text("Material concept").font(.headline)
                        Picker("Material", selection: $material) { ForEach(InsoleMaterial.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).tint(material.color)
                        Text(material.detail).font(.callout).foregroundStyle(.secondary)
                        Text("Arch zone intensity").font(.callout)
                        Slider(value: $support, in: 0...1).tint(material.color).accessibilityLabel("Arch zone visual intensity")
                        Text("Surface density").font(.callout)
                        Slider(value: $density, in: 0...1).tint(material.color).accessibilityLabel("Surface pattern density")
                    }
                    NavigationLink { InsoleRequestView(initialEnvironment: .earth) } label: { Label("Prepare a custom-insole request", systemImage: "doc.badge.plus").frame(maxWidth: .infinity).padding(.vertical, 4) }.buttonStyle(ArchyPrimaryButtonStyle()).accessibilityIdentifier("astrofit.request")
                    if let url = StartupConfiguration.websiteURL, url.scheme == "https" {
                        Link(destination: url) { Label("Visit the future AstroFit studio", systemImage: "arrow.up.right").frame(maxWidth: .infinity).padding() }.buttonStyle(ArchyPrimaryButtonStyle())
                    } else {
                        Button { showWebsiteInfo = true } label: { Label("AstroFit studio · Coming soon", systemImage: "arrow.up.right").frame(maxWidth: .infinity).padding() }.buttonStyle(.bordered)
                    }
                    Text("Concept only. Requests can be prepared locally and shared after consent. No checkout, NASA endorsement or medical certification.").font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
        }.foregroundStyle(Color.archyForeground).navigationTitle("AstroFit").navigationBarTitleDisplayMode(.inline).tint(Color.archyForeground)
            .sensoryFeedback(.selection, trigger: material)
            .alert("A new studio is on the horizon", isPresented: $showWebsiteInfo) { Button("Keep exploring", role: .cancel) {} } message: { Text("The separate startup website isn’t configured yet. Your customizations and measurements stay on this device.") }
    }
    private var insolePreview: some View {
                    ZStack {
                        Ellipse().fill(material.color.opacity(0.12)).frame(width: 220, height: 85).blur(radius: 15).offset(y: 130)
                        InsoleShape().fill(.black).frame(width: previewWidth, height: 300).scaleEffect(x: side == .left ? 1 : -1, y: 1).rotationEffect(.degrees(side == .left ? 18 : -18)).rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0)).offset(x: 7, y: 12)
                        ZStack {
                            InsoleShape().fill(LinearGradient(colors: [material.color.opacity(0.9), .ink, material.color.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            surfacePattern
                            supportZone
                            InsoleShape().stroke(material.color.opacity(0.8), lineWidth: 1.5)
                            Text("ASTROFIT").font(.system(.caption2, design: .monospaced, weight: .bold)).tracking(4).rotationEffect(.degrees(-90)).offset(y: 50).scaleEffect(x: side == .left ? 1 : -1, y: 1)
                        }.frame(width: previewWidth, height: 300).scaleEffect(x: side == .left ? 1 : -1, y: 1).rotationEffect(.degrees(side == .left ? 18 : -18)).rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0)).shadow(color: material.color.opacity(0.25), radius: 24)
                    }.frame(maxWidth: .infinity).frame(height: 350).animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: material).animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: side).accessibilityLabel("\(side.title) insole preview, \(material.rawValue), support \(Int(support * 100)) percent, surface density \(Int(density * 100)) percent")
    }
    private var surfacePattern: some View {
                            Canvas { context, size in
                                let spacing = 19 - density * 9
                                for row in 0..<36 {
                                    for col in 0..<22 {
                                        let x = Double(col) * spacing + (row % 2 == 0 ? 0 : spacing / 2)
                                        let y = Double(row) * spacing
                                        let rect = CGRect(x: x, y: y, width: material == .carbon ? 5 : 3, height: material == .orbital ? 6 : 3)
                                        context.fill(Path(ellipseIn: rect), with: .color(material.color.opacity(0.5)))
                                    }
                                }
                            }.clipShape(InsoleShape())
    }
    private var supportZone: some View {
        let zoneWidth: CGFloat = 38 + CGFloat(support) * 38
        let zoneHeight: CGFloat = 95 + CGFloat(support) * 50
        return Ellipse().fill(material.color.opacity(0.25 + support * 0.5))
            .frame(width: zoneWidth, height: zoneHeight)
            .offset(x: -20, y: 30).blur(radius: 8)
    }
    private var previewWidth: CGFloat {
        guard let foot else { return 155 }
        return CGFloat(min(210, max(110, 300 * foot.width / foot.fullLength * 1.4)))
    }
}
