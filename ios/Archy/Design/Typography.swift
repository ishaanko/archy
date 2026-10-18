import SwiftUI

// Headings and big numbers use Instrument Sans (the archy wordmark face, bundled in Resources/Fonts).
// Body copy and controls use the system font. Numbers that tick use monospaced digits.

/// The display type scale. Every size scales with Dynamic Type.
enum DisplayStyle {
    /// One per screen at most: onboarding and the top of a tab.
    case hero
    /// Screen and sheet titles.
    case title
    /// Section headings and card titles.
    case headline
    /// Large live numbers (AHI, countdowns, percentages).
    case metric

    var size: CGFloat {
        switch self {
        case .hero: 44
        case .title: 32
        case .headline: 22
        case .metric: 56
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .hero, .metric: .largeTitle
        case .title: .title
        case .headline: .title3
        }
    }

    /// Tight negative tracking, like the web's -0.02em to -0.03em.
    var tracking: CGFloat {
        switch self {
        case .hero: -1.4
        case .title: -0.9
        case .headline: -0.4
        case .metric: -1.8
        }
    }
}

extension Font {
    /// Instrument Sans at a display size.
    static func display(_ style: DisplayStyle) -> Font {
        .custom("InstrumentSans-Medium", size: style.size, relativeTo: style.relativeTo)
    }
}

extension View {
    /// Applies the display font and its tracking. Use on `Text` headings and metrics.
    func display(_ style: DisplayStyle) -> some View {
        font(.display(style))
            .tracking(style.tracking)
            .monospacedDigit()
    }
}
