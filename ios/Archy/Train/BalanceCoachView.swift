import SwiftUI

extension CoachProgram {
    static let balance = CoachProgram(
        roundName: "Hold",
        idleTitle: "Tandem balance",
        idleDetail: "Fingertips on a solid counter. One foot in front of the other, heel to toe.",
        readyDetail: "Eyes on one spot.",
        holdTitle: "Hold",
        restTitle: "Rest",
        holdDetail: { round in round == 1 ? "Left foot leads. Breathe." : "Right foot leads. Breathe." },
        restDetail: { round in round == 1 ? "Switch your front foot." : "Nice and steady." },
        safety: "Stay at the counter. Stop if you feel unsteady.",
        finishedFact: "2 holds · 1 min",
        setup: ("balance.setup", "Stand beside a solid counter on a stable floor. Keep fingertip support. Place one foot ahead of the other, heel toward toe, and look at a fixed point. Stop if you feel unsteady."),
        hold: ("balance.hold", "Hold with fingertip support. Keep your eyes on a fixed point and breathe."),
        rest: ("balance.relax", "Rest in a comfortable stance, keeping your support. Change your leading foot for the next hold."),
        complete: ("balance.complete", "Practice complete. Stay supported as you finish.")
    )
}

/// Supported tandem balance. Debug launches can start it mid-practice with `init(debugElapsed:)`.
struct BalanceCoachView: View {
    private var start = BalanceSession()
    private var running = false

    init() {}

    #if DEBUG
    init(debugElapsed: Int) {
        start = BalanceSession(debugElapsed: debugElapsed)
        running = true
    }
    #endif

    var body: some View {
        CoachScreen(program: .balance, session: start, running: running) { phase, round in
            BalanceStanceDiagram(tandem: phase != .rest, leftLeads: round == 1, holding: phase == .hold)
        }
    }
}

/// Top view of both feet beside the counter. Tandem puts one foot ahead of the other; the leading foot
/// takes the brand stroke while holding.
struct BalanceStanceDiagram: View {
    var tandem: Bool
    var leftLeads: Bool
    var holding: Bool

    var body: some View {
        GeometryReader { proxy in
            let u = proxy.size.height / 172
            HStack(spacing: 28 * u) {
                RoundedRectangle(cornerRadius: Radius.md * u, style: .continuous)
                    .fill(Color.surface3)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md * u, style: .continuous).strokeBorder(Color.line3))
                    .frame(width: 14 * u, height: proxy.size.height)
                ZStack {
                    foot(mirrored: false, front: leftLeads, u: u)
                    foot(mirrored: true, front: !leftLeads, u: u)
                }
                .frame(width: 90 * u, height: proxy.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.smooth, value: tandem)
            .animation(Motion.smooth, value: leftLeads)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tandem ? "Top view beside a counter. \(leftLeads ? "Left" : "Right") foot in front of the other, heel toward toe." : "Top view beside a counter. Feet side by side.")
    }

    private func foot(mirrored: Bool, front: Bool, u: CGFloat) -> some View {
        let sideX: CGFloat = (mirrored ? 24 : -24) * u
        let tandemX: CGFloat = (mirrored ? 8 : -8) * u
        let y: CGFloat = tandem ? (front ? -46 : 46) * u : 0
        let active = holding && front
        return InsoleShape()
            .fill(Color.ink.opacity(0.06))
            .overlay(InsoleShape().stroke(active ? Color.brand : Color.ink, lineWidth: 2))
            .frame(width: 36 * u, height: 80 * u)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .offset(x: tandem ? tandemX : sideX, y: y)
    }
}
