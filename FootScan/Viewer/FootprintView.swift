//
//  FootprintView.swift
//  FootScan
//

import SwiftUI

/// The sole drawn as a footprint on the floor: heel at the bottom, toes at the top, inner (arch) side
/// on the left. Solid ink where the foot touches the floor, fading lighter the higher the sole lifts.
@MainActor
struct FootprintView: View {
    let footprint: Footprint

    @Environment(\.colorScheme) private var colorScheme

    /// Lifted cells fade from just off the floor to faintest at this height.
    private static let fadeHeight: Float = 0.025
    private static let fadeSteps = 6

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(idealWidth: 120, idealHeight: 170)
            .accessibilityLabel("Footprint: dark where the sole touches the floor, light where it lifts")

            // Side by side, or stacked if the frame is too narrow.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { legend }
                VStack(alignment: .leading, spacing: 2) { legend }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var legend: some View {
        legendItem("On the floor", fill: Color.accentColor)
        legendItem("Lifted (arch)", fill: LinearGradient(colors: [liftedColor(step: 0), liftedColor(step: Self.fadeSteps - 1)],
                                                         startPoint: .leading, endPoint: .trailing))
    }

    private func legendItem(_ title: String, fill: some ShapeStyle) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(fill)
                .frame(width: 12, height: 8)
            Text(title)
                .lineLimit(1)
        }
    }

    /// Step 0 is just off the floor; the last step is `fadeHeight` or higher. Dark mode needs more
    /// opacity for the faintest cells to stand out from the background.
    private func liftedColor(step: Int) -> Color {
        let opacity = colorScheme == .dark ? 0.25...0.6 : 0.15...0.5
        let fraction = Double(step) / Double(Self.fadeSteps - 1)
        return Color.accentColor.opacity(opacity.upperBound - fraction * (opacity.upperBound - opacity.lowerBound))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let f = footprint
        guard f.heelColumn >= 0, f.heelColumn <= f.toeTipColumn, f.toeTipColumn < f.columns,
              f.heights.count == f.columns * f.rows, f.contact.count == f.heights.count else { return }
        let footColumns = f.heelColumn...f.toeTipColumn

        var cells: [(row: Int, column: Int)] = []
        for row in 0..<f.rows {
            for column in footColumns where f.heights[row * f.columns + column] < FootArchAnalyzer.outlineHeight {
                cells.append((row, column))
            }
        }
        guard let minRow = cells.map(\.row).min(), let maxRow = cells.map(\.row).max() else { return }

        // Fit the footprint's true proportions, leaving room on the left for the arch label.
        let label = context.resolve(Text("arch").font(.caption2).foregroundStyle(.secondary))
        let margin = f.archPeakColumn == nil ? 0 : label.measure(in: size).width + 16
        let across = CGFloat(maxRow - minRow + 1), along = CGFloat(footColumns.count)
        let side = max(0, min((size.width - margin) / across, size.height / along))
        let origin = CGPoint(x: max(margin, (size.width - across * side) / 2), y: (size.height - along * side) / 2)

        func rect(row: Int, column: Int) -> CGRect {
            let x = CGFloat(f.innerSideAtHighRows ? maxRow - row : row - minRow)
            let y = CGFloat(f.toeTipColumn - column)
            return CGRect(x: origin.x + x * side, y: origin.y + y * side, width: side, height: side)
        }

        // One path per shade, so neighboring cells of the same shade don't show seams.
        var ink = Path()
        var lifted = [Path](repeating: Path(), count: Self.fadeSteps)
        for (row, column) in cells {
            let i = row * f.columns + column
            if f.contact[i] {
                ink.addRect(rect(row: row, column: column))
            } else {
                let fraction = min(max(f.heights[i], 0) / Self.fadeHeight, 1)
                lifted[Int((fraction * Float(Self.fadeSteps - 1)).rounded())].addRect(rect(row: row, column: column))
            }
        }
        for (step, path) in lifted.enumerated() {
            context.fill(path, with: .color(liftedColor(step: step)))
        }
        context.fill(ink, with: .color(.accentColor))

        if let peak = f.archPeakColumn, footColumns.contains(peak),
           let edge = cells.filter({ $0.column == peak }).map({ rect(row: $0.row, column: peak).minX }).min() {
            let y = rect(row: minRow, column: peak).midY
            var leader = Path()
            leader.move(to: CGPoint(x: edge - 3, y: y))
            leader.addLine(to: CGPoint(x: edge - 13, y: y))
            context.stroke(leader, with: .color(.secondary), lineWidth: 0.75)
            context.draw(label, at: CGPoint(x: edge - 15, y: y), anchor: .trailing)
        }
    }
}
