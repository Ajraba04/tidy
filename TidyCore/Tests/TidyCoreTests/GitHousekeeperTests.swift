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

    private func git(_ arguments: [String], in repo: URL) async throws {
        guard let gitPath = ToolLocator.locate("git") else {
            Issue.record("git not found")
            return
        }
        let output = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: gitPath),
            arguments: ["-C", repo.path] + arguments,
            environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": NSHomeDirectory(),
                "GIT_AUTHOR_NAME": "Tidy Tests",
                "GIT_AUTHOR_EMAIL": "tests@example.com",
                "GIT_COMMITTER_NAME": "Tidy Tests",
                "GIT_COMMITTER_EMAIL": "tests@example.com"
            ]
        )
        #expect(output.succeeded, "git \(arguments.joined(separator: " ")) failed: \(output.standardError)")
    }

    private func makeRepoWithOneCommit() async throws -> URL {
        let scratch = try makeScratchDirectory()
        try await git(["init", "-q"], in: scratch)
        try Data("hello".utf8).write(to: scratch.appendingPathComponent("file.txt"))
        try await git(["add", "file.txt"], in: scratch)
        try await git(["commit", "-q", "-m", "initial"], in: scratch)
        return scratch
    }

    @Test("conservative housekeeping succeeds on a real repository and leaves it usable")
    func conservativeHousekeepingSucceeds() async throws {
        let repo = try await makeRepoWithOneCommit()
        defer { try? FileManager.default.removeItem(at: repo) }

        let result = await GitHousekeeper.runConservative(repoPath: repo.path)
        #expect(result.succeeded)

        // The repo must still be fully usable afterward.
        guard let gitPath = ToolLocator.locate("git") else {
            Issue.record("git not found")
            return
        }
        let log = try await ProcessRunner.run(executableURL: URL(fileURLWithPath: gitPath), arguments: ["-C", repo.path, "log", "--oneline"])
        #expect(log.succeeded)
        #expect(log.standardOutput.contains("initial"))
    }

    @Test("aggressive reflog expiry succeeds and also leaves the repository usable")
    func aggressiveReflogExpirySucceeds() async throws {
        let repo = try await makeRepoWithOneCommit()
        defer { try? FileManager.default.removeItem(at: repo) }

        let result = await GitHousekeeper.runAggressiveReflogExpiry(repoPath: repo.path)
        #expect(result.succeeded)

        guard let gitPath = ToolLocator.locate("git") else {
            Issue.record("git not found")
            return
        }
        let status = try await ProcessRunner.run(executableURL: URL(fileURLWithPath: gitPath), arguments: ["-C", repo.path, "status"])
        #expect(status.succeeded)
    }

    @Test("cleans up stale gc.log and index.lock files")
    func cleansUpStaleLockFiles() async throws {
        let repo = try await makeRepoWithOneCommit()
        defer { try? FileManager.default.removeItem(at: repo) }

        try Data().write(to: repo.appendingPathComponent(".git/gc.log"))
        try Data().write(to: repo.appendingPathComponent(".git/index.lock"))

        let result = await GitHousekeeper.runConservative(repoPath: repo.path)
        #expect(result.succeeded)
        #expect(!FileManager.default.fileExists(atPath: repo.path + "/.git/gc.log"))
        #expect(!FileManager.default.fileExists(atPath: repo.path + "/.git/index.lock"))
    }

    @Test("fails gracefully on a directory that is not a git repository")
    func failsGracefullyOnNonRepository() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let result = await GitHousekeeper.runConservative(repoPath: scratch.path)
        #expect(!result.succeeded)
    }
}
