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
    /// Smooth per-vertex normals for `mesh`.
    private let normals: [SIMD3<Float>]

    var size: SIMD3<Float> { mesh.size }

    enum Failure: LocalizedError {
        case missingResource
        case unreadable

        var errorDescription: String? {
            switch self {
            case .missingResource: "The sample scan is missing from the app."
            case .unreadable: "The sample scan couldn't be read."
            }
        }
    }

    /// Parses the binary STL: 80-byte header, a triangle count, then 50 bytes per triangle.
    static func load() throws -> SampleScan {
        guard let url = Bundle.main.url(forResource: "scan-ishaan", withExtension: "stl") else {
            throw Failure.missingResource
        }
        let data = try Data(contentsOf: url)
        guard data.count >= 84 else { throw Failure.unreadable }
        let triangleCount = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self) })
        guard triangleCount > 0, data.count >= 84 + triangleCount * 50 else { throw Failure.unreadable }

        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var indexOfVertex: [SIMD3<Float>: UInt32] = [:]
        indices.reserveCapacity(triangleCount * 3)

        data.withUnsafeBytes { bytes in
            for t in 0..<triangleCount {
                // Skip the 12-byte face normal; smooth normals are rebuilt below.
                let base = 84 + t * 50 + 12
                for corner in 0..<3 {
                    let offset = base + corner * 12
                    // STL is millimeters with Z up; the viewer wants meters with Y up.
                    let stl = SIMD3(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self),
                                    bytes.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                                    bytes.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
                    if let existing = indexOfVertex[stl] {
                        indices.append(existing)
                    } else {
                        let index = UInt32(vertices.count)
                        indexOfVertex[stl] = index
                        vertices.append(SIMD3(stl.x, stl.z, -stl.y) * 0.001)
                        indices.append(index)
                    }
                }
            }
        }

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

        return SampleScan(stlURL: url, mesh: FootMesh(vertices: vertices, indices: indices), normals: normals)
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
