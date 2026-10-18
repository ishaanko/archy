import SwiftUI
import OSLog

/// One-line wizard copy for each landmark. `halfLength` is the midpoint hint for the dorsum reading.
private extension MeasurementField {
    func prompt(halfLength: String?) -> String {
        switch self {
        case .fullLength: "Heel to the tip of your longest toe."
        case .truncatedLength: "Heel to the ball of your foot, just behind the big toe."
        case .dorsumHeight: "Floor to the top of your foot, \(halfLength.map { "\($0) from the heel" } ?? "halfway along its length")."
        case .width: "Across the widest part of your forefoot, from above."
        case .seatedNavicular: "Sitting with feet flat, floor to the bony bump on your inner midfoot."
        case .standingNavicular: "Standing evenly, floor to the same bump on your inner midfoot."
        }
    }
}

/// Twelve measurements, one per screen: six for the left foot, a short switch moment, six for the right.
/// Calls `onComplete` once the assessment is saved.
struct MeasurementWizard: View {
    let onComplete: (Assessment) -> Void
    @EnvironmentObject private var store: AssessmentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("accessibility.voiceGuidance") private var narration = false
    @State private var voice = GuidanceVoice()
    @State private var left: FootMeasurements
    @State private var right = FootMeasurements()
    @State private var step: Int
    @AppStorage(MeasurementUnit.storageKey) private var unit = MeasurementUnit.localeDefault()
    @State private var entry = ""
    @State private var message: String?
    @State private var switching = false
    @FocusState private var focused: Bool
    private let logger = Logger(subsystem: "archy", category: "Wizard")

    /// `startStep` and `left` let a debug route open straight into the right-foot half.
    init(startStep: Int = 0, left: FootMeasurements = FootMeasurements(), onComplete: @escaping (Assessment) -> Void) {
        self.onComplete = onComplete
        _step = State(initialValue: startStep)
        _left = State(initialValue: left)
    }

    private var side: FootSide { step < 6 ? .left : .right }
    private var field: MeasurementField { MeasurementField.allCases[step % 6] }
    private var current: FootMeasurements { side == .left ? left : right }
    private var parsed: Double? {
        let text = entry.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite, value > 0 else { return nil }
        return unit.toMillimeters(value)
    }
    private var animation: Animation { Motion.smooth.reduced(reduceMotion) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Space.page)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.sm)
                .background(Color.bg)
                .zIndex(1)
            ScrollView {
                content
                    .padding(.horizontal, Space.page)
                    .padding(.top, Space.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .archyScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { readInstruction() } label: { Image(systemName: "speaker.wave.2") }
                    .accessibilityLabel("Read this step aloud")
            }
        }
        .sensoryFeedback(.selection, trigger: step)
        .sensoryFeedback(.impact, trigger: switching) { _, now in now }
        .task {
            if narration { readInstruction() }
            // Wait out the push transition so the keyboard doesn't fight it.
            try? await Task.sleep(for: .milliseconds(450))
            focused = true
        }
        .onChange(of: step) { _, _ in if narration { readInstruction() } }
        .onDisappear { voice.stop() }
        .onChange(of: unit) { old, new in
            if let raw = Double(entry.replacingOccurrences(of: ",", with: ".")), raw.isFinite {
                let mm = old.toMillimeters(raw)
                entry = String(format: "%.2f", new.fromMillimeters(mm))
            }
        }
    }

    // MARK: Pieces

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            FootDiagram(field: field)
                .rotation3DEffect(.degrees(side == .right ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .animation(Motion.playful.reduced(reduceMotion), value: side)
            ZStack(alignment: .topLeading) {
                if switching {
                    switchText.id("switch").transition(.step)
                } else {
                    stepText.id(step).transition(.step)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            input
                .opacity(switching ? 0 : 1)
                .allowsHitTesting(!switching)
                .accessibilityHidden(switching)
        }
    }

    private var header: some View {
        VStack(spacing: Space.md) {
            StepProgress(value: Double(step) / 12)
            HStack {
                Text(switching ? "Left foot" : "\(side.title) foot")
                Spacer()
                Text("\(switching ? step : step + 1) of 12").monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var stepText: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(field.title).display(.title)
            Text(field.prompt(halfLength: field == .dorsumHeight ? halfLengthText : nil))
                .font(.body)
                .foregroundStyle(.inkSecondary)
        }
    }

    private var switchText: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Now your\nright foot.").display(.hero)
            Text("Same six measurements.").foregroundStyle(.inkSecondary)
        }
    }

    private var input: some View {
        VStack(spacing: Space.sm) {
            HStack(spacing: Space.md) {
                TextField("0", text: $entry)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .display(.metric)
                    .accessibilityLabel("\(side.title) \(field.title) in \(unit.spokenName)")
                    .accessibilityIdentifier("measure.field")
                ArchySegmented(selection: $unit, options: MeasurementUnit.allCases) { $0.symbol }
                    .frame(width: 112)
            }
            Rectangle().fill(focused ? Color.ink : .line3).frame(height: 1)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.negative)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .animation(Motion.snappy.reduced(reduceMotion), value: message)
    }

    private var bottomBar: some View {
        HStack(spacing: Space.md) {
            Button("Back") { back() }
                .buttonStyle(.archyGhost)
                .opacity(step == 0 ? 0 : 1)
                .disabled(step == 0)
                .accessibilityIdentifier("measure.back")
            Button(switching ? "Continue" : step == 11 ? "Save" : "Next") { advance() }
                .buttonStyle(.archyPrimary)
                .disabled(!switching && parsed == nil)
                .accessibilityIdentifier("measure.next")
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.md)
        .background(Color.bg)
    }

    /// Half of this foot's full length in the chosen unit, once the first reading is in.
    private var halfLengthText: String? {
        let half = current.fullLength / 2
        guard half > 0 else { return nil }
        return unit.format(millimeters: half)
    }

    // MARK: Actions

    private func readInstruction() {
        voice.readScript("measurement." + side.rawValue + "." + field.rawValue,
                         fallback: side.title + " foot. " + field.title + ". " + field.prompt(halfLength: nil))
    }

    private func capture() {
        guard let value = parsed else { return }
        if side == .left { left[field] = value } else { right[field] = value }
    }

    /// Saves the current entry, then shows `newStep` with its stored value (if any) in the field.
    private func go(to newStep: Int, switching showSwitch: Bool = false) {
        capture()
        let values = newStep < 6 ? left : right
        let stored = values[MeasurementField.allCases[newStep % 6]]
        entry = stored > 0 ? String(format: "%.2f", unit.fromMillimeters(stored)) : ""
        withAnimation(animation) {
            step = newStep
            switching = showSwitch
            message = nil
        }
        if showSwitch { focused = false }
    }

    private func back() {
        go(to: switching ? 5 : step - 1)
    }

    private func advance() {
        if switching {
            withAnimation(animation) { switching = false }
            focused = true
            return
        }
        guard parsed != nil else { return }
        capture()
        if step % 6 == 5, !current.validationErrors.isEmpty {
            message = current.validationErrors.joined(separator: " ") + " Use Back to correct earlier readings."
            return
        }
        switch step {
        case 5: go(to: 6, switching: true)
        case 11:
            let assessment = Assessment(left: left, right: right)
            if store.save(assessment) {
                logger.info("Completed bilateral assessment")
                focused = false
                onComplete(assessment)
            } else {
                message = store.errorMessage ?? "Could not save. Please try again."
            }
        default: go(to: step + 1)
        }
    }
}

/// Thin determinate bar that springs forward as steps complete.
private struct StepProgress: View {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule().fill(Color.line2)
            .frame(height: 3)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.ink)
                    .scaleEffect(x: max(value, 0.0001), anchor: .leading)
            }
            .clipShape(Capsule())
            .animation(Motion.smooth.reduced(reduceMotion), value: value)
            .accessibilityHidden(true)
    }
}
