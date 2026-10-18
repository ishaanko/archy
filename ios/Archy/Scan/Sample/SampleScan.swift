import Foundation
import RealityKit
import simd
import UIKit

/// The bundled example scan (`scan-ishaan.stl`), read straight from the STL into a mesh the viewer can show.
/// (ModelIO can't export USDZ on iOS, so there is no conversion step.) Used when the device has no LiDAR,
/// and as a preview on devices that do.
struct SampleScan {
    /// The original millimeter, Z-up STL, offered by Share.
    let stlURL: URL
    /// Welded triangles in meters, Y up, like a reconstructed scan.
    let mesh: FootMesh
    /// The arch read from the sample's sole, like a real scan; nil if the footprint couldn't be measured.
    let arch: FootArchAnalysis?
    /// Smooth per-vertex normals for `mesh`.
    private let normals: [SIMD3<Float>]

    var size: SIMD3<Float> { mesh.size }

    enum Failure: LocalizedError {
        case missingResource

        var errorDescription: String? {
            switch self {
            case .missingResource: "The sample scan is missing from the app."
            }
        }
    }

    /// Reads the bundled STL, rebuilds smooth normals and measures the arch.
    static func load() throws -> SampleScan {
        guard let url = Bundle.main.url(forResource: "scan-ishaan", withExtension: "stl") else {
            throw Failure.missingResource
        }
        let mesh = try FootMesh.loadSTL(from: url)
        let (vertices, indices) = (mesh.vertices, mesh.indices)

        var normals = [SIMD3<Float>](repeating: .zero, count: vertices.count)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let (a, b, c) = (Int(indices[t]), Int(indices[t + 1]), Int(indices[t + 2]))
            // Unnormalized, so larger faces weigh more.
            let faceNormal = simd_cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
            normals[a] += faceNormal
            normals[b] += faceNormal
            normals[c] += faceNormal
        }
        normals = normals.map { simd_length($0) > 0 ? simd_normalize($0) : SIMD3(0, 1, 0) }

        return SampleScan(stlURL: url, mesh: mesh, arch: try? FootArchAnalyzer.analyze(mesh), normals: normals)
    }

    /// The foot as a RealityKit entity, in meters.
    func makeEntity() throws -> ModelEntity {
        var descriptor = MeshDescriptor(name: "sample foot")
        descriptor.positions = MeshBuffer(mesh.vertices)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(mesh.indices)
        let resource = try MeshResource.generate(from: [descriptor])
        let material = SimpleMaterial(color: UIColor(white: 0.86, alpha: 1), roughness: 0.55, isMetallic: false)
        return ModelEntity(mesh: resource, materials: [material])
    }
}
