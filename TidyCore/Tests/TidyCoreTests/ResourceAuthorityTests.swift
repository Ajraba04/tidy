import Darwin
import Foundation
import Testing
@testable import TidyCore

private final class LeaseState: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var acquisitions = 0
    private(set) var releasedAfterEffect = false
    private let effectWitness: URL

    init(effectWitness: URL) { self.effectWitness = effectWitness }
    func acquired() { lock.withLock { acquisitions += 1 } }
    func released() {
        lock.withLock { releasedAfterEffect = !FileManager.default.fileExists(atPath: effectWitness.path) }
    }
}

private final class FixtureProducerLease: ProducerExclusionLease, @unchecked Sendable {
    let proof: RuntimeProducerProof
    let acquiredAt: ContinuousClock.Instant
    let deadline: ContinuousClock.Instant
    private let state: LeaseState
    init(proof: RuntimeProducerProof, state: LeaseState,
         acquiredAt: ContinuousClock.Instant, deadline: ContinuousClock.Instant) {
        self.proof = proof
        self.state = state
        self.acquiredAt = acquiredAt
        self.deadline = deadline
    }
    deinit { state.released() }
}

private struct FixtureLeaseProvider: ProducerExclusionLeaseProviding {
    let state: LeaseState
    let adapterVersion: String
    let ownerIDs: Set<String>
    let observedAt: Date
    let validUntil: Date

    func acquireLease(for resource: ResourceIdentity) throws -> any ProducerExclusionLease {
        state.acquired()
        let acquiredAt = ContinuousClock.now
        let seconds = validUntil.timeIntervalSince(observedAt)
        return FixtureProducerLease(proof: RuntimeProducerProof(
            adapterID: AppleDerivedDataInventory.adapterID,
            adapterVersion: adapterVersion,
            resource: resource,
            producerIDs: ["fixture.xcode-build-system"],
            ownerIDs: ownerIDs,
            sharedOwnerIDs: [],
            completeness: .complete,
            observedAt: observedAt,
            validUntil: validUntil,
            method: .producerExclusionLease
        ), state: state, acquiredAt: acquiredAt,
           deadline: acquiredAt.advanced(by: .seconds(seconds)))
    }
}

private struct AuthorityScratch {
    let root: URL
    let journal: URL
    let derivedData: URL
    let protected: URL
    let outside: URL
    let unchanged: URL
    let changed: URL
    let unicode: URL

    init() throws {
        guard let resolved = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw ResourceCaptureError.unavailable
        }
        defer { free(resolved) }
        root = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
            .appendingPathComponent("Tidy-R02-\(UUID().uuidString)", isDirectory: true)
        journal = root.appendingPathComponent("journal", isDirectory: true)
        derivedData = root.appendingPathComponent("home/Library/Developer/Xcode/DerivedData", isDirectory: true)
        protected = derivedData.appendingPathComponent("Protected", isDirectory: true)
        outside = root.appendingPathComponent("outside.txt")
        unchanged = derivedData.appendingPathComponent("Project/Build/unchanged.o")
        changed = derivedData.appendingPathComponent("Project/Build/changed.o")
        unicode = derivedData.appendingPathComponent("مشروع/نتيجة-🧪.txt")
        for directory in [protected, unchanged.deletingLastPathComponent(), unicode.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Data("protected".utf8).write(to: protected.appendingPathComponent("keep.txt"))
        try Data("outside".utf8).write(to: outside)
        try Data("unchanged".utf8).write(to: unchanged)
        try Data("changed".utf8).write(to: changed)
        try Data("unicode".utf8).write(to: unicode)
    }

    func association(for seal: ReviewedFileResource, observedAt: Date,
                     validUntil: Date? = nil, owners: Set<String> = ["project.fixture"],
                     sharedOwners: Set<String> = [], completeness: OwnershipCompleteness = .complete,
                     adapterVersion: String = AppleDerivedDataInventory.contractVersion) -> ResourceAssociationEvidence {
        ResourceAssociationEvidence(
            adapterID: AppleDerivedDataInventory.adapterID,
            adapterVersion: adapterVersion,
            resource: .filesystem(seal.identity),
            producerIDs: ["fixture.xcode-build-system"],
            ownerIDs: owners,
            sharedOwnerIDs: sharedOwners,
            completeness: completeness,
            observedAt: observedAt,
            validUntil: validUntil ?? observedAt.addingTimeInterval(60),
            method: .producerManifest
        )
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@Suite("R02 sealed resource authority", .serialized)
struct ResourceAuthorityTests {
    @Test("Coordinator retains the review-time manifest while production selection remains quarantined")
    func coordinatorBindsReviewTimeManifest() async throws {
        let scratch = try AuthorityScratch(); defer { scratch.cleanup() }
        let home = scratch.root.appendingPathComponent("home", isDirectory: true)
        let coordinator = ExecutionCoordinator(environment: CleanEnvironment(
            homeDirectory: home.path, detectedTools: [.xcode], protectedRoots: [scratch.protected.path]),
            journalDirectory: scratch.journal)
        let review = try await coordinator.prepareReview(
            engine: CleanEngine(sizeScanner: SizeScanner()), tier: .safe, selectDefaults: false)
        let captured = try #require(await coordinator.reviewedFilesystemIdentities(
            planID: review.binding.planID, itemID: DerivedDataEffectAdapter.acceptedItemID).first)
        let digest = try #require(captured.manifest).digest
        try Data("new after review".utf8).write(
            to: scratch.derivedData.appendingPathComponent("new-root-child"))
        let retained = try #require(await coordinator.reviewedFilesystemIdentities(
            planID: review.binding.planID, itemID: DerivedDataEffectAdapter.acceptedItemID).first)
        #expect(retained.manifest?.digest == digest)
        #expect(!ResourcePreflight.unchanged(retained))
        await #expect(throws: ConfirmationError.unavailableSelection) {
            _ = try await coordinator.setSelection(planID: review.binding.planID,
                selectedIDs: [DerivedDataEffectAdapter.acceptedItemID])
        }
    }

    @Test("Production DerivedData inventory is explicit inventory-only unknown authority")
    func productionInventoryDoesNotMintAuthority() throws {
        let scratch = try AuthorityScratch(); defer { scratch.cleanup() }
        let record = try AppleDerivedDataInventory.inspect(root: scratch.derivedData, observedAt: Date(timeIntervalSince1970: 1))
        #expect(record.adapterID == AppleDerivedDataInventory.adapterID)
        #expect(record.capability == .inventoryOnly)
        #expect(record.activity == .unknown)
        #expect(record.ownerIDs.isEmpty)
        #expect(record.reason.contains("no supported Xcode producer exclusion"))
        #expect(AppleDerivedDataInventory.productionLeaseProvider == nil)
    }

    @Test("Review seal binds exact root ancestors manifest and protection scope in bounded batches")
    func reviewSealContract() throws {
        let scratch = try AuthorityScratch(); defer { scratch.cleanup() }
        let seal = try ResourcePreflight.captureReviewedDirectory(
            at: scratch.derivedData.path,
            protectedRoots: [scratch.protected.path],
            maxNodesPerBatch: 2,
            maxBytesPerBatch: 8 * 1_024 * 1_024
        )
        let manifest = try #require(seal.identity.manifest)
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.digest == seal.tree.digest)
        #expect(manifest.protectionDigest == seal.protection.digest)
        #expect(manifest.batchIDs == seal.tree.batches.map(\.id))
        #expect(manifest.nodeCount == seal.tree.batches.reduce(0) { $0 + $1.entries.count })
        #expect(seal.tree.batches.allSatisfy { (1...2).contains($0.entries.count) })
        #expect(seal.tree.batches.allSatisfy { $0.encodedBytes <= 8 * 1_024 * 1_024 })
        #expect(seal.identity.parentChain.allSatisfy { $0.mode & UInt32(S_IFMT) == UInt32(S_IFDIR) })
        #expect(seal.tree.entry("Protected") == nil)
        #expect(seal.matchesProtectionScope([scratch.protected.path]))
        #expect(!seal.matchesProtectionScope([]))

        let encoded = try seal.persistenceArchive.encodedBounded()
        let decoded = try ReviewedManifestArchive.decodeBounded(encoded)
        let restored = try decoded.restore()
        #expect(restored.identity == seal.identity)
        #expect(restored.tree.batches.flatMap(\.entries).map(\.relativePath)
                == seal.tree.batches.flatMap(\.entries).map(\.relativePath))
    }

    @Test("Archive cannot splice an unprotected manifest onto a valid protected scope")
    func mixedManifestAndProtectionAreRejected() throws {
        let scratch = try AuthorityScratch(); defer { scratch.cleanup() }
        let unprotected = try ResourcePreflight.captureReviewedDirectory(
            at: scratch.derivedData.path, protectedRoots: [])
        let protected = try ResourcePreflight.captureReviewedDirectory(
            at: scratch.derivedData.path, protectedRoots: [scratch.protected.path])
        let unprotectedData = try unprotected.persistenceArchive.encodedBounded()
        let protectedData = try protected.persistenceArchive.encodedBounded()
        var mixed = try #require(
            JSONSerialization.jsonObject(with: unprotectedData) as? [String: Any])
        let protectedObject = try #require(
            JSONSerialization.jsonObject(with: protectedData) as? [String: Any])
        guard let protectedScope = protectedObject["protection"] else {
            throw GuardedFileError.invalidManifest
        }
        mixed["protection"] = protectedScope
        let mixedData = try JSONSerialization.data(withJSONObject: mixed, options: [.sortedKeys])
        let decoded = try ReviewedManifestArchive.decodeBounded(mixedData)

        #expect(throws: GuardedFileError.invalidManifest) { _ = try decoded.restore() }
        #expect(try Data(contentsOf: scratch.protected.appendingPathComponent("keep.txt"))
                == Data("protected".utf8))
        #expect(try Data(contentsOf: scratch.unchanged) == Data("unchanged".utf8))
    }

    @Test("Held fresh lease removes only unchanged reviewed leaves")
    func unchangedLeavesOnly() throws {
        let scratch = try AuthorityScratch(); defer { scratch.cleanup() }
        let reviewedChangedBytes = try Data(contentsOf: scratch.changed)
        let seal = try ResourcePreflight.captureReviewedDirectory(
            at: scratch.derivedData.path, protectedRoots: [scratch.protected.path])
        try Data("grown after review".utf8).append(to: scratch.changed)
        let newChild = scratch.derivedData.appendingPathComponent("Project/Build/new-after-review.o")
        try Data("new".utf8).write(to: newChild)
        let now = Date()
        let association = scratch.association(for: seal, observedAt: now)
        let state = LeaseState(effectWitness: scratch.unchanged)
        let provider = FixtureLeaseProvider(state: state,
            adapterVersion: AppleDerivedDataInventory.contractVersion,
            ownerIDs: association.ownerIDs, observedAt: now, validUntil: now.addingTimeInterval(5))

        let effect = try DerivedDataEffectAdapter.executeReviewed(
            seal: seal, association: association, currentProtectedRoots: [scratch.protected.path],
            leaseProvider: provider)

        #expect(state.acquisitions == effect.outcomes.count)
        #expect(state.acquisitions > 1)
        #expect(state.releasedAfterEffect)
        #expect(!FileManager.default.fileExists(atPath: scratch.unchanged.path))
        #expect(!FileManager.default.fileExists(atPath: scratch.unicode.path))
        #expect(FileManager.default.fileExists(atPath: scratch.changed.path))
        #expect(try Data(contentsOf: scratch.changed).starts(with: reviewedChangedBytes))
        #expect(FileManager.default.fileExists(atPath: newChild.path))
        #expect(try Data(contentsOf: scratch.protected.appendingPathComponent("keep.txt")) == Data("protected".utf8))
        #expect(try Data(contentsOf: scratch.outside) == Data("outside".utf8))
        #expect(effect.outcomes.contains { $0.relativePath.hasSuffix("changed.o") && $0.status == .skipped })
    }

    @Test("Incomplete unknown shared stale changed-owner unsupported-version expired and rollback evidence deny",
          arguments: ["incomplete", "unknown", "shared", "stale", "owner", "version", "runtime-expired", "wall-rollback"])
    func proofDenials(kind: String) throws {
        let scratch = try AuthorityScratch(); defer { scratch.cleanup() }
        let seal = try ResourcePreflight.captureReviewedDirectory(at: scratch.derivedData.path, protectedRoots: [])
        let now = Date()
        var association = scratch.association(for: seal, observedAt: now)
        var providerOwners = association.ownerIDs
        let providerVersion = AppleDerivedDataInventory.contractVersion
        var providerObservedAt = now
        var leaseUntil = now.addingTimeInterval(5)
        switch kind {
        case "incomplete": association = scratch.association(for: seal, observedAt: now, completeness: .incomplete)
        case "unknown": association = scratch.association(for: seal, observedAt: now, completeness: .unknown)
        case "shared": association = scratch.association(for: seal, observedAt: now,
            sharedOwners: ["unobserved.project"])
        case "stale": association = scratch.association(for: seal, observedAt: now.addingTimeInterval(-86_401),
            validUntil: now.addingTimeInterval(-1))
        case "owner": providerOwners = ["different.owner"]
        case "version": association = scratch.association(for: seal, observedAt: now,
            adapterVersion: "unsupported")
        case "runtime-expired": leaseUntil = now.addingTimeInterval(-1)
        default:
            providerObservedAt = now.addingTimeInterval(1)
            leaseUntil = providerObservedAt.addingTimeInterval(5)
        }
        let state = LeaseState(effectWitness: scratch.unchanged)
        let provider = FixtureLeaseProvider(state: state, adapterVersion: providerVersion,
            ownerIDs: providerOwners, observedAt: providerObservedAt, validUntil: leaseUntil)

        #expect(throws: ResourceAuthorityError.self) {
            _ = try DerivedDataEffectAdapter.executeReviewed(
                seal: seal, association: association, currentProtectedRoots: [],
                leaseProvider: provider)
        }
        #expect(FileManager.default.fileExists(atPath: scratch.unchanged.path))
        if ["incomplete", "unknown", "shared", "stale", "version"].contains(kind) {
            #expect(state.acquisitions == 0)
        }
    }

    @Test("Monotonic deadline expires even when wall time is frozen")
    func monotonicDeadlineDoesNotUseWallTime() throws {
        let scratch = try AuthorityScratch(); defer { scratch.cleanup() }
        let seal = try ResourcePreflight.captureReviewedDirectory(
            at: scratch.derivedData.path, protectedRoots: [])
        let wallNow = Date()
        let association = scratch.association(for: seal, observedAt: wallNow)
        let proof = RuntimeProducerProof(
            adapterID: AppleDerivedDataInventory.adapterID,
            adapterVersion: AppleDerivedDataInventory.contractVersion,
            resource: .filesystem(seal.identity),
            producerIDs: ["fixture.xcode-build-system"], ownerIDs: association.ownerIDs,
            sharedOwnerIDs: [], completeness: .complete,
            observedAt: wallNow, validUntil: wallNow.addingTimeInterval(5),
            method: .producerExclusionLease)
        let acquired = ContinuousClock.now
        #expect(throws: ResourceAuthorityError.staleRuntimeProof) {
            try ResourceAuthorityValidator.validateRuntime(proof,
                association: association, resource: .filesystem(seal.identity),
                adapterID: AppleDerivedDataInventory.adapterID,
                adapterVersion: AppleDerivedDataInventory.contractVersion,
                now: wallNow,
                monotonicAcquiredAt: acquired,
                monotonicDeadline: acquired.advanced(by: .seconds(5)),
                monotonicNow: acquired.advanced(by: .seconds(6)))
        }
    }

    @Test("New hard link symlink and replacement root cannot inherit reviewed authority")
    func hostileIdentityChanges() throws {
        let scratch = try AuthorityScratch(); defer { scratch.cleanup() }
        let seal = try ResourcePreflight.captureReviewedDirectory(at: scratch.derivedData.path, protectedRoots: [])
        let hardlink = scratch.root.appendingPathComponent("hardlink")
        #expect(link(scratch.unchanged.path, hardlink.path) == 0)
        let moved = scratch.root.appendingPathComponent("reviewed-root")
        try FileManager.default.moveItem(at: scratch.derivedData, to: moved)
        try FileManager.default.createDirectory(at: scratch.derivedData, withIntermediateDirectories: true)
        try Data("replacement".utf8).write(to: scratch.derivedData.appendingPathComponent("replacement"))
        let now = Date()
        let association = scratch.association(for: seal, observedAt: now)
        let state = LeaseState(effectWitness: scratch.unchanged)
        let provider = FixtureLeaseProvider(state: state,
            adapterVersion: AppleDerivedDataInventory.contractVersion,
            ownerIDs: association.ownerIDs, observedAt: now, validUntil: now.addingTimeInterval(5))

        #expect(throws: (any Error).self) {
            _ = try DerivedDataEffectAdapter.executeReviewed(seal: seal, association: association,
                currentProtectedRoots: [], leaseProvider: provider)
        }
        #expect(try Data(contentsOf: hardlink) == Data("unchanged".utf8))
        #expect(try Data(contentsOf: scratch.derivedData.appendingPathComponent("replacement")) == Data("replacement".utf8))
    }

    @Test("streamed effect renews leases and stops before the next leaf after cancellation")
    func streamedCancellationUsesFreshLeafAuthority() throws {
        let scratch = try AuthorityScratch(); defer { scratch.cleanup() }
        let seal = try ResourcePreflight.captureReviewedDirectory(
            at: scratch.derivedData.path, protectedRoots: [scratch.protected.path])
        let now = Date()
        let association = scratch.association(for: seal, observedAt: now)
        let state = LeaseState(effectWitness: scratch.unchanged)
        let provider = FixtureLeaseProvider(state: state,
            adapterVersion: AppleDerivedDataInventory.contractVersion,
            ownerIDs: association.ownerIDs, observedAt: now,
            validUntil: now.addingTimeInterval(5))
        let cancellation = EffectCancellationToken()
        let schedule = try FilesystemEffectSchedule(allocatedByteLimit: Int64.max,
            leafLimit: 100, deadline: ContinuousClock.now.advanced(by: .seconds(5)),
            cancellation: cancellation,
            policyBarrier: PolicyInvalidationBarrier(coordinatorID: UUID()),
            policyRevision: 1)
        var outcomes: [TargetEffectOutcome] = []
        let result = try DerivedDataEffectAdapter.streamReviewed(seal: seal,
            association: association, currentProtectedRoots: [scratch.protected.path],
            leaseProvider: provider, schedule: schedule) { outcome in
                outcomes.append(outcome)
                cancellation.cancel()
            }

        #expect(result.stop == .cancelled)
        #expect(result.scheduledLeaves == 1)
        #expect(outcomes.count == 1)
        #expect(state.acquisitions == 1)
        #expect(try Data(contentsOf: scratch.outside) == Data("outside".utf8))
        #expect(try Data(contentsOf: scratch.protected.appendingPathComponent("keep.txt"))
            == Data("protected".utf8))
    }
}

private extension Data {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: self)
    }
}
