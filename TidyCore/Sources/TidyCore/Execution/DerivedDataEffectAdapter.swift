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
    private final class OutcomeCollector {
        var values: [TargetEffectOutcome] = []
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
        let barrier = PolicyInvalidationBarrier(coordinatorID: UUID())
        let cancellation = EffectCancellationToken()
        let schedule = try FilesystemEffectSchedule(
            allocatedByteLimit: 256 * 1_024 * 1_024 * 1_024,
            leafLimit: ReviewedManifestArchive.maximumNodeCount,
            deadline: ContinuousClock.now.advanced(by: .seconds(60)),
            cancellation: cancellation, policyBarrier: barrier, policyRevision: 1)
        let outcomes = OutcomeCollector()
        let streamed = try streamReviewed(seal: seal, association: association,
            currentProtectedRoots: currentProtectedRoots, leaseProvider: leaseProvider,
            schedule: schedule) { outcomes.values.append($0) }
        return Effect(outcomes: outcomes.values,
            freeSpaceBeforeBytes: streamed.freeSpaceBeforeBytes,
            freeSpaceAfterBytes: streamed.freeSpaceAfterBytes)
    }

    /// Streams one result at a time and performs every synchronous unlink while
    /// the exact policy revision is held. Durability work belongs to the caller
    /// outside this barrier.
    static func streamReviewed(seal: ReviewedFileResource,
                               association: ResourceAssociationEvidence,
                               currentProtectedRoots: [String],
                               leaseProvider: any ProducerExclusionLeaseProviding,
                               schedule: FilesystemEffectSchedule,
                               onOutcome: @escaping (TargetEffectOutcome) throws -> Void) throws
        -> StreamedFilesystemEffect {
        try streamReviewedBatches(seal: seal, association: association,
            currentProtectedRoots: currentProtectedRoots,
            leaseProvider: leaseProvider, schedule: schedule,
            forEachBatchReversed: { body in
                for batch in seal.tree.batches.reversed() { try body(batch) }
            }, onOutcome: onOutcome)
    }

    static func streamPersistedReviewed(
        seal: ReviewedFileResource,
        reference: ReviewedManifestReference,
        association: ResourceAssociationEvidence,
        currentProtectedRoots: [String],
        leaseProvider: any ProducerExclusionLeaseProviding,
        schedule: FilesystemEffectSchedule,
        forEachBatchReversed: (_ body: (ReviewedBatch) throws -> Void) throws -> Void,
        onOutcome: @escaping (TargetEffectOutcome) throws -> Void
    ) throws -> StreamedFilesystemEffect {
        guard reference.manifestDigest == seal.tree.digest,
              reference.protectionDigest == seal.protection.digest else {
            throw GuardedFileError.invalidManifest
        }
        return try streamReviewedBatches(seal: seal, association: association,
            currentProtectedRoots: currentProtectedRoots,
            leaseProvider: leaseProvider, schedule: schedule,
            forEachBatchReversed: forEachBatchReversed, onOutcome: onOutcome)
    }

    private static func streamReviewedBatches(
        seal: ReviewedFileResource,
        association: ResourceAssociationEvidence,
        currentProtectedRoots: [String],
        leaseProvider: any ProducerExclusionLeaseProviding,
        schedule: FilesystemEffectSchedule,
        forEachBatchReversed: (_ body: (ReviewedBatch) throws -> Void) throws -> Void,
        onOutcome: @escaping (TargetEffectOutcome) throws -> Void
    ) throws -> StreamedFilesystemEffect {
        guard seal.identity.canonicalPath.hasSuffix(acceptedRelativeSuffix) else {
            throw AdapterError.wrongTarget
        }
        let resource = ResourceIdentity.filesystem(seal.identity)
        try ResourceAuthorityValidator.validateAssociation(association,
            resource: resource, adapterID: AppleDerivedDataInventory.adapterID,
            adapterVersion: AppleDerivedDataInventory.contractVersion, now: Date())
        let anchor = try ResourcePreflight.openValidated(
            seal, currentProtectedRoots: currentProtectedRoots)

        let before = Self.freeBytes(atDirectory: seal.identity.canonicalPath)
        var volumeUnreadable = false
        var lease: (any ProducerExclusionLease)?
        var budget = try LeafScheduleBudget(allocatedByteLimit: schedule.allocatedByteLimit,
            leafLimit: schedule.leafLimit, deadline: schedule.deadline)
        var scheduled = 0
        var overruns = 0
        var stop: SchedulingStop?
        let exclusions = Set(seal.tree.excludedRelativePaths)

        // Batches preserve the manifest's global preorder (parents before
        // children) across their boundaries, so replaying batches in
        // reverse order and each batch's entries in reverse order removes
        // every child before the parent that contains it without having to
        // re-walk the tree.
        try forEachBatchReversed { batch in
            guard stop == nil else { return }
            if !volumeUnreadable, Self.freeBytes(atDirectory: seal.identity.canonicalPath) == nil {
                volumeUnreadable = true
            }
            guard !volumeUnreadable else {
                for entry in batch.entries.reversed() { try onOutcome(Self.withheldOutcome(entry)) }
                return
            }
            for entry in batch.entries.reversed() {
                let now = ContinuousClock.now
                if let reason = budget.reserve(allocatedEstimate: entry.snapshot.allocatedBytes,
                                               now: now,
                                               cancelled: schedule.cancellation.isCancelled
                                                   || withUnsafeCurrentTask {
                                                       $0?.isCancelled ?? false
                                                   }) {
                    stop = reason
                    return
                }
                let fresh: any ProducerExclusionLease
                if let lease {
                    fresh = try leaseProvider.renewLease(for: resource, after: lease)
                } else {
                    fresh = try leaseProvider.acquireLease(for: resource)
                }
                lease = fresh
                let effectNow = Date()
                let effectInstant = ContinuousClock.now
                try ResourceAuthorityValidator.validateAssociation(association,
                    resource: resource, adapterID: AppleDerivedDataInventory.adapterID,
                    adapterVersion: AppleDerivedDataInventory.contractVersion, now: effectNow)
                try ResourceAuthorityValidator.validateRuntime(fresh.proof,
                    association: association, resource: resource,
                    adapterID: AppleDerivedDataInventory.adapterID,
                    adapterVersion: AppleDerivedDataInventory.contractVersion, now: effectNow,
                    monotonicAcquiredAt: fresh.acquiredAt,
                    monotonicDeadline: fresh.deadline,
                    monotonicNow: effectInstant)
                var boundaryStop: SchedulingStop?
                let outcome: TargetEffectOutcome? = try withExtendedLifetime(fresh) {
                    try schedule.policyBarrier.withCurrentPolicy(
                        revision: schedule.policyRevision) {
                        if schedule.cancellation.isCancelled
                            || withUnsafeCurrentTask(body: { $0?.isCancelled ?? false }) {
                            boundaryStop = .cancelled
                            return nil
                        }
                        if ContinuousClock.now >= schedule.deadline {
                            boundaryStop = .deadline
                            return nil
                        }
                        return AnchoredFileOperations.unlinkReviewedLeaf(anchor: anchor,
                            reviewed: entry, excludedRelativePaths: exclusions)
                    }
                }
                if let boundaryStop {
                    stop = boundaryStop
                    return
                }
                guard let outcome else { throw GuardedFileError.invalidBudget }
                scheduled += 1
                if ContinuousClock.now > schedule.deadline { overruns += 1 }
                try onOutcome(outcome)
            }
        }
        lease = nil
        let after = Self.freeBytes(atDirectory: seal.identity.canonicalPath)
        return StreamedFilesystemEffect(freeSpaceBeforeBytes: before,
            freeSpaceAfterBytes: after, scheduledLeaves: scheduled,
            deadlineOverruns: overruns, stop: stop)
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
