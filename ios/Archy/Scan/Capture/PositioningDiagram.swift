import SwiftUI

/// Side view of the scan setup: the helper circles the standing foot twice, at knee height and near the floor.
/// Plays once when it appears (lap 1, then lap 2); tap to replay. It never loops.
@MainActor
struct PositioningDiagram: View {
    private static let canvas = CGSize(width: 350, height: 250)
    private static let floorY: CGFloat = 200
    private static let phoneX: CGFloat = 52
    private static let kneeY: CGFloat = 52
    private static let lowY: CGFloat = 182

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lap = 1
    /// How far around the floor ring the helper is, 0 to 1.
    @State private var progress = 0.0
    @State private var playback: Task<Void, Never>?

    private var phoneY: CGFloat { lap == 1 ? Self.kneeY : Self.lowY }

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: Space.md) {
                GeometryReader { proxy in
                    scene
                        .frame(width: Self.canvas.width, height: Self.canvas.height)
                        .scaleEffect(proxy.size.width / Self.canvas.width, anchor: .topLeading)
                }
                .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)

                HStack {
                    Text(lap == 1 ? "Lap 1 · knee height" : "Lap 2 · near the floor")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.ink2)
                        .contentTransition(.opacity)
                    Spacer()
                    Text("Tap to replay")
                        .font(.footnote)
                        .foregroundStyle(.inkTertiary)
                }
            }
        }
        .buttonStyle(.archyPressable)
        .accessibilityLabel("Hold the phone about 50 centimeters from the foot. Walk all the way around once at knee height, then again with the phone near the floor.")
        .accessibilityHint("Replays the animation")
        .onAppear(perform: play)
        .onDisappear { playback?.cancel() }
    }

    /// Back of the ring and the sight lines sit under the leg; the front of the ring and the phone sit over it.
    private var scene: some View {
        let sweep = StrokeStyle(lineWidth: 2.5, lineCap: .round)
        return ZStack {
            LapArc(progress: progress, back: true).stroke(Color.brand, style: sweep)
            SightLines(phoneY: phoneY)
                .stroke(Color.inkTertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))
            Canvas { context, _ in Self.drawLeg(in: &context) }
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.35)],
                                     startPoint: .top, endPoint: .bottom))
            LapArc(progress: progress, back: false).stroke(Color.brand, style: sweep)
            LapHead(progress: progress).fill(Color.brand)
            Image(systemName: "iphone")
                .font(.system(size: 28))
                .foregroundStyle(.ink)
                .rotationEffect(.degrees(lap == 1 ? 35 : 4))
                .position(x: Self.phoneX, y: phoneY)
        }
    }

    /// Lap 1 sweeps the ring at knee height, then the phone drops and lap 2 sweeps it again.
    private func play() {
        playback?.cancel()
        playback = Task {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { lap = 1; progress = 0 }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.reveal.reduced(reduceMotion)) { progress = 1 }
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.smooth.reduced(reduceMotion)) { lap = 2 }
            withTransaction(instant) { progress = 0 }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.reveal.reduced(reduceMotion)) { progress = 1 }
        }
    }

    private static func drawLeg(in context: inout GraphicsContext) {
        let place = CGAffineTransform(translationX: 144, y: floorY)
        let legFill = FootProfile.path(shinHeight: 180, closed: true).applying(place)
        let legOutline = FootProfile.path(shinHeight: 180, closed: false).applying(place)

        context.stroke(Path { $0.move(to: CGPoint(x: 8, y: floorY)); $0.addLine(to: CGPoint(x: 342, y: floorY)) },
                       with: .color(.inkTertiary), lineWidth: 1.5)
        context.fill(legFill, with: .color(.bg))
        context.fill(legFill, with: .color(.ink.opacity(0.08)))
        context.stroke(legOutline, with: .color(.ink),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        drawDistance(from: phoneX, to: LapGeometry.ring.midX, y: 238, in: context)
    }

    /// The "≈ 50 cm" dimension marker under the floor, from the phone to the middle of the foot.
    private static func drawDistance(from x0: CGFloat, to x1: CGFloat, y: CGFloat, in context: GraphicsContext) {
        let label = context.resolve(Text("≈ 50 cm").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.inkSecondary))
        let mid = (x0 + x1) / 2
        let gap = label.measure(in: CGSize(width: 200, height: 40)).width / 2 + 5
        let ticks = Path { path in
            path.move(to: CGPoint(x: x0, y: 206)); path.addLine(to: CGPoint(x: x0, y: y + 6))
            path.move(to: CGPoint(x: x1, y: 228)); path.addLine(to: CGPoint(x: x1, y: y + 6))
            path.move(to: CGPoint(x: x0 + 1, y: y)); path.addLine(to: CGPoint(x: mid - gap, y: y))
            path.move(to: CGPoint(x: mid + gap, y: y)); path.addLine(to: CGPoint(x: x1 - 1, y: y))
        }
        context.stroke(ticks, with: .color(.inkTertiary), lineWidth: 1)
        context.fill(DiagramShapes.arrowhead(at: CGPoint(x: x0 + 1, y: y), heading: .degrees(180), size: 5), with: .color(.inkTertiary))
        context.fill(DiagramShapes.arrowhead(at: CGPoint(x: x1 - 1, y: y), heading: .zero, size: 5), with: .color(.inkTertiary))
        context.draw(label, at: CGPoint(x: mid, y: y))
    }
}

/// Plain geometry shared by the diagram's animatable shapes, in the diagram's 350 x 250 space.
private nonisolated enum LapGeometry {
    /// The helper's walking path on the floor, centered on the foot.
    static let ring = CGRect(x: 52, y: 176, width: 292, height: 48)

    /// Point on the ring at angle `t` (y points down, so 0 to pi is the near half).
    static func point(at t: Double) -> CGPoint {
        CGPoint(x: ring.midX + ring.width / 2 * cos(t), y: ring.midY + ring.height / 2 * sin(t))
    }
}

/// The near or far half of the walking ring, drawn up to `progress` (0 to 1 around the whole ring).
private nonisolated struct LapArc: Shape {
    var progress: Double
    let back: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let start = back ? Double.pi : 0
        let end = min(start + .pi, progress * 2 * .pi)
        guard end > start else { return Path() }
        return Path { path in
            let steps = 48
            for i in 0...steps {
                let point = LapGeometry.point(at: start + (end - start) * Double(i) / Double(steps))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

/// Arrowhead riding the leading end of the walking ring.
private nonisolated struct LapHead: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard progress > 0.001 else { return Path() }
        let t = progress * 2 * .pi
        let tip = LapGeometry.point(at: t)
        let heading = atan2(LapGeometry.ring.height / 2 * cos(t), -LapGeometry.ring.width / 2 * sin(t))
        let size: CGFloat = 9
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: -size, y: -size * 0.6))
        path.addLine(to: CGPoint(x: -size, y: size * 0.6))
        path.closeSubpath()
        return path.applying(CGAffineTransform(rotationAngle: heading).concatenating(CGAffineTransform(translationX: tip.x, y: tip.y)))
    }
}

/// Dashed lines from the phone's camera to the foot. Follows the phone as it drops between laps.
private nonisolated struct SightLines: Shape {
    var phoneY: CGFloat

    var animatableData: CGFloat {
        get { phoneY }
        set { phoneY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let from = CGPoint(x: 52, y: phoneY)
        // Aim at the shin for the high phone and the ankle for the low one.
        let target = CGPoint(x: 190, y: 178 + (phoneY - 52) * 14 / 130)
        let dx = target.x - from.x, dy = target.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        return Path { path in
            path.move(to: CGPoint(x: from.x + dx / length * 14, y: from.y + dy / length * 14))
            path.addLine(to: target)
        }
    }
}

/// Small white sketch for the camera overlay: drag the box's top edge down from the shin to the ankle bone.
@MainActor
struct BoxTrimDiagram: View {
    private static let canvas = CGSize(width: 160, height: 100)

    var body: some View {
        Canvas { context, size in
            let scale = size.width / Self.canvas.width
            context.scaleBy(x: scale, y: scale)
            Self.draw(in: &context)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .frame(maxWidth: 170)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Drag the top of the box down to the ankle bone.")
    }

    private static func draw(in context: inout GraphicsContext) {
        let white = GraphicsContext.Shading.color(.white)
        let floorY: CGFloat = 72
        let place = CGAffineTransform(scaleX: 0.55, y: 0.55).concatenating(.init(translationX: 41, y: floorY))
        let ankle = FootProfile.ankleBone.applying(place)

        context.stroke(Path { $0.move(to: CGPoint(x: 16, y: floorY)); $0.addLine(to: CGPoint(x: 144, y: floorY)) },
                       with: .color(.white.opacity(0.5)), lineWidth: 1)
        context.fill(FootProfile.path(shinHeight: 127, closed: true).applying(place), with: .color(.white.opacity(0.2)))
        context.stroke(FootProfile.path(shinHeight: 127, closed: false).applying(place), with: white,
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        context.fill(Path(ellipseIn: CGRect(x: ankle.x - 2.5, y: ankle.y - 2.5, width: 5, height: 5)), with: white)

        // Box as auto-detected: the top sits on the shin.
        let front = CGRect(x: 28, y: 16, width: 76, height: 60)
        let depth = CGSize(width: 10, height: -7)
        context.stroke(box(front: front, depth: depth), with: .color(.white.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        // Trimmed top at the ankle bone.
        let newTop = ankle.y + 3
        let top = Path { path in
            path.addLines([CGPoint(x: front.minX, y: newTop), CGPoint(x: front.maxX, y: newTop),
                           CGPoint(x: front.maxX + depth.width, y: newTop + depth.height),
                           CGPoint(x: front.minX + depth.width, y: newTop + depth.height)])
            path.closeSubpath()
        }
        context.fill(top, with: .color(.white.opacity(0.15)))
        context.stroke(top, with: white, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        let arrowX: CGFloat = 130
        let arrowTop = front.minY + depth.height / 2
        let arrowTip = newTop + depth.height / 2
        context.stroke(Path { $0.move(to: CGPoint(x: arrowX, y: arrowTop)); $0.addLine(to: CGPoint(x: arrowX, y: arrowTip - 4)) },
                       with: white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        context.fill(DiagramShapes.arrowhead(at: CGPoint(x: arrowX, y: arrowTip), heading: .degrees(90), size: 7), with: white)

        context.draw(Text("Drag top to ankle").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white),
                     at: CGPoint(x: 80, y: 89))
    }

    /// Wireframe cube: front face, back face offset by `depth`, and the four connecting edges.
    private static func box(front: CGRect, depth: CGSize) -> Path {
        let back = front.offsetBy(dx: depth.width, dy: depth.height)
        return Path { path in
            path.addRect(front)
            path.addRect(back)
            for (a, b) in [(CGPoint(x: front.minX, y: front.minY), CGPoint(x: back.minX, y: back.minY)),
                           (CGPoint(x: front.maxX, y: front.minY), CGPoint(x: back.maxX, y: back.minY)),
                           (CGPoint(x: front.minX, y: front.maxY), CGPoint(x: back.minX, y: back.maxY)),
                           (CGPoint(x: front.maxX, y: front.maxY), CGPoint(x: back.maxX, y: back.maxY))] {
                path.move(to: a)
                path.addLine(to: b)
            }
        }
    }
}

/// Lower leg and foot in profile, toes pointing left. Floor at y = 0, toe tip at x = 0, foot about 108 long.
@MainActor
private enum FootProfile {
    static let ankleBone = CGPoint(x: 82, y: -40)

    /// `shinHeight` is how far up the leg goes. Closing the path adds the cut across the top of the shin.
    static func path(shinHeight h: CGFloat, closed: Bool) -> Path {
        let calf = max(0, h - 48)
        var path = Path()
        path.move(to: CGPoint(x: 66, y: -h))
        if h > 170 {
            path.addLine(to: CGPoint(x: 66, y: -166))
            path.addCurve(to: CGPoint(x: 64, y: -128), control1: CGPoint(x: 73, y: -158), control2: CGPoint(x: 70, y: -136))
        }
        path.addLine(to: CGPoint(x: 63, y: -54))
        path.addCurve(to: CGPoint(x: 24, y: -24), control1: CGPoint(x: 55, y: -48), control2: CGPoint(x: 38, y: -35))
        path.addCurve(to: CGPoint(x: 8, y: -17), control1: CGPoint(x: 16, y: -21), control2: CGPoint(x: 12, y: -18))
        path.addCurve(to: CGPoint(x: 6, y: 0), control1: CGPoint(x: -1, y: -15), control2: CGPoint(x: -1, y: 0))
        path.addLine(to: CGPoint(x: 34, y: 0))
        path.addCurve(to: CGPoint(x: 84, y: 0), control1: CGPoint(x: 48, y: -11), control2: CGPoint(x: 70, y: -14))
        path.addLine(to: CGPoint(x: 94, y: 0))
        path.addCurve(to: CGPoint(x: 108, y: -14), control1: CGPoint(x: 103, y: 0), control2: CGPoint(x: 108.5, y: -6))
        path.addCurve(to: CGPoint(x: 99, y: -46), control1: CGPoint(x: 107.5, y: -24), control2: CGPoint(x: 99, y: -34))
        path.addCurve(to: CGPoint(x: 104, y: -h),
                      control1: CGPoint(x: 99 + calf * 0.04, y: -46 - calf * 0.4),
                      control2: CGPoint(x: 100 + calf * 0.12, y: -46 - calf * 0.7))
        if closed { path.closeSubpath() }
        return path
    }
}

@MainActor
private enum DiagramShapes {
    /// Part of the ellipse inscribed in `rect`, from angle `t0` to `t1` in radians (y points down, so 0…π is the near half).
    static func arc(in rect: CGRect, from t0: Double, to t1: Double) -> Path {
        Path { path in
            let steps = 64
            for i in 0...steps {
                let t = t0 + (t1 - t0) * Double(i) / Double(steps)
                let point = CGPoint(x: rect.midX + rect.width / 2 * cos(t), y: rect.midY + rect.height / 2 * sin(t))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }

    /// Filled triangle with its tip at `tip`, pointing along `heading` (0° points right, 90° points down).
    static func arrowhead(at tip: CGPoint, heading: Angle, size: CGFloat) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: -size, y: -size * 0.6))
        path.addLine(to: CGPoint(x: -size, y: size * 0.6))
        path.closeSubpath()
        return path.applying(CGAffineTransform(rotationAngle: heading.radians)
            .concatenating(CGAffineTransform(translationX: tip.x, y: tip.y)))
    }
}
