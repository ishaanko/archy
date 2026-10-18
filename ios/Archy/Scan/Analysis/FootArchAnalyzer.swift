//
//  FootArchAnalyzer.swift
//  archy
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
nonisolated enum FootArchAnalyzer {
    /// Grid resolution of the footprint.
    static let cellSize: Float = 0.003
    /// Surface this close to the floor counts as contact. 3 mm is within the mesh's noise.
    static let contactHeight: Float = 0.005
    /// The front of the footprint treated as toes and left out, as in the published method.
    static let toeFraction: Float = 0.20
    /// Inner arch lower than this (in mm, as displayed: rounded to 0.1) is flat. From six test scans of four
    /// feet: known flat feet measured 1.4–5.8 mm, the normal foot 13.6–15.5 mm, and repeat scans of a foot
    /// agreed within about 2 mm.
    static let flatArchHeightMM = 10.0
    /// A sole tilted more than this many degrees wasn't standing flat (weight back, sloped floor).
    nonisolated static let unevenSoleTilt: Float = 4
    /// A footprint shorter than this isn't a foot (adult feet are about 22–30 cm).
    static let minimumFootLength: Float = 0.15

    /// Messages give only the cause; the viewer shows them under "Arch not measured".
    enum Failure: LocalizedError {
        case noFootprint(lengthCM: Double, tiltDegrees: Double)
        case noArchProfile
        case unreadableMesh

        var errorDescription: String? {
            switch self {
            case .noFootprint(_, let tilt) where tilt > Double(FootArchAnalyzer.unevenSoleTilt):
                "There's no foot-sized footprint on the floor (sole tilted \(String(format: "%.1f", tilt))°). Stand with weight on the whole foot."
            case .noFootprint:
                "There's no foot-sized footprint on the floor."
            case .noArchProfile:
                "The sides of the sole couldn't be traced."
            case .unreadableMesh:
                "The model's shape couldn't be read."
            }
        }
    }

    static func analyze(_ mesh: FootMesh) throws -> FootArchAnalysis {
        // FootMesh.load already rejects these; checked again because a damaged mesh must never crash this.
        guard mesh.isUsable else { throw Failure.unreadableMesh }
        let floorY = mesh.bounds.min.y
        let axes = footAxes(mesh, floorY: floorY)
        var grid = HeightGrid(mesh: mesh, axes: axes, floorY: floorY, cellSize: cellSize)
        let (soleTilt, floorSlope) = grid.levelToSupportPlane(cellSize: cellSize)
        let contact = footRegions(of: grid.lowest.map { $0 < contactHeight }, columns: grid.columns, rows: grid.rows)

        // Footprint extent along the foot: columns with a real strip of contact, not single stray cells.
        let minimumCells = 3
        let contactColumns = (0..<grid.columns).filter { column in
            (0..<grid.rows).count(where: { contact[$0 * grid.columns + column] }) >= minimumCells
        }
        guard let contactHeel = contactColumns.first, let contactToe = contactColumns.last else {
            throw Failure.noFootprint(lengthCM: 0, tiltDegrees: Double(soleTilt))
        }
        // The foot runs past its contact patch where the sole lifts (toes, the heel's edge). Grow the span
        // along the sole's outline so length, the arch measurement and the drawing include them.
        func outlineCells(_ column: Int) -> Int {
            (0..<grid.rows).count(where: { grid.lowest[$0 * grid.columns + column] < outlineHeight })
        }
        var heel = contactHeel, toeTip = contactToe
        while heel > 0, outlineCells(heel - 1) >= minimumCells { heel -= 1 }
        while toeTip < grid.columns - 1, outlineCells(toeTip + 1) >= minimumCells { toeTip += 1 }
        let lengthColumns = toeTip - heel + 1
        guard lengthColumns >= Int((minimumFootLength / cellSize).rounded()) else {
            throw Failure.noFootprint(lengthCM: Double(Float(lengthColumns) * cellSize * 100),
                                      tiltDegrees: Double(soleTilt))
        }

        // Arch Index over the contact footprint without toes, as in the published method. The thirds rarely
        // fall on whole columns, so each column's contact is split by overlap; whole-column thirds bias it.
        let third = Float(contactToe - contactHeel + 1) * (1 - toeFraction) / 3
        var thirds: [Float] = [0, 0, 0]
        var maxWidthCells = 0
        for column in heel...toeTip {
            // Width from the sole's outline, not its contact: a rolled foot touches with a narrow strip.
            maxWidthCells = max(maxWidthCells, outlineCells(column))
            guard column >= contactHeel, column <= contactToe else { continue }
            let cells = (0..<grid.rows).count(where: { contact[$0 * grid.columns + column] })
            let start = Float(column - contactHeel), end = start + 1
            for k in 0..<3 {
                let overlap = min(end, Float(k + 1) * third) - max(start, Float(k) * third)
                if overlap > 0 { thirds[k] += Float(cells) * overlap }
            }
        }
        let archIndex = Double(thirds[1] / max(thirds.reduce(0, +), 1))

        guard let arch = measureArch(grid: grid, heel: heel, toeTip: toeTip) else { throw Failure.noArchProfile }
        // Classify the value the user sees, so "10.0 mm" can never sit under "flat is under 10 mm".
        let archHeightMM = (Double(arch.height) * 10_000).rounded() / 10
        let archType: ArchType = archHeightMM < flatArchHeightMM ? .flat : .normal
        let footprint = Footprint(cellSize: cellSize, columns: grid.columns, rows: grid.rows, contact: contact,
                                  heights: grid.lowest, heelColumn: heel, toeTipColumn: toeTip,
                                  innerSideAtHighRows: arch.innerSideAtHighRows,
                                  archPeakColumn: archType == .normal ? arch.peakColumn : nil)
        return FootArchAnalysis(archIndex: archIndex,
                                archHeightMM: archHeightMM,
                                archType: archType,
                                footLengthCM: Double(Float(lengthColumns) * cellSize * 100),
                                footWidthCM: Double(Float(maxWidthCells) * cellSize * 100),
                                soleTiltDegrees: Double(soleTilt),
                                floorNormal: axes.floorNormal(slope: floorSlope),
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
        -> (height: Float, innerSideAtHighRows: Bool, peakColumn: Int?)? {
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
        // Without a heel and ball level on at least one side there's no baseline: report that, not "0 mm, flat".
        var measuredSides = 0
        for (side, raw) in profiles.enumerated() {
            // Smooth with a 5-column (1.5 cm) running median so a single noisy column can't make an arch.
            let profile = raw.indices.map { i in median(raw[max(0, i - 2)...min(raw.count - 1, i + 2)].filter(\.isFinite)) }
            func level(_ from: Float, _ to: Float) -> Float {
                median(profile[Int(from * length)..<Int(to * length)].filter(\.isFinite))
            }
            let heelLevel = level(0.05, 0.20), ballLevel = level(0.65, 0.80)
            guard heelLevel.isFinite, ballLevel.isFinite else { continue }
            measuredSides += 1
            for i in Int(0.25 * length)..<Int(0.60 * length) where profile[i].isFinite {
                let f = Float(i) / length
                let baseline = heelLevel + (ballLevel - heelLevel) * (f - 0.125) / (0.725 - 0.125)
                let rise = profile[i] - baseline
                if rise > best.height {
                    best = (rise, side == 1, heel + i)
                }
            }
        }
        return measuredSides > 0 ? best : nil
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

        /// Unit up direction, in mesh coordinates, of a floor rising `slope` meters per meter along and across.
        func floorNormal(slope: SIMD2<Float>) -> SIMD3<Float> {
            let gradient = slope.x * along + slope.y * across
            return simd_normalize(SIMD3(-gradient.x, 1, -gradient.y))
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

    /// Keeps the foot's contact patches and drops specks such as floor debris. A patch counts if it's at least
    /// 15% the size of the biggest one: a high arch splits the footprint into heel and forefoot, and keeping
    /// only the biggest would measure the forefoot alone and call the foot flat.
    static func footRegions(of cells: [Bool], columns: Int, rows: Int) -> [Bool] {
        var label = [Int](repeating: -1, count: cells.count)
        var regions: [[Int]] = []
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
            regions.append(region)
        }
        let largest = regions.map(\.count).max() ?? 0
        var result = [Bool](repeating: false, count: cells.count)
        for region in regions where Double(region.count) >= 0.15 * Double(largest) {
            for i in region { result[i] = true }
        }
        return result
    }
}

nonisolated enum ArchType: String {
    case flat
    /// Includes high arches; the app only needs to know whether the foot is flat.
    case normal
}

/// The result of `FootArchAnalyzer.analyze(_:)`.
nonisolated struct FootArchAnalysis {
    let archIndex: Double
    /// How far the inner arch lifts off the floor, against a heel-to-ball line.
    let archHeightMM: Double
    let archType: ArchType
    /// Heel to toe tip, from the footprint (the bounding box can include the lower leg).
    let footLengthCM: Double
    /// Widest part of the footprint.
    let footWidthCM: Double
    /// How tilted the plane the sole rests on was. A foot standing with weight on it is close to 0°; more
    /// than `FootArchAnalyzer.unevenSoleTilt` suggests weight back on the heel or a sloped floor.
    let soleTiltDegrees: Double
    /// Up direction of the plane the sole rests on, in the mesh's coordinates; straight up when it wasn't
    /// leveled. The viewer rotates the model by it so the displayed foot stands level.
    let floorNormal: SIMD3<Float>
    let footprint: Footprint

    /// The scan wasn't of a foot standing flat, so the result is less certain.
    var isSoleUneven: Bool { soleTiltDegrees > Double(FootArchAnalyzer.unevenSoleTilt) }
}

/// The sole as seen from below, for drawing: columns run heel → toe, rows across the foot.
/// Arrays are row-major: `contact[row * columns + column]`.
nonisolated struct Footprint {
    let cellSize: Float
    let columns: Int
    let rows: Int
    /// Touching the floor (the foot's contact patches; floor specks dropped).
    let contact: [Bool]
    /// Height of the sole's underside above the plane it rests on, in meters; infinity where there's no
    /// surface. The sole's outline is where this is below `FootArchAnalyzer.outlineHeight`.
    let heights: [Float]
    let heelColumn: Int
    let toeTipColumn: Int
    /// Whether the inner (big-toe, arch) side is at high row numbers.
    let innerSideAtHighRows: Bool
    /// Where along the foot the arch is highest, for labeling it; nil when the foot is classified flat.
    let archPeakColumn: Int?
}

/// The lowest surface height above the floor in each cell of a grid laid along the foot.
private nonisolated struct HeightGrid {
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

    /// Re-measures every height from the plane the sole rests on (heel, ball, outer edge) instead of from
    /// the scan's lowest point. Without this, a sole tilted by weight on the heel or a sloped floor loses
    /// most of its footprint. Returns the plane's tilt in degrees and the slope it removed (meters per meter
    /// along and across the foot); a tilt over 15° is left alone as implausible, with zero slope.
    mutating func levelToSupportPlane(cellSize: Float) -> (tilt: Float, slope: SIMD2<Float>) {
        // Sole cells only: the lower leg, when the scan includes it, is 10 cm or more up.
        var points: [SIMD3<Double>] = []
        for row in 0..<rows {
            for column in 0..<columns where lowest[row * columns + column] < 0.08 {
                points.append(SIMD3(Double(column), Double(row), Double(lowest[row * columns + column])))
            }
        }
        guard points.count >= 50 else { return (0, .zero) }

        // Plane h = a + b·column + c·row. Refit to the lower half of the points each round: the arch and
        // the sole's edges sit above the support plane, so they drop out and the fit settles onto it.
        var plane = SIMD3<Double>.zero
        for _ in 0..<5 {
            guard let fit = Self.fitPlane(points) else { break }
            plane = fit
            let residuals = points.map { $0.z - (plane.x + plane.y * $0.x + plane.z * $0.y) }
            let cutoff = residuals.sorted()[residuals.count / 2]
            points = zip(points, residuals).filter { $0.1 <= cutoff }.map(\.0)
            if points.count < 30 { break }
        }

        let slope = SIMD2(plane.y, plane.z) / Double(cellSize)
        let tilt = Float(atan(simd_length(slope)) * 180 / .pi)
        guard tilt < 15 else { return (tilt, .zero) }
        for row in 0..<rows {
            for column in 0..<columns where lowest[row * columns + column].isFinite {
                lowest[row * columns + column] -= Float(plane.x + plane.y * Double(column) + plane.z * Double(row))
            }
        }
        return (tilt, SIMD2<Float>(slope))
    }

    /// Least-squares plane z = a + b·x + c·y, as (a, b, c); nil if the points are degenerate.
    private static func fitPlane(_ points: [SIMD3<Double>]) -> SIMD3<Double>? {
        var normal = simd_double3x3()
        var right = SIMD3<Double>.zero
        for p in points {
            let row = SIMD3(1, p.x, p.y)
            normal += simd_double3x3(columns: (row * row.x, row * row.y, row * row.z))
            right += row * p.z
        }
        guard abs(normal.determinant) > 1e-9 else { return nil }
        return normal.inverse * right
    }
}
