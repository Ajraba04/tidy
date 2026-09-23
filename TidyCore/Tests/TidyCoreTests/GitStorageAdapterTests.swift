import Foundation
import Testing
@testable import TidyCore

@Suite("Git storage adapter", .serialized)
struct GitStorageAdapterTests {
    @Test("shared common directory is counted once and live lock remains blocked")
    func sharedLockedCommonDirectory() throws {
        let fixture = try AdapterTestFixture(); defer { fixture.remove() }
        let commonURL = try fixture.directory("Projects/common.git")
        try Data("locked".utf8).write(to: commonURL.appendingPathComponent("index.lock"))
        let common = try ResourcePreflight.captureFile(at: commonURL.path)
        let firstRoot = try fixture.directory("Projects/first")
        let secondRoot = try fixture.directory("Projects/second")
        let firstIdentity = try ResourcePreflight.captureFile(at: firstRoot.path)
        let secondIdentity = try ResourcePreflight.captureFile(at: secondRoot.path)
        func project(_ id: String, root: URL, identity: FileResourceIdentity)
            -> ProjectInventoryRecord {
            let git = ProjectGitMetadata(layout: .linkedWorktree, markerIdentity: nil,
                gitDirectoryIdentity: common, commonDirectoryIdentity: common,
                worktreeIdentity: identity, dirtyState: .unknown, untrackedState: .unknown)
            return ProjectInventoryRecord(id: id, canonicalRoot: root.path,
                rootIdentity: identity, git: git, manifests: [], toolchains: [],
                capability: .inventoryOnly, confidence: .partial, activity: .unknown,
                recommendationEligible: false, reasons: [])
        }
        let context = fixture.context(projects: [
            project("first", root: firstRoot, identity: firstIdentity),
            project("second", root: secondRoot, identity: secondIdentity)
        ])
        let entries = try GitStorageAdapter().inventory(context: context)
        #expect(entries.count == 1)
        #expect(entries[0].record.ownerIDs == ["first", "second"])
        #expect(entries[0].record.reason.contains("lock is present"))
        #expect(entries[0].record.capability == .inventoryOnly)
    }
}
