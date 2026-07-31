import Foundation
import Testing
@testable import TidyCore

@Suite("GitRepoScanner")
struct GitRepoScannerTests {

    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitRepoScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("finds a repository by its .git directory")
    func findsRepositoryByGitDirectory() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let repo = scratch.appendingPathComponent("my-project", isDirectory: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let results = GitRepoScanner.findRepositories(roots: [scratch.path], protectedRoots: [])
        #expect(results == [PathGuard.canonicalize(repo.path)])
    }

    @Test("does not walk into .git's own contents")
    func doesNotWalkIntoGitContents() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let repo = scratch.appendingPathComponent("my-project", isDirectory: true)
        let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
        // A nested directory named ".git" inside objects/ should never be
        // reported as a second repository.
        try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("objects/.git"), withIntermediateDirectories: true)

        let results = GitRepoScanner.findRepositories(roots: [scratch.path], protectedRoots: [])
        #expect(results == [PathGuard.canonicalize(repo.path)])
    }

    @Test("excludes a repository under a protected root")
    func excludesProtectedRoot() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let protectedDir = scratch.appendingPathComponent("CloudStorage", isDirectory: true)
        let repo = protectedDir.appendingPathComponent("my-project", isDirectory: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let results = GitRepoScanner.findRepositories(roots: [scratch.path], protectedRoots: [protectedDir.path])
        #expect(results.isEmpty)
    }

    @Test("respects maxDepth")
    func respectsMaxDepth() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let deepRepo = scratch
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
            .appendingPathComponent("c", isDirectory: true)
            .appendingPathComponent("d", isDirectory: true)
            .appendingPathComponent("e", isDirectory: true)
            .appendingPathComponent("f", isDirectory: true)
        try FileManager.default.createDirectory(at: deepRepo.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let results = GitRepoScanner.findRepositories(roots: [scratch.path], protectedRoots: [], maxDepth: 2)
        #expect(results.isEmpty)
    }

    @Test("finds multiple repositories across multiple roots")
    func findsMultipleRepositoriesAcrossRoots() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let rootA = scratch.appendingPathComponent("roots-a", isDirectory: true)
        let rootB = scratch.appendingPathComponent("roots-b", isDirectory: true)
        let repoA = rootA.appendingPathComponent("proj-a", isDirectory: true)
        let repoB = rootB.appendingPathComponent("proj-b", isDirectory: true)
        try FileManager.default.createDirectory(at: repoA.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoB.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let results = GitRepoScanner.findRepositories(roots: [rootA.path, rootB.path], protectedRoots: [])
        #expect(Set(results) == Set([PathGuard.canonicalize(repoA.path), PathGuard.canonicalize(repoB.path)]))
    }
}
