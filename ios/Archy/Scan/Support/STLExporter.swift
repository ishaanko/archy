//
//  STLExporter.swift
//  archy
//

import Foundation
import simd

/// Writes a `FootMesh` as a binary STL in millimeters with Z up, the convention slicers and CAD tools expect.
/// (STL has no unit field; millimeters is the de facto standard.)
enum STLExporter {
    static func write(_ mesh: FootMesh, to url: URL) throws {
        var data = Data(capacity: 84 + mesh.triangleCount * 50)

        // 80-byte header. It must not start with "solid", or readers treat the file as ASCII STL.
        var header = Data("archy binary STL, millimeters, Z up".utf8)
        header.count = 80
        data.append(header)
        data.appendLittleEndian(UInt32(mesh.triangleCount))

        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = toSTLSpace(mesh.vertices[Int(mesh.indices[t])])
            let b = toSTLSpace(mesh.vertices[Int(mesh.indices[t + 1])])
            let c = toSTLSpace(mesh.vertices[Int(mesh.indices[t + 2])])
            let cross = simd_cross(b - a, c - a)
            let length = simd_length(cross)
            let normal = length > 0 ? cross / length : .zero

            for v in [normal, a, b, c] {
                data.appendLittleEndian(v.x.bitPattern)
                data.appendLittleEndian(v.y.bitPattern)
                data.appendLittleEndian(v.z.bitPattern)
            }
            data.appendLittleEndian(UInt16(0))  // attribute byte count
        }

        try data.write(to: url, options: .atomic)
    }

    /// Meters, Y up → millimeters, Z up (a +90° turn about X, which keeps triangle winding).
    private static func toSTLSpace(_ p: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(p.x, -p.z, p.y) * 1000
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
