import Foundation

enum FootSide: String, CaseIterable, Codable, Identifiable, Sendable {
    case left, right
    var id: String { rawValue }
    var title: String { self == .left ? "Left" : "Right" }
}
enum MeasurementUnit: String, CaseIterable, Identifiable, Sendable {
    case millimeters, centimeters
    var id: String { rawValue }
    var symbol: String { self == .millimeters ? "mm" : "cm" }
    func toMillimeters(_ value: Double) -> Double { self == .centimeters ? value * 10 : value }
}
enum MeasurementField: String, CaseIterable, Identifiable, Sendable {
    case fullLength, truncatedLength, dorsumHeight, width, seatedNavicular, standingNavicular
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullLength: "Full foot length"
        case .truncatedLength: "Truncated foot length"
        case .dorsumHeight: "Dorsum height"
        case .width: "Forefoot width"
        case .seatedNavicular: "Seated navicular height"
        case .standingNavicular: "Standing navicular height"
        }
    }
    var instruction: String {
        switch self {
        case .fullLength: "Measure from the back of the heel to the tip of the longest toe."
        case .truncatedLength: "Measure from the back of the heel to the center of the first metatarsal head (the ball behind the big toe)."
        case .dorsumHeight: "Measure vertically from the supporting surface to the top of the foot at 50% of full foot length."
        case .width: "Measure across the widest part of the forefoot between the first and fifth metatarsal heads."
        case .seatedNavicular: "Sit with knees bent about 90°, feet flat and relaxed. Find the bony bump on the inner midfoot, below and forward of the inner ankle (navicular tuberosity). Mark it and measure vertically from the floor to the mark."
        case .standingNavicular: "Stand relaxed with weight shared evenly between both feet. Keep the same marked navicular landmark and measure vertically from the floor. Ask a helper to read the ruler without shifting your weight."
        }
    }
    var landmark: String {
        switch self {
        case .fullLength: "Heel → longest toe"
        case .truncatedLength: "Heel → first metatarsal head"
        case .dorsumHeight: "Dorsum at 50% of foot length"
        case .width: "First → fifth metatarsal head"
        case .seatedNavicular, .standingNavicular: "Navicular tuberosity"
        }
    }
}
/// All distances are stored in millimeters. Zero defaults represent incomplete entry.
struct FootMeasurements: Codable, Equatable, Hashable, Sendable {
    var fullLength: Double = 0
    var truncatedLength: Double = 0
    var dorsumHeight: Double = 0
    var width: Double = 0
    var seatedNavicular: Double = 0
    var standingNavicular: Double = 0
    subscript(field: MeasurementField) -> Double {
        get {
            switch field {
            case .fullLength: fullLength
            case .truncatedLength: truncatedLength
            case .dorsumHeight: dorsumHeight
            case .width: width
            case .seatedNavicular: seatedNavicular
            case .standingNavicular: standingNavicular
            }
        }
        set {
            switch field {
            case .fullLength: fullLength = newValue
            case .truncatedLength: truncatedLength = newValue
            case .dorsumHeight: dorsumHeight = newValue
            case .width: width = newValue
            case .seatedNavicular: seatedNavicular = newValue
            case .standingNavicular: standingNavicular = newValue
            }
        }
    }
    var validationErrors: [String] {
        var errors: [String] = MeasurementField.allCases.compactMap { field in
            self[field].isFinite && self[field] > 0 ? nil : "\(field.title) must be a finite number greater than zero."
        }
        if fullLength.isFinite && fullLength > 0 {
            for field in MeasurementField.allCases where field != .fullLength {
                if self[field].isFinite && self[field] >= fullLength {
                    errors.append("\(field.title) must be less than full foot length.")
                }
            }
        }
        return errors
    }
}
enum MeasurementError: Error, LocalizedError, Equatable {
    case invalidMeasurements([String])
    var errorDescription: String? {
        switch self { case .invalidMeasurements(let errors): errors.joined(separator: " ") }
    }
}
enum MeasurementMath {
    private static func validate(_ values: FootMeasurements) throws {
        let errors = values.validationErrors
        guard errors.isEmpty else { throw MeasurementError.invalidMeasurements(errors) }
    }
    static func archHeightIndex(_ values: FootMeasurements) throws -> Double {
        try validate(values)
        return try archHeightIndex(dorsumHeight: values.dorsumHeight, truncatedLength: values.truncatedLength)
    }
    static func archHeightIndex(dorsumHeight: Double, truncatedLength: Double) throws -> Double {
        guard dorsumHeight.isFinite, truncatedLength.isFinite, dorsumHeight > 0, truncatedLength > 0 else {
            throw MeasurementError.invalidMeasurements(["Arch dimensions must be finite and greater than zero."])
        }
        let result = dorsumHeight / truncatedLength
        guard result.isFinite else { throw MeasurementError.invalidMeasurements(["The AHI ratio is not finite. Recheck the readings."]) }
        return result
    }
    /// Signed millimeters: seated minus standing; negative results are preserved.
    static func navicularDrop(_ values: FootMeasurements) throws -> Double {
        try validate(values)
        return values.seatedNavicular - values.standingNavicular
    }
    static func widthLengthRatio(_ values: FootMeasurements) throws -> Double {
        try validate(values)
        return values.width / values.fullLength
    }
}
struct Assessment: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var date: Date = Date()
    var left: FootMeasurements
    var right: FootMeasurements
    var isSynthetic: Bool = false
    func measurements(for side: FootSide) -> FootMeasurements { side == .left ? left : right }
    static var synthetic: Assessment {
        Assessment(
            left: FootMeasurements(fullLength: 260, truncatedLength: 190, dorsumHeight: 62, width: 98, seatedNavicular: 42, standingNavicular: 35),
            right: FootMeasurements(fullLength: 262, truncatedLength: 192, dorsumHeight: 63, width: 99, seatedNavicular: 43, standingNavicular: 36),
            isSynthetic: true
        )
    }
}
