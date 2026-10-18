import SwiftUI

// Shapes shared by Measure, Space, Insole and Train. Keep their names and initializers stable.

/// Side view of a foot; `height` (0...1) sets the arch rise. Animatable.
nonisolated struct FootArchShape: Shape {
    var height: Double
    var animatableData: Double { get { height } set { height = newValue } }
    func path(in r: CGRect) -> Path {
        let w = r.width, base = r.height * 0.84
        let top = base - r.height * CGFloat(height)
        var p = Path()
        p.move(to: CGPoint(x: w * 0.06, y: base))
        p.addCurve(to: CGPoint(x: w * 0.2, y: top + 12), control1: CGPoint(x: -w * 0.02, y: base - 25), control2: CGPoint(x: w * 0.08, y: top))
        p.addCurve(to: CGPoint(x: w * 0.78, y: base - 30), control1: CGPoint(x: w * 0.49, y: top - 20), control2: CGPoint(x: w * 0.6, y: base - 39))
        p.addCurve(to: CGPoint(x: w * 0.97, y: base), control1: CGPoint(x: w * 0.95, y: base - 39), control2: CGPoint(x: w, y: base - 19))
        p.addLine(to: CGPoint(x: w * 0.7, y: base))
        p.addCurve(to: CGPoint(x: w * 0.2, y: base), control1: CGPoint(x: w * 0.51, y: base - r.height * CGFloat(height) * 0.75), control2: CGPoint(x: w * 0.37, y: base - r.height * CGFloat(height) * 0.63))
        p.closeSubpath()
        return p
    }
}

/// Top view of an insole outline, toe at the top.
nonisolated struct InsoleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.5, y: r.height * 0.98))
        p.addCurve(to: CGPoint(x: r.width * 0.16, y: r.height * 0.68), control1: CGPoint(x: r.width * 0.04, y: r.height), control2: CGPoint(x: r.width * 0.05, y: r.height * 0.86))
        p.addCurve(to: CGPoint(x: r.width * 0.14, y: r.height * 0.3), control1: CGPoint(x: r.width * 0.3, y: r.height * 0.5), control2: CGPoint(x: r.width * 0.08, y: r.height * 0.45))
        p.addCurve(to: CGPoint(x: r.width * 0.82, y: r.height * 0.04), control1: CGPoint(x: r.width * 0.15, y: -r.height * 0.05), control2: CGPoint(x: r.width * 0.58, y: -r.height * 0.01))
        p.addCurve(to: CGPoint(x: r.width * 0.86, y: r.height * 0.36), control1: CGPoint(x: r.width * 1.03, y: r.height * 0.1), control2: CGPoint(x: r.width, y: r.height * 0.2))
        p.addCurve(to: CGPoint(x: r.width * 0.8, y: r.height * 0.74), control1: CGPoint(x: r.width * 0.64, y: r.height * 0.56), control2: CGPoint(x: r.width * 0.84, y: r.height * 0.6))
        p.addCurve(to: CGPoint(x: r.width * 0.5, y: r.height * 0.98), control1: CGPoint(x: r.width * 0.9, y: r.height * 0.92), control2: CGPoint(x: r.width * 0.8, y: r.height))
        return p
    }
}
