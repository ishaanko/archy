import SwiftUI

/// A finished assessment: both arches rise to their measured height, then the detail rows.
struct ResultsView: View {
    let assessment: Assessment
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var leftRisen = false
    @State private var rightRisen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(assessment.isSynthetic ? "An example" : "Your arches").display(.title)
                    Text(subtitle).font(.subheadline).foregroundStyle(.inkSecondary)
                }
                .reveal(0)

                HStack(alignment: .bottom, spacing: Space.lg) {
                    ArchColumn(side: .left, ahi: assessment.ahi(.left), risen: leftRisen)
                    ArchColumn(side: .right, ahi: assessment.ahi(.right), risen: rightRisen)
                }

                VStack(spacing: 0) {
                    ComparisonGrid(rows: comparisonRows)
                }
                .reveal(2)

                DisclosureGroup("Raw measurements") {
                    ComparisonGrid(rows: rawRows).padding(.top, Space.sm)
                }
                .accessibilityIdentifier("results.raw")
                .reveal(3)

                Button { router.tab = .insole } label: {
                    HStack {
                        Text("Design your insole").font(.body.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.inkTertiary)
                    }
                    .frame(minHeight: 52)
                }
                .buttonStyle(.archyPressable)
                .accessibilityIdentifier("results.insole")
                .reveal(4)

                Text("Educational self-measurement, not a diagnosis. A home tape measure is less precise than clinical tools.")
                    .font(.footnote)
                    .foregroundStyle(.inkTertiary)
                    .reveal(5)
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.lg)
        }
        .archyScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: rightRisen) { _, risen in risen }
        .task {
            // Left rises first, right a beat later; the haptic fires as the second lands.
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(Motion.playful.reduced(reduceMotion)) { leftRisen = true }
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(Motion.playful.reduced(reduceMotion)) { rightRisen = true }
        }
    }

    private var subtitle: String {
        let date = assessment.date.formatted(.dateTime.month(.abbreviated).day().year())
        return assessment.isSynthetic ? "Sample numbers, not yours. \(date)" : date
    }

    private var comparisonRows: [ComparisonGrid.Row] {
        let drop = { (mm: Double) in mm.formatted(.number.precision(.fractionLength(1))) }
        let ratio = { (value: Double) in value.formatted(.number.precision(.fractionLength(3))) }
        let (l, r) = (assessment.left, assessment.right)
        return [
            row("Navicular drop, mm", try? MeasurementMath.navicularDrop(l), try? MeasurementMath.navicularDrop(r), format: drop),
            row("Width to length", try? MeasurementMath.widthLengthRatio(l), try? MeasurementMath.widthLengthRatio(r), format: ratio),
        ]
    }

    private var rawRows: [ComparisonGrid.Row] {
        MeasurementField.allCases.map { field in
            let format = { (mm: Double) in mm.formatted(.number.precision(.fractionLength(1))) }
            return ComparisonGrid.Row(title: field.title, left: format(assessment.left[field]), right: format(assessment.right[field]), difference: format(abs(assessment.left[field] - assessment.right[field])))
        }
    }

    private func row(_ title: String, _ left: Double?, _ right: Double?, format: (Double) -> String) -> ComparisonGrid.Row {
        ComparisonGrid.Row(
            title: title,
            left: left.map(format) ?? "n/a",
            right: right.map(format) ?? "n/a",
            difference: left.flatMap { l in right.map { format(abs(l - $0)) } } ?? "n/a"
        )
    }
}

/// One foot: its arch and AHI. The shape rises and the number rolls up when `risen` flips.
private struct ArchColumn: View {
    let side: FootSide
    let ahi: Double?
    let risen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ArchFigure(ahi: ahi ?? 0.2, risen: risen)
            MetricText(value: risen ? (ahi ?? 0) : 0, fractionDigits: 3, style: .hero)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("\(side.title) AHI").font(.subheadline).foregroundStyle(.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("results.\(side.rawValue)")
    }
}

/// Dense left, right and difference rows in monospaced digits.
private struct ComparisonGrid: View {
    struct Row: Identifiable {
        let title: String
        let left: String
        let right: String
        let difference: String
        var id: String { title }
    }

    let rows: [Row]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: Space.md, verticalSpacing: 0) {
            GridRow {
                Color.clear.gridColumnAlignment(.leading).frame(height: 1)
                Text("Left"); Text("Right"); Text("Diff")
            }
            .font(.footnote)
            .foregroundStyle(.inkTertiary)
            .padding(.bottom, Space.sm)
            ForEach(rows) { row in
                Hairline().gridCellColumns(4)
                GridRow {
                    Text(row.title).font(.subheadline).foregroundStyle(.inkSecondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.left); Text(row.right)
                    Text(row.difference).foregroundStyle(.inkSecondary)
                }
                .font(.body.monospacedDigit())
                .frame(minHeight: 44)
            }
        }
    }
}
