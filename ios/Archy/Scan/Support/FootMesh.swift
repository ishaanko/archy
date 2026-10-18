//
//  FootMesh.swift
//  archy
//

import Foundation
import ModelIO
import simd

/// The reconstructed foot as plain triangles in world space, in the USDZ's units (meters, Y up).
/// The STL export, the arch analysis and the viewer all read it.
nonisolated struct FootMesh {
    var vertices: [SIMD3<Float>]
    /// Three vertex indices per triangle.
    var indices: [UInt32]

    var triangleCount: Int { indices.count / 3 }

    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        vertices.reduce((SIMD3<Float>(repeating: .infinity), SIMD3<Float>(repeating: -.infinity))) {
            (simd_min($0.0, $1), simd_max($0.1, $1))
        }
    }

    /// Width × height × depth of the bounding box, in meters.
    var size: SIMD3<Float> { bounds.max - bounds.min }

    enum LoadError: LocalizedError {
        case noTriangles(URL)
        case unusableGeometry(URL)

        var errorDescription: String? {
            switch self {
            case .noTriangles(let url): "\(url.lastPathComponent) has no triangle mesh."
            case .unusableGeometry(let url): "\(url.lastPathComponent) has damaged geometry."
            }
        }
    }

    /// Every point is a real number and the whole model fits in 2 m. Object Capture output always
    /// passes; a damaged file could otherwise crash or exhaust memory in the arch analysis.
    var isUsable: Bool {
        guard vertices.count >= 3,
              vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return false }
        let extent = bounds.max - bounds.min
        return max(extent.x, extent.y, extent.z) < 2
    }

    /// Loads every triangle mesh in the file, with each mesh's transform applied.
    static func load(from url: URL) throws -> FootMesh {
        let asset = MDLAsset(url: url)
        let meshes = asset.childObjects(of: MDLMesh.self).compactMap { $0 as? MDLMesh }
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for mesh in meshes {
            guard let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition,
                                                           as: .float3) else { continue }
            let transform = MDLTransform.globalTransform(with: mesh, atTime: 0)
            let firstIndex = UInt32(vertices.count)

            for i in 0..<mesh.vertexCount {
                let p = positions.dataStart + i * positions.stride
                let local = SIMD4<Float>(p.loadUnaligned(as: Float.self),
                                         p.loadUnaligned(fromByteOffset: 4, as: Float.self),
                                         p.loadUnaligned(fromByteOffset: 8, as: Float.self),
                                         1)
                let world = transform * local
                vertices.append(SIMD3(world.x, world.y, world.z))
            }

            for case let submesh as MDLSubmesh in mesh.submeshes ?? [] where submesh.geometryType == .triangles {
                let bytes = submesh.indexBuffer.map().bytes
                for i in 0..<submesh.indexCount {
                    let index: UInt32 = switch submesh.indexType {
                    case .uInt8: UInt32(bytes.loadUnaligned(fromByteOffset: i, as: UInt8.self))
                    case .uInt16: UInt32(bytes.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
                    default: bytes.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                    }
                    indices.append(firstIndex + index)
                }
            }
        }

        guard !indices.isEmpty else { throw LoadError.noTriangles(url) }
        let mesh = FootMesh(vertices: vertices, indices: indices)
        guard mesh.isUsable else { throw LoadError.unusableGeometry(url) }
        return mesh
    }

    /// Reads a binary STL (80-byte header, triangle count, 50 bytes per triangle) in millimeters, Z up,
    /// like `STLExporter` writes. Returns welded triangles in meters, Y up, like a reconstructed scan.
    static func loadSTL(from url: URL) throws -> FootMesh {
        let data = try Data(contentsOf: url)
        guard data.count >= 84 else { throw LoadError.noTriangles(url) }
        let triangleCount = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self) })
        guard triangleCount > 0, data.count >= 84 + triangleCount * 50 else { throw LoadError.noTriangles(url) }

        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var indexOfVertex: [SIMD3<Float>: UInt32] = [:]
        indices.reserveCapacity(triangleCount * 3)
        data.withUnsafeBytes { bytes in
            for t in 0..<triangleCount {
                // Skip the 12-byte face normal.
                let base = 84 + t * 50 + 12
                for corner in 0..<3 {
                    let offset = base + corner * 12
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
        let mesh = FootMesh(vertices: vertices, indices: indices)
        guard mesh.isUsable else { throw LoadError.unusableGeometry(url) }
        return mesh
    }
}
