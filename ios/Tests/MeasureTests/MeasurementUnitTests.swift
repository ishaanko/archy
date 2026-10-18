import Foundation
import Testing
@testable import MeasurementCore

struct MeasurementUnitTests {
    @Test func inchesConvertThroughMillimeters() {
        #expect(MeasurementUnit.inches.toMillimeters(1) == 25.4)
        #expect(abs(MeasurementUnit.inches.fromMillimeters(260) - 10.2362) < 0.0001)
    }

    @Test(arguments: MeasurementUnit.allCases, [0.5, 62, 260.4])
    func roundTripsThroughMillimeters(unit: MeasurementUnit, millimeters: Double) {
        #expect(abs(unit.toMillimeters(unit.fromMillimeters(millimeters)) - millimeters) < 1e-9)
    }

    /// The wizard converts what's typed when the unit changes: 260 mm -> in -> cm lands on 26 cm.
    @Test func switchingUnitsKeepsTheSameLength() {
        let inches = MeasurementUnit.inches.fromMillimeters(MeasurementUnit.millimeters.toMillimeters(260))
        let mm = MeasurementUnit.inches.toMillimeters(inches)
        #expect(abs(MeasurementUnit.centimeters.fromMillimeters(mm) - 26) < 1e-9)
    }

    @Test func formatsWithTheUnitsPrecision() {
        #expect(MeasurementUnit.inches.format(millimeters: 260) == "10.2 in")
        #expect(MeasurementUnit.inches.format(millimeters: 15.9, fine: true) == "0.63 in")
        #expect(MeasurementUnit.centimeters.format(millimeters: 260) == "26.0 cm")
        #expect(MeasurementUnit.millimeters.format(millimeters: 62) == "62 mm")
        #expect(MeasurementUnit.millimeters.format(millimeters: 7, fine: true, symbol: false) == "7.0")
    }

    @Test func defaultsToInchesOnlyForTheUSLocale() {
        #expect(MeasurementUnit.localeDefault(for: Locale(identifier: "en_US")) == .inches)
        #expect(MeasurementUnit.localeDefault(for: Locale(identifier: "de_DE")) == .millimeters)
        #expect(MeasurementUnit.localeDefault(for: Locale(identifier: "en_GB")) == .millimeters)
    }
}
