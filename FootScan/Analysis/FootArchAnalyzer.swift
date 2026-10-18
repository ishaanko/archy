//
//  FootArchAnalyzer.swift
//  FootScan
//

import Foundation
import simd

/// Flat vs. normal arch from the reconstructed mesh of a standing foot.
///
/// Object Capture can't see the sole while the foot stands on the floor, so it closes the bottom with
/// large flat triangles at floor height, but it does reconstruct the gap under an arch. Rasterizing the
/// mesh's lowest surface onto a grid gives the sole's underside heights and a virtual footprint.
///
/// The classifier is the **arch height**: how far the inner side of the sole lifts at mid-foot, against
/// a heel-to-ball line. The **Arch Index** (Cavanagh & Rodgers 1987: middle third of the toe-less
/// footprint over the whole; ≥ 0.26 flat) is reported too, but a foot rolled onto its outer edge
/// pushes it toward "flat" even with a clear arch, so it doesn't decide.
enum FootArchAnalyzer {
    /// Grid resolution of the footprint.
    static let cellSize: Float = 0.003
    /// Surface this close to the floor counts as contact. 3 mm is within the mesh's noise.
    static let contactHeight: Float = 0.005
    /// The front of the footprint treated as toes and left out, as in the published method.
    static let toeFraction: Float = 0.20
    /// Arch Index at or above this is flat (published cutoff; reported, not used to classify).
    static let flatArchIndex = 0.26
    /// Inner arch lower than this is flat. Set halfway between the first test feet: a known flat foot
    /// measured 5.9 mm and a normal one 15.9 mm. Refine as more scans come in.
    static let flatArchHeight: Float = 0.010

    enum Failure: LocalizedError {
        case noFootprint

        var errorDescription: String? {
            switch self {
            case .noFootprint: "The scan has no footprint on the floor, so the arch can't be measured."
            }
        }
    }

    static func analyze(_ mesh: FootMesh) throws -> FootArchAnalysis {
        let floorY = mesh.bounds.min.y
        let axes = footAxes(mesh, floorY: floorY)
        let grid = HeightGrid(mesh: mesh, axes: axes, floorY: floorY, cellSize: cellSize)
        let contact = largestRegion(of: grid.lowest.map { $0 < contactHeight }, columns: grid.columns, rows: grid.rows)

        // Footprint extent along the foot: columns with a real strip of contact, not single stray cells.
        let minimumCells = 3
        let contactColumns = (0..<grid.columns).filter { column in
            (0..<grid.rows).count(where: { contact[$0 * grid.columns + column] }) >= minimumCells
        }
        guard let heel = contactColumns.first, let toeTip = contactColumns.last, toeTip - heel >= 30 else {
            throw Failure.noFootprint
        }
        let lengthColumns = toeTip - heel + 1
        // Thirds of the toe-less footprint, in columns from the heel. They rarely fall on whole columns, so
        // each column's contact is split between thirds by overlap; whole-column thirds would bias the index.
        let third = Float(lengthColumns) * (1 - toeFraction) / 3
        var thirds: [Float] = [0, 0, 0]
        var maxWidthCells = 0
        for column in heel...toeTip {
            let cells = (0..<grid.rows).count(where: { contact[$0 * grid.columns + column] })
            // Width from the sole's outline, not its contact: a rolled foot touches with a narrow strip.
            let outlineCells = (0..<grid.rows).count(where: { grid.lowest[$0 * grid.columns + column] < outlineHeight })
            maxWidthCells = max(maxWidthCells, outlineCells)
            let start = Float(column - heel), end = start + 1
            for k in 0..<3 {
                let overlap = min(end, Float(k + 1) * third) - max(start, Float(k) * third)
                if overlap > 0 { thirds[k] += Float(cells) * overlap }
            }
        }
        let archIndex = Double(thirds[1] / max(thirds.reduce(0, +), 1))
        // Rounded positions, for drawing only.
        let toesStart = heel + Int((3 * third).rounded())
        let thirdBoundaries = [heel + Int(third.rounded()), heel + Int((2 * third).rounded())]

        let arch = measureArch(grid: grid, heel: heel, toeTip: toeTip)
        let archType: ArchType = arch.height < flatArchHeight ? .flat : .normal
        let footprint = Footprint(cellSize: cellSize, columns: grid.columns, rows: grid.rows, contact: contact,
                                  heights: grid.lowest, heelColumn: heel, toesStartColumn: toesStart,
                                  toeTipColumn: toeTip, thirdBoundaries: thirdBoundaries,
                                  innerSideAtHighRows: arch.innerSideAtHighRows,
                                  archPeakColumn: archType == .normal ? arch.peakColumn : nil)
        return FootArchAnalysis(archIndex: archIndex,
                                archHeightMM: Double(arch.height * 1000),
                                archType: archType,
                                footLengthCM: Double(Float(lengthColumns) * cellSize * 100),
                                footWidthCM: Double(Float(maxWidthCells) * cellSize * 100),
                                footprint: footprint)
    }

    /// Underside this high or lower counts as part of the sole's outline (arch gaps are 1–3 cm).
    static let outlineHeight: Float = 0.04

    /// How far the inner arch lifts off the floor. Each side's underside profile (heel → toe, from the
    /// outer quarter of the sole's width) is measured against a straight line from its heel to its ball,
    /// so a foot rolled onto its outer edge or a sloped floor doesn't count as arch. The side with the
    /// bigger rise at mid-foot is the inner side. Returns that rise in meters, which side it is, and
    /// the column where the arch is highest.
    private static func measureArch(grid: HeightGrid, heel: Int, toeTip: Int)
        -> (height: Float, innerSideAtHighRows: Bool, peakColumn: Int?) {
        var profiles: [[Float]] = [[], []]
        for column in heel...toeTip {
            let rows = (0..<grid.rows).filter { grid.lowest[$0 * grid.columns + column] < outlineHeight }
            guard let first = rows.first, let last = rows.last, last - first >= 4 else {
                profiles[0].append(.nan)
                profiles[1].append(.nan)
                continue
            }
            let band = max(1, (last - first + 1) / 4)
            let sideRows = [Array(first..<(first + band)), Array((last - band + 1)...last)]
            for side in 0..<2 {
                let heights = sideRows[side].map { grid.lowest[$0 * grid.columns + column] }.filter { $0 < outlineHeight }
                profiles[side].append(median(heights))
            }
        }

        let length = Float(toeTip - heel + 1)
        var best: (height: Float, innerSideAtHighRows: Bool, peakColumn: Int?) = (0, true, nil)
        for (side, raw) in profiles.enumerated() {
            // Smooth with a 5-column (1.5 cm) running median so a single noisy column can't make an arch.
            let profile = raw.indices.map { i in median(raw[max(0, i - 2)...min(raw.count - 1, i + 2)].filter(\.isFinite)) }
            func level(_ from: Float, _ to: Float) -> Float {
                median(profile[Int(from * length)..<Int(to * length)].filter(\.isFinite))
            }
            let heelLevel = level(0.05, 0.20), ballLevel = level(0.65, 0.80)
            guard heelLevel.isFinite, ballLevel.isFinite else { continue }
            for i in Int(0.25 * length)..<Int(0.60 * length) where profile[i].isFinite {
                let f = Float(i) / length
                let baseline = heelLevel + (ballLevel - heelLevel) * (f - 0.125) / (0.725 - 0.125)
                let rise = profile[i] - baseline
                if rise > best.height {
                    best = (rise, side == 1, heel + i)
                }
            }
        }
        return best
    }

    /// Median of the values, or NaN if there are none.
    private static func median<S: Sequence<Float>>(_ values: S) -> Float {
        let sorted = values.sorted()
        return sorted.isEmpty ? .nan : sorted[sorted.count / 2]
    }

    // MARK: - Steps

    /// Horizontal directions along (heel → toe) and across the foot, plus the center they're measured from.
    struct Axes {
        let center: SIMD2<Float>
        let along: SIMD2<Float>
        var across: SIMD2<Float> { SIMD2(-along.y, along.x) }

        /// (along, across) position of a point, in meters.
        func project(_ p: SIMD3<Float>) -> SIMD2<Float> {
            let d = SIMD2(p.x, p.z) - center
            return SIMD2(simd_dot(d, along), simd_dot(d, across))
        }
    }

    /// The long axis is the main direction of the foot's outline near the floor (PCA). The heel end is the
    /// one under the shin, the tallest part of the scan. Object Capture's own axes vary from scan to scan.
    static func footAxes(_ mesh: FootMesh, floorY: Float) -> Axes {
        var low = mesh.vertices.filter { $0.y - floorY < 0.03 }
        if low.count < 100 { low = mesh.vertices }

        var center = SIMD2<Float>.zero
        for p in low { center += SIMD2(p.x, p.z) }
        center /= Float(low.count)
        var xx: Float = 0, xz: Float = 0, zz: Float = 0
        for p in low {
            let d = SIMD2(p.x, p.z) - center
            xx += d.x * d.x
            xz += d.x * d.y
            zz += d.y * d.y
        }
        let angle = 0.5 * atan2(2 * xz, xx - zz)
        var along = SIMD2<Float>(cos(angle), sin(angle))

        let shin = mesh.vertices.max { $0.y < $1.y }!
        if simd_dot(SIMD2(shin.x, shin.z) - center, along) > 0 {
            along = -along
        }
        return Axes(center: center, along: along)
    }

    /// Keeps only the biggest connected patch of contact (the foot), dropping specks such as floor debris.
    static func largestRegion(of cells: [Bool], columns: Int, rows: Int) -> [Bool] {
        var label = [Int](repeating: -1, count: cells.count)
        var best: [Int] = []
        for start in cells.indices where cells[start] && label[start] < 0 {
            var region = [start]
            label[start] = start
            var next = 0
            while next < region.count {
                let i = region[next]
                next += 1
                let column = i % columns, row = i / columns
                for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let c = column + dc, r = row + dr
                    guard c >= 0, c < columns, r >= 0, r < rows else { continue }
                    let j = r * columns + c
                    if cells[j] && label[j] < 0 {
                        label[j] = start
                        region.append(j)
                    }
                }
            }
            if region.count > best.count { best = region }
        }
        var result = [Bool](repeating: false, count: cells.count)
        for i in best { result[i] = true }
        return result
    }
}

enum ArchType: String {
    case flat
    /// Includes high arches; the app only needs to know whether the foot is flat.
    case normal
}

/// The result of `FootArchAnalyzer.analyze(_:)`.
struct FootArchAnalysis {
    let archIndex: Double
    /// How far the inner arch lifts off the floor, against a heel-to-ball line.
    let archHeightMM: Double
    let archType: ArchType
    /// Heel to toe tip, from the footprint (the bounding box can include the lower leg).
    let footLengthCM: Double
    /// Widest part of the footprint.
    let footWidthCM: Double
    let footprint: Footprint
}

/// The sole as seen from below, for drawing: columns run heel → toe, rows across the foot.
/// Arrays are row-major: `contact[row * columns + column]`.
struct Footprint {
    let cellSize: Float
    let columns: Int
    let rows: Int
    /// Touching the floor (the foot's main contact patch only).
    let contact: [Bool]
    /// Height of the sole's underside above the floor, in meters; infinity where there's no surface.
    /// The sole's outline is where this is below `FootArchAnalyzer.outlineHeight`.
    let heights: [Float]
    let heelColumn: Int
    let toesStartColumn: Int
    let toeTipColumn: Int
    /// Where the middle third (for the Arch Index) starts and ends.
    let thirdBoundaries: [Int]
    /// Whether the inner (big-toe, arch) side is at high row numbers.
    let innerSideAtHighRows: Bool
    /// Where along the foot the arch is highest, for labeling it; nil when the foot is classified flat.
    let archPeakColumn: Int?
}

/// The lowest surface height above the floor in each cell of a grid laid along the foot.
private struct HeightGrid {
    let columns: Int
    let rows: Int
    /// Meters above the floor; infinity where there's no surface.
    private(set) var lowest: [Float]

    init(mesh: FootMesh, axes: FootArchAnalyzer.Axes, floorY: Float, cellSize: Float) {
        let points = mesh.vertices.map { (position: axes.project($0), height: $0.y - floorY) }
        let minAlong = points.map(\.position.x).min() ?? 0
        let minAcross = points.map(\.position.y).min() ?? 0
        let maxAlong = points.map(\.position.x).max() ?? 0
        let maxAcross = points.map(\.position.y).max() ?? 0
        columns = Int(((maxAlong - minAlong) / cellSize).rounded(.up)) + 1
        rows = Int(((maxAcross - minAcross) / cellSize).rounded(.up)) + 1
        lowest = [Float](repeating: .infinity, count: columns * rows)

        // Grid coordinates (in cells) of a projected point.
        func cellPoint(_ p: SIMD2<Float>) -> SIMD2<Float> {
            SIMD2((p.x - minAlong) / cellSize, (p.y - minAcross) / cellSize)
        }
        // Fill each triangle so the big flat ones closing the sole count everywhere they cover. Only cell
        // centers inside a triangle count; recording its corners too would add a false rim of contact.
        for t in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = points[Int(mesh.indices[t])], b = points[Int(mesh.indices[t + 1])], c = points[Int(mesh.indices[t + 2])]
            let pa = cellPoint(a.position), pb = cellPoint(b.position), pc = cellPoint(c.position)
            let area = (pb.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (pb.y - pa.y)
            guard abs(area) > 1e-6 else { continue }  // vertical, seen edge-on from above
            let x0 = Int(min(pa.x, pb.x, pc.x)), x1 = Int(max(pa.x, pb.x, pc.x).rounded(.up))
            let y0 = Int(min(pa.y, pb.y, pc.y)), y1 = Int(max(pa.y, pb.y, pc.y).rounded(.up))
            for y in y0...y1 {
                for x in x0...x1 {
                    let p = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                    let wa = ((pb.x - p.x) * (pc.y - p.y) - (pc.x - p.x) * (pb.y - p.y)) / area
                    let wb = ((pc.x - p.x) * (pa.y - p.y) - (pa.x - p.x) * (pc.y - p.y)) / area
                    let wc = 1 - wa - wb
                    guard wa >= 0, wb >= 0, wc >= 0 else { continue }
                    record(x, y, wa * a.height + wb * b.height + wc * c.height)
                }
            }
        }
    }

    private mutating func record(_ column: Int, _ row: Int, _ height: Float) {
        guard column >= 0, column < columns, row >= 0, row < rows else { return }
        let i = row * columns + column
        lowest[i] = min(lowest[i], height)
    }
}
