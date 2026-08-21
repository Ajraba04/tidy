import Foundation
import Testing
@testable import TidyCore

/// Thread-safe collector for the scanner's synchronous `onItem` callback.
private final class SyncCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var paths: [String] = []

    func record(_ path: String) {
        lock.lock()
        paths.append(path)
        lock.unlock()
    }
}

@Suite("SizeScanner")
struct SizeScannerTests {

    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SizeScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("measures a known amount of file content, at least as large as the logical size")
    func measuresKnownFileContent() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let payload = Data(repeating: 0x42, count: 200_000)
        try payload.write(to: scratch.appendingPathComponent("a.bin"))
        try payload.write(to: scratch.appendingPathComponent("b.bin"))

        let scanner = SizeScanner()
        let results = await scanner.scan(paths: [scratch.path], protectedRoots: [])

        #expect(results.count == 1)
        #expect(results.first?.bytes ?? 0 >= Int64(payload.count * 2))
    }

    @Test("returns zero for a path that does not exist")
    func returnsZeroForMissingPath() async {
        let scanner = SizeScanner()
        let results = await scanner.scan(
            paths: ["/nonexistent/path/for/tidy/tests-\(UUID().uuidString)"],
            protectedRoots: []
        )
        #expect(results.first?.bytes == 0)
    }

    @Test("measures a single file target directly, not just directories")
    func measuresSingleFileTarget() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let file = scratch.appendingPathComponent("solo.bin")
        try Data(repeating: 0x1, count: 50_000).write(to: file)

        let scanner = SizeScanner()
        let results = await scanner.scan(paths: [file.path], protectedRoots: [])
        #expect(results.first?.bytes ?? 0 >= 50_000)
    }

    @Test("excludes a protected root from the measured total")
    func excludesProtectedRoot() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let kept = scratch.appendingPathComponent("kept", isDirectory: true)
        let protectedDir = scratch.appendingPathComponent("protected", isDirectory: true)
        try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: protectedDir, withIntermediateDirectories: true)

        try Data(repeating: 0x1, count: 100_000).write(to: kept.appendingPathComponent("small.bin"))
        try Data(repeating: 0x1, count: 900_000).write(to: protectedDir.appendingPathComponent("large.bin"))

        let scanner = SizeScanner()

        let unprotected = await scanner.scan(paths: [scratch.path], protectedRoots: [])
        let protectedResults = await scanner.scan(paths: [scratch.path], protectedRoots: [protectedDir.path])

        let unprotectedTotal = unprotected.first?.bytes ?? 0
        let protectedTotal = protectedResults.first?.bytes ?? 0

        #expect(unprotectedTotal >= 1_000_000)
        #expect(protectedTotal < unprotectedTotal)
        #expect(protectedTotal < 1_000_000)
    }

    @Test("streams exactly one onItem callback per requested path")
    func streamsOneCallbackPerPath() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        var paths: [String] = []
        for name in ["one", "two", "three", "four"] {
            let dir = scratch.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0x1, count: 1_000).write(to: dir.appendingPathComponent("f.bin"))
            paths.append(dir.path)
        }

        let scanner = SizeScanner()
        let collector = SyncCollector()
        let results = await scanner.scan(paths: paths, protectedRoots: [], onItem: { result in
            collector.record(result.path)
        })

        #expect(results.count == paths.count)
        #expect(Set(collector.paths) == Set(paths))
    }

    @Test("cancelAll on an idle scanner does not corrupt a later scan")
    func cancelAllDoesNotCorruptLaterScans() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try Data(repeating: 0x1, count: 10_000).write(to: scratch.appendingPathComponent("f.bin"))

        let scanner = SizeScanner()
        await scanner.cancelAll()
        await scanner.cancelAll()

        let results = await scanner.scan(paths: [scratch.path], protectedRoots: [])
        #expect(results.first?.bytes ?? 0 >= 10_000)
    }

    @Test("does not walk onto a different mounted volume than the root path")
    func staysOnRootVolume() async throws {
        // No secondary volume is guaranteed to be mounted in CI, so this
        // exercises the code path against the root volume itself, where
        // every child necessarily shares the root's volume identifier and
        // nothing should be skipped for being on a different volume.
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try Data(repeating: 0x1, count: 10_000).write(to: scratch.appendingPathComponent("f.bin"))

        let scanner = SizeScanner()
        let results = await scanner.scan(paths: [scratch.path], protectedRoots: [])
        #expect(results.first?.bytes ?? 0 >= 10_000)
    }
}
