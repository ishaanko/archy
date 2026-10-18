import SwiftUI
import UIKit

// archy design tokens: the native twin of sim/src/theme.css.
// Warm near-black / off-white that follows the system theme, ink-tinted text and lines,
// and one brand orange used sparingly (logo, the single most important thing on a screen).

extension Color {
    /// A color with separate light and dark values, resolved by UIKit at render time.
    static func archy(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }

    // Surfaces, from the page up.
    static let bg = archy(light: 0xf7f7f4, dark: 0x14120b)
    static let surface = archy(light: 0xf2f1ed, dark: 0x1b1913)
    static let surface2 = archy(light: 0xebeae5, dark: 0x201e18)
    static let surface3 = archy(light: 0xe6e5e0, dark: 0x26241e)
    static let surface4 = archy(light: 0xe1e0db, dark: 0x2b2923)

    // Ink: primary text and every tint derived from it.
    static let ink = archy(light: 0x26251e, dark: 0xedecec)
    static let ink2 = archy(light: 0x3b3a33, dark: 0xd7d6d5)
    static let inkSecondary = ink.opacity(0.6)
    static let inkTertiary = ink.opacity(0.4)

    // Hairlines.
    static let line = ink.opacity(0.05)
    static let line2 = ink.opacity(0.10)
    static let line3 = ink.opacity(0.20)

    // Signals.
    static let brand = Color(red: 229 / 255, green: 83 / 255, blue: 45 / 255)
    static let positive = Color(red: 31 / 255, green: 138 / 255, blue: 101 / 255)
    static let negative = Color(red: 207 / 255, green: 45 / 255, blue: 86 / 255)
}

// Lets token names work directly in `.foregroundStyle(.inkSecondary)` and `.fill(.surface)`.
extension ShapeStyle where Self == Color {
    static var bg: Color { .bg }
    static var surface: Color { .surface }
    static var surface2: Color { .surface2 }
    static var surface3: Color { .surface3 }
    static var surface4: Color { .surface4 }
    static var ink: Color { .ink }
    static var ink2: Color { .ink2 }
    static var inkSecondary: Color { .inkSecondary }
    static var inkTertiary: Color { .inkTertiary }
    static var line: Color { .line }
    static var line2: Color { .line2 }
    static var line3: Color { .line3 }
    static var brand: Color { .brand }
    static var positive: Color { .positive }
    static var negative: Color { .negative }
}

/// Corner radii, matching the web scale.
enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 24
}

/// Spacing scale. Screens use `page` as horizontal padding.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
    static let page: CGFloat = 20
}
