import Foundation
import simd

/// The bundled example scan (`scan-ishaan.stl`), read straight from the STL into the mesh the viewer shows.
/// (ModelIO can't export USDZ on iOS, so there is no conversion step.) Used when the device has no LiDAR,
/// and as a preview on devices that do.
struct SampleScan {
    /// The original millimeter, Z-up STL, offered by Share.
    let stlURL: URL
    /// Welded triangles in meters, Y up, like a reconstructed scan.
    let mesh: FootMesh
    /// The arch read from the sample's sole, like a real scan; nil if the footprint couldn't be measured.
    let arch: FootArchAnalysis?

    var size: SIMD3<Float> { mesh.size }

    enum Failure: LocalizedError {
        case missingResource

        var errorDescription: String? {
            switch self {
            case .missingResource: "The sample scan is missing from the app."
            }
        }
    }

    /// Reads the bundled STL and measures the arch.
    static func load() throws -> SampleScan {
        guard let url = Bundle.main.url(forResource: "scan-ishaan", withExtension: "stl") else {
            throw Failure.missingResource
        }
        let mesh = try FootMesh.loadSTL(from: url)
        return SampleScan(stlURL: url, mesh: mesh, arch: try? FootArchAnalyzer.analyze(mesh))
    }
}
