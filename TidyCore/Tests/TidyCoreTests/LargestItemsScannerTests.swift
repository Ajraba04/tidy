import Foundation
import Testing
@testable import TidyCore

@Suite("LargestItemsScanner")
struct LargestItemsScannerTests {

    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LargestItemsScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("matches visible entries and lowercase dot-entries, excludes capitalized dot-entries", arguments: [
        ("Documents", true),
        ("Desktop", true),
        (".gradle", true),
        (".npm", true),
        (".ssh", true),
        (".cache", true),
        (".Trash", false),
        (".DS_Store", false),
        (".Spotlight-V100", false),
        (".", false),
        ("", false)
    ])
    func matchesHomeTopLevelPattern(name: String, expected: Bool) {
        #expect(LargestItemsScanner.matchesHomeTopLevelPattern(name) == expected)
    }

    @Test("homeTopLevelEntries filters out capitalized dot-entries")
    func homeTopLevelEntriesFilters() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        for name in ["Documents", ".gradle", ".Trash", ".DS_Store"] {
            try FileManager.default.createDirectory(
                at: scratch.appendingPathComponent(name),
                withIntermediateDirectories: true
            )
        }

        let entries = LargestItemsScanner.homeTopLevelEntries(homeDirectory: scratch.path)
        let names = Set(entries.map { ($0 as NSString).lastPathComponent })

        #expect(names.contains("Documents"))
        #expect(names.contains(".gradle"))
        #expect(!names.contains(".Trash"))
        #expect(!names.contains(".DS_Store"))
    }

    @Test("libraryEntries lists every immediate child, dot or not")
    func libraryEntriesListsEverything() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let library = scratch.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Caches"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Application Support"), withIntermediateDirectories: true)

        let entries = LargestItemsScanner.libraryEntries(homeDirectory: scratch.path)
        let names = Set(entries.map { ($0 as NSString).lastPathComponent })
        #expect(names == ["Caches", "Application Support"])
    }

    @Test("filesAtLeast finds only files at or above the threshold, largest first")
    func filesAtLeastFindsLargeFiles() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        try Data(repeating: 0x1, count: 2_000_000).write(to: scratch.appendingPathComponent("big.bin"))
        try Data(repeating: 0x1, count: 3_000_000).write(to: scratch.appendingPathComponent("bigger.bin"))
        try Data(repeating: 0x1, count: 1_000).write(to: scratch.appendingPathComponent("small.bin"))

        let results = LargestItemsScanner.filesAtLeast(
            1_500_000,
            homeDirectory: scratch.path,
            protectedRoots: [],
            limit: 8
        )

        #expect(results.count == 2)
        #expect(results.first?.path.hasSuffix("bigger.bin") == true)
    }

    @Test("filesAtLeast excludes protected roots")
    func filesAtLeastExcludesProtectedRoots() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let protectedDir = scratch.appendingPathComponent("CloudStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: protectedDir, withIntermediateDirectories: true)
        try Data(repeating: 0x1, count: 2_000_000).write(to: protectedDir.appendingPathComponent("big.bin"))

        let results = LargestItemsScanner.filesAtLeast(
            1_500_000,
            homeDirectory: scratch.path,
            protectedRoots: [protectedDir.path],
            limit: 8
        )
        #expect(results.isEmpty)
    }

    @Test("filesAtLeast respects the limit")
    func filesAtLeastRespectsLimit() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        for i in 0..<5 {
            try Data(repeating: 0x1, count: 2_000_000 + i).write(to: scratch.appendingPathComponent("file\(i).bin"))
        }

        let results = LargestItemsScanner.filesAtLeast(
            1_000_000,
            homeDirectory: scratch.path,
            protectedRoots: [],
            limit: 3
        )
        #expect(results.count == 3)
    }
}
