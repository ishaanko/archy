import SwiftUI

/// Where the studio can push to.
enum InsoleRoute: Hashable {
    case saved, research, request(UUID)
}

/// The one-screen insole configurator: live top and side views, a few controls, and the request button.
struct InsoleStudioView: View {
    @EnvironmentObject private var assessments: AssessmentStore
    @Environment(InsoleRequestStore.self) private var requests
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var design: InsoleDesign
    @State private var requesting: Bool

    /// `debugRoute` is only honored in DEBUG builds: `insole.mars` selects Mars, `insole.request` opens the sheet.
    init(debugRoute: String? = nil) {
        var design = InsoleDesign()
        var requesting = false
        #if DEBUG
        if debugRoute == "insole.mars" { design.environment = .mars }
        requesting = debugRoute == "insole.request"
        #endif
        _design = State(initialValue: design)
        _requesting = State(initialValue: requesting)
    }

    /// The newest complete saved assessment, or illustrative defaults.
    private var assessment: Assessment {
        assessments.records.first { $0.left.validationErrors.isEmpty && $0.right.validationErrors.isEmpty } ?? Self.sample
    }
    private static let sample = Assessment.synthetic
    private var foot: FootMeasurements { assessment.measurements(for: design.side) }
    private var ahi: Double { (try? MeasurementMath.archHeightIndex(foot)) ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header.reveal(0)
                stage.reveal(1)
                controls.reveal(2)
                science.reveal(3)
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.lg)
        }
        .scrollIndicators(.hidden)
        .archyScreen()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { requestBar }
        .sheet(isPresented: $requesting) {
            InsoleRequestSheet(design: design, assessment: assessment)
        }
    }

    private var header: some View {
        HStack {
            Text("Your insole").display(.title)
            Spacer()
            if !requests.requests.isEmpty {
                NavigationLink(value: InsoleRoute.saved) {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full")
                        Text("\(requests.requests.count)").monospacedDigit().contentTransition(.numericText())
                    }
                }
                .buttonStyle(.archyGhost)
                .accessibilityLabel("Saved requests, \(requests.requests.count)")
                .accessibilityIdentifier("insole.saved")
            }
        }
        .animation(Motion.snappy.reduced(reduceMotion), value: requests.requests.count)
    }

    // MARK: Stage

    private var stage: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            VStack(spacing: Space.md) {
                InsoleTopView(design: design, aspect: foot.insoleAspect)
                    .frame(maxWidth: .infinity)
                ArchySegmented(selection: $design.side, options: FootSide.allCases, label: \.title)
            }
            .frame(width: 150)
            VStack(alignment: .leading, spacing: Space.lg) {
                metric(design.environment.g, digits: 2, unit: "g")
                ArchSideView(design: design, rest: foot.restingArch)
                    .frame(maxWidth: .infinity, alignment: .leading)
                metric(ahi, digits: 3, unit: "AHI", note: assessment.isSynthetic ? "Sample" : "Saved")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ value: Double, digits: Int, unit: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            MetricText(value: value, fractionDigits: digits, style: .title)
            Text(unit).font(.subheadline).foregroundStyle(.inkSecondary)
            if let note { Text(note).font(.footnote).foregroundStyle(.inkTertiary) }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            EnvironmentChips(selection: environmentBinding)
            VStack(spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("Arch support").font(.subheadline.weight(.medium))
                    Spacer()
                    MetricText(value: design.support * 100, style: .headline)
                    Text("%").font(.subheadline).foregroundStyle(.inkSecondary)
                }
                .accessibilityHidden(true)
                Slider(value: $design.support, in: 0...1)
                    .accessibilityLabel("Arch support")
                    .accessibilityValue("\(Int(design.support * 100)) percent")
                    .accessibilityIdentifier("insole.support")
            }
            .sensoryFeedback(.selection, trigger: Int((design.support * 10).rounded()))
            ArchySegmented(selection: $design.material, options: InsoleMaterial.allCases, label: \.rawValue)
        }
    }

    /// Environment changes spring the arch, wedge and zone together.
    private var environmentBinding: Binding<GravityMode> {
        Binding(get: { design.environment }, set: { mode in
            withAnimation(Motion.smooth.reduced(reduceMotion)) { design.environment = mode }
        })
    }

    // MARK: Footer

    private var science: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(spacing: 0) {
                Hairline()
                NavigationLink(value: InsoleRoute.research) {
                    HStack {
                        Text("Read the science").font(.body.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.inkTertiary)
                    }
                    .frame(minHeight: 52)
                }
                .buttonStyle(.archyPressable)
                .accessibilityIdentifier("insole.research")
                Hairline()
            }
            Text("Educational concept. Gravity doesn't change your measurements. No NASA affiliation.")
                .font(.footnote).foregroundStyle(.inkTertiary)
        }
    }

    private var requestBar: some View {
        Button("Request this insole") { requesting = true }
            .buttonStyle(.archyPrimary)
            .accessibilityIdentifier("insole.request")
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.sm)
            .background(Color.bg)
    }
}

/// Four environments as chips with a sliding pill; each shows its gravity.
private struct EnvironmentChips: View {
    @Binding var selection: GravityMode
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(GravityMode.allCases) { mode in
                let isOn = mode == selection
                Button { selection = mode } label: {
                    VStack(spacing: 2) {
                        Text(mode.title).font(.subheadline.weight(.medium))
                        Text("\(mode.g, format: .number.precision(.fractionLength(2))) g").font(.caption).foregroundStyle(.inkTertiary)
                    }
                    .foregroundStyle(isOn ? Color.ink : .inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background {
                        if isOn {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(Color.bg)
                                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Color.line2))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityValue("\(mode.g.formatted(.number.precision(.fractionLength(2)))) g")
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("insole.env.\(mode.rawValue.lowercased())")
            }
        }
        .padding(3)
        .background(Color.surface3, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .sensoryFeedback(.selection, trigger: selection)
    }
}
