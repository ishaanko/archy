import SwiftUI

extension Assessment {
    /// Arch height index for one foot, or nil if the readings are invalid.
    func ahi(_ side: FootSide) -> Double? {
        try? MeasurementMath.archHeightIndex(measurements(for: side))
    }
}

/// The side-view arch in brand orange, sized to a measured AHI. Height changes animate with the caller's transaction.
/// `risen: false` shows a flat starting pose so a result can rise into place.
struct ArchFigure: View {
    let ahi: Double
    var risen = true

    /// Maps AHI onto `FootArchShape.height`; a typical 0.33 lands near the middle of the range.
    static func shapeHeight(forAHI ahi: Double) -> Double { min(max(ahi * 1.5, 0.18), 0.8) }

    var body: some View {
        let height = risen ? Self.shapeHeight(forAHI: ahi) : 0.1
        // Drawn at a fixed 300x155 and scaled, so the curve proportions hold at any size.
        GeometryReader { geo in
            let scale = geo.size.width / 300
            FootArchShape(height: height)
                .fill(Color.brand.opacity(0.14))
                .overlay { FootArchShape(height: height).stroke(Color.brand, style: StrokeStyle(lineWidth: 2 / scale, lineCap: .round, lineJoin: .round)) }
                .frame(width: 300, height: 155)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(300 / 155, contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel("Side view of an arch, height index \(ahi.formatted(.number.precision(.fractionLength(3))))")
    }
}
