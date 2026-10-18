import SwiftUI

extension CoachProgram {
    static let heelRaise = CoachProgram(
        roundName: "Rep",
        idleTitle: "Heel raises",
        idleDetail: "Hands on a counter, feet hip-width apart. Rise onto the balls of your feet, then lower slowly.",
        readyDetail: "Hands on the counter, weight even.",
        holdTitle: "Rise",
        restTitle: "Lower",
        holdDetail: { _ in "Up on the balls of your feet. Pause." },
        restDetail: { _ in "Slowly down. Weight over your big toes." },
        safety: "Hold the counter. Stop if you feel unsteady or it hurts.",
        finishedFact: "10 reps · 1 min",
        setup: ("heelraise.setup", "Stand facing a solid counter with your hands resting on it and your feet hip-width apart. Rise slowly onto the balls of your feet, pause, then lower slowly. Keep your weight over your big toes."),
        hold: ("heelraise.rise", "Rise onto the balls of your feet and pause."),
        rest: ("heelraise.lower", "Lower slowly."),
        complete: ("heelraise.complete", "Practice complete. Shake out your calves.")
    )
}

/// Standing heel raises at a counter. Debug launches can start it mid-practice with `init(debugElapsed:)`.
struct HeelRaiseCoachView: View {
    private var start = HeelRaiseSession()
    private var running = false

    init() {}

    #if DEBUG
    init(debugElapsed: Int) {
        start = HeelRaiseSession(debugElapsed: debugElapsed)
        running = true
    }
    #endif

    var body: some View {
        CoachScreen(program: .heelRaise, session: start, running: running) { phase, _ in
            HeelRaiseDiagram(rise: phase == .hold ? 1 : 0)
        }
    }
}

/// Side view of a foot rising onto the ball of the foot. `rise` (0...1) lifts the heel and ankle while the
/// toes stay planted; the back of the leg takes the brand stroke, the calf being worked.
struct HeelRaiseDiagram: View {
    var rise: Double

    var body: some View {
        ZStack {
            HeelRaiseGround().stroke(Color.line3, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            HeelRaiseShank(rise: rise).fill(Color.ink.opacity(0.06))
            HeelRaiseFoot(rise: rise).fill(Color.ink.opacity(0.06))
            HeelRaiseFoot(rise: rise).stroke(Color.ink, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            HeelRaiseLeg(rise: rise, back: false).stroke(Color.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            HeelRaiseLeg(rise: rise, back: true).stroke(Color.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            HeelRaiseBall().fill(Color.ink)
        }
        .aspectRatio(heelDesign.width / heelDesign.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Side view of a foot. Heel \(rise > 0.5 ? "raised" : "lowered"), toes planted.")
    }
}

// Drawn in a 300 x 170 design space and scaled to fit. The foot turns about the ball of the foot;
// shapes are written with the ground at y = 126 and `scaled` drops everything 44 to leave room for the leg.
private let heelDesign = CGSize(width: 300, height: 170)
nonisolated private let heelPivot = CGPoint(x: 226, y: 126)
nonisolated private let heelMaxAngle: CGFloat = 0.32

nonisolated private func scaled(_ p: CGPoint, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + p.x * rect.width / 300, y: rect.minY + (p.y + 44) * rect.height / 170)
}

/// A design-space point turned about the ball of the foot by the current rise.
nonisolated private func turned(_ x: CGFloat, _ y: CGFloat, rise: Double) -> CGPoint {
    let angle = CGFloat(rise) * heelMaxAngle
    let dx = x - heelPivot.x, dy = y - heelPivot.y
    return CGPoint(x: heelPivot.x + dx * cos(angle) - dy * sin(angle),
                   y: heelPivot.y + dx * sin(angle) + dy * cos(angle))
}

nonisolated private struct HeelRaiseGround: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: scaled(CGPoint(x: 12, y: 126), in: rect))
        path.addLine(to: scaled(CGPoint(x: 288, y: 126), in: rect))
        return path
    }
}

/// Heel and midfoot turn with the rise; the toes stay flat on the floor.
nonisolated private struct HeelRaiseFoot: Shape {
    var rise: Double
    var animatableData: Double { get { rise } set { rise = newValue } }

    func path(in rect: CGRect) -> Path {
        func t(_ x: CGFloat, _ y: CGFloat) -> CGPoint { scaled(turned(x, y, rise: rise), in: rect) }
        func flat(_ x: CGFloat, _ y: CGFloat) -> CGPoint { scaled(CGPoint(x: x, y: y), in: rect) }
        var path = Path()
        path.move(to: t(58, 126))
        path.addCurve(to: t(54, 84), control1: t(42, 112), control2: t(44, 92))
        path.addCurve(to: t(112, 62), control1: t(60, 66), control2: t(92, 58))
        path.addCurve(to: t(226, 100), control1: t(150, 66), control2: t(190, 96))
        path.addCurve(to: flat(262, 118), control1: flat(246, 102), control2: flat(258, 108))
        path.addQuadCurve(to: flat(258, 126), control: flat(268, 126))
        path.addLine(to: flat(226, 126))
        path.addCurve(to: t(58, 126), control1: t(190, 110), control2: t(100, 112))
        path.closeSubpath()
        return path
    }
}

/// Where the shank meets the foot, turned with the heel, and how far each side of the shank sits from it.
nonisolated private let shankHalfWidth: CGFloat = 20

nonisolated private func ankle(rise: Double) -> CGPoint { turned(78, 62, rise: rise) }

/// The lower leg: straight up from the ankle to the top edge, so it rises with the heel.
nonisolated private struct HeelRaiseShank: Shape {
    var rise: Double
    var animatableData: Double { get { rise } set { rise = newValue } }

    func path(in rect: CGRect) -> Path {
        let a = ankle(rise: rise)
        var path = Path()
        path.move(to: scaled(CGPoint(x: a.x - shankHalfWidth, y: a.y + 8), in: rect))
        path.addLine(to: scaled(CGPoint(x: a.x - shankHalfWidth, y: -44), in: rect))
        path.addLine(to: scaled(CGPoint(x: a.x + shankHalfWidth, y: -44), in: rect))
        path.addLine(to: scaled(CGPoint(x: a.x + shankHalfWidth, y: a.y + 8), in: rect))
        path.closeSubpath()
        return path
    }
}

/// One side of the shank. The back line is the calf side.
nonisolated private struct HeelRaiseLeg: Shape {
    var rise: Double
    var back: Bool
    var animatableData: Double { get { rise } set { rise = newValue } }

    func path(in rect: CGRect) -> Path {
        let a = ankle(rise: rise)
        let x = a.x + (back ? -shankHalfWidth : shankHalfWidth)
        var path = Path()
        path.move(to: scaled(CGPoint(x: x, y: a.y + 8), in: rect))
        path.addLine(to: scaled(CGPoint(x: x, y: -44), in: rect))
        return path
    }
}

/// The planted ball of the foot, the pivot.
nonisolated private struct HeelRaiseBall: Shape {
    func path(in rect: CGRect) -> Path {
        let c = scaled(heelPivot, in: rect)
        return Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
    }
}
