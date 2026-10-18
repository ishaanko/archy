import SwiftUI

// Old names from the two pre-merge apps, kept only so unconverted screens compile.
// Delete this file once nothing references it. New code must not use anything here.

extension Color {
    static let archyBackground = Color.bg
    static let archyForeground = Color.ink
    static let archyCard = Color.surface
    static let archyRaised = Color.surface3
    static let archyAccent = Color.brand
    static let archyGreen = Color.positive
    static let archyBorder = Color.line2
    static let archySecondary = Color.inkSecondary
    static let lunar = Color.brand
    static let mintSignal = Color.positive
    static let journeyAccent = Color.brand
    static let journeyBackground = Color.bg
    static let journeySecondary = Color.inkSecondary
}

struct Panel<Content: View>: View {
    var dark = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }.surface(padding: 20)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View { EmptyView() }
}

struct ArchyWordmark: View {
    var body: some View { ArchyLogo() }
}

struct SpaceBackground: View {
    var body: some View { Color.bg.ignoresSafeArea().accessibilityHidden(true) }
}
