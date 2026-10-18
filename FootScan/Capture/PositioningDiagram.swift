//
//  PositioningDiagram.swift
//  FootScan
//

import SwiftUI

/// Side view of the scan setup: the helper circles the standing foot twice, at knee height and near the floor.
@MainActor
struct PositioningDiagram: View {
    private static let canvas = CGSize(width: 350, height: 250)
    private static let floorY: CGFloat = 200
    /// The helper's walking path on the floor, centered on the foot.
    private static let ring = CGRect(x: 52, y: 176, width: 292, height: 48)
    private static let lap1Phone = CGPoint(x: 52, y: 52)
    private static let lap2Phone = CGPoint(x: 52, y: 182)

    var body: some View {
        Canvas { context, size in
            let scale = size.width / Self.canvas.width
            context.scaleBy(x: scale, y: scale)
            Self.draw(in: &context)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Hold the phone about 50 centimeters from the foot. Walk all the way around once at knee height, then again with the phone near the floor.")
    }

    private static func draw(in context: inout GraphicsContext) {
        let place = CGAffineTransform(translationX: 144, y: floorY)
        let legFill = FootProfile.path(shinHeight: 180, closed: true).applying(place)
        let legOutline = FootProfile.path(shinHeight: 180, closed: false).applying(place)
        let tint = GraphicsContext.Shading.style(.tint)
        let dashed = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4])

        context.stroke(Path { $0.move(to: CGPoint(x: 8, y: floorY)); $0.addLine(to: CGPoint(x: 342, y: floorY)) },
                       with: .color(.secondary), lineWidth: 1.5)

        // The back of the ring and the sight lines disappear behind the leg.
        var behind = context
        behind.clip(to: legFill, options: .inverse)
        behind.stroke(DiagramShapes.arc(in: ring, from: .pi, to: 2 * .pi), with: tint,
                      style: StrokeStyle(lineWidth: 2, lineCap: .round))
        behind.stroke(sightLine(from: lap1Phone, to: CGPoint(x: 190, y: 178)), with: tint, style: dashed)
        behind.stroke(sightLine(from: lap2Phone, to: CGPoint(x: 190, y: 192)), with: tint, style: dashed)
        behind.stroke(Path { $0.move(to: CGPoint(x: 72, y: lap1Phone.y)); $0.addLine(to: CGPoint(x: 230, y: lap1Phone.y)) },
                      with: .color(.secondary), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 4]))

        context.fill(legFill, with: .color(.secondary.opacity(0.18)))
        context.stroke(legOutline, with: .color(.primary),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        context.stroke(DiagramShapes.arc(in: ring, from: 0, to: .pi), with: tint,
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        for t in [Double.pi / 4, -Double.pi / 4 - 0.25] {
            let point = CGPoint(x: ring.midX + ring.width / 2 * cos(t), y: ring.midY + ring.height / 2 * sin(t))
            let heading = Angle(radians: atan2(-ring.height * cos(t), ring.width * sin(t)))
            context.fill(DiagramShapes.arrowhead(at: point, heading: heading, size: 9), with: tint)
        }

        drawPhone(at: lap1Phone, tilt: 35, in: context)
        drawPhone(at: lap2Phone, tilt: 4, in: context)

        let labelFont = Font.system(size: 12)
        context.draw(Text("\(Text("Lap 1").bold()) · knee height").font(labelFont),
                     at: CGPoint(x: 16, y: 20), anchor: .leading)
        context.draw(Text("\(Text("Lap 2").bold()) · near the floor").font(labelFont),
                     at: CGPoint(x: 16, y: 152), anchor: .leading)
        context.draw(Text("walk all the\nway around").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tint),
                     at: CGPoint(x: 302, y: 154), anchor: .center)

        drawDistance(from: lap2Phone.x, to: ring.midX, y: 238, in: context)
    }

    /// A dashed line from the phone's camera to a point on the foot.
    private static func sightLine(from phone: CGPoint, to target: CGPoint) -> Path {
        let dx = target.x - phone.x, dy = target.y - phone.y
        let length = (dx * dx + dy * dy).squareRoot()
        let start = CGPoint(x: phone.x + dx / length * 14, y: phone.y + dy / length * 14)
        return Path { $0.move(to: start); $0.addLine(to: target) }
    }

    private static func drawPhone(at point: CGPoint, tilt: Double, in context: GraphicsContext) {
        var phone = context
        phone.translateBy(x: point.x, y: point.y)
        phone.rotate(by: .degrees(tilt))
        phone.draw(Text(Image(systemName: "iphone")).font(.system(size: 28)).foregroundStyle(.tint), at: .zero)
    }

    /// The "≈ 50 cm" dimension marker under the floor, from the phone to the middle of the foot.
    private static func drawDistance(from x0: CGFloat, to x1: CGFloat, y: CGFloat, in context: GraphicsContext) {
        let label = context.resolve(Text("≈ 50 cm").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary))
        let mid = (x0 + x1) / 2
        let gap = label.measure(in: CGSize(width: 200, height: 40)).width / 2 + 5
        let ticks = Path { path in
            path.move(to: CGPoint(x: x0, y: 206)); path.addLine(to: CGPoint(x: x0, y: y + 6))
            path.move(to: CGPoint(x: x1, y: 228)); path.addLine(to: CGPoint(x: x1, y: y + 6))
            path.move(to: CGPoint(x: x0 + 1, y: y)); path.addLine(to: CGPoint(x: mid - gap, y: y))
            path.move(to: CGPoint(x: mid + gap, y: y)); path.addLine(to: CGPoint(x: x1 - 1, y: y))
        }
        context.stroke(ticks, with: .color(.secondary), lineWidth: 1)
        context.fill(DiagramShapes.arrowhead(at: CGPoint(x: x0 + 1, y: y), heading: .degrees(180), size: 5), with: .color(.secondary))
        context.fill(DiagramShapes.arrowhead(at: CGPoint(x: x1 - 1, y: y), heading: .zero, size: 5), with: .color(.secondary))
        context.draw(label, at: CGPoint(x: mid, y: y))
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
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
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
