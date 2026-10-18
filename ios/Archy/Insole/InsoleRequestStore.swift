import SwiftUI

/// Saved insole requests, one JSON file each in Application Support/archy/requests.
@MainActor @Observable
final class InsoleRequestStore {
    private(set) var requests: [InsoleRequest] = []
    var error: String?
    private let folder = URL.applicationSupportDirectory.appending(path: "archy/requests", directoryHint: .isDirectory)
    init() { reload() }
    func reload() {
        do {
            guard FileManager.default.fileExists(atPath: folder.path) else { return }
            requests = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { try JSONDecoder().decode(InsoleRequest.self, from: Data(contentsOf: $0)) }.sorted { $0.createdAt > $1.createdAt }
            error = nil
        } catch { self.error = "Saved requests could not be opened. Existing files have been kept." }
    }
    func save(_ request: InsoleRequest) -> URL? {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(request).write(to: url(request), options: [.atomic, .completeFileProtection])
            reload(); return url(request)
        } catch { self.error = "The request could not be saved. Please try again."; return nil }
    }
    func url(_ request: InsoleRequest) -> URL { folder.appending(path: "AstroFit-\(request.id.uuidString).json") }
    func delete(_ request: InsoleRequest) {
        do { try FileManager.default.removeItem(at: url(request)); reload() }
        catch { self.error = "The request could not be deleted." }
    }
}
