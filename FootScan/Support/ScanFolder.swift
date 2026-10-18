//
//  ScanFolder.swift
//  FootScan
//

import Foundation
import os

/// On-disk layout for one scan: `Documents/Scans/<timestamp>/{Images/, Checkpoint/, foot.usdz}`.
/// Images and Checkpoint are kept after reconstruction so the scan can be reprocessed on a Mac.
struct ScanFolder {
    let root: URL

    var images: URL { root.appending(path: "Images", directoryHint: .isDirectory) }
    var checkpoint: URL { root.appending(path: "Checkpoint", directoryHint: .isDirectory) }
    var modelURL: URL { root.appending(path: "foot.usdz") }

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

    func delete() {
        do {
            try FileManager.default.removeItem(at: root)
            Log.files.notice("Deleted scan folder \(root.path, privacy: .public)")
        } catch {
            Log.files.error("Couldn't delete scan folder \(root.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
