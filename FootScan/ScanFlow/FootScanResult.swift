//
//  FootScanResult.swift
//  FootScan
//

import Foundation

/// A finished scan, handed to the app that presented `FootScannerView` when the user taps Done.
/// The files stay in `Documents/Scans/<timestamp>/`; the host app can copy, upload or delete them.
struct FootScanResult {
    /// The deliverable: binary STL in millimeters, Z up.
    let stlURL: URL
    /// The colored model in meters, Y up (what the viewer shows).
    let usdzURL: URL
    /// The captured photos, for a higher-detail reprocess on a Mac.
    let imagesURL: URL

    /// Bounding-box size of the whole model, in centimeters. It can include part of the lower leg.
    let lengthCM: Double
    let widthCM: Double
    let heightCM: Double

    /// Flat vs. normal arch; nil if the sole couldn't be measured (see `archFailureReason`).
    /// The model and STL are fine either way.
    let archType: ArchType?
    /// Why `archType` is nil, e.g. "There's no foot-sized footprint on the floor."
    let archFailureReason: String?
    /// How far the inner arch lifts off the floor at mid-foot, rounded to 0.1 mm.
    /// Below `FootArchAnalyzer.flatArchHeightMM` counts as flat.
    let archHeightMM: Double?
    /// Arch Index of the footprint (Cavanagh & Rodgers 1987). Diagnostic only: on these 3D scans it can
    /// read as "flat" (≥ 0.26) for a normal foot, so the scanner doesn't show it. Use `archType`.
    let archIndex: Double?
    /// Heel to toe tip and widest part, measured on the sole (more accurate than the bounding box).
    let footLengthCM: Double?
    let footWidthCM: Double?
    /// The foot wasn't standing flat (sole tilted more than `FootArchAnalyzer.unevenSoleTilt` degrees:
    /// weight back on the heel, sloped floor), so `archType` is less certain. False when it wasn't measured.
    let isSoleUneven: Bool

    init(folder: ScanFolder, size: SIMD3<Float>, arch: FootArchAnalysis?, archError: String?) {
        stlURL = folder.stlURL
        usdzURL = folder.modelURL
        imagesURL = folder.images
        // Y is up. Object Capture doesn't line the foot up with x or z consistently,
        // so the longer horizontal side is the length.
        lengthCM = Double(max(size.x, size.z)) * 100
        widthCM = Double(min(size.x, size.z)) * 100
        heightCM = Double(size.y) * 100
        archType = arch?.archType
        archFailureReason = arch == nil ? archError : nil
        archHeightMM = arch?.archHeightMM
        archIndex = arch?.archIndex
        footLengthCM = arch?.footLengthCM
        footWidthCM = arch?.footWidthCM
        isSoleUneven = arch?.isSoleUneven ?? false
    }
}
