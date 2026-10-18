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

    /// Flat vs. normal arch; nil if the sole couldn't be measured (the model and STL are still fine).
    let archType: ArchType?
    /// How far the inner arch lifts off the floor at mid-foot. Below 10 mm counts as flat.
    let archHeightMM: Double?
    /// Arch Index of the footprint (Cavanagh & Rodgers 1987), for reference: 0.26 or more suggests flat.
    let archIndex: Double?
    /// Heel to toe tip and widest part, measured on the sole (more accurate than the bounding box).
    let footLengthCM: Double?
    let footWidthCM: Double?

    init(folder: ScanFolder, size: SIMD3<Float>, arch: FootArchAnalysis?) {
        stlURL = folder.stlURL
        usdzURL = folder.modelURL
        imagesURL = folder.images
        // Y is up. Object Capture doesn't line the foot up with x or z consistently,
        // so the longer horizontal side is the length.
        lengthCM = Double(max(size.x, size.z)) * 100
        widthCM = Double(min(size.x, size.z)) * 100
        heightCM = Double(size.y) * 100
        archType = arch?.archType
        archHeightMM = arch?.archHeightMM
        archIndex = arch?.archIndex
        footLengthCM = arch?.footLengthCM
        footWidthCM = arch?.footWidthCM
    }
}
