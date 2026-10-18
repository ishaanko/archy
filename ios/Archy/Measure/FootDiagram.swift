import SwiftUI

struct FootDiagram: View {
    let field: MeasurementField
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if field == .width {
                    InsoleShape().fill(Color.archyAccent.opacity(0.12)).frame(width: 110, height: 230).rotationEffect(.degrees(90))
                    InsoleShape().stroke(Color.archyAccent, lineWidth: 2).frame(width: 110, height: 230).rotationEffect(.degrees(90))
                    Path { p in p.move(to: CGPoint(x: 85, y: 25)); p.addLine(to: CGPoint(x: 85, y: 123)) }.stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [5]))
                } else {
                    FootArchShape(height: 0.48).fill(Color.archyAccent.opacity(0.12))
                    FootArchShape(height: 0.48).stroke(Color.archyAccent, lineWidth: 2)
                    if field == .fullLength || field == .truncatedLength {
                        Path { p in p.move(to: CGPoint(x: 20, y: 135)); p.addLine(to: CGPoint(x: field == .truncatedLength ? 225 : 285, y: 135)) }.stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [5]))
                    } else {
                        let landmarkX: CGFloat = field == .dorsumHeight ? 150 : 110
                        let landmarkY: CGFloat = field == .dorsumHeight ? 65 : 85
                        Path { p in p.move(to: CGPoint(x: landmarkX, y: 130)); p.addLine(to: CGPoint(x: landmarkX, y: landmarkY)) }.stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [5]))
                        Circle().fill(.orange).frame(width: 10).position(x: landmarkX, y: landmarkY)
                    }
                }
            }.frame(width: 300, height: 155)
            Text(field == .width ? "Width: measure across the widest forefoot from above." : "Side view · schematic, not to scale").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).accessibilityLabel("Foot landmark schematic. \(field.landmark)")
    }
}
