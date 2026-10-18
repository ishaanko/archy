import SwiftUI

/// A label and value on one hairline-separated line, shared by the request sheet and saved requests.
struct InsoleDetailRow: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).foregroundStyle(.inkSecondary)
                Spacer(minLength: Space.lg)
                Text(value).multilineTextAlignment(.trailing).monospacedDigit()
            }
            .font(.body)
            .frame(minHeight: 44)
            Hairline()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Review of the configured design, optional scan, one consent, Save. Swaps to a confirmation once saved.
struct InsoleRequestSheet: View {
    let design: InsoleDesign
    let assessment: Assessment
    @Environment(InsoleRequestStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MeasurementUnit.storageKey) private var unit = MeasurementUnit.localeDefault()
    @State private var consent = false
    @State private var scan: InsoleScan?
    @State private var saved: URL?
    @State private var failed = false

    private var foot: FootMeasurements { assessment.measurements(for: design.side) }
    private var ahi: Double { (try? MeasurementMath.archHeightIndex(foot)) ?? 0 }

    var body: some View {
        ZStack {
            if saved == nil {
                review.transition(.step)
            } else if let saved {
                confirmation(saved).transition(.step)
            }
        }
        .animation(Motion.smooth.reduced(reduceMotion), value: saved)
        .archyScreen()
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: saved)
    }

    // MARK: Review

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("Request this insole").display(.title)
                VStack(spacing: 0) {
                    Hairline()
                    InsoleDetailRow(label: "Foot", value: design.side.title)
                    InsoleDetailRow(label: "Walking on", value: "\(design.environment.title), \(design.environment.g.formatted(.number.precision(.fractionLength(2)))) g")
                    InsoleDetailRow(label: "Material", value: design.material.rawValue)
                    InsoleDetailRow(label: "Arch support", value: "\(Int((design.support * 100).rounded()))%")
                    InsoleDetailRow(label: "Measurements", value: "\(unit.format(millimeters: foot.fullLength, symbol: false)) \u{00D7} \(unit.format(millimeters: foot.width, symbol: false)) \(unit.symbol), AHI \(ahi.formatted(.number.precision(.fractionLength(3))))")
                    InsoleDetailRow(label: "Source", value: assessment.isSynthetic ? "Sample" : "Saved \(assessment.date.formatted(date: .abbreviated, time: .omitted))")
                }
                VStack(spacing: 0) {
                    ScanAttachmentPicker(side: design.side, attachment: $scan)
                        .padding(.vertical, Space.md)
                    Hairline()
                }
                VStack(alignment: .leading, spacing: Space.md) {
                    Toggle("Include my measurements in this request", isOn: $consent)
                        .font(.body)
                        .accessibilityIdentifier("request.consent")
                    Button("Save request", action: save)
                        .buttonStyle(.archyPrimary)
                        .disabled(!consent)
                        .accessibilityIdentifier("insole.save")
                    if failed || store.error != nil {
                        Text(store.error ?? "Check your measurements and try again.")
                            .font(.footnote).foregroundStyle(.negative)
                    }
                    Text("Quote request only. Nothing is ordered or charged. Quiz answers stay on your phone.")
                        .font(.footnote).foregroundStyle(.inkTertiary)
                }
            }
            .padding(Space.page)
            .padding(.top, Space.md)
        }
        .scrollIndicators(.hidden)
    }

    private func save() {
        do {
            let request = try InsoleRequest(assessment: assessment, side: design.side, material: design.material.rawValue, environment: design.environment.rawValue, gravity: design.environment.g, photos: [:], consent: consent, scan: scan, support: design.support)
            failed = false
            if let url = store.save(request) { saved = url }
        } catch { failed = true }
    }

    // MARK: Confirmation

    private func confirmation(_ url: URL) -> some View {
        VStack(spacing: Space.xl) {
            Spacer()
            InsoleTopView(design: design, aspect: foot.insoleAspect, height: 200)
            VStack(spacing: Space.sm) {
                Text("Saved.").display(.hero)
                Text(design.environment.savedLine).font(.body).foregroundStyle(.inkSecondary)
            }
            .accessibilityIdentifier("request.saved")
            Spacer()
            VStack(spacing: Space.sm) {
                ShareLink(item: url) { Text("Share for a quote") }
                    .buttonStyle(.archyPrimary)
                    .accessibilityIdentifier("request.share")
                Button("Done") { dismiss() }.buttonStyle(.archyGhost)
            }
        }
        .multilineTextAlignment(.center)
        .padding(Space.page)
    }
}

private extension GravityMode {
    /// The playful line on the saved confirmation.
    var savedLine: String {
        switch self {
        case .earth: "Down to earth, and ready."
        case .moon: "One small step, mapped."
        case .mars: "Red dust, meet arch support."
        case .microgravity: "Nothing to weigh you down."
        }
    }
}
