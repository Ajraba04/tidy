import Darwin
import Foundation
import Testing
@testable import TidyCore

private final class LifecycleLease: ProducerExclusionLease, @unchecked Sendable {
    let proof: RuntimeProducerProof
    let acquiredAt: ContinuousClock.Instant
    let deadline: ContinuousClock.Instant
    init(resource: ResourceIdentity, owners: Set<String>, observedAt: Date) {
        acquiredAt = .now
        deadline = acquiredAt.advanced(by: .seconds(5))
        proof = RuntimeProducerProof(adapterID: AppleDerivedDataInventory.adapterID,
            adapterVersion: AppleDerivedDataInventory.contractVersion,
            resource: resource, producerIDs: ["fixture.producer"],
            ownerIDs: owners, sharedOwnerIDs: [], completeness: .complete,
            observedAt: observedAt, validUntil: observedAt.addingTimeInterval(5),
            method: .producerExclusionLease)
    }
}

private struct LifecycleLeaseProvider: ProducerExclusionLeaseProviding {
    let owners: Set<String>
    func acquireLease(for resource: ResourceIdentity) throws -> any ProducerExclusionLease {
        LifecycleLease(resource: resource, owners: owners, observedAt: Date())
    }
}

@Suite("Durable effect lifecycle", .serialized)
struct EffectLifecycleTests {
    private struct Fixture {
        let root: URL
        let journal: URL
        let target: URL
        let reviewed: ReviewedFileResource
        let association: ResourceAssociationEvidence
        init() throws {
            guard let resolved = realpath(FileManager.default.temporaryDirectory.path, nil) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            defer { free(resolved) }
            let temporary = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
            root = temporary
                .appendingPathComponent("Tidy-Effect-Lifecycle-\(UUID())", isDirectory: true)
            journal = root.appendingPathComponent("journal", isDirectory: true)
            target = root.appendingPathComponent(
                "home/Library/Developer/Xcode/DerivedData", isDirectory: true)
            try FileManager.default.createDirectory(at: journal,
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: target.appendingPathComponent("Build"),
                withIntermediateDirectories: true)
            try Data("object".utf8).write(to: target.appendingPathComponent("Build/a.o"))
            reviewed = try ResourcePreflight.captureReviewedDirectory(
                at: target.path, protectedRoots: [])
            let now = Date()
            association = ResourceAssociationEvidence(
                adapterID: AppleDerivedDataInventory.adapterID,
                adapterVersion: AppleDerivedDataInventory.contractVersion,
                resource: .filesystem(reviewed.identity),
                producerIDs: ["fixture.producer"], ownerIDs: ["fixture.owner"],
                sharedOwnerIDs: [], completeness: .complete,
                observedAt: now, validUntil: now.addingTimeInterval(60),
                method: .producerManifest)
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    @Test("terminal proof is durable before intent retirement and finished history remains valid")
    func synchronousFilesystemLifecycle() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let admission = try MutationAdmissionStore(directory: fixture.journal)
        #expect(admission.acquire() == .ready)
        defer { admission.release() }
        let journal = try RunJournal(store: admission,
            storage: DurableJournalStorage(directory: fixture.journal))
        let runID = UUID(), operationID = UUID()
        try journal.append(JournalEvent(runID: runID, sequence: 1,
            phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(JournalEvent(runID: runID, sequence: 2,
            phase: .confirmed, operationID: nil, status: nil, reason: nil))
        let lifecycle = FilesystemEffectLifecycle(journal: journal)
        let prepared = try lifecycle.prepare(runID: runID, operationID: operationID,
            planID: UUID(), planRevision: 1, policyRevision: 1,
            selectedItemID: DerivedDataEffectAdapter.acceptedItemID, targetOrdinal: 0,
            reviewed: fixture.reviewed, association: fixture.association)
        #expect(admission.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)

        let barrier = PolicyInvalidationBarrier(coordinatorID: UUID())
        let schedule = try FilesystemEffectSchedule(allocatedByteLimit: Int64.max,
            leafLimit: 100, deadline: ContinuousClock.now.advanced(by: .seconds(5)),
            cancellation: EffectCancellationToken(), policyBarrier: barrier,
            policyRevision: 1)
        _ = try lifecycle.execute(prepared, reviewed: fixture.reviewed,
            association: fixture.association, currentProtectedRoots: [],
            leaseProvider: LifecycleLeaseProvider(owners: ["fixture.owner"]),
            schedule: schedule)
        #expect(admission.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
        try lifecycle.finish(runID: runID)

        #expect(admission.readAdmissionWhileLocked() == .ready)
        #expect(try journal.events(runID: runID).last?.phase == .finished)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.target.appendingPathComponent("Build/a.o").path))
        var names = try FileManager.default.contentsOfDirectory(atPath: fixture.journal.path)
        #expect(names.contains { $0.hasPrefix("effect-manifest-") })
        #expect(names.contains { $0.hasPrefix("effect-proof-") })
        try journal.applyHistoryLimits(days: 1, bytes: 1_048_576,
                                       now: .distantFuture)
        names = try FileManager.default.contentsOfDirectory(atPath: fixture.journal.path)
        #expect(!names.contains { $0.hasPrefix("effect-manifest-")
            || $0.hasPrefix("effect-proof-") || $0.hasPrefix(".effect-stage-") })
    }

    @Test("crash after durable start remains blocked and never replays the effect")
    func unfinishedFilesystemIntentRemainsBlocked() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let admission = try MutationAdmissionStore(directory: fixture.journal)
        #expect(admission.acquire() == .ready)
        let journal = try RunJournal(store: admission,
            storage: DurableJournalStorage(directory: fixture.journal))
        let runID = UUID()
        try journal.append(JournalEvent(runID: runID, sequence: 1,
            phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(JournalEvent(runID: runID, sequence: 2,
            phase: .confirmed, operationID: nil, status: nil, reason: nil))
        let lifecycle = FilesystemEffectLifecycle(journal: journal)
        _ = try lifecycle.prepare(runID: runID, operationID: UUID(), planID: UUID(),
            planRevision: 1, policyRevision: 1,
            selectedItemID: DerivedDataEffectAdapter.acceptedItemID, targetOrdinal: 0,
            reviewed: fixture.reviewed, association: fixture.association)
        admission.release()

        let reopened = try MutationAdmissionStore(directory: fixture.journal)
        #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
        reopened.release()
        #expect(try Data(contentsOf: fixture.target.appendingPathComponent("Build/a.o"))
            == Data("object".utf8))
    }
}
