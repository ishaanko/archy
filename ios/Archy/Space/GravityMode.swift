import Foundation

/// Where the insole will be walked on. Raw values are stored in saved requests.
enum GravityMode: String, CaseIterable, Identifiable {
    case earth = "Earth", moon = "Moon", mars = "Mars", microgravity = "Microgravity"
    var id: String { rawValue }
    /// Surface gravity relative to Earth.
    var g: Double { switch self { case .earth: 1; case .moon: 0.165; case .mars: 0.38; case .microgravity: 0 } }
    /// Short name for controls.
    var title: String { self == .microgravity ? "Zero-g" : rawValue }
}
