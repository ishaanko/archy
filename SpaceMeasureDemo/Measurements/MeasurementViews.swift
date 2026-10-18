import SwiftUI
import OSLog

struct MeasurementHome: View {
    @EnvironmentObject private var store: AssessmentStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Measure / Understand / Revisit")
                Text("A little precision.\nA clearer picture.").font(.largeTitle.weight(.medium))
                Panel {
                    Label("Before you begin", systemImage: "ruler").font(.title2.weight(.medium))
                    Text("Gather a tape measure, a rigid ruler, paper and a pen. Use a firm, level floor and bare feet. A helper makes vertical measurements easier.")
                    Text("Take length, width and dorsum measurements standing with weight shared evenly. Sit for the seated navicular reading, then stand for the second reading. Repeat each reading and keep posture consistent.").font(.callout).foregroundStyle(.secondary)
                    NavigationLink { MeasurementWizard() } label: { Label("Begin assessment", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(8) }.buttonStyle(ArchyPrimaryButtonStyle())
                }
                NavigationLink { ResultsView(assessment: .synthetic) } label: { Label("Explore a synthetic example", systemImage: "sparkles").font(.headline) }
                Text("Your assessment history").font(.title2.weight(.medium))
                if let error = store.errorMessage { Text(error).foregroundStyle(.red).font(.callout) }
                if store.records.isEmpty {
                    ContentUnavailableView("A fresh start", systemImage: "clock", description: Text("Completed assessments will appear here, stored only on your device."))
                }
                ForEach(store.records) { record in
                    NavigationLink { ResultsView(assessment: record) } label: {
                        Panel { HStack { VStack(alignment: .leading) { Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.headline); Text("Left + right foot · 3 measures of structure").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") } }
                    }.buttonStyle(.plain)
                }
                Text("Educational self-measurement, not a diagnosis. A tape-based home protocol is less precise than a standardized clinical instrument.").font(.footnote).foregroundStyle(.secondary)
            }.padding(22)
        }.background(Color.archyBackground).navigationTitle("Measurements").navigationBarTitleDisplayMode(.inline)
    }
}
struct MeasurementWizard: View {
    @EnvironmentObject private var store: AssessmentStore
    @State private var left = FootMeasurements()
    @State private var right = FootMeasurements()
    @State private var step = 0
    @State private var unit: MeasurementUnit = .millimeters
    @State private var entry = ""
    @State private var message: String?
    @State private var completed: Assessment?
    @FocusState private var focused: Bool
    private let logger = Logger(subsystem: "SpaceMeasureDemo", category: "Wizard")
    private var side: FootSide { step < 6 ? .left : .right }
    private var field: MeasurementField { MeasurementField.allCases[step % 6] }
    private var current: FootMeasurements { side == .left ? left : right }
    private var parsed: Double? {
        let text = entry.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite, value > 0 else { return nil }
        return unit.toMillimeters(value)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Eyebrow(text: "\(side.title) foot"); Spacer(); Text("\(step + 1) / 12").monospacedDigit().foregroundStyle(.secondary) }
                ProgressView(value: Double(step + 1), total: 12).tint(Color.archyAccent)
                Text(field.title).font(.largeTitle.weight(.medium)).id("title-\(step)")
                Panel {
                    FootDiagram(field: field)
                    Text(field.instruction).font(.headline)
                    if field == .dorsumHeight { Text("Mark the midpoint at \(current.fullLength / 2, specifier: "%.1f") mm from the heel.").font(.callout).foregroundStyle(Color.archyAccent) }
                    Label(field.landmark, systemImage: "scope").font(.callout).foregroundStyle(.secondary)
                }
                Picker("Measurement units", selection: $unit) {
                    ForEach(MeasurementUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                }.pickerStyle(.segmented)
                HStack(alignment: .firstTextBaseline) {
                    TextField("0", text: $entry).keyboardType(.decimalPad).focused($focused).font(.system(.largeTitle, weight: .medium)).accessibilityLabel("\(side.title) \(field.title) in \(unit.symbol)")
                    Text(unit.symbol).font(.title2).foregroundStyle(.secondary)
                }.padding(20).background(Color.archyCard, in: RoundedRectangle(cornerRadius: 12))
                Text("Record to the nearest millimeter. Keep the tape straight and read at eye level; don’t compress the skin.").font(.footnote).foregroundStyle(.secondary)
                if let message { Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red) }
                HStack {
                    Button("Back") { navigate(-1) }.buttonStyle(.bordered).disabled(step == 0)
                    Spacer()
                    Button(step == 11 ? "Save assessment" : "Next step", systemImage: step == 11 ? "checkmark" : "arrow.right") { advance() }.buttonStyle(ArchyPrimaryButtonStyle()).disabled(parsed == nil)
                }
                if step >= 6 { Text("Left foot complete. These entries belong to your right foot only.").font(.caption).foregroundStyle(.secondary) }
            }.padding(22)
        }.background(Color.archyBackground).navigationTitle("Guided measurement").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
            .onChange(of: unit) { old, new in
                if let raw = Double(entry.replacingOccurrences(of: ",", with: ".")), raw.isFinite {
                    let mm = old.toMillimeters(raw)
                    entry = String(format: "%.2f", new == .millimeters ? mm : mm / 10)
                }
            }
            .navigationDestination(item: $completed) { ResultsView(assessment: $0) }
    }
    private func capture() {
        guard let value = parsed else { return }
        if side == .left { left[field] = value } else { right[field] = value }
    }
    private func navigate(_ offset: Int) {
        capture(); step += offset; message = nil; focused = false
        let value = current[field]
        entry = value > 0 ? String(format: "%.2f", unit == .millimeters ? value : value / 10) : ""
    }
    private func advance() {
        guard parsed != nil else { return }
        capture(); focused = false
        if step % 6 == 5, !current.validationErrors.isEmpty { message = current.validationErrors.joined(separator: " ") + " Use Back to correct earlier readings."; return }
        if step == 11 {
            let assessment = Assessment(left: left, right: right)
            if store.save(assessment) { logger.info("Completed bilateral assessment"); completed = assessment }
            else { message = store.errorMessage ?? "Could not save. Please try again." }
        } else { navigate(1) }
    }
}
struct ResultsView: View {
    let assessment: Assessment
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: assessment.isSynthetic ? "Synthetic example / Not your measurements" : "Your foundation / On record")
                Text("Every foot tells\na different story.").font(.largeTitle.weight(.medium))
                Text(assessment.date.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
                metric("Arch Height Index", subtitle: "Dorsum height ÷ truncated length", left: try? MeasurementMath.archHeightIndex(assessment.left), right: try? MeasurementMath.archHeightIndex(assessment.right), decimals: 3, unit: "")
                metric("Navicular Drop", subtitle: "Seated height − standing height", left: try? MeasurementMath.navicularDrop(assessment.left), right: try? MeasurementMath.navicularDrop(assessment.right), decimals: 1, unit: " mm")
                metric("Width-to-Length Ratio", subtitle: "Maximum width ÷ full length", left: try? MeasurementMath.widthLengthRatio(assessment.left), right: try? MeasurementMath.widthLengthRatio(assessment.right), decimals: 3, unit: "")
                Panel {
                    Text("Read the structure, not a score.").font(.title3.bold())
                    Text("AHI describes dorsum height relative to truncated foot length. It is different from footprint-based Arch Index. Width-to-length ratio describes proportions. Navicular drop records the change between your seated and standing readings.")
                    Text("Differences between feet can reflect anatomy, posture or measurement error. Repeat readings before drawing conclusions. A negative drop means the standing reading exceeded the seated reading; recheck landmarks and posture.").foregroundStyle(.secondary)
                }
                Panel {
                    Text("Your raw measurements").font(.headline)
                    ForEach(MeasurementField.allCases) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.title).font(.callout)
                            Text("L \(assessment.left[field], specifier: "%.1f") mm    R \(assessment.right[field], specifier: "%.1f") mm").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink { BiomechanicsExplorer(initial: assessment) } label: { Label("Explore these measurements in SpaceLab", systemImage: "sparkles").frame(maxWidth: .infinity).padding(8) }.buttonStyle(ArchyPrimaryButtonStyle())
                Text("Not a diagnosis or treatment recommendation. Home measurements do not establish foot function or a clinical condition. If you have pain or concerns, discuss them with a qualified professional.").font(.footnote).foregroundStyle(.secondary)
            }.padding(22)
        }.background(Color.archyBackground).navigationTitle("Assessment").navigationBarTitleDisplayMode(.inline)
    }
    private func metric(_ title: String, subtitle: String, left: Double?, right: Double?, decimals: Int, unit: String) -> some View {
        Panel {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            HStack {
                number("LEFT", value: left, decimals: decimals, unit: unit)
                Spacer()
                number("RIGHT", value: right, decimals: decimals, unit: unit)
            }
            if let left, let right { Text("Absolute difference  \(String(format: "%.*f", decimals, abs(left - right)))\(unit)").font(.caption).foregroundStyle(Color.archyAccent) }
        }
    }
    private func number(_ label: String, value: Double?, decimals: Int, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Eyebrow(text: label); Text(value.map { String(format: "%.*f", decimals, $0) + unit } ?? "—").font(.system(.title, weight: .medium)).minimumScaleFactor(0.7).foregroundStyle(Color.archyAccent) }
    }
}
