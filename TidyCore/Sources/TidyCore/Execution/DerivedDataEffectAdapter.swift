import Darwin
import Foundation

/// The sole accepted production effect adapter. Bound at compile time to
/// exactly one catalog item (`safe.xcode.derived-data`) and one action
/// (`.deleteContents`); it refuses to touch anything else even if a caller
/// mistakenly hands it a different item's target. `ExecutionCoordinator` is
/// the only production caller: this type never registers itself anywhere,
/// and `CleanEngine.execute` remains unconditional denial.
///
/// Deletes the reviewed contents of the target directory (children of the
/// anchored root), never the root itself, matching `.deleteContents`
/// semantics used elsewhere in the catalog. All mutation goes through
/// `DirectoryAnchor`/`ReviewedTree`/`AnchoredFileOperations`
/// (`GuardedFileDeleter.swift`): no-follow anchored descriptors, an
/// identity-checked manifest captured immediately before mutation, and a
/// checked identity re-verification on every single removal.
enum DerivedDataEffectAdapter {
    static let acceptedItemID = "safe.xcode.derived-data"
    static let acceptedRelativeSuffix = "Library/Developer/Xcode/DerivedData"

    enum AdapterError: Error, Equatable {
        case wrongItem
        case wrongTarget
        case notAFilesystemTarget
    }

    struct Effect {
        let outcomes: [TargetEffectOutcome]
        /// Bytes statfs reported free on the containing volume immediately
        /// before the first removal in this target's manifest, or nil if
        /// the measurement itself could not be taken.
        let freeSpaceBeforeBytes: Int64?
        /// The equivalent measurement after the last removal attempted for
        /// this target (including any batches withheld by the preflight).
        let freeSpaceAfterBytes: Int64?
    }

    /// Runs the guarded deletion for one already-reviewed, already
    /// capability-checked target. Never called with a target this adapter
    /// did not itself validate: the two identity checks below are a second,
    /// independent gate behind `CapabilityRegistry`, not a substitute for it.
    static func execute(itemID: String, action: CleanAction, target: TargetPath) throws -> Effect {
        guard itemID == acceptedItemID else { throw AdapterError.wrongItem }
        guard case .deleteContents = action else { throw AdapterError.wrongItem }
        guard target.isFilesystemPath else { throw AdapterError.notAFilesystemTarget }
        guard target.path.hasSuffix(acceptedRelativeSuffix) else { throw AdapterError.wrongTarget }

        let anchor = try DirectoryAnchor.open(path: target.path)
        let tree = try ReviewedTree.capture(anchor: anchor, excluding: [])

        var outcomes: [TargetEffectOutcome] = []
        let before = Self.freeBytes(atDirectory: target.path)
        var volumeUnreadable = false

        // Batches preserve the manifest's global preorder (parents before
        // children) across their boundaries, so replaying batches in
        // reverse order and each batch's entries in reverse order removes
        // every child before the parent that contains it without having to
        // re-walk the tree.
        for batch in tree.batches.reversed() {
            if !volumeUnreadable, Self.freeBytes(atDirectory: target.path) == nil {
                volumeUnreadable = true
            }
            guard !volumeUnreadable else {
                outcomes.append(contentsOf: batch.entries.map(Self.withheldOutcome))
                continue
            }
            for entry in batch.entries.reversed() {
                outcomes.append(AnchoredFileOperations.unlinkReviewedLeaf(
                    anchor: anchor, reviewed: entry, excludedRelativePaths: []))
            }
        }

        let after = Self.freeBytes(atDirectory: target.path)
        return Effect(outcomes: outcomes, freeSpaceBeforeBytes: before, freeSpaceAfterBytes: after)
    }

    private static func withheldOutcome(_ entry: ReviewedLeaf) -> TargetEffectOutcome {
        let unavailable = ByteObservation(bytes: nil, explanation: "Withheld: free-space preflight failed")
        return TargetEffectOutcome(relativePath: entry.relativePath, status: .uncertain,
            reason: "Free-space preflight could not confirm the volume before this batch; withheld.",
            completedRemovals: 0, removedApparentBytes: unavailable,
            removedAllocatedBytes: unavailable, provenReclaimedBytes: unavailable)
    }

    /// Same descriptor-based, no-follow `statfs` shape as
    /// `ResourcePreflight`, opened independently of the deletion anchor:
    /// this is a reporting measurement only, never an authority the
    /// deletion path depends on.
    private static func freeBytes(atDirectory path: String) -> Int64? {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = statfs()
        guard fstatfs(fd, &info) == 0 else { return nil }
        let (bytes, overflow) = Int64(info.f_bavail).multipliedReportingOverflow(by: Int64(info.f_bsize))
        return overflow ? nil : bytes
    }
}
