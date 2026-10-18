//
//  Log.swift
//  FootScan
//

import os

/// One logger per area. In Console.app, filter on `subsystem:archy`.
nonisolated enum Log {
    static let flow = Logger(subsystem: "archy", category: "ScanFlow")
    static let capture = Logger(subsystem: "archy", category: "Capture")
    static let reconstruction = Logger(subsystem: "archy", category: "Reconstruction")
    static let viewer = Logger(subsystem: "archy", category: "Viewer")
    static let files = Logger(subsystem: "archy", category: "Files")
}
