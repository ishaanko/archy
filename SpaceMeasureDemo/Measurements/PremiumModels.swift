import Foundation

struct InsoleScan: Codable, Equatable {
    let filename: String
    let side: FootSide
    let bytes: Data
    var isValidAttachment: Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["stl", "obj", "ply", "glb", "usdz"].contains(ext) && !filename.contains("/") && !bytes.isEmpty && bytes.count <= 20 * 1_024 * 1_024
    }
}

/// A request for human review, never a prescription, charge, or fulfilled order.
struct InsoleRequest: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let kind: String
    let side: FootSide
    let assessmentID: UUID
    let assessmentDate: Date
    let synthetic: Bool
    let measurementsMM: FootMeasurements
    let material: String
    let environment: String
    let relativeGravity: Double
    let designIntent: String
    let photos: [String: Data]
    let scan: InsoleScan?
    let exportConsentAt: Date
    static let disclosureText = "Quote request only. No payment or order placed. Measurements are unchanged; space design intent is illustrative, not a validated fitting model. Recipient is selected by the user when sharing. Photos and attached scans require calibration and manufacturing review."
    let disclosure: String
    enum CodingKeys: String, CodingKey {
        case id, createdAt, kind, side, assessmentID, assessmentDate, synthetic, measurementsMM, material, environment, relativeGravity, designIntent, photos, scan, exportConsentAt, disclosure
    }
    init(assessment: Assessment, side: FootSide, material: String, environment: String, gravity: Double, photos: [String: Data], consent: Bool, scan: InsoleScan? = nil) throws {
        guard consent else { throw RequestError.consentRequired }
        let foot = assessment.measurements(for: side)
        guard foot.validationErrors.isEmpty, gravity.isFinite, (0...1).contains(gravity) else { throw RequestError.invalidMeasurements }
        if let scan { guard scan.isValidAttachment, scan.side == side else { throw RequestError.invalidAttachment } }
        self.scan = scan
        disclosure = Self.disclosureText
        id = UUID(); createdAt = .now; exportConsentAt = .now
        kind = environment == "Earth" ? "AstroFit custom insole" : "Space Insole concept"
        self.side = side; assessmentID = assessment.id; assessmentDate = assessment.date
        synthetic = assessment.isSynthetic; measurementsMM = foot; self.material = material
        self.environment = environment; relativeGravity = gravity
        designIntent = environment == "Earth" ? "Everyday fit review: assess cushioning, heel retention and arch support with a qualified fitter." : "Reduced-load concept: explore heel retention and adjustable cushioning for \(environment). Human review required; no anatomical change or support height is predicted."
        // Only the selected foot's reviewed photos may enter this export.
        self.photos = photos.filter { $0.key.hasPrefix(side.rawValue + ".") }
    }
    enum RequestError: Error { case consentRequired, invalidMeasurements, invalidAttachment }
}
