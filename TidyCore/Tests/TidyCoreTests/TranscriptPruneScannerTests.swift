import Foundation
import Testing
@testable import TidyCore

@Suite("TranscriptPruneScanner")
struct TranscriptPruneScannerTests {

    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptPruneScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func setModificationDate(_ date: Date, at url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test("finds an old transcript file")
    func findsOldTranscriptFile() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let projectDir = scratch.appendingPathComponent("some-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let transcript = projectDir.appendingPathComponent("session-1.jsonl")
        try Data("{}".utf8).write(to: transcript)
        try setModificationDate(Date().addingTimeInterval(-90 * 86400), at: transcript)

        let results = TranscriptPruneScanner.findOldTranscripts(claudeProjectsDirectory: scratch.path, olderThanDays: 45)
        #expect(results.map(\.path) == [PathGuard.canonicalize(transcript.path)])
    }

    @Test("does not report a recent transcript file")
    func ignoresRecentTranscriptFile() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let projectDir = scratch.appendingPathComponent("some-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: projectDir.appendingPathComponent("session-1.jsonl"))

        let results = TranscriptPruneScanner.findOldTranscripts(claudeProjectsDirectory: scratch.path, olderThanDays: 45)
        #expect(results.isEmpty)
    }

    @Test("never walks into a memory/ directory, no matter how old its contents are")
    func neverWalksIntoMemoryDirectory() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let projectDir = scratch.appendingPathComponent("some-project", isDirectory: true)
        let memoryDir = projectDir.appendingPathComponent("memory", isDirectory: true)
        try FileManager.default.createDirectory(at: memoryDir, withIntermediateDirectories: true)

        let memoryFile = memoryDir.appendingPathComponent("user_role.md")
        try Data("# old but important".utf8).write(to: memoryFile)
        try setModificationDate(Date().addingTimeInterval(-365 * 86400), at: memoryFile)
        try setModificationDate(Date().addingTimeInterval(-365 * 86400), at: memoryDir)

        let oldTranscript = projectDir.appendingPathComponent("session-old.jsonl")
        try Data("{}".utf8).write(to: oldTranscript)
        try setModificationDate(Date().addingTimeInterval(-90 * 86400), at: oldTranscript)

        let results = TranscriptPruneScanner.findOldTranscripts(claudeProjectsDirectory: scratch.path, olderThanDays: 45)

        let resultPaths = Set(results.map(\.path))
        #expect(resultPaths.contains(PathGuard.canonicalize(oldTranscript.path)))
        #expect(!resultPaths.contains(PathGuard.canonicalize(memoryFile.path)))

        // The file is still physically present and untouched after the
        // scan (the scan itself never deletes; this also guards against a
        // future regression where memory/ contents got listed at all).
        #expect(FileManager.default.fileExists(atPath: memoryFile.path))
    }

    @Test("finds a memory-adjacent nested project's old transcripts while still preserving that project's own memory dir")
    func handlesMultipleProjectsIndependently() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        for project in ["project-a", "project-b"] {
            let projectDir = scratch.appendingPathComponent(project, isDirectory: true)
            let memoryDir = projectDir.appendingPathComponent("memory", isDirectory: true)
            try FileManager.default.createDirectory(at: memoryDir, withIntermediateDirectories: true)
            let memoryFile = memoryDir.appendingPathComponent("notes.md")
            try Data("notes".utf8).write(to: memoryFile)
            try setModificationDate(Date().addingTimeInterval(-200 * 86400), at: memoryFile)

            let transcript = projectDir.appendingPathComponent("session.jsonl")
            try Data("{}".utf8).write(to: transcript)
            try setModificationDate(Date().addingTimeInterval(-90 * 86400), at: transcript)
        }

        let results = TranscriptPruneScanner.findOldTranscripts(claudeProjectsDirectory: scratch.path, olderThanDays: 45)
        #expect(results.count == 2)
        for result in results {
            #expect(!result.path.contains("/memory/"))
        }
    }

    @Test("returns nothing when the threshold is not positive")
    func returnsNothingForNonPositiveThreshold() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(TranscriptPruneScanner.findOldTranscripts(claudeProjectsDirectory: scratch.path, olderThanDays: 0).isEmpty)
    }
}
