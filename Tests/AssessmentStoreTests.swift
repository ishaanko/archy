import Foundation
import Testing
@testable import MeasurementCore

struct AssessmentStoreTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AssessmentStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    @Test @MainActor
    func savesReloadsAndReplacesMatchingID() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("nested/assessments.json")
        let store = AssessmentStore(fileURL: file)
        #expect(store.records.isEmpty)
        var assessment = Assessment.synthetic
        assessment.isSynthetic = false
        #expect(store.save(assessment))
        #expect(store.records == [assessment])
        assessment.left.width += 1
        #expect(store.save(assessment))
        #expect(store.records == [assessment])
        let reloaded = AssessmentStore(fileURL: file)
        #expect(reloaded.records == [assessment])
        #expect(reloaded.errorMessage == nil)
    }
    @Test @MainActor
    func failedWriteLeavesMemoryUnchangedAndSuccessClearsError() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("assessments.json")
        let store = AssessmentStore(fileURL: file)
        let first = Assessment.synthetic
        #expect(store.save(first))
        // A regular file in place of the parent directory guarantees a write failure.
        try FileManager.default.removeItem(at: directory)
        try Data("write blocker".utf8).write(to: directory)
        #expect(!store.save(Assessment.synthetic))
        #expect(store.records == [first])
        #expect(store.errorMessage != nil)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(store.save(first))
        #expect(store.errorMessage == nil)
    }
    @Test @MainActor
    func corruptedExistingFileIsPreserved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("assessments.json")
        let corrupt = Data("not valid JSON".utf8)
        try corrupt.write(to: file)
        let store = AssessmentStore(fileURL: file)
        #expect(store.records.isEmpty)
        #expect(store.errorMessage != nil)
        #expect(!store.save(Assessment.synthetic))
        #expect(store.records.isEmpty)
        #expect(try Data(contentsOf: file) == corrupt)
    }
    @Test @MainActor
    func invalidAssessmentDoesNotChangeStoredRecord() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("assessments.json")
        let store = AssessmentStore(fileURL: file)
        let valid = Assessment.synthetic
        #expect(store.save(valid))
        let originalData = try Data(contentsOf: file)
        var invalid = valid
        invalid.right.fullLength = .nan
        #expect(!store.save(invalid))
        #expect(store.records == [valid])
        #expect(store.errorMessage != nil)
        #expect(try Data(contentsOf: file) == originalData)
    }
}
