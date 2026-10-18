import Foundation
import Testing
@testable import MeasurementCore

struct PremiumTests {
    @Test func sharingRequiresExplicitConsent() {
        #expect(throws: InsoleRequest.RequestError.consentRequired) {
            try InsoleRequest(assessment: .synthetic, side: .left, material: "Lunar lattice", environment: "Earth", gravity: 1, photos: [:], consent: false)
        }
    }
    @Test(arguments: [0.0, 0.165, 0.38, 1.0]) func gravityNeverChangesMeasurements(_ gravity: Double) throws {
        let assessment = Assessment.synthetic
        let request = try InsoleRequest(assessment: assessment, side: .right, material: "Orbital foam", environment: "Moon", gravity: gravity, photos: ["left.top": Data([1]), "right.top": Data([2])], consent: true)
        #expect(request.measurementsMM == assessment.right)
        #expect(request.photos.keys.sorted() == ["right.top"])
        #expect(request.synthetic)
        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["pain"] == nil)
        #expect(json["diagnosis"] == nil)
        #expect(json["quiz"] == nil)
        let decoded = try JSONDecoder().decode(InsoleRequest.self, from: data)
        #expect(decoded.measurementsMM == request.measurementsMM)
        #expect(decoded.disclosure == request.disclosure)
        #expect(decoded.photos == request.photos)
    }
    @Test(arguments: [Double.nan, Double.infinity, -1.0, 1.01]) func rejectsInvalidGravity(_ gravity: Double) {
        #expect(throws: InsoleRequest.RequestError.invalidMeasurements) {
            try InsoleRequest(assessment: .synthetic, side: .left, material: "Lunar", environment: "Moon", gravity: gravity, photos: [:], consent: true)
        }
    }
    @Test func scanRoundTripAndWrongFootRejection() throws {
        let scan = InsoleScan(filename: "my-foot.stl", side: .left, bytes: Data("solid example\nendsolid".utf8))
        let request = try InsoleRequest(assessment: .synthetic, side: .left, material: "Lunar", environment: "Earth", gravity: 1, photos: [:], consent: true, scan: scan)
        let decoded = try JSONDecoder().decode(InsoleRequest.self, from: JSONEncoder().encode(request))
        #expect(decoded.scan == scan)
        #expect(throws: InsoleRequest.RequestError.invalidAttachment) {
            try InsoleRequest(assessment: .synthetic, side: .right, material: "Lunar", environment: "Earth", gravity: 1, photos: [:], consent: true, scan: scan)
        }
    }
    @Test(arguments: ["not-a-scan.json", "../foot.stl", "empty.stl"]) func rejectsInvalidScanAttachments(_ name: String) {
        let scan = InsoleScan(filename: name, side: .left, bytes: name == "empty.stl" ? Data() : Data([1]))
        #expect(!scan.isValidAttachment)
    }
    @Test func shortFootPhasesAndCompletionDoNotOverrun() {
        var session = ShortFootSession()
        #expect(session.phase == .hold)
        #expect(session.repetition == 1)
        for _ in 0..<5 { session.tick() }
        #expect(session.phase == .relax)
        #expect(session.secondsRemaining == 5)
        for _ in 0..<5 { session.tick() }
        #expect(session.phase == .hold)
        #expect(session.repetition == 2)
        for _ in 0..<50 { session.tick() }
        #expect(session.elapsed == 50)
        #expect(session.phase == .complete)
        #expect(session.repetition == 5)
    }
}
