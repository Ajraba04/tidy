import Foundation
import Testing
@testable import TidyCore

@Suite("GitHousekeeper")
struct GitHousekeeperTests {

    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitHousekeeperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("direct Git helpers are quarantined without commands or scratch mutation")
    func directHelpersDenyWithoutMutatingScratchRepository() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let gitDirectory = scratch.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        let lock = gitDirectory.appendingPathComponent("index.lock")
        let log = gitDirectory.appendingPathComponent("gc.log")
        let lockBytes = Data("retain index lock".utf8)
        let logBytes = Data("retain gc log".utf8)
        try lockBytes.write(to: lock)
        try logBytes.write(to: log)

        let recorder = GitCommandRecorder()
        let results = [
            await GitHousekeeper.runConservative(repoPath: scratch.path, commandRunner: recorder),
            await GitHousekeeper.runAggressiveReflogExpiry(repoPath: scratch.path, commandRunner: recorder)
        ]

        for result in results {
            #expect(!result.succeeded)
            #expect(result.message == CapabilityRegistry.quarantineReason)
        }
        #expect(try Data(contentsOf: lock) == lockBytes)
        #expect(try Data(contentsOf: log) == logBytes)
        #expect(await recorder.calls.isEmpty)
    }
}

private actor GitCommandRecorder: CleanupCommandRunning {
    private(set) var calls: [String] = []

    func run(executableName: String, arguments: [String], timeout: TimeInterval) async -> CleanupCommandOutput {
        calls.append(([executableName] + arguments).joined(separator: " "))
        return CleanupCommandOutput(succeeded: true)
    }
}
