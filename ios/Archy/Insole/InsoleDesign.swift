import SwiftUI

/// The three surface concepts. Raw values are stored in saved requests.
enum InsoleMaterial: String, CaseIterable, Identifiable {
    case lattice = "Lattice", foam = "Foam", carbon = "Carbon"
    var id: String { rawValue }
}

/// Everything the user dials in on the studio, plus the load model the visuals share.
struct InsoleDesign: Equatable {
    var side: FootSide = .left
    var environment: GravityMode = .earth
    /// Arch support, 0...1.
    var support = 0.5
    var material: InsoleMaterial = .lattice

    /// How strongly the support zone reads: the slider, eased down as the load drops.
    var zoneStrength: Double { support * (0.55 + 0.45 * environment.g) }

    /// Side-view arch height (0...1): the resting height, sagging under load; support holds the sag back.
    func loadedArch(rest: Double) -> Double { rest * (1 - 0.4 * environment.g * (1 - 0.8 * support)) }
}

extension FootMeasurements {
    /// Resting arch height for `FootArchShape`, from dorsum height relative to foot length.
    var restingArch: Double { min(0.75, max(0.16, dorsumHeight / fullLength * 2)) }

    /// Width-to-height ratio for the top-view insole.
    var insoleAspect: CGFloat { min(0.62, max(0.45, CGFloat(width / fullLength) * 1.4)) }
}
