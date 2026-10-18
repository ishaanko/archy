import SwiftUI

extension CoachProgram {
    static let toeYoga = CoachProgram(
        roundName: "Round",
        idleTitle: "Toe yoga",
        idleDetail: "Sit with your foot flat. Lift only your big toe, then only the four small toes.",
        readyDetail: "Foot flat, toes relaxed.",
        holdTitle: "Big toe up",
        restTitle: "Small toes up",
        holdDetail: { _ in "The four small toes stay down." },
        restDetail: { _ in "Your big toe stays down." },
        safety: "Go gently. Stop if it hurts or cramps.",
        finishedFact: "5 rounds · 40 sec",
        setup: ("toeyoga.setup", "Sit with your bare foot flat on the floor. Lift only your big toe while the four small toes stay down. Then lower it and lift only the four small toes while your big toe stays down. Go gently."),
        hold: ("toeyoga.big", "Lift your big toe. Keep the small toes down."),
        rest: ("toeyoga.small", "Now lift the four small toes. Keep your big toe down."),
        complete: ("toeyoga.complete", "Practice complete. Check how your feet feel.")
    )
}

/// Seated toe yoga. Debug launches can start it mid-practice with `init(debugElapsed:)`.
struct ToeYogaCoachView: View {
    private var start = ToeYogaSession()
    private var running = false

    init() {}

    #if DEBUG
    init(debugElapsed: Int) {
        start = ToeYogaSession(debugElapsed: debugElapsed)
        running = true
    }
    #endif

    var body: some View {
        CoachScreen(program: .toeYoga, session: start, running: running) { phase, _ in
            ToeYogaDiagram(bigLift: phase == .hold ? 1 : 0, smallLift: phase == .rest ? 1 : 0)
        }
    }
}

/// Top view of a foot with the toes up. A lifted toe rises, grows slightly and takes the brand stroke,
/// leaving a dashed ghost where it rests.
struct ToeYogaDiagram: View {
    var bigLift: Double
    var smallLift: Double

    private struct Toe: Identifiable {
        let id: Int
        let center: CGPoint
        let radius: CGSize
    }

    private static let big = Toe(id: 0, center: CGPoint(x: 62, y: 38), radius: CGSize(width: 17, height: 22))
    private static let small = [
        Toe(id: 1, center: CGPoint(x: 98, y: 46), radius: CGSize(width: 11, height: 15)),
        Toe(id: 2, center: CGPoint(x: 122, y: 56), radius: CGSize(width: 10, height: 13)),
        Toe(id: 3, center: CGPoint(x: 143, y: 68), radius: CGSize(width: 9, height: 11)),
        Toe(id: 4, center: CGPoint(x: 160, y: 82), radius: CGSize(width: 8, height: 10)),
    ]

    var body: some View {
        GeometryReader { proxy in
            let u = proxy.size.height / 170
            ZStack(alignment: .topLeading) {
                ToeYogaFoot().fill(Color.ink.opacity(0.06))
                ToeYogaFoot().stroke(Color.ink, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                toe(Self.big, lift: bigLift, u: u)
                ForEach(Self.small) { toe($0, lift: smallLift, u: u) }
            }
            .frame(width: 200 * u, height: 170 * u)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bigLift > 0.5 ? "Top view of a foot. Big toe lifted, small toes down."
            : smallLift > 0.5 ? "Top view of a foot. Four small toes lifted, big toe down."
            : "Top view of a foot. All toes down.")
    }

    private func toe(_ toe: Toe, lift: Double, u: CGFloat) -> some View {
        let lifted = lift > 0.5
        return ZStack {
            Ellipse().stroke(Color.line3, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .opacity(lift)
            ZStack {
                Ellipse().fill(Color.bg)
                Ellipse().fill(lifted ? Color.brand.opacity(0.18) : Color.ink.opacity(0.06))
                Ellipse().stroke(lifted ? Color.brand : Color.ink, lineWidth: lifted ? 3 : 2)
            }
            .offset(y: -10 * u * lift)
            .scaleEffect(1 + 0.14 * lift)
        }
        .frame(width: toe.radius.width * 2 * u, height: toe.radius.height * 2 * u)
        .position(x: toe.center.x * u, y: toe.center.y * u)
    }
}

/// The sole and heel, without the toes.
nonisolated private struct ToeYogaFoot: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width / 200, y: rect.minY + y * rect.height / 170)
        }
        var path = Path()
        path.move(to: p(42, 58))
        path.addCurve(to: p(174, 94), control1: p(92, 50), control2: p(148, 66))
        path.addCurve(to: p(146, 146), control1: p(186, 112), control2: p(172, 138))
        path.addCurve(to: p(100, 168), control1: p(136, 160), control2: p(118, 168))
        path.addCurve(to: p(62, 140), control1: p(80, 168), control2: p(64, 156))
        path.addCurve(to: p(42, 58), control1: p(60, 112), control2: p(28, 92))
        path.closeSubpath()
        return path
    }
}
