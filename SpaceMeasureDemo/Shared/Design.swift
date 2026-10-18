import SwiftUI
import UIKit

// Native equivalents of sim/src/theme.css. UIKit resolves both palettes at runtime.
extension Color {
    static func archy(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static let archyBackground = archy(light: 0xf7f7f4, dark: 0x14120b)
    static let archyForeground = archy(light: 0x26251e, dark: 0xedecec)
    static let archyCard = archy(light: 0xf2f1ed, dark: 0x1b1913)
    static let archyRaised = archy(light: 0xe6e5e0, dark: 0x26241e)
    static let archyAccent = Color(red: 229 / 255.0, green: 83 / 255.0, blue: 45 / 255.0)
    static let archyGreen = Color(red: 31 / 255.0, green: 138 / 255.0, blue: 101 / 255.0)
    static let archyBorder = archyForeground.opacity(0.10)
    static let archySecondary = archyForeground.opacity(0.72)
    static let ink = archyBackground
    static let lunar = archyAccent
    static let mintSignal = archyGreen
}
struct Panel<Content: View>: View {
    var dark = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Color.archyCard, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.archyBorder))
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(.caption, design: .monospaced, weight: .medium))
            .tracking(1).foregroundStyle(Color.archySecondary)
    }
}
struct ArchyWordmark: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "shoeprints.fill").foregroundStyle(Color.archyAccent).font(.title3)
            Text("archy").font(.title2.weight(.medium)).tracking(-1).foregroundStyle(Color.archyForeground)
        }.accessibilityElement(children: .ignore).accessibilityLabel("archy")
    }
}
struct ArchyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.medium))
            .frame(minHeight: 44).padding(.horizontal, 16)
            .foregroundStyle(Color.archyBackground)
            .background(Color.archyForeground.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.4)
    }
}
struct SpaceBackground: View {
    var body: some View { Color.archyBackground.ignoresSafeArea().accessibilityHidden(true) }
}
struct FootArchShape: Shape {
    var height: Double
    var animatableData: Double { get { height } set { height = newValue } }
    func path(in r: CGRect) -> Path {
        let w = r.width, base = r.height * 0.84
        let top = base - r.height * CGFloat(height)
        var p = Path()
        p.move(to: CGPoint(x: w * 0.06, y: base))
        p.addCurve(to: CGPoint(x: w * 0.2, y: top + 12), control1: CGPoint(x: -w * 0.02, y: base - 25), control2: CGPoint(x: w * 0.08, y: top))
        p.addCurve(to: CGPoint(x: w * 0.78, y: base - 30), control1: CGPoint(x: w * 0.49, y: top - 20), control2: CGPoint(x: w * 0.6, y: base - 39))
        p.addCurve(to: CGPoint(x: w * 0.97, y: base), control1: CGPoint(x: w * 0.95, y: base - 39), control2: CGPoint(x: w, y: base - 19))
        p.addLine(to: CGPoint(x: w * 0.7, y: base))
        p.addCurve(to: CGPoint(x: w * 0.2, y: base), control1: CGPoint(x: w * 0.51, y: base - r.height * CGFloat(height) * 0.75), control2: CGPoint(x: w * 0.37, y: base - r.height * CGFloat(height) * 0.63))
        p.closeSubpath()
        return p
    }
}
struct FootDiagram: View {
    let field: MeasurementField
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if field == .width {
                    InsoleShape().fill(Color.archyAccent.opacity(0.12)).frame(width: 110, height: 230).rotationEffect(.degrees(90))
                    InsoleShape().stroke(Color.archyAccent, lineWidth: 2).frame(width: 110, height: 230).rotationEffect(.degrees(90))
                    Path { p in p.move(to: CGPoint(x: 85, y: 25)); p.addLine(to: CGPoint(x: 85, y: 123)) }.stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [5]))
                } else {
                    FootArchShape(height: 0.48).fill(Color.archyAccent.opacity(0.12))
                    FootArchShape(height: 0.48).stroke(Color.archyAccent, lineWidth: 2)
                    if field == .fullLength || field == .truncatedLength {
                        Path { p in p.move(to: CGPoint(x: 20, y: 135)); p.addLine(to: CGPoint(x: field == .truncatedLength ? 225 : 285, y: 135)) }.stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [5]))
                    } else {
                        let landmarkX: CGFloat = field == .dorsumHeight ? 150 : 110
                        let landmarkY: CGFloat = field == .dorsumHeight ? 65 : 85
                        Path { p in p.move(to: CGPoint(x: landmarkX, y: 130)); p.addLine(to: CGPoint(x: landmarkX, y: landmarkY)) }.stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [5]))
                        Circle().fill(.orange).frame(width: 10).position(x: landmarkX, y: landmarkY)
                    }
                }
            }.frame(width: 300, height: 155)
            Text(field == .width ? "Width: measure across the widest forefoot from above." : "Side view · schematic, not to scale").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).accessibilityLabel("Foot landmark schematic. \(field.landmark)")
    }
}
