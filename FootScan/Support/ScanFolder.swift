//
//  ScanFolder.swift
//  FootScan
//

import Foundation
import os

/// On-disk layout for one scan: `Documents/Scans/<timestamp>/{Images/, Checkpoint/, foot.usdz, foot.stl}`.
/// Images and Checkpoint are kept after reconstruction so the scan can be reprocessed on a Mac.
struct ScanFolder {
    let root: URL

    var images: URL { root.appending(path: "Images", directoryHint: .isDirectory) }
    var checkpoint: URL { root.appending(path: "Checkpoint", directoryHint: .isDirectory) }
    var modelURL: URL { root.appending(path: "foot.usdz") }
    var stlURL: URL { root.appending(path: "foot.stl") }

    static var scansRoot: URL {
        URL.documentsDirectory.appending(path: "Scans", directoryHint: .isDirectory)
    }

    /// Creates a new, empty scan folder named after the current time (no colons, so AirDrop/Finder friendly).
    static func createNew() throws -> ScanFolder {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let folder = ScanFolder(root: scansRoot.appending(path: formatter.string(from: .now),
                                                          directoryHint: .isDirectory))
        do {
            for directory in [folder.images, folder.checkpoint] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        } catch {
            Log.files.error("Couldn't create scan folder \(folder.root.path, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
        Log.files.notice("Created scan folder \(folder.root.path, privacy: .public)")
        return folder
    }

    /// Number of captured HEIC images in `Images/`.
    func imageCount() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "heic" }.count
    }

    /// Removes `foot.usdz` and `foot.stl` from an earlier attempt so reprocessing starts clean.
    func removeOutputs() {
        for url in [modelURL, stlURL] where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
                Log.files.notice("Removed old \(url.lastPathComponent, privacy: .public)")
            } catch {
                Log.files.error("Couldn't remove \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// File size in MB for logging, or 0 if the file is missing.
    static func sizeInMB(of url: URL) -> Double {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return Double(bytes) / 1_000_000
    }

    func delete() {
        do {
            try FileManager.default.removeItem(at: root)
            Log.files.notice("Deleted scan folder \(root.path, privacy: .public)")
        } catch {
            Log.files.error("Couldn't delete scan folder \(root.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
