import SwiftUI

// The studio's live pictures: a top-view insole with its support zone, and a side-view foot
// with load arrows. Every shape morphs through animatableData, so the springs set by the caller
// (environment change, foot flip) carry through without extra code here.

/// Nested topographic ellipses over the medial arch. `scale` (0...1) grows the zone.
nonisolated struct ArchZoneShape: Shape {
    var scale: Double
    /// Fraction of the full zone this ring covers.
    var ring: Double = 1
    var animatableData: Double { get { scale } set { scale = newValue } }
    func path(in r: CGRect) -> Path {
        let w = r.width * (0.26 + 0.34 * scale) * ring
        let h = r.height * (0.2 + 0.3 * scale) * ring
        return Path(ellipseIn: CGRect(x: r.width * 0.54 - w / 2, y: r.height * 0.6 - h / 2, width: w, height: h))
    }
}

/// The plate and the support wedge under the arch in the side view.
nonisolated struct SupportWedgeShape: Shape {
    /// Wedge height as a fraction of the frame height.
    var lift: Double
    var animatableData: Double { get { lift } set { lift = newValue } }
    func path(in r: CGRect) -> Path {
        let base = r.height * 0.84
        let rise = r.height * CGFloat(lift) / 0.75
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.2, y: base))
        p.addCurve(to: CGPoint(x: r.width * 0.7, y: base),
                   control1: CGPoint(x: r.width * 0.3, y: base - rise),
                   control2: CGPoint(x: r.width * 0.58, y: base - rise))
        p.closeSubpath()
        return p
    }
}

/// Top-view outline of a left insole, toe up, big toe on the right. Mirrored in 3D for the right foot.
private nonisolated struct InsoleOutline: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var p = Path()
        p.move(to: pt(0.5, 1))
        p.addCurve(to: pt(0.14, 0.84), control1: pt(0.28, 1), control2: pt(0.13, 0.95))
        p.addCurve(to: pt(0.2, 0.56), control1: pt(0.15, 0.74), control2: pt(0.22, 0.66))
        p.addCurve(to: pt(0.04, 0.3), control1: pt(0.18, 0.46), control2: pt(0.04, 0.42))
        p.addCurve(to: pt(0.5, 0.01), control1: pt(0.04, 0.12), control2: pt(0.26, 0.01))
        p.addCurve(to: pt(0.96, 0.24), control1: pt(0.8, 0), control2: pt(0.96, 0.1))
        p.addCurve(to: pt(0.62, 0.6), control1: pt(0.97, 0.4), control2: pt(0.66, 0.46))
        p.addCurve(to: pt(0.86, 0.84), control1: pt(0.58, 0.72), control2: pt(0.88, 0.7))
        p.addCurve(to: pt(0.5, 1), control1: pt(0.84, 0.96), control2: pt(0.68, 1))
        p.closeSubpath()
        return p
    }
}

/// A thin rule at the insole plate level in the side view.
private nonisolated struct PlateShape: Shape {
    func path(in r: CGRect) -> Path {
        Path(roundedRect: CGRect(x: 0, y: r.height * 0.84, width: r.width, height: 4), cornerRadius: 2)
    }
}

/// A down arrow whose shaft grows with `length` (0...1 of the frame height).
private nonisolated struct LoadArrowShape: Shape {
    var length: Double
    var animatableData: Double { get { length } set { length = newValue } }
    func path(in r: CGRect) -> Path {
        let tail = r.height * (1 - CGFloat(length))
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: tail))
        p.addLine(to: CGPoint(x: r.midX, y: r.height))
        p.move(to: CGPoint(x: r.midX - 5, y: r.height - 6))
        p.addLine(to: CGPoint(x: r.midX, y: r.height))
        p.addLine(to: CGPoint(x: r.midX + 5, y: r.height - 6))
        return p
    }
}

/// Dots, lines or weave over the insole, one per material.
private struct MaterialPattern: View {
    let material: InsoleMaterial
    var body: some View {
        Canvas { context, size in
            let tint = GraphicsContext.Shading.color(Color.ink.opacity(0.16))
            switch material {
            case .lattice:
                for row in 0..<Int(size.height / 10) + 1 {
                    for col in 0..<Int(size.width / 10) + 1 {
                        let x = Double(col) * 10 + (row.isMultiple(of: 2) ? 0 : 5), y = Double(row) * 10
                        context.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)), with: tint)
                    }
                }
            case .foam:
                for row in 0..<Int(size.height / 9) + 1 {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: Double(row) * 9))
                    line.addLine(to: CGPoint(x: size.width, y: Double(row) * 9))
                    context.stroke(line, with: tint, lineWidth: 2)
                }
            case .carbon:
                for step in stride(from: -size.height, to: size.width, by: 9) {
                    var rising = Path(), falling = Path()
                    rising.move(to: CGPoint(x: step, y: size.height)); rising.addLine(to: CGPoint(x: step + size.height, y: 0))
                    falling.move(to: CGPoint(x: step, y: 0)); falling.addLine(to: CGPoint(x: step + size.height, y: size.height))
                    context.stroke(rising, with: tint, lineWidth: 1)
                    context.stroke(falling, with: tint, lineWidth: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Top view of the insole: outline, material, and the arch zone. Flips in 3D between feet.
struct InsoleTopView: View {
    let design: InsoleDesign
    let aspect: CGFloat
    var height: CGFloat = 230

    var body: some View {
        ZStack {
            InsoleOutline().fill(Color.surface2)
            ZStack {
                MaterialPattern(material: design.material)
                    .id(design.material)
                    .transition(.opacity)
                ForEach([1.0, 0.64, 0.3], id: \.self) { ring in
                    ArchZoneShape(scale: design.zoneStrength, ring: ring)
                        .fill(Color.brand.opacity(ring == 1 ? 0.2 : ring > 0.5 ? 0.35 : 0.7))
                }
            }
            .clipShape(InsoleOutline())
            InsoleOutline().stroke(Color.line3, lineWidth: 1.5)
        }
        .frame(width: height * aspect, height: height)
        .rotation3DEffect(.degrees(design.side == .right ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(design.side.title) insole, \(design.material.rawValue), arch support \(Int(design.support * 100)) percent")
    }
}

/// Side view of the foot arch under the chosen gravity, with the support wedge holding it up.
struct ArchSideView: View {
    let design: InsoleDesign
    let rest: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size = CGSize(width: 180, height: 130)
    private let arrowXs: [CGFloat] = [0.2, 0.36, 0.52]

    var body: some View {
        let arch = design.loadedArch(rest: rest)
        let g = design.environment.g
        let tip = size.height * (0.84 - arch) - 6
        ZStack(alignment: .topLeading) {
            PlateShape().fill(Color.line3)
            FootArchShape(height: arch).fill(Color.surface3)
            FootArchShape(height: arch).stroke(Color.ink, lineWidth: 1.5)
            SupportWedgeShape(lift: arch * 0.52 * (0.2 + 0.75 * design.support)).fill(Color.brand)
            ForEach(arrowXs.indices, id: \.self) { index in
                LoadArrowShape(length: 0.2 + 0.8 * g)
                    .stroke(Color.ink.opacity(0.3 + 0.7 * g), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 40)
                    .animation(Motion.playful.delay(Double(index) * 0.04).reduced(reduceMotion), value: g)
                    .offset(x: size.width * arrowXs[index] - 7, y: tip - 40)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Side view of the arch under \(design.environment.title) gravity")
    }
}
