import SwiftUI

extension CoachProgram {
    static let shortFoot = CoachProgram(
        roundName: "Rep",
        idleTitle: "Short foot",
        idleDetail: "Foot flat on the floor. Draw the base of your big toe toward your heel. Keep your toes long.",
        readyDetail: "Foot flat, toes long.",
        holdTitle: "Lift your arch",
        restTitle: "Relax",
        holdDetail: { _ in "Toes long. Breathe." },
        restDetail: { _ in "Let your arch settle." },
        safety: "Stop if it hurts.",
        finishedFact: "5 reps · 1 min",
        setup: ("exercise.setup", "Sit comfortably with your foot flat. Gently draw the base of your big toe toward your heel, keep both planted and your toes long, then relax."),
        hold: ("exercise.hold", "Hold gently. Keep your toes long and breathe."),
        rest: ("exercise.relax", "Relax your foot completely."),
        complete: ("exercise.complete", "Practice complete. Check how your feet feel.")
    )
}

/// Seated short-foot practice. Debug launches can start it mid-practice with `init(debugElapsed:)`.
struct ExerciseCoachView: View {
    private var start = ShortFootSession()
    private var running = false

    init() {}

    #if DEBUG
    init(debugElapsed: Int) {
        start = ShortFootSession(debugElapsed: debugElapsed)
        running = true
    }
    #endif

    var body: some View {
        CoachScreen(program: .shortFoot, session: start, running: running) { phase, _ in
            CoachFootDiagram(lift: phase == .hold ? 1 : 0)
        }
    }
}

/// Side view of a foot on the floor. `lift` (0...1) raises the arch while heel and big-toe base stay planted.
/// Ink outlines; brand marks only the arch, the zone being worked.
struct CoachFootDiagram: View {
    var lift: Double

    var body: some View {
        ZStack {
            CoachGround().stroke(Color.line3, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            CoachFoot(lift: lift).fill(Color.ink.opacity(0.06))
            CoachFoot(lift: lift).stroke(Color.ink, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            CoachSole(lift: lift).fill(Color.brand.opacity(0.18))
            CoachSole(lift: lift).stroke(Color.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            CoachContacts(lift: lift).fill(Color.ink)
        }
        .aspectRatio(coachDesign.width / coachDesign.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Side view of a foot. Arch \(lift > 0.5 ? "raised" : "relaxed"), heel and big-toe base planted.")
    }
}

// The diagram is drawn in a 300 x 145 design space and scaled to fit.
private let coachDesign = CGSize(width: 300, height: 145)
nonisolated private let coachBase: CGFloat = 120

nonisolated private func coachPoint(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + x * rect.width / 300, y: rect.minY + y * rect.height / 145)
}

nonisolated private func coachToe(_ lift: Double) -> CGFloat { 264 - 7.5 * CGFloat(lift) }

nonisolated private struct CoachGround: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: coachPoint(12, 126, in: rect))
        path.addLine(to: coachPoint(288, 126, in: rect))
        return path
    }
}

/// The foot body, closed along the underside.
nonisolated private struct CoachFoot: Shape {
    var lift: Double
    var animatableData: Double { get { lift } set { lift = newValue } }

    func path(in rect: CGRect) -> Path {
        let l = CGFloat(lift), toe = coachToe(lift), heel: CGFloat = 36, base = coachBase
        var path = Path()
        path.move(to: coachPoint(heel, base, in: rect))
        path.addCurve(to: coachPoint(heel + 22, 55, in: rect),
                      control1: coachPoint(heel - 22, 100, in: rect), control2: coachPoint(heel - 5, 55, in: rect))
        path.addCurve(to: coachPoint(toe, base - 20, in: rect),
                      control1: coachPoint(135, 38, in: rect), control2: coachPoint(toe - 45, 95, in: rect))
        path.addQuadCurve(to: coachPoint(toe, base, in: rect), control: coachPoint(toe + 27, base, in: rect))
        path.addCurve(to: coachPoint(heel, base, in: rect),
                      control1: coachPoint(177, base - 10 - 26 * l, in: rect), control2: coachPoint(117, base - 8 - 25 * l, in: rect))
        path.closeSubpath()
        return path
    }
}

/// The arch line under the foot; filled, it is the gap between arch and floor.
nonisolated private struct CoachSole: Shape {
    var lift: Double
    var animatableData: Double { get { lift } set { lift = newValue } }

    func path(in rect: CGRect) -> Path {
        let l = CGFloat(lift)
        var path = Path()
        path.move(to: coachPoint(36, coachBase, in: rect))
        path.addCurve(to: coachPoint(coachToe(lift), coachBase, in: rect),
                      control1: coachPoint(117, 112 - 25 * l, in: rect), control2: coachPoint(177, 110 - 26 * l, in: rect))
        return path
    }
}

/// The two points that stay planted: heel and big-toe base.
nonisolated private struct CoachContacts: Shape {
    var lift: Double
    var animatableData: Double { get { lift } set { lift = newValue } }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in [CGFloat(36), coachToe(lift)] {
            let c = coachPoint(x, coachBase, in: rect)
            path.addEllipse(in: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
        }
        return path
    }
}
