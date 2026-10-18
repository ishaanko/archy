import Foundation
import Testing
@testable import ScanCore

/// The arch classifier on real iPhone scans. The web demo's scans are read from `sim/public/models`;
/// Pranav's flat left foot is a fixture because its sole came out tilted 6.6°, which leveling fixes.
struct ArchAnalyzerTests {
    static let models = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../sim/public/models").standardized

    static let scans: [(url: URL, type: ArchType)] = [
        (Bundle.module.url(forResource: "pranav-flat-left", withExtension: "stl", subdirectory: "Fixtures")!, .flat),
        (models.appending(path: "scan-ishaan.stl"), .flat),
        (models.appending(path: "scan-prakhar.stl"), .flat),
        (models.appending(path: "scan-pranav.stl"), .normal),
    ]

    @Test(arguments: scans)
    func classifiesRealScans(scan: (url: URL, type: ArchType)) throws {
        let arch = try FootArchAnalyzer.analyze(FootMesh.loadSTL(from: scan.url))
        #expect(arch.archType == scan.type, "\(scan.url.lastPathComponent): \(arch.archHeightMM) mm lift")
        #expect((20...30).contains(arch.footLengthCM), "\(scan.url.lastPathComponent): \(arch.footLengthCM) cm long")
    }

    @Test func flagsTheTiltedScanAsUneven() throws {
        let tilted = try FootArchAnalyzer.analyze(FootMesh.loadSTL(from: Self.scans[0].url))
        #expect(tilted.isSoleUneven, "\(tilted.soleTiltDegrees)° sole tilt")
        #expect(tilted.floorNormal.y < cos(Float(FootArchAnalyzer.unevenSoleTilt) * .pi / 180))
        for scan in Self.scans.dropFirst() {
            let arch = try FootArchAnalyzer.analyze(FootMesh.loadSTL(from: scan.url))
            #expect(!arch.isSoleUneven, "\(scan.url.lastPathComponent): \(arch.soleTiltDegrees)° sole tilt")
        }
    }
}
