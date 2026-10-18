//
//  ScanFolder.swift
//  archy
//

import Foundation
import os

/// On-disk layout for one scan: `Documents/Scans/<timestamp>/{Images/, Checkpoint/, foot.usdz, foot.stl}`.
/// Images are kept after reconstruction so the scan can be reprocessed on a Mac. The checkpoint
/// (the biggest part, 300–650 MB) is only needed until the model is built, so it's deleted then.
struct ScanFolder {
    let root: URL

    var images: URL { root.appending(path: "Images", directoryHint: .isDirectory) }
    var checkpoint: URL { root.appending(path: "Checkpoint", directoryHint: .isDirectory) }
    var modelURL: URL { root.appending(path: "foot.usdz") }
    var stlURL: URL { root.appending(path: "foot.stl") }
    /// Zip of `Images/` for sharing. Lives in the temporary folder, which iOS clears on its own,
    /// so it doesn't double each scan's size on disk.
    var imagesZipURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "\(root.lastPathComponent)-Images.zip")
    }

    static var scansRoot: URL {
        URL.documentsDirectory.appending(path: "Scans", directoryHint: .isDirectory)
    }

    /// ObjectCaptureSession refuses to start with less free space than this.
    static let requiredFreeBytes: Int64 = 4_000_000_000

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

    /// Removes `foot.usdz`, `foot.stl` and the shared zip from an earlier attempt so reprocessing starts clean.
    func removeOutputs() {
        for url in [modelURL, stlURL, imagesZipURL] {
            Self.remove(url)
        }
    }

    /// Frees the checkpoint once the model has been built.
    func removeCheckpoint() {
        let freed = Self.remove(checkpoint)
        Log.files.notice("Removed checkpoint, freed \(Self.formatted(freed), privacy: .public)")
    }

    func delete() {
        Self.remove(root)
    }

    // MARK: - Storage

    /// Free space iOS will make available for app data, or nil if it won't say.
    static func freeBytes() -> Int64? {
        try? URL.documentsDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    static func storageMessage(requiredBytes: Int64 = requiredFreeBytes) -> String {
        let free = freeBytes().map { ", this iPhone has \(formatted($0))" } ?? ""
        return "Not enough space. archy needs about \(formatted(requiredBytes)) free\(free). "
            + "Delete old scans in Files › archy › Scans, or free up space in Settings."
    }

    nonisolated static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// File size in MB for logging, or 0 if the file is missing.
    static func sizeInMB(of url: URL) -> Double {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return Double(bytes) / 1_000_000
    }

    /// Run at launch. Removes empty scan folders left by failed starts, checkpoints of scans that
    /// already have a model, and zips that older builds kept inside scan folders. Photos and models stay.
    static func cleanUp() {
        let fileManager = FileManager.default
        let scans = (try? fileManager.contentsOfDirectory(at: scansRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var freed: Int64 = 0
        var emptyFolders = 0
        for root in scans where isDirectory(root) {
            let folder = ScanFolder(root: root)
            let hasModel = fileManager.fileExists(atPath: folder.modelURL.path)
            if folder.imageCount() == 0 && !hasModel {
                freed += remove(root)
                emptyFolders += 1
                continue
            }
            if hasModel {
                freed += remove(folder.checkpoint)
            }
            freed += remove(root.appending(path: "Images.zip"))
        }
        let free = freeBytes().map(formatted) ?? "unknown"
        Log.files.notice("Cleanup: removed \(emptyFolders) empty scan folders, freed \(formatted(freed), privacy: .public). Free space: \(free, privacy: .public)")
    }

    /// Deletes a file or folder if it exists and returns how many bytes that freed.
    @discardableResult
    private static func remove(_ url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let size = allocatedSize(of: url)
        do {
            try FileManager.default.removeItem(at: url)
            Log.files.notice("Deleted \(url.path, privacy: .public) (\(formatted(size), privacy: .public))")
            return size
        } catch {
            Log.files.error("Couldn't delete \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return 0
        }
    }

    private static func allocatedSize(of url: URL) -> Int64 {
        let key = URLResourceKey.totalFileAllocatedSizeKey
        guard isDirectory(url) else {
            return Int64((try? url.resourceValues(forKeys: [key]).totalFileAllocatedSize) ?? 0)
        }
        var total: Int64 = 0
        let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [key])
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [key]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
