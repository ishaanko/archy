//
//  Log.swift
//  FootScan
//

import os

/// One logger per area. In Console.app, filter on `subsystem:FootScan`.
nonisolated enum Log {
    static let flow = Logger(subsystem: "FootScan", category: "ScanFlow")
    static let capture = Logger(subsystem: "FootScan", category: "Capture")
    static let reconstruction = Logger(subsystem: "FootScan", category: "Reconstruction")
    static let viewer = Logger(subsystem: "FootScan", category: "Viewer")
    static let analysis = Logger(subsystem: "FootScan", category: "Analysis")
    static let files = Logger(subsystem: "FootScan", category: "Files")
}
