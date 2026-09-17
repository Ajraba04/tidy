import Darwin
import Foundation

/// Quarantined DerivedData effect boundary. Production has no supported Xcode
/// producer-exclusion provider, so the coordinator-facing entry point always
/// denies. The internal reviewed entry point is the exact R02/R03 contract and
/// is exercised only with disposable fixture leases until a real producer
/// primitive is documented and separately accepted.
enum DerivedDataEffectAdapter {
    static let acceptedItemID = "safe.xcode.derived-data"
    static let acceptedRelativeSuffix = "Library/Developer/Xcode/DerivedData"

    enum AdapterError: Error, Equatable {
        case wrongItem
        case wrongTarget
        case notAFilesystemTarget
        case productionProofUnavailable
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

    /// Existing production call shape is retained as an explicit denial so a
    /// stale coordinator binary cannot fall back to fresh-tree authorization.
    static func execute(itemID: String, action: CleanAction, target: TargetPath) throws -> Effect {
        guard itemID == acceptedItemID else { throw AdapterError.wrongItem }
        guard case .deleteContents = action else { throw AdapterError.wrongItem }
        guard target.isFilesystemPath else { throw AdapterError.notAFilesystemTarget }
        guard target.path.hasSuffix(acceptedRelativeSuffix) else { throw AdapterError.wrongTarget }
        throw AdapterError.productionProofUnavailable
    }

    /// Consumes only a review-time tree. This function never walks a fresh
    /// execution-time tree and never expands the reviewed manifest.
    static func executeReviewed(seal: ReviewedFileResource,
                                association: ResourceAssociationEvidence,
                                currentProtectedRoots: [String],
                                leaseProvider: any ProducerExclusionLeaseProviding) throws -> Effect {
        guard seal.identity.canonicalPath.hasSuffix(acceptedRelativeSuffix) else {
            throw AdapterError.wrongTarget
        }
        let resource = ResourceIdentity.filesystem(seal.identity)
        try ResourceAuthorityValidator.validateAssociation(association,
            resource: resource, adapterID: AppleDerivedDataInventory.adapterID,
            adapterVersion: AppleDerivedDataInventory.contractVersion, now: Date())
        let anchor = try ResourcePreflight.openValidated(
            seal, currentProtectedRoots: currentProtectedRoots)

        var outcomes: [TargetEffectOutcome] = []
        let before = Self.freeBytes(atDirectory: seal.identity.canonicalPath)
        var volumeUnreadable = false

        // Acquisition is deliberately the final preparatory step. The lease
        // is strongly retained across every unlink and validates positive,
        // complete producer evidence no older than five seconds.
        let lease = try leaseProvider.acquireLease(for: resource)
        let effectInstant = ContinuousClock.now
        let effectNow = Date()
        try ResourceAuthorityValidator.validateAssociation(association,
            resource: resource, adapterID: AppleDerivedDataInventory.adapterID,
            adapterVersion: AppleDerivedDataInventory.contractVersion, now: effectNow)
        try ResourceAuthorityValidator.validateRuntime(lease.proof,
            association: association, resource: resource,
            adapterID: AppleDerivedDataInventory.adapterID,
            adapterVersion: AppleDerivedDataInventory.contractVersion, now: effectNow,
            monotonicAcquiredAt: lease.acquiredAt,
            monotonicDeadline: lease.deadline,
            monotonicNow: effectInstant)

        // Batches preserve the manifest's global preorder (parents before
        // children) across their boundaries, so replaying batches in
        // reverse order and each batch's entries in reverse order removes
        // every child before the parent that contains it without having to
        // re-walk the tree.
        let effect = withExtendedLifetime(lease) { () -> Effect in
            for batch in seal.tree.batches.reversed() {
                if !volumeUnreadable, Self.freeBytes(atDirectory: seal.identity.canonicalPath) == nil {
                    volumeUnreadable = true
                }
                guard !volumeUnreadable else {
                    outcomes.append(contentsOf: batch.entries.map(Self.withheldOutcome))
                    continue
                }
                for entry in batch.entries.reversed() {
                    outcomes.append(AnchoredFileOperations.unlinkReviewedLeaf(
                        anchor: anchor, reviewed: entry,
                        excludedRelativePaths: Set(seal.tree.excludedRelativePaths)))
                }
            }
            let after = Self.freeBytes(atDirectory: seal.identity.canonicalPath)
            return Effect(outcomes: outcomes, freeSpaceBeforeBytes: before, freeSpaceAfterBytes: after)
        }
        return effect
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
