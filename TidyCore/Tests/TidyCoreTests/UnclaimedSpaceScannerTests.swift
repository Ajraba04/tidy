import Foundation
import Testing
@testable import TidyCore

@Suite("UnclaimedSpaceScanner")
struct UnclaimedSpaceScannerTests {

    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnclaimedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("a directory containing a claimed path counts as covered")
    func directoryContainingClaimIsCovered() {
        let claimed = ["/home/Library/Application Support/Claude/vm_bundles"]
        #expect(UnclaimedSpaceScanner.subtreeTouchesAnyClaim("/home/Library", claimed: claimed))
        #expect(UnclaimedSpaceScanner.subtreeTouchesAnyClaim(
            "/home/Library/Application Support/Claude",
            claimed: claimed
        ))
    }

    @Test("a claimed path's own descendants count as covered")
    func descendantOfClaimIsCovered() {
        let claimed = ["/home/.npm"]
        #expect(UnclaimedSpaceScanner.subtreeTouchesAnyClaim("/home/.npm/_cacache", claimed: claimed))
    }

    @Test("a directory with no claim anywhere inside it is unclaimed")
    func unrelatedDirectoryIsUnclaimed() {
        let claimed = ["/home/.npm", "/home/Library/Caches"]
        #expect(!UnclaimedSpaceScanner.subtreeTouchesAnyClaim("/home/.codex", claimed: claimed))
    }

    /// A sibling that a prefix comparison would wrongly match.
    @Test("a name-prefix sibling of a claim is not treated as covered")
    func prefixSiblingIsNotCovered() {
        let claimed = ["/home/.npmrc-backup"]
        #expect(!UnclaimedSpaceScanner.subtreeTouchesAnyClaim("/home/.npm", claimed: claimed))
    }

    @Test("flags a big top-level directory that no catalog item claims")
    func flagsUnclaimedTopLevelDirectory() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let unclaimed = scratch.appendingPathComponent("unclaimed-store", isDirectory: true)
        try FileManager.default.createDirectory(at: unclaimed, withIntermediateDirectories: true)

        let claimedItem = CleanItem(
            id: "test.claimed",
            title: "Claimed",
            tier: .safe,
            declaredRoot: { _ in scratch.path },
            locate: { _ in [TargetPath(path: scratch.appendingPathComponent("covered").path)] },
            action: .deletePath
        )

        let found = UnclaimedSpaceScanner.find(
            measuredPaths: [unclaimed.path: 900_000_000],
            environment: CleanEnvironment(homeDirectory: scratch.path, protectedRoots: []),
            catalog: [claimedItem],
            thresholdBytes: 500_000_000
        )

        #expect(found.contains { $0.path == unclaimed.path })
    }

    @Test("does not flag a directory below the size threshold")
    func ignoresSmallDirectories() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let found = UnclaimedSpaceScanner.find(
            measuredPaths: [scratch.path + "/tiny": 1_000],
            environment: CleanEnvironment(homeDirectory: scratch.path, protectedRoots: []),
            catalog: [],
            thresholdBytes: 500_000_000
        )

        #expect(found.isEmpty)
    }

    /// The drift case that motivated this scanner: one child of a directory
    /// is covered, and siblings that grew up later are not.
    @Test("flags an unclaimed sibling of a claimed path")
    func flagsUnclaimedSibling() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let parent = scratch.appendingPathComponent("AppSupport", isDirectory: true)
        let covered = parent.appendingPathComponent("vm_bundles", isDirectory: true)
        let drifted = parent.appendingPathComponent("agent-sessions", isDirectory: true)
        for directory in [parent, covered, drifted] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(repeating: 0x4, count: 700_000).write(to: drifted.appendingPathComponent("blob.bin"))

        let item = CleanItem(
            id: "test.vm-bundles",
            title: "vm_bundles",
            tier: .deep,
            declaredRoot: { _ in parent.path },
            locate: { _ in [TargetPath(path: covered.path)] },
            action: .deletePath
        )

        let found = UnclaimedSpaceScanner.find(
            measuredPaths: [:],
            environment: CleanEnvironment(homeDirectory: scratch.path, protectedRoots: []),
            catalog: [item],
            thresholdBytes: 500_000
        )

        // The scanner reports resolved paths, and a temp directory lives
        // under the /var -> /private/var symlink, so compare canonically.
        let reported = Set(found.map { PathGuard.canonicalize($0.path) })
        #expect(reported.contains(PathGuard.canonicalize(drifted.path)), "the drifted sibling should be reported")
        #expect(!reported.contains(PathGuard.canonicalize(covered.path)), "the covered child must not be reported")
    }

    /// Structural guarantee: this scanner reports `RankedItem` and nothing
    /// else, so nothing it finds can reach a `CleanPlan` without a human
    /// writing a catalog item for it first.
    @Test("reports ranked items only, never anything deletable")
    func reportsRankedItemsOnly() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let found: [RankedItem] = UnclaimedSpaceScanner.find(
            measuredPaths: [:],
            environment: CleanEnvironment(homeDirectory: scratch.path, protectedRoots: []),
            catalog: []
        )
        #expect(found.isEmpty)
    }
}
