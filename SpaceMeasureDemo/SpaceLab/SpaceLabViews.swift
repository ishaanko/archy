import SwiftUI
import OSLog

struct SpaceLabHome: View {
    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ArchyWordmark()
                    Eyebrow(text: "A laboratory for your next step")
                    Text("SpaceLab").font(.system(.largeTitle, weight: .medium)).tracking(-2)
                    Text("Explore the human foundation\nin extraordinary environments.").font(.title3).foregroundStyle(Color.archySecondary)
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color.archyCard)
                        VStack(spacing: 12) {
                            FootArchShape(height: 0.5)
                                .fill(Color.archyAccent.opacity(0.12))
                                .overlay(FootArchShape(height: 0.5).stroke(Color.archyAccent, lineWidth: 1.5))
                                .frame(height: 120)
                            HStack { Text("STRUCTURE"); Spacer(); Text("ENVIRONMENT") }
                                .font(.system(.caption2, design: .monospaced)).tracking(1)
                                .foregroundStyle(Color.archySecondary)
                        }.padding(24)
                    }.frame(height: 200)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.archyBorder)).accessibilityHidden(true)
                    NavigationLink { BiomechanicsExplorer() } label: { labCard("01", "Biomechanics Explorer", "Change your perspective on structure and gravity.", "waveform.path.ecg", .lunar) }
                    NavigationLink { AstroFitView() } label: { labCard("02", "AstroFit", "A personalized insole concept, imagined for tomorrow.", "shoeprints.fill", .mintSignal) }
                    NavigationLink { ResearchView() } label: { labCard("03", "Space Medicine", "Real research. Extraordinary human adaptation.", "books.vertical", .orange) }
                    Text("Independent educational concept. No NASA affiliation or endorsement.").font(.footnote).foregroundStyle(Color.archySecondary)
                }.padding(24)
            }
        }.foregroundStyle(Color.archyForeground).navigationTitle("").navigationBarTitleDisplayMode(.inline).tint(Color.archyForeground)
    }
    private func labCard(_ index: String, _ title: String, _ subtitle: String, _ icon: String, _ color: Color) -> some View {
        Panel(dark: true) {
            HStack { Image(systemName: icon).font(.title2).foregroundStyle(color); Spacer(); Text(index).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary); Image(systemName: "arrow.up.right") }
            Text(title).font(.title2.weight(.medium))
            Text(subtitle).font(.callout).foregroundStyle(Color.archySecondary)
        }.contentShape(Rectangle())
    }
}
enum GravityMode: String, CaseIterable, Identifiable {
    case earth = "Earth", moon = "Moon", mars = "Mars", microgravity = "Microgravity"
    var id: String { rawValue }
    var g: Double { switch self { case .earth: 1; case .moon: 0.165; case .mars: 0.38; case .microgravity: 0 } }
    var color: Color { switch self { case .earth: .mintSignal; case .moon: .lunar; case .mars: .orange; case .microgravity: .purple } }
    var symbol: String { switch self { case .earth: "globe.europe.africa.fill"; case .moon: "moon.fill"; case .mars: "sun.haze.fill"; case .microgravity: "sparkles" } }
}
struct BiomechanicsExplorer: View {
    @EnvironmentObject private var store: AssessmentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var initial: Assessment? = nil
    @State private var selectedRecord: UUID?
    @State private var side: FootSide = .left
    @State private var mode: GravityMode = .earth
    @AppStorage("space.selectedEnvironment") private var selectedEnvironment = "Earth"
    @State private var height = 60.0
    @State private var truncated = 180.0
    @State private var full = 260.0
    @State private var source = "Illustrative geometry"
    private var ahi: Double { (try? MeasurementMath.archHeightIndex(dorsumHeight: height, truncatedLength: truncated)) ?? 0 }
    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Eyebrow(text: "Interactive / Structure × environment")
                    Text("A new point\nof view.").font(.system(.largeTitle, weight: .medium))
                    HStack { Label(mode.rawValue, systemImage: mode.symbol); Spacer(); Text(String(format: "%.3f g", mode.g)).monospacedDigit() }.foregroundStyle(mode.color)
                    ZStack {
                        Ellipse().fill(mode.color.opacity(0.09)).frame(height: 90).offset(y: 75)
                        VStack { Spacer(); Rectangle().fill(mode.color.opacity(0.35)).frame(height: 1); HStack { Text("HEEL"); Spacer(); Text("FOREFOOT") }.font(.system(.caption2, design: .monospaced)).tracking(3).foregroundStyle(.secondary) }.padding(.bottom, 14)
                        FootArchShape(height: min(0.75, max(0.16, height / full * 2)))
                            .fill(LinearGradient(colors: [mode.color.opacity(0.9), Color.archyCard], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(FootArchShape(height: min(0.75, max(0.16, height / full * 2))).stroke(mode.color, lineWidth: 1.5))
                            .shadow(color: mode.color.opacity(0.35), radius: 20)
                            .padding(.horizontal, 10).padding(.vertical, 30)
                        HStack(spacing: 40) { ForEach(0..<4) { _ in Image(systemName: "arrow.down").font(.system(size: 14 + 22 * mode.g)).opacity(0.2 + mode.g * 0.7) } }.foregroundStyle(mode.color).offset(y: -85)
                    }.frame(height: 270).animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8), value: height).animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: mode)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Interactive foot arch, dorsum height \(Int(height)) millimeters. \(mode.rawValue) loading context.")
                    HStack {
                        VStack(alignment: .leading) { Eyebrow(text: "Arch height index"); Text(ahi, format: .number.precision(.fractionLength(3))).font(.system(.largeTitle, weight: .regular)).contentTransition(.numericText()) }
                        Spacer()
                        VStack(alignment: .trailing) { Text("\(height, specifier: "%.1f") mm").font(.headline); Text("dorsum height").font(.caption).foregroundStyle(.secondary) }
                    }
                    Panel(dark: true) {
                        Text("Shape the arch").font(.headline)
                        Slider(value: $height, in: 1...max(110, full - 1), step: 1).tint(mode.color).accessibilityLabel("Dorsum height in millimeters")
                        Text("AHI = height ÷ \(truncated, specifier: "%.1f") mm truncated length").font(.caption).foregroundStyle(.secondary)
                        Text(source).font(.caption).foregroundStyle(mode.color)
                    }
                    NavigationLink { InsoleRequestView(initialEnvironment: mode) } label: { Label("Explore a Space Insole request", systemImage: "shoeprints.fill").frame(minHeight: 44) }
                    Text("Choose an environment").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(GravityMode.allCases) { gravity in
                            Button { mode = gravity; selectedEnvironment = gravity.rawValue } label: {
                                VStack(alignment: .leading, spacing: 8) { Label(gravity.rawValue, systemImage: gravity.symbol).font(.headline); Text(String(format: "%.3f g", gravity.g)).font(.system(.caption, design: .monospaced)) }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(mode == gravity ? gravity.color.opacity(0.18) : Color.archyCard, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(mode == gravity ? gravity.color : .clear))
                            }.buttonStyle(.plain).accessibilityIdentifier("gravity." + gravity.rawValue).accessibilityAddTraits(mode == gravity ? .isSelected : [])
                        }
                    }
                    Panel(dark: true) {
                        Text("Start with your measurements").font(.headline)
                        Picker("Foot", selection: $side) { ForEach(FootSide.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                        if !store.records.isEmpty {
                            Picker("Assessment", selection: $selectedRecord) { Text("Choose a saved assessment").tag(nil as UUID?); ForEach(store.records) { Text($0.date.formatted(date: .abbreviated, time: .shortened)).tag(Optional($0.id)) } }
                            Button("Load selected measurements") { if let record = store.records.first(where: { $0.id == selectedRecord }) { load(record) } }.disabled(selectedRecord == nil)
                        } else { Text("Complete an assessment to load personal geometry here.").font(.callout).foregroundStyle(.secondary) }
                        Button("Reset illustrative geometry") { height = 60; truncated = 180; full = 260; source = "Illustrative geometry" }
                    }
                    Text("Gravity changes the loading arrows; the slider changes the arch. This illustration does not predict foot changes. Microgravity ≈ 0g.").font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
        }.foregroundStyle(Color.archyForeground).navigationTitle("Biomechanics").navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: mode)
            .onAppear { mode = GravityMode(rawValue: selectedEnvironment) ?? .earth; if let initial { selectedRecord = initial.id; load(initial) } }
            .onChange(of: side) { _, _ in if let initial, selectedRecord == initial.id { load(initial) } else if let record = store.records.first(where: { $0.id == selectedRecord }) { load(record) } }
    }
    private func load(_ record: Assessment) {
        let foot = record.measurements(for: side)
        guard foot.validationErrors.isEmpty else { return }
        height = foot.dorsumHeight; truncated = foot.truncatedLength; full = foot.fullLength
        source = record.isSynthetic ? "Synthetic example · \(side.title) foot" : "Saved assessment · \(side.title) foot"
        Logger(subsystem: "SpaceMeasureDemo", category: "Explorer").info("Loaded assessment geometry")
    }
}
