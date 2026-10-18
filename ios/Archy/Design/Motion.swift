import SwiftUI

// Motion tokens. Everything animates with springs so motion can be interrupted and retargeted.
// Personality: crisp by default, with a little bounce reserved for selection and success moments.
// Never hand-type a spring in a feature file; pick one of these.

enum Motion {
    /// Finger down on a control: fast, no overshoot.
    static let pressIn = Animation.spring(duration: 0.16, bounce: 0)
    /// Finger up: springs back with a small pop.
    static let release = Animation.spring(duration: 0.4, bounce: 0.4)
    /// Default for state changes: toggles, value swaps, small layout shifts.
    static let snappy = Animation.spring(duration: 0.3, bounce: 0)
    /// Larger morphs: screen content swaps, cards expanding, step changes.
    static let smooth = Animation.spring(duration: 0.45, bounce: 0)
    /// Selection and success: a choice locking in, a lap completing, a result landing.
    static let playful = Animation.spring(duration: 0.5, bounce: 0.3)
    /// Entrances of content that appears once per visit.
    static let reveal = Animation.spring(duration: 0.6, bounce: 0)
    /// Gap between items in a staggered entrance. Keep groups short; stagger never blocks taps.
    static let staggerStep = 0.05
    /// Reduced-motion stand-in: a short fade, no movement.
    static let fade = Animation.easeOut(duration: 0.2)
}

extension Animation {
    /// This animation, or a plain fade when Reduce Motion is on.
    func reduced(_ reduceMotion: Bool) -> Animation { reduceMotion ? Motion.fade : self }
}

/// Fades, lifts and unblurs content into place the first time it appears.
/// `index` staggers siblings by `Motion.staggerStep`. Reduce Motion keeps only the fade.
private struct Reveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let settled = shown || reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .offset(y: settled ? 0 : 14)
            .blur(radius: settled ? 0 : 6)
            .onAppear {
                guard !shown else { return }
                let animation = reduceMotion ? Motion.fade : Motion.reveal.delay(Double(index) * Motion.staggerStep)
                withAnimation(animation) { shown = true }
            }
    }
}

extension View {
    /// Staggered entrance for content that appears once per visit (screen tops, onboarding steps, results).
    /// Don't use on list rows that scroll in and out repeatedly.
    func reveal(_ index: Int = 0) -> some View { modifier(Reveal(index: index)) }
}

/// Screen-content swap used between steps (onboarding questions, scan phases, coach states):
/// incoming slides up slightly and unblurs, outgoing fades out without moving.
extension AnyTransition {
    static var step: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 16)).combined(with: .modifier(active: BlurModifier(radius: 6), identity: BlurModifier(radius: 0))),
            removal: .opacity
        )
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}
