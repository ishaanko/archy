import SwiftUI

// Building blocks for OnboardingView: the progress bar, answer rows, the welcome logo entrance,
// the pain ruler and the finish check.

/// Thin segmented progress along the top. Each segment's fill springs in or out as `filled` changes.
struct SegmentedProgress: View {
    let filled: Int
    var count = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<count, id: \.self) { index in
                let isOn = index < filled
                Capsule()
                    .fill(.line2)
                    .overlay {
                        Capsule().fill(.ink)
                            .scaleEffect(x: isOn || reduceMotion ? 1 : 0, anchor: .leading)
                            .opacity(isOn ? 1 : 0)
                    }
                    .clipShape(Capsule())
                    .frame(height: 3)
            }
        }
        .animation(Motion.playful.reduced(reduceMotion), value: filled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question \(min(filled, count)) of \(count)")
    }
}

/// A full-width answer. The chosen row pops and its border turns to ink while the others dim.
struct ChoiceRow: View {
    let title: String
    let selected: Bool
    let dimmed: Bool
    var font: Font = .title3.weight(.medium)
    var minHeight: CGFloat = 28
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .surface(radius: Radius.lg, selected: selected)
                .scaleEffect(selected && !reduceMotion ? 1.02 : 1)
                .opacity(dimmed ? 0.35 : 1)
        }
        .buttonStyle(.archyPressable)
        .animation(Motion.playful.reduced(reduceMotion), value: selected)
        .animation(Motion.snappy.reduced(reduceMotion), value: dimmed)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The welcome logo: the footprint drops in and lands, then the wordmark reveals beside it.
/// Plays once when first shown.
struct WelcomeLogo: View {
    var height: CGFloat = 80
    @State private var landed = false
    @State private var thud = false
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The logo asset is 296.91 x 92.5 units with the footprint in its last 29 units.
    private var unit: CGFloat { height / 92.5 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArchyLogo(height: height)
                .mask(alignment: .leading) { Rectangle().frame(width: 266 * unit) }
                .opacity(revealed ? 1 : 0)
                .blur(radius: revealed || reduceMotion ? 0 : 8)
                .offset(x: revealed || reduceMotion ? 0 : -16)
            ArchyMark(height: 59.86 * unit)
                .scaleEffect(landed || reduceMotion ? 1 : 1.25)
                .offset(x: 269.93 * unit, y: (landed || reduceMotion ? 0 : -140) + 14.94 * unit)
                .opacity(landed ? 1 : 0)
        }
        .frame(width: 296.91 * unit, height: height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("archy")
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.7), trigger: thud)
        .task {
            withAnimation(Motion.playful.reduced(reduceMotion).delay(0.15)) { landed = true }
            try? await Task.sleep(for: .milliseconds(380))
            thud.toggle()
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(Motion.reveal.reduced(reduceMotion)) { revealed = true }
        }
    }
}

/// Horizontal ruler from 1 to 10. Drag anywhere on it: ticks near the finger rise and the chosen one turns brand.
struct PainScale: View {
    let level: Int
    let isSet: Bool
    let onSelect: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let range = 1...10
    private let tickHeight: CGFloat = 88

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(range), id: \.self) { value in
                    Capsule()
                        .fill(color(for: value))
                        .frame(width: 4, height: tickHeight)
                        .scaleEffect(y: height(for: value), anchor: .bottom)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let slot = proxy.size.width / CGFloat(range.count)
                    let value = min(max(Int(drag.location.x / slot) + 1, range.lowerBound), range.upperBound)
                    if value != level || !isSet { onSelect(value) }
                }
            )
        }
        .frame(height: tickHeight)
        .animation(Motion.snappy.reduced(reduceMotion), value: level)
        .animation(Motion.snappy.reduced(reduceMotion), value: isSet)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pain level")
        .accessibilityValue(isSet ? "\(level) out of 10" : "Not set")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSelect(min(level + 1, range.upperBound))
            case .decrement: onSelect(max(level - 1, range.lowerBound))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("quiz.pain.rating")
    }

    /// Tick height as a fraction of full: tall at the chosen value, tapering over three steps.
    private func height(for value: Int) -> CGFloat {
        let distance = CGFloat(abs(value - level))
        return 0.28 + 0.72 * max(0, 1 - distance / 3.5)
    }

    private func color(for value: Int) -> Color {
        guard isSet else { return .inkTertiary }
        return value == level ? .brand : .inkTertiary
    }
}

/// A ring that draws itself, then a check inside it. Plays once when shown.
struct DrawnCheck: View {
    var size: CGFloat = 96
    @State private var ringDrawn = false
    @State private var checkDrawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: ringDrawn ? 1 : 0)
                .stroke(.line3, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CheckShape()
                .trim(from: 0, to: checkDrawn ? 1 : 0)
                .stroke(.brand, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .padding(size * 0.28)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task {
            if reduceMotion { ringDrawn = true; checkDrawn = true; return }
            withAnimation(Motion.reveal) { ringDrawn = true }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(Motion.playful) { checkDrawn = true }
        }
    }
}

private nonisolated struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}
