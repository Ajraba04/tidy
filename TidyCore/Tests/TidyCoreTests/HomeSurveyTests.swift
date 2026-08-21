import Foundation
import Testing
@testable import TidyCore

/// The single-pass survey replaced three overlapping traversals. These
/// tests keep the *old* code paths as the oracle: whatever `HomeSurvey`
/// reports must equal what `SizeScanner.diskUsage` and
/// `LargestItemsScanner.filesAtLeast` reported for the same tree. That is
/// the cheapest available guard against the refactor quietly changing a
/// number somebody trusts.
@Suite("HomeSurvey")
struct HomeSurveyTests {

    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeSurveyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A tree with nesting, several children of differing size, a file
    /// large enough to trip a threshold, and a symlink.
    private func buildFixture(at root: URL) throws {
        let fm = FileManager.default
        for (name, fileCount, byteCount) in [("alpha", 3, 40_000), ("beta", 2, 10_000)] {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for index in 0..<fileCount {
                try Data(repeating: 0x7, count: byteCount)
                    .write(to: dir.appendingPathComponent("f\(index).bin"))
            }
            let nested = dir.appendingPathComponent("nested", isDirectory: true)
            try fm.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data(repeating: 0x9, count: byteCount)
                .write(to: nested.appendingPathComponent("deep.bin"))
        }
        try Data(repeating: 0x1, count: 300_000).write(to: root.appendingPathComponent("big.bin"))
        try fm.createSymbolicLink(
            at: root.appendingPathComponent("link.bin"),
            withDestinationURL: root.appendingPathComponent("big.bin")
        )
    }

    @Test("total matches what SizeScanner.diskUsage reports for the same tree")
    func totalMatchesDiskUsageOracle() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try buildFixture(at: scratch)

        let oracle = SizeScanner.diskUsage(ofPath: scratch.path, protectedRoots: [])
        let survey = HomeSurvey.walk(
            root: scratch.path,
            protectedRoots: [],
            largeFileThreshold: 0,
            breakOutChildren: false
        )

        #expect(survey.totalBytes == oracle)
    }

    @Test("per-child totals match a diskUsage call made directly against each child")
    func childTotalsMatchDiskUsageOracle() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try buildFixture(at: scratch)

        let survey = HomeSurvey.walk(
            root: scratch.path,
            protectedRoots: [],
            largeFileThreshold: 0,
            breakOutChildren: true
        )

        #expect(!survey.childTotals.isEmpty)
        for child in survey.childTotals {
            let oracle = SizeScanner.diskUsage(ofPath: child.path, protectedRoots: [])
            #expect(child.bytes == oracle, "mismatch for \(child.path)")
        }
    }

    @Test("large files match what LargestItemsScanner.filesAtLeast reports")
    func largeFilesMatchOracle() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try buildFixture(at: scratch)

        let threshold: Int64 = 200_000
        let oracle = LargestItemsScanner.filesAtLeast(
            threshold,
            homeDirectory: scratch.path,
            protectedRoots: [],
            limit: 100
        )
        let survey = HomeSurvey.walk(
            root: scratch.path,
            protectedRoots: [],
            largeFileThreshold: threshold,
            breakOutChildren: false
        )

        #expect(Set(survey.largeFiles.map(\.path)) == Set(oracle.map(\.path)))
        #expect(survey.largeFiles.count == 1)
    }

    @Test("counts a hardlinked file once, the way du does")
    func deduplicatesHardlinks() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let original = scratch.appendingPathComponent("original.bin")
        try Data(repeating: 0x5, count: 400_000).write(to: original)
        try FileManager.default.linkItem(
            at: original,
            to: scratch.appendingPathComponent("hardlink.bin")
        )

        let survey = HomeSurvey.walk(
            root: scratch.path,
            protectedRoots: [],
            largeFileThreshold: 0,
            breakOutChildren: false
        )
        let naive = SizeScanner.diskUsage(ofPath: scratch.path, protectedRoots: [])

        // The old path counts both links; the survey counts the inode once,
        // so it must be meaningfully smaller but still cover the content.
        #expect(survey.totalBytes >= 400_000)
        #expect(survey.totalBytes < naive)
    }

    @Test("honors protected roots and does not descend into them")
    func honorsProtectedRoots() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try buildFixture(at: scratch)

        let protected = scratch.appendingPathComponent("alpha", isDirectory: true).path
        let survey = HomeSurvey.walk(
            root: scratch.path,
            protectedRoots: [protected],
            largeFileThreshold: 0,
            breakOutChildren: true
        )

        #expect(!survey.childTotals.contains { $0.path == protected })
    }

    @Test("a file root measures as itself")
    func fileRootMeasuresAsItself() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let file = scratch.appendingPathComponent("solo.bin")
        try Data(repeating: 0x3, count: 90_000).write(to: file)

        let survey = HomeSurvey.walk(
            root: file.path,
            protectedRoots: [],
            largeFileThreshold: 0,
            breakOutChildren: false
        )
        #expect(survey.totalBytes == SizeScanner.diskUsage(ofPath: file.path, protectedRoots: []))
    }

    @Test("returns nothing for a path that does not exist")
    func handlesMissingPath() {
        let survey = HomeSurvey.walk(
            root: "/nonexistent/tidy/\(UUID().uuidString)",
            protectedRoots: [],
            largeFileThreshold: 0,
            breakOutChildren: true
        )
        #expect(survey.totalBytes == 0)
        #expect(survey.largeFiles.isEmpty)
        #expect(survey.childTotals.isEmpty)
    }
}
