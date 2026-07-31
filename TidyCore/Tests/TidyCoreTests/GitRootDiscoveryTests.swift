import Foundation
import Testing
@testable import TidyCore

@Suite("GitRootDiscovery")
struct GitRootDiscoveryTests {
    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitRootDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("finds a candidate root containing at least one repository")
    func findsCandidateRootWithRepository() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let developer = scratch.appendingPathComponent("Developer", isDirectory: true)
        let project = developer.appendingPathComponent("my-project", isDirectory: true)
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let candidates = GitRootDiscovery.discoverCandidates(homeDirectory: scratch.path)
        #expect(candidates.count == 1)
        #expect(candidates.first?.path == developer.path)
        #expect(candidates.first?.repositoryCount == 1)
    }

    @Test("does not report a candidate root with no repositories")
    func doesNotReportRootWithoutRepositories() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let documents = scratch.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents.appendingPathComponent("resume.pdf"), withIntermediateDirectories: true)

        let candidates = GitRootDiscovery.discoverCandidates(homeDirectory: scratch.path)
        #expect(candidates.isEmpty)
    }

    @Test("counts multiple repositories under the same root")
    func countsMultipleRepositories() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let projects = scratch.appendingPathComponent("Projects", isDirectory: true)
        for name in ["a", "b", "c"] {
            try FileManager.default.createDirectory(
                at: projects.appendingPathComponent(name).appendingPathComponent(".git"),
                withIntermediateDirectories: true
            )
        }

        let candidates = GitRootDiscovery.discoverCandidates(homeDirectory: scratch.path)
        #expect(candidates.first?.repositoryCount == 3)
    }

    @Test("returns nothing when no candidate roots exist at all")
    func returnsNothingWhenNoCandidateRootsExist() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(GitRootDiscovery.discoverCandidates(homeDirectory: scratch.path).isEmpty)
    }
}
