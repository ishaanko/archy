import SwiftUI

// Shared building blocks. Feature folders compose these instead of restyling controls locally.

/// The archy wordmark with the orange footprint. Adapts to light and dark.
struct ArchyLogo: View {
    var height: CGFloat = 26
    var body: some View {
        Image("Logo").resizable().scaledToFit().frame(height: height)
            .accessibilityLabel("archy")
    }
}

/// The orange footprint on its own.
struct ArchyMark: View {
    var height: CGFloat = 28
    var body: some View {
        Image("LogoMark").resizable().scaledToFit().frame(height: height)
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// Shared press feel: quick squeeze in, springy release, a soft tap on press.
private struct PressFeedback: ViewModifier {
    let isPressed: Bool
    var scale: CGFloat = 0.97
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1)
            .animation(isPressed ? Motion.pressIn : Motion.release, value: isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: isPressed) { _, pressed in pressed }
    }
}

/// Inverted-ink primary action. One per screen.
struct ArchyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 20)
            .foregroundStyle(.bg)
            .background(Color.ink, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .modifier(PressFeedback(isPressed: configuration.isPressed))
            .animation(Motion.snappy, value: isEnabled)
    }
}

/// Outlined secondary action.
struct ArchySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 20)
            .foregroundStyle(.ink)
            .background(configuration.isPressed ? Color.line : .clear, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Color.line3))
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .modifier(PressFeedback(isPressed: configuration.isPressed))
    }
}

/// Text-only action, for "Back", "Skip", "Not now".
struct ArchyGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .foregroundStyle(configuration.isPressed ? Color.ink : .inkSecondary)
            .contentShape(Rectangle())
            .modifier(PressFeedback(isPressed: configuration.isPressed))
    }
}

/// For tappable cards and rows (NavigationLink labels, choice tiles): a subtler squeeze.
struct ArchyPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .modifier(PressFeedback(isPressed: configuration.isPressed, scale: 0.98))
    }
}

extension ButtonStyle where Self == ArchyPrimaryButtonStyle { static var archyPrimary: Self { .init() } }
extension ButtonStyle where Self == ArchySecondaryButtonStyle { static var archySecondary: Self { .init() } }
extension ButtonStyle where Self == ArchyGhostButtonStyle { static var archyGhost: Self { .init() } }
extension ButtonStyle where Self == ArchyPressableStyle { static var archyPressable: Self { .init() } }

// MARK: - Surfaces

extension View {
    /// The one card treatment: raised surface, hairline border, continuous corners.
    /// `selected` swaps the border for ink so a chosen card reads without color.
    func surface(radius: CGFloat = Radius.xl, padding: CGFloat = Space.lg, selected: Bool = false) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(selected ? Color.ink : .line2, lineWidth: selected ? 1.5 : 1))
    }

    /// Page background plus the standard ink foreground. Apply at the root of every screen.
    func archyScreen() -> some View {
        self.foregroundStyle(.ink)
            .background(Color.bg.ignoresSafeArea())
            .tint(.ink)
    }
}

/// A 1pt hairline divider in the ink tint.
struct Hairline: View {
    var body: some View { Rectangle().fill(.line2).frame(height: 1).accessibilityHidden(true) }
}

// MARK: - Controls

/// Segmented control matching the web `.seg`: a sunken track with a raised pill that slides between options.
struct ArchySegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button {
                    withAnimation(Motion.playful.reduced(reduceMotion)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isOn ? Color.ink : .inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(Color.bg)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Color.line2))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.surface3, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A big display number that rolls between values.
struct MetricText: View {
    let value: Double
    var fractionDigits = 0
    var style: DisplayStyle = .metric
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(value, format: .number.precision(.fractionLength(fractionDigits)))
            .display(style)
            .contentTransition(.numericText(value: value))
            .animation(Motion.snappy.reduced(reduceMotion), value: value)
    }
}
