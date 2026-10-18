import Foundation
import Combine
import OSLog

@MainActor
final class AssessmentStore: ObservableObject {
    @Published private(set) var records: [Assessment] = []
    @Published var errorMessage: String?
    private let fileURL: URL
    private let logger = Logger(subsystem: "archy", category: "AssessmentStore")
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "archy", directoryHint: .isDirectory)
            .appending(path: "assessments.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            records = try JSONDecoder().decode([Assessment].self, from: Data(contentsOf: self.fileURL))
                .sorted { $0.date > $1.date }
        } catch {
            errorMessage = "Saved assessments could not be loaded. \(error.localizedDescription)"
            logger.error("Assessment load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    /// Updates observable records only after the complete file is atomically written.
    @discardableResult
    func save(_ assessment: Assessment) -> Bool {
        do {
            let errors = assessment.left.validationErrors + assessment.right.validationErrors
            guard errors.isEmpty else { throw MeasurementError.invalidMeasurements(errors) }
            // Preserve a file that could not be decoded rather than overwriting it.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try JSONDecoder().decode([Assessment].self, from: Data(contentsOf: fileURL))
            }
            var updated = records.filter { $0.id != assessment.id }
            updated.append(assessment)
            updated.sort { $0.date > $1.date }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(updated)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            records = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Assessment could not be saved. \(error.localizedDescription)"
            logger.error("Assessment save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
