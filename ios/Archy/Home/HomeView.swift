import SwiftUI

private enum HomeRoute: Hashable {
    case wizard(startStep: Int)
    case results(Assessment)
}

/// Home tab entry point. Owns its NavigationStack.
/// Debug routes: home.empty, home.seed, measure.wizard, measure.wizard.right, measure.results.example.
struct HomeTab: View {
    @Environment(AppRouter.self) private var router
    @Environment(OnboardingStore.self) private var onboarding
    @EnvironmentObject private var assessments: AssessmentStore
    @State private var path: [HomeRoute] = []
    @State private var editingAnswers = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeContent(
                forceEmpty: router.debugRoute == "home.empty",
                onScan: { router.tab = .scan },
                onMeasure: { path.append(.wizard(startStep: 0)) },
                onExample: { path.append(.results(.synthetic)) },
                onOpen: { path.append(.results($0)) },
                onEditAnswers: { editingAnswers = true },
                onSettings: { showingSettings = true }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .wizard(let startStep):
                    MeasurementWizard(startStep: startStep, left: startStep >= 6 ? Assessment.synthetic.left : FootMeasurements()) { path = [.results($0)] }
                case .results(let assessment):
                    ResultsView(assessment: assessment)
                }
            }
        }
        .sheet(isPresented: $editingAnswers) {
            OnboardingView(initial: onboarding.completed?.answers ?? OnboardingAnswers(), onCancel: { editingAnswers = false }) { answers in
                if onboarding.complete(answers) { editingAnswers = false }
            }
        }
        .sheet(isPresented: $showingSettings) { GuidanceSettingsView() }
        .task { openDebugRoute() }
    }

    private func openDebugRoute() {
        #if DEBUG
        switch router.debugRoute {
        case "home.seed": if assessments.records.isEmpty { assessments.save(.synthetic) }
        case "measure.wizard": path = [.wizard(startStep: 0)]
        case "measure.wizard.right": path = [.wizard(startStep: 6)]
        case "measure.results.example": path = [.results(.synthetic)]
        default: break
        }
        #endif
    }
}

/// The Home screen: your arch, then quick links and history.
private struct HomeContent: View {
    @EnvironmentObject private var assessments: AssessmentStore
    let forceEmpty: Bool
    let onScan: () -> Void
    let onMeasure: () -> Void
    let onExample: () -> Void
    let onOpen: (Assessment) -> Void
    let onEditAnswers: () -> Void
    let onSettings: () -> Void

    private var latest: Assessment? { forceEmpty ? nil : assessments.records.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                topBar
                if let latest {
                    ArchHero(assessment: latest).reveal(1)
                } else {
                    EmptyHero(onScan: onScan, onMeasure: onMeasure, onExample: onExample)
                }
                QuickLinks().reveal(2)
                if !assessments.records.isEmpty { history.reveal(3) }
                Button("Edit your answers", action: onEditAnswers)
                    .buttonStyle(.archyGhost)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("home.editAnswers")
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.xl)
        }
        .archyScreen()
    }

    private var topBar: some View {
        HStack {
            ArchyLogo(height: 24)
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.archyPressable)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("home.settings")
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("History").display(.headline)
                Spacer()
                Button("Measure by hand", action: onMeasure)
                    .buttonStyle(.archyGhost)
                    .font(.subheadline)
                    .accessibilityIdentifier("home.measure")
            }
            ForEach(assessments.records) { record in
                Hairline()
                Button { onOpen(record) } label: { HistoryRow(record: record) }
                    .buttonStyle(.archyPressable)
            }
        }
    }
}

/// Large arch for the latest assessment: the shape springs to the measured height, the AHI rolls, a toggle morphs between feet.
private struct ArchHero: View {
    let assessment: Assessment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var side: FootSide = .left
    @State private var risen = false

    private var ahi: Double { assessment.ahi(side) ?? 0 }
    private var dorsumMM: Int { Int(assessment.measurements(for: side).dorsumHeight.rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ArchFigure(ahi: ahi, risen: risen)
            HStack(alignment: .firstTextBaseline) {
                MetricText(value: risen ? ahi : 0, fractionDigits: 3)
                Text("AHI").foregroundStyle(.inkSecondary)
                Spacer()
                ArchySegmented(selection: $side, options: FootSide.allCases) { $0.title }
                    .frame(width: 148)
            }
            Text("Your \(side.title.lowercased()) foot stands \(dorsumMM) mm tall at its midpoint. AHI compares that to its heel-to-ball length.")
                .foregroundStyle(.inkSecondary)
                .contentTransition(.numericText())
                .animation(Motion.snappy.reduced(reduceMotion), value: side)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(Motion.playful.reduced(reduceMotion)) { risen = true }
        }
    }
}

/// First-run hero: the arch draws itself in, then the two ways to measure.
private struct EmptyHero: View {
    let onScan: () -> Void
    let onMeasure: () -> Void
    let onExample: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            ZStack {
                FootArchShape(height: 0.5).fill(Color.brand.opacity(0.14))
                    .opacity(drawn ? 1 : 0)
                    .animation(Motion.reveal.delay(0.3).reduced(reduceMotion), value: drawn)
                FootArchShape(height: 0.5)
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .animation(Motion.reveal.reduced(reduceMotion), value: drawn)
            }
            .aspectRatio(300 / 155, contentMode: .fit)
            .accessibilityHidden(true)

            Text("Check your arch.\nPrint your insole.").display(.hero)

            VStack(spacing: Space.sm) {
                Button("Scan your feet", action: onScan)
                    .buttonStyle(.archyPrimary)
                    .accessibilityIdentifier("home.scan")
                Button("Measure by hand", action: onMeasure)
                    .buttonStyle(.archySecondary)
                    .accessibilityIdentifier("home.measure")
                Button("Try an example", action: onExample)
                    .buttonStyle(.archyGhost)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("home.example")
            }
        }
        .reveal(1)
        .onAppear { drawn = true }
    }
}

/// Compact rows into the other tabs.
private struct QuickLinks: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            link("Insole", detail: "Design yours", tab: .insole)
            Hairline()
            link("Train", detail: "Short exercises", tab: .train)
        }
    }

    private func link(_ title: String, detail: String, tab: AppTab) -> some View {
        Button { router.tab = tab } label: {
            HStack {
                Text(title).font(.body.weight(.medium))
                Spacer()
                Text(detail).foregroundStyle(.inkSecondary)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.inkTertiary)
            }
            .frame(minHeight: 52)
        }
        .buttonStyle(.archyPressable)
        .accessibilityIdentifier("home.link.\(tab.rawValue)")
    }
}

/// One saved assessment: date, then left and right AHI.
private struct HistoryRow: View {
    let record: Assessment

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.date.formatted(.dateTime.month(.abbreviated).day().year()))
                if record.isSynthetic { Text("Example").font(.footnote).foregroundStyle(.inkTertiary) }
            }
            Spacer()
            ahi("L", record.ahi(.left))
            ahi("R", record.ahi(.right))
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.inkTertiary)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private func ahi(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: Space.xs) {
            Text(label).foregroundStyle(.inkTertiary)
            Text(value?.formatted(.number.precision(.fractionLength(3))) ?? "n/a").monospacedDigit()
        }
        .font(.subheadline)
    }
}
