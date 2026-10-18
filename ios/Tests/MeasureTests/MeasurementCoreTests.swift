import Foundation
import XCTest
@testable import MeasurementCore

final class MeasurementCoreTests: XCTestCase {
    private var values: FootMeasurements { Assessment.synthetic.left }
    func testEquations() throws {
        XCTAssertEqual(try MeasurementMath.archHeightIndex(values), 62.0 / 190, accuracy: 0.000001)
        XCTAssertEqual(try MeasurementMath.navicularDrop(values), 7)
        XCTAssertEqual(try MeasurementMath.widthLengthRatio(values), 98.0 / 260, accuracy: 0.000001)
    }
    func testExplorerArchCalculationRejectsInvalidDimensions() throws {
        XCTAssertEqual(try MeasurementMath.archHeightIndex(dorsumHeight: 60, truncatedLength: 180), 1.0 / 3, accuracy: 0.000001)
        for invalid in [Double.nan, Double.infinity, 0, -1] {
            XCTAssertThrowsError(try MeasurementMath.archHeightIndex(dorsumHeight: invalid, truncatedLength: 180))
            XCTAssertThrowsError(try MeasurementMath.archHeightIndex(dorsumHeight: 60, truncatedLength: invalid))
        }
        XCTAssertThrowsError(try MeasurementMath.archHeightIndex(dorsumHeight: 60, truncatedLength: .leastNonzeroMagnitude))
    }
    func testUnitConversion() {
        XCTAssertEqual(MeasurementUnit.centimeters.toMillimeters(26), 260)
        XCTAssertEqual(MeasurementUnit.millimeters.toMillimeters(260), 260)
    }
    func testEveryCalculationRejectsInvalidValues() {
        for field in MeasurementField.allCases {
            for invalid in [Double.nan, Double.infinity, -Double.infinity, 0, -1] {
                var candidate = values
                candidate[field] = invalid
                XCTAssertFalse(candidate.validationErrors.isEmpty)
                XCTAssertThrowsError(try MeasurementMath.archHeightIndex(candidate))
                XCTAssertThrowsError(try MeasurementMath.navicularDrop(candidate))
                XCTAssertThrowsError(try MeasurementMath.widthLengthRatio(candidate))
            }
        }
    }
    func testImpossibleGeometry() {
        for field in MeasurementField.allCases where field != .fullLength {
            for invalid in [values.fullLength, values.fullLength + 1] {
                var candidate = values
                candidate[field] = invalid
                XCTAssertThrowsError(try MeasurementMath.archHeightIndex(candidate))
            }
        }
    }
    func testNegativeNavicularDropIsPreserved() throws {
        var candidate = values
        candidate.standingNavicular = candidate.seatedNavicular + 3
        XCTAssertTrue(candidate.validationErrors.isEmpty)
        XCTAssertEqual(try MeasurementMath.navicularDrop(candidate), -3)
    }
    func testFeetRemainIndependentAndCodable() throws {
        var assessment = Assessment.synthetic
        let originalRight = assessment.right
        assessment.left.width = 101
        XCTAssertEqual(assessment.measurements(for: .right), originalRight)
        XCTAssertEqual(assessment.measurements(for: .left).width, 101)
        XCTAssertEqual(try JSONDecoder().decode(Assessment.self, from: JSONEncoder().encode(assessment)), assessment)
    }
}
