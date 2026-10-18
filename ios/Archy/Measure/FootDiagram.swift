import SwiftUI

/// Schematic foot with the landmark being measured highlighted. The highlight springs between
/// landmarks as the wizard steps; width swaps the side view for a top view.
struct FootDiagram: View {
    let field: MeasurementField

    /// A measured span in unit coordinates (0...1 of the diagram), drawn as a line with a dot at each end.
    private struct Landmark {
        var from: CGPoint
        var to: CGPoint
    }

    private var landmark: Landmark {
        switch field {
        case .fullLength: Landmark(from: CGPoint(x: 0.07, y: 0.92), to: CGPoint(x: 0.96, y: 0.92))
        case .truncatedLength: Landmark(from: CGPoint(x: 0.07, y: 0.92), to: CGPoint(x: 0.75, y: 0.92))
        case .dorsumHeight: Landmark(from: CGPoint(x: 0.5, y: 0.84), to: CGPoint(x: 0.5, y: 0.4))
        case .seatedNavicular, .standingNavicular: Landmark(from: CGPoint(x: 0.37, y: 0.84), to: CGPoint(x: 0.37, y: 0.55))
        case .width: Landmark(from: CGPoint(x: 0.65, y: 0.24), to: CGPoint(x: 0.65, y: 0.76))
        }
    }

    var body: some View {
        let isTopView = field == .width
        GeometryReader { geo in
            ZStack {
                FootArchShape(height: 0.48)
                    .stroke(Color.ink, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    .opacity(isTopView ? 0 : 1)
                Rectangle().fill(Color.line3).frame(height: 1)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.84)
                    .opacity(isTopView ? 0 : 1)
                // Rotated so the toe points right, matching the side view's direction.
                InsoleShape()
                    .stroke(Color.ink, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    .frame(width: geo.size.height * 0.71, height: geo.size.height * 1.48)
                    .rotationEffect(.degrees(90))
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(isTopView ? 1 : 0)
                LandmarkLine(from: landmark.from, to: landmark.to)
                    .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                marker(at: landmark.from, in: geo.size)
                marker(at: landmark.to, in: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(300 / 155, contentMode: .fit)
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
        .animation(Motion.smooth, value: field)
        .accessibilityElement()
        .accessibilityLabel("Foot diagram. \(field.landmark)")
    }

    private func marker(at point: CGPoint, in size: CGSize) -> some View {
        Circle().fill(Color.brand).frame(width: 9, height: 9)
            .position(x: point.x * size.width, y: point.y * size.height)
    }
}

/// A line between two unit-coordinate points; both ends animate.
private nonisolated struct LandmarkLine: Shape {
    var from: CGPoint
    var to: CGPoint

    var animatableData: AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData> {
        get { AnimatablePair(from.animatableData, to.animatableData) }
        set { from.animatableData = newValue.first; to.animatableData = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: from.x * r.width, y: from.y * r.height))
        p.addLine(to: CGPoint(x: to.x * r.width, y: to.y * r.height))
        return p
    }
}
