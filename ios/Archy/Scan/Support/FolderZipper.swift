//
//  FolderZipper.swift
//  FootScan
//

import Foundation

/// Zips a folder with the system archiver (the one behind Compress in the Files app).
/// AirDrop handles one zip more reliably than a folder of photos.
nonisolated enum FolderZipper {
    /// Synchronous and slow for big folders; call it off the main actor.
    static func zip(_ folder: URL, to destination: URL) throws {
        var coordinatorError: NSError?
        var moveError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { tempZip in
            // `tempZip` is deleted when this block returns, so move it out first.
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempZip, to: destination)
            } catch {
                moveError = error
            }
        }
        if let error = coordinatorError ?? moveError { throw error }
    }
}
