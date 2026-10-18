import CoreGraphics
import RealityKit
import UIKit

/// The foot as the viewer shows it: a warm clay surface that fades out toward the ankle, so the scan's
/// crop line never shows as a hard, hollow edge. Used for real scans and the bundled sample alike.
enum FootModel {
    /// Fraction of the foot's height where the fade begins, and where it is fully clear.
    static let fadeStart: Float = 0.45
    static let fadeEnd: Float = 0.92

    enum Failure: Error { case fadeTexture }

    /// `floorNormal` is the analyzer's sole support plane; the model is turned so it points up, which
    /// stands a tilted scan level and keeps the fade parallel to the floor. Nil shows the scan as captured.
    static func entity(for scan: FootMesh, floorNormal: SIMD3<Float>?) throws -> ModelEntity {
        let rotation = simd_quatf(from: floorNormal ?? SIMD3(0, 1, 0), to: SIMD3(0, 1, 0))
        let mesh = FootMesh(vertices: scan.vertices.map { rotation.act($0) }, indices: scan.indices)
        let (bottom, top) = (mesh.bounds.min.y, mesh.bounds.max.y)
        let height = max(top - bottom, .ulpOfOne)

        let heights = mesh.vertices.map { ($0.y - bottom) / height }
        // Triangles entirely above the fade are invisible, but their crop edge still leaves a dark hairline.
        var kept: [UInt32] = []
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let corners = mesh.indices[t..<t + 3]
            if corners.contains(where: { heights[Int($0)] < fadeEnd }) { kept.append(contentsOf: corners) }
        }

        var descriptor = MeshDescriptor(name: "foot")
        descriptor.positions = MeshBuffer(mesh.vertices)
        descriptor.normals = MeshBuffer(smoothNormals(mesh))
        // Only v matters: it is the vertex's height, which looks up the fade.
        descriptor.textureCoordinates = MeshBuffer(heights.map { SIMD2<Float>(0.5, $0) })
        descriptor.primitives = .triangles(kept)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.91, green: 0.89, blue: 0.86, alpha: 1))
        material.roughness = .init(floatLiteral: 0.62)
        material.metallic = .init(floatLiteral: 0)
        // Transparent PBR keeps its reflections like glass, which would leave a grey ghost where the fade is clear.
        material.specular = .init(floatLiteral: 0)
        material.faceCulling = .back
        material.blending = .transparent(opacity: .init(scale: 1, texture: .init(try fadeTexture())))
        return ModelEntity(mesh: try MeshResource.generate(from: [descriptor]), materials: [material])
    }

    /// Area-weighted vertex normals, so the clay shades smoothly instead of faceted.
    private static func smoothNormals(_ mesh: FootMesh) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: mesh.vertices.count)
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let (a, b, c) = (Int(mesh.indices[t]), Int(mesh.indices[t + 1]), Int(mesh.indices[t + 2]))
            // Unnormalized, so larger faces weigh more.
            let face = simd_cross(mesh.vertices[b] - mesh.vertices[a], mesh.vertices[c] - mesh.vertices[a])
            normals[a] += face
            normals[b] += face
            normals[c] += face
        }
        return normals.map { simd_length($0) > 0 ? simd_normalize($0) : SIMD3(0, 1, 0) }
    }

    /// A vertical opacity ramp: opaque below `fadeStart`, clear above `fadeEnd`, smoothstepped between.
    /// Texture v runs bottom to top, so the last image row is the floor.
    private static func fadeTexture() throws -> TextureResource {
        let rows = 256
        var pixels = [UInt8](repeating: 0, count: rows)
        for row in 0..<rows {
            let v = 1 - Float(row) / Float(rows - 1)
            let x = min(max((v - fadeStart) / (fadeEnd - fadeStart), 0), 1)
            pixels[row] = UInt8((1 - x * x * (3 - 2 * x)) * 255)
        }
        let image = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: 1, height: rows, bitsPerComponent: 8, bytesPerRow: 1,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
        guard let image else { throw Failure.fadeTexture }
        return try TextureResource(image: image, options: .init(semantic: .raw))
    }
}
