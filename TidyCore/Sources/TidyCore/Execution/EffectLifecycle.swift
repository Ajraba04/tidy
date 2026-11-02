import CryptoKit
import Foundation

enum PersistedEffectKind: String, Codable, Sendable {
    case filesystem
    case process
    case service
}

struct ReviewedManifestReference: Codable, Equatable, Sendable {
    static let schemaVersion: UInt32 = 1
    let schema: UInt32
    let id: UUID
    let manifestDigest: Data
    let protectionDigest: Data
    let batchCount: Int
    let artifactCount: Int
    let encodedBytes: Int

    init(id: UUID, manifestDigest: Data, protectionDigest: Data, batchCount: Int,
         artifactCount: Int, encodedBytes: Int) {
        self.schema = Self.schemaVersion
        self.id = id
        self.manifestDigest = manifestDigest
        self.protectionDigest = protectionDigest
        self.batchCount = batchCount
        self.artifactCount = artifactCount
        self.encodedBytes = encodedBytes
    }
}

struct PersistedResourceAssociation: Codable, Equatable, Sendable {
    let adapterID: String
    let adapterVersion: String
    let producerIDs: [String]
    let ownerIDs: [String]
    let sharedOwnerIDs: [String]
    let completeness: String
    let observedAt: Date
    let validUntil: Date
    let method: String

    init(_ evidence: ResourceAssociationEvidence) {
        adapterID = evidence.adapterID
        adapterVersion = evidence.adapterVersion
        producerIDs = evidence.producerIDs.sorted()
        ownerIDs = evidence.ownerIDs.sorted()
        sharedOwnerIDs = evidence.sharedOwnerIDs.sorted()
        completeness = evidence.completeness.rawValue
        observedAt = evidence.observedAt
        validUntil = evidence.validUntil
        method = evidence.method.rawValue
    }

    func restore(resource: ResourceIdentity) throws -> ResourceAssociationEvidence {
        guard let completeness = OwnershipCompleteness(rawValue: completeness),
              let method = AssociationEvidenceMethod(rawValue: method),
              Set(producerIDs).count == producerIDs.count,
              Set(ownerIDs).count == ownerIDs.count,
              Set(sharedOwnerIDs).count == sharedOwnerIDs.count,
              producerIDs == producerIDs.sorted(), ownerIDs == ownerIDs.sorted(),
              sharedOwnerIDs == sharedOwnerIDs.sorted() else {
            throw JournalError.corrupt
        }
        return ResourceAssociationEvidence(adapterID: adapterID,
            adapterVersion: adapterVersion, resource: resource,
            producerIDs: Set(producerIDs), ownerIDs: Set(ownerIDs),
            sharedOwnerIDs: Set(sharedOwnerIDs), completeness: completeness,
            observedAt: observedAt, validUntil: validUntil, method: method)
    }
}

struct FilesystemEffectBinding: Codable, Equatable, Sendable {
    static let schemaVersion: UInt32 = 1
    let schema: UInt32
    let adapterID: String
    let adapterVersion: String
    let planID: UUID
    let planRevision: UInt64
    let policyRevision: UInt64
    let selectedItemID: String
    let targetOrdinal: Int
    let manifest: ReviewedManifestReference
    let association: PersistedResourceAssociation

    init(adapterID: String, adapterVersion: String, planID: UUID,
         planRevision: UInt64, policyRevision: UInt64, selectedItemID: String,
         targetOrdinal: Int, manifest: ReviewedManifestReference,
         association: ResourceAssociationEvidence) {
        schema = Self.schemaVersion
        self.adapterID = adapterID
        self.adapterVersion = adapterVersion
        self.planID = planID
        self.planRevision = planRevision
        self.policyRevision = policyRevision
        self.selectedItemID = selectedItemID
        self.targetOrdinal = targetOrdinal
        self.manifest = manifest
        self.association = PersistedResourceAssociation(association)
    }
}

struct ProcessEffectBinding: Codable, Equatable, Sendable {
    static let schemaVersion: UInt32 = 1
    let schema: UInt32
    let adapterID: String
    let adapterVersion: String
    let operationKey: String
    let executablePath: String
    let executableDevice: UInt64
    let executableInode: UInt64
}

enum PersistedEffectBinding: Codable, Equatable, Sendable {
    case filesystem(FilesystemEffectBinding)
    case process(ProcessEffectBinding)
    case service(ManualServiceEffectBinding)

    var kind: PersistedEffectKind {
        switch self {
        case .filesystem: return .filesystem
        case .process: return .process
        case .service: return .service
        }
    }
}

struct EffectProofReference: Codable, Equatable, Sendable {
    static let schemaVersion: UInt32 = 1
    let schema: UInt32
    let id: UUID
    let operationID: UUID
    let digest: Data
    let encodedBytes: Int

    init(id: UUID, operationID: UUID, digest: Data, encodedBytes: Int) {
        schema = Self.schemaVersion
        self.id = id
        self.operationID = operationID
        self.digest = digest
        self.encodedBytes = encodedBytes
    }
}

struct EffectTerminalProofArchive: Codable, Equatable, Sendable {
    static let schemaVersion: UInt32 = 1
    let schema: UInt32
    let proofID: UUID
    let runID: UUID
    let operationID: UUID
    let adapterID: String
    let adapterVersion: String
    let manifest: ReviewedManifestReference?
    let terminalStatus: EffectStatus
    let outcomeDigest: Data
    let outcomeCount: Int
    let schedulingStop: SchedulingStop?
    let verifiedAt: Date
    let verifier: String
    var service: ManualServiceTerminalArchive? = nil

}

struct EffectOutcomeProofSummary: Sendable {
    private var hash = SHA256()
    private(set) var count = 0
    private var containsUncertain = false
    private var containsRemoval = false
    private var allRemovedSucceeded = true
    private var containsFailed = false
    private var containsCancelled = false

    mutating func append(_ outcome: TargetEffectOutcome) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(outcome)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
        hash.update(data: bytes)
        count += 1
        containsUncertain = containsUncertain || outcome.status == .uncertain
        containsRemoval = containsRemoval || outcome.completedRemovals > 0
        allRemovedSucceeded = allRemovedSucceeded
            && outcome.status == .succeeded && outcome.completedRemovals > 0
        containsFailed = containsFailed || outcome.status == .failed
        containsCancelled = containsCancelled || outcome.status == .cancelled
    }

    var status: EffectStatus {
        if containsUncertain { return .uncertain }
        if containsRemoval { return allRemovedSucceeded ? .succeeded : .partial }
        if containsFailed { return .failed }
        if containsCancelled { return .cancelled }
        return .skipped
    }
    mutating func finalizeDigest() -> Data { Data(hash.finalize()) }
}
private final class EffectOutcomeProofAccumulator {
    var value = EffectOutcomeProofSummary()
    func append(_ outcome: TargetEffectOutcome) throws { try value.append(outcome) }
}

/// A proof value cannot be initialized by callers. Only a compiled verifier
/// that has observed the adapter's terminal protocol can create one.
struct VerifiedEffectTerminalProof: Sendable {
    let archive: EffectTerminalProofArchive
    fileprivate init(archive: EffectTerminalProofArchive) { self.archive = archive }
}

enum CompiledEffectTerminalVerifier {
    private static let filesystemVerifier = "tidy.sync-filesystem.v1"
    private static let neverSubmittedVerifier = "tidy.sync-filesystem.never-submitted.v1"
    private static let serviceNeverSubmittedVerifier = "tidy.manual-service.never-submitted.v1"
    private static let simulatorNeverSpawnedVerifier = "tidy.manual-service.simulator-never-spawned.v1"
    private static let simulatorFixtureNeverSpawnedVerifier = "tidy.manual-service.simulator-fixture-never-spawned.v1"
    private static let simulatorNativeVerifier = "tidy.manual-service.simulator-native.v1"

    private static let simulatorFixtureVerifier = "tidy.manual-service.simulator-owned-fixture.v1"
    private static let dockerRemovalVerifier = "tidy.manual-service.docker-removal.v1"

    static func manualNeverSubmitted(_ receipt: ManualNeverSubmittedReceipt) throws -> VerifiedEffectTerminalProof {
        let digest = try receipt.binding.canonicalDigest()
        var archive = EffectTerminalProofArchive(schema: EffectTerminalProofArchive.schemaVersion,
            proofID: receipt.operationID, runID: receipt.runID, operationID: receipt.operationID,
            adapterID: receipt.binding.operation.adapter.rawValue, adapterVersion: "manual-service-v1",
            manifest: nil, terminalStatus: .cancelled, outcomeDigest: digest, outcomeCount: 0,
            schedulingStop: .cancelled, verifiedAt: Date(), verifier: serviceNeverSubmittedVerifier)
        archive.service = .init(schema: 1, binding: receipt.binding, bindingDigest: digest, kind: .neverSubmitted)
        return VerifiedEffectTerminalProof(archive: archive)
    }

    static func manualDockerReceipt(_ receipt: BoundDockerServiceReceipt) throws -> VerifiedEffectTerminalProof {
        let evidence = DockerServiceTerminalEvidence(receipt: receipt)
        guard evidence.validate(binding: receipt.binding),
              case .container(let object) = receipt.binding.operation.object else { throw JournalError.invalidTransition }
        let absent = "No such container: \(object.id)"
        switch receipt.kind {
        case .removed:
            guard receipt.responseMessage == nil, receipt.postconditionMessage == absent else { throw JournalError.invalidTransition }
        case .alreadyAbsent:
            guard receipt.responseMessage == absent, receipt.postconditionMessage == nil else { throw JournalError.invalidTransition }
        case .refused:
            guard let message = receipt.responseMessage, !message.isEmpty, message.utf8.count <= 4096,
                  receipt.postconditionMessage == nil else { throw JournalError.invalidTransition }
        }
        let digest = try receipt.binding.canonicalDigest()
        var archive = EffectTerminalProofArchive(schema: EffectTerminalProofArchive.schemaVersion,
            proofID: receipt.operationID, runID: receipt.runID, operationID: receipt.operationID,
            adapterID: receipt.binding.operation.adapter.rawValue, adapterVersion: "manual-service-v1",
            manifest: nil, terminalStatus: evidence.terminalStatus, outcomeDigest: digest,
            outcomeCount: evidence.outcomeCount, schedulingStop: nil, verifiedAt: Date(), verifier: dockerRemovalVerifier)
        archive.service = .init(schema: 1, binding: receipt.binding, bindingDigest: digest,
            kind: .dockerRemoval, docker: evidence)
        return VerifiedEffectTerminalProof(archive: archive)
    }

    static func manualSimulatorNeverSpawned(_ receipt: ManualSimulatorNeverSpawnedReceipt) throws -> VerifiedEffectTerminalProof {
        let evidence = SimulatorNeverSpawnedEvidence(receipt: receipt)
        guard evidence.validate(binding: receipt.binding) else { throw JournalError.invalidTransition }
        let digest = try receipt.binding.canonicalDigest()
        var archive = EffectTerminalProofArchive(schema: EffectTerminalProofArchive.schemaVersion,
            proofID: receipt.operationID, runID: receipt.runID, operationID: receipt.operationID,
            adapterID: receipt.binding.operation.adapter.rawValue, adapterVersion: "manual-service-v1",
            manifest: nil, terminalStatus: .failed, outcomeDigest: digest, outcomeCount: 0,
            schedulingStop: nil, verifiedAt: Date(),
            verifier: evidence.isFixture ? simulatorFixtureNeverSpawnedVerifier : simulatorNeverSpawnedVerifier)
        archive.service = .init(schema: 1, binding: receipt.binding, bindingDigest: digest,
            kind: .simulatorNeverSpawned, rejectedSpawn: evidence)
        return VerifiedEffectTerminalProof(archive: archive)
    }

    static func manualSimulatorNativeReceipt(_ receipt: NativeSimulatorServiceReceipt) throws -> VerifiedEffectTerminalProof {
        try AppleSimulatorOperation.requireAcceptedProducer(for: receipt.binding.operation)
        guard receipt.terminalVerificationLease.sessionID == receipt.childSessionID,
              receipt.terminalVerificationLease.ownedIdentity == receipt.childIdentity,
              receipt.terminalVerificationLease.rawStatus == receipt.rawWaitStatus else { throw JournalError.invalidTransition }
        try receipt.terminalVerificationLease.checkValidity()
        let evidence = SimulatorNativeTerminalEvidence(receipt: receipt)
        guard evidence.validate(binding: receipt.binding) else { throw JournalError.invalidTransition }
        let digest = try receipt.binding.canonicalDigest()
        var archive = EffectTerminalProofArchive(schema: EffectTerminalProofArchive.schemaVersion,
            proofID: receipt.operationID, runID: receipt.runID, operationID: receipt.operationID,
            adapterID: receipt.binding.operation.adapter.rawValue, adapterVersion: "manual-service-v1",
            manifest: nil, terminalStatus: .succeeded, outcomeDigest: digest, outcomeCount: 1,
            schedulingStop: nil, verifiedAt: Date(), verifier: simulatorNativeVerifier)
        archive.service = .init(schema: 1, binding: receipt.binding, bindingDigest: digest,
            kind: .simulatorNative, nativeSimulator: evidence)
        return VerifiedEffectTerminalProof(archive: archive)
    }

    static func manualSimulatorFixtureReceipt(_ receipt: BoundSimulatorServiceReceipt) throws -> VerifiedEffectTerminalProof {
        guard receipt.invocationOrigin == .cooperativeFixture,
              receipt.terminalVerificationLease.sessionID == receipt.childSessionID,
              receipt.terminalVerificationLease.ownedIdentity == receipt.childIdentity,
              receipt.terminalVerificationLease.rawStatus == receipt.rawWaitStatus else {
            throw JournalError.invalidTransition
        }
        let evidence = SimulatorFixtureTerminalEvidence(receipt: receipt)
        guard evidence.validate(binding: receipt.binding) else { throw JournalError.invalidTransition }
        let digest = try receipt.binding.canonicalDigest()
        var archive = EffectTerminalProofArchive(schema: EffectTerminalProofArchive.schemaVersion,
            proofID: receipt.operationID, runID: receipt.runID, operationID: receipt.operationID,
            adapterID: receipt.binding.operation.adapter.rawValue, adapterVersion: "manual-service-v1",
            manifest: nil, terminalStatus: .succeeded, outcomeDigest: digest,
            outcomeCount: 1, schedulingStop: nil, verifiedAt: Date(), verifier: simulatorFixtureVerifier)
        archive.service = .init(schema: 1, binding: receipt.binding, bindingDigest: digest,
            kind: .simulatorOwnedFixture, simulator: evidence)
        return VerifiedEffectTerminalProof(archive: archive)
    }

    private static func validServiceArchive(_ archive: EffectTerminalProofArchive) -> Bool {
        guard let service = archive.service, service.validate(),
              archive.schema == EffectTerminalProofArchive.schemaVersion,
              archive.proofID == archive.operationID, archive.manifest == nil,
              archive.adapterVersion == "manual-service-v1",
              archive.adapterID == service.binding.operation.adapter.rawValue,
              archive.outcomeDigest == service.bindingDigest else { return false }
        switch service.kind {
        case .neverSubmitted:
            return archive.outcomeCount == 0 && archive.terminalStatus == .cancelled
                && archive.schedulingStop == .cancelled && archive.verifier == serviceNeverSubmittedVerifier
        case .dockerRemoval:
            guard let evidence = service.docker else { return false }
            return archive.verifier == dockerRemovalVerifier && archive.schedulingStop == nil
                && archive.outcomeCount == evidence.outcomeCount && archive.terminalStatus == evidence.terminalStatus
        case .simulatorOwnedFixture:
            guard let evidence = service.simulator else { return false }
            return archive.verifier == simulatorFixtureVerifier && archive.schedulingStop == nil
                && archive.outcomeCount == 1 && archive.terminalStatus == .succeeded
                && evidence.runID == archive.runID && evidence.operationID == archive.operationID
        case .simulatorNeverSpawned:
            guard let evidence = service.rejectedSpawn else { return false }
            return archive.verifier == (evidence.isFixture ? simulatorFixtureNeverSpawnedVerifier : simulatorNeverSpawnedVerifier)
                && archive.schedulingStop == nil && archive.outcomeCount == 0 && archive.terminalStatus == .failed
                && evidence.runID == archive.runID && evidence.operationID == archive.operationID
        case .simulatorNative:
            guard let evidence = service.nativeSimulator else { return false }
            return archive.verifier == simulatorNativeVerifier && archive.schedulingStop == nil
                && archive.outcomeCount == 1 && archive.terminalStatus == .succeeded
                && evidence.runID == archive.runID && evidence.operationID == archive.operationID
        }
    }

    fileprivate static func synchronousFilesystem(runID: UUID, operationID: UUID,
                                                  binding: FilesystemEffectBinding,
                                                  summary: EffectOutcomeProofSummary,
                                                  streamed: StreamedFilesystemEffect,
                                                  now: Date) throws
        -> VerifiedEffectTerminalProof {
        guard binding.schema == FilesystemEffectBinding.schemaVersion,
              binding.adapterID == AppleDerivedDataInventory.adapterID,
              binding.adapterVersion == AppleDerivedDataInventory.contractVersion,
              summary.count == streamed.scheduledLeaves,
              summary.count > 0 || streamed.stop != nil else {
            throw JournalError.invalidTransition
        }
        var summary = summary
        let digest = summary.finalizeDigest()
        let status: EffectStatus
        if summary.count == 0 {
            status = streamed.stop == .cancelled ? .cancelled : .skipped
        } else if streamed.stop != nil, summary.status == .succeeded {
            status = .partial
        } else {
            status = summary.status
        }
        let verifier = summary.count == 0 ? neverSubmittedVerifier : filesystemVerifier
        let archive = EffectTerminalProofArchive(schema: EffectTerminalProofArchive.schemaVersion,
            proofID: UUID(), runID: runID, operationID: operationID,
            adapterID: binding.adapterID, adapterVersion: binding.adapterVersion,
            manifest: binding.manifest, terminalStatus: status,
            outcomeDigest: digest, outcomeCount: summary.count,
            schedulingStop: streamed.stop,
            verifiedAt: now, verifier: verifier)
        return VerifiedEffectTerminalProof(archive: archive)
    }

    static func validate(_ archive: EffectTerminalProofArchive,
                         intent: PendingEffectIntent) -> Bool {
        if case .service(let binding)? = intent.binding {
            let expectedPhase: SubmissionPhase = archive.service?.kind == .neverSubmitted ? .prepared : .submitted
            let childMatches = archive.service?.kind != .simulatorOwnedFixture
                || archive.service?.simulator?.matchesChild(intent) == true
            let noChild = archive.service?.kind != .simulatorNeverSpawned
                || archive.service?.rejectedSpawn?.matchesUnspawnedIntent(intent) == true
            let nativeChildMatches = archive.service?.kind != .simulatorNative
                || archive.service?.nativeSimulator?.matchesChild(intent) == true
            return childMatches && nativeChildMatches && noChild && intent.schemaVersion == 3 && intent.phase == expectedPhase
                && archive.runID == intent.runID && archive.operationID == intent.operationID
                && archive.service?.binding == binding && validServiceArchive(archive)
        }
        guard archive.schema == EffectTerminalProofArchive.schemaVersion,
              archive.service == nil,
              archive.runID == intent.runID, archive.operationID == intent.operationID,
              archive.outcomeCount >= 0,
              archive.outcomeDigest.count == SHA256.Digest.byteCount,
              case .filesystem(let binding)? = intent.binding,
              archive.adapterID == binding.adapterID,
              archive.adapterVersion == binding.adapterVersion,
              archive.manifest == binding.manifest else { return false }
        if archive.outcomeCount == 0 {
            guard archive.verifier == neverSubmittedVerifier,
                  archive.schedulingStop != nil,
                  archive.terminalStatus == .cancelled
                    || archive.terminalStatus == .skipped else { return false }
        } else {
            guard archive.verifier == filesystemVerifier else { return false }
        }
        return archive.terminalStatus != .uncertain
    }

    static func validateHistorical(_ archive: EffectTerminalProofArchive,
                                   reference: EffectProofReference) -> Bool {
        if archive.service != nil {
            return archive.proofID == reference.id && archive.operationID == reference.operationID
                && validServiceArchive(archive)
        }
        let base = archive.schema == EffectTerminalProofArchive.schemaVersion
            && archive.proofID == reference.id
            && archive.operationID == reference.operationID
            && archive.outcomeCount >= 0
            && archive.outcomeDigest.count == SHA256.Digest.byteCount
            && archive.terminalStatus != .uncertain
            && archive.manifest != nil
        guard base else { return false }
        if archive.outcomeCount == 0 {
            return archive.verifier == neverSubmittedVerifier
                && archive.schedulingStop != nil
                && (archive.terminalStatus == .cancelled
                    || archive.terminalStatus == .skipped)
        }
        return archive.verifier == filesystemVerifier
    }
}

public enum RecoveryReconciliationDisposition: String, Equatable, Sendable {
    case noUnfinishedEffects
    case blocked
    case requireFreshReview
    case storageUnavailable
}

public struct RecoveryReconciliationReport: Equatable, Sendable {
    public let disposition: RecoveryReconciliationDisposition
    public let inspectedEffects: Int
    public let reconciledEffects: Int
}

public enum ExecutionProgressPhase: String, Equatable, Sendable {
    case idle
    case preparing
    case executing
    case reconciling
    case blocked
}

public struct ExecutionProgressSnapshot: Equatable, Sendable {
    public let runID: UUID?
    public let phase: ExecutionProgressPhase
    public let completedEffects: Int
    public let scheduledEffects: Int
    public let cancellationRequested: Bool
    public let recovery: MutationAdmission
}

final class EffectCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false
    private var observers: [UUID: @Sendable () -> Void] = [:]
    func cancel() {
        let callbacks: [@Sendable () -> Void] = lock.withLock {
            requested = true
            let values = Array(observers.values)
            observers.removeAll()
            return values
        }
        // Never invoke a gate callback while holding the token's lock.
        for callback in callbacks { callback() }
    }
    var isCancelled: Bool { lock.withLock { requested } }
    func observeCancellation(_ callback: @escaping @Sendable () -> Void) throws -> UUID? {
        let id: UUID? = try lock.withLock {
            if requested { return nil }
            guard observers.count < 16 else { throw POSIXError(.EAGAIN) }
            let id = UUID(); observers[id] = callback; return id
        }
        if id == nil { callback() }
        return id
    }
    func removeCancellationObserver(_ id: UUID) { _ = lock.withLock { observers.removeValue(forKey: id) } }
}

final class ExecutionCancellationRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var token: EffectCancellationToken?
    func install(_ token: EffectCancellationToken) {
        lock.withLock { self.token = token }
    }
    func cancel() { lock.withLock { token?.cancel() } }
    func clear(_ expected: EffectCancellationToken) {
        lock.withLock {
            if token === expected { token = nil }
        }
    }
    var isCancelled: Bool { lock.withLock { token?.isCancelled ?? false } }
}

struct FilesystemEffectSchedule: Sendable {
    let allocatedByteLimit: Int64
    let leafLimit: Int
    let deadline: ContinuousClock.Instant
    let cancellation: EffectCancellationToken
    let policyBarrier: PolicyInvalidationBarrier
    let policyRevision: UInt64

    init(allocatedByteLimit: Int64, leafLimit: Int,
         deadline: ContinuousClock.Instant,
         cancellation: EffectCancellationToken,
         policyBarrier: PolicyInvalidationBarrier, policyRevision: UInt64) throws {
        guard allocatedByteLimit >= 0, leafLimit > 0 else {
            throw GuardedFileError.invalidBudget
        }
        self.allocatedByteLimit = allocatedByteLimit
        self.leafLimit = leafLimit
        self.deadline = deadline
        self.cancellation = cancellation
        self.policyBarrier = policyBarrier
        self.policyRevision = policyRevision
    }
}

struct StreamedFilesystemEffect: Sendable {
    let freeSpaceBeforeBytes: Int64?
    let freeSpaceAfterBytes: Int64?
    let scheduledLeaves: Int
    let deadlineOverruns: Int
    let stop: SchedulingStop?
}

struct PreparedFilesystemEffect: Sendable {
    let runID: UUID
    let operationID: UUID
    let binding: FilesystemEffectBinding
}
struct CompletedFilesystemEffect: Sendable {
    let proof: EffectProofReference
    let streamed: StreamedFilesystemEffect
    let status: EffectStatus
}

/// Durable ordering for one synchronous filesystem effect. The effect closure
/// runs only after the manifest, intent, and started event are durable. A
/// thrown or interrupted effect leaves the intent unresolved and blocking.
final class FilesystemEffectLifecycle {
    private let journal: RunJournal
    init(journal: RunJournal) { self.journal = journal }

    func prepare(runID: UUID, operationID: UUID, planID: UUID,
                 planRevision: UInt64, policyRevision: UInt64,
                 selectedItemID: String, targetOrdinal: Int,
                 reviewed: ReviewedFileResource,
                 association: ResourceAssociationEvidence) throws
        -> PreparedFilesystemEffect {
        let manifest = try journal.prepareReviewedManifest(reviewed)
        let reference = manifest.reference
        let binding = FilesystemEffectBinding(adapterID: association.adapterID,
            adapterVersion: association.adapterVersion, planID: planID,
            planRevision: planRevision, policyRevision: policyRevision,
            selectedItemID: selectedItemID, targetOrdinal: targetOrdinal,
            manifest: reference, association: association)
        let intent = PendingEffectIntent(runID: runID, operationID: operationID,
            filesystem: binding)
        try journal.persistIntent(intent)
        try journal.publishReviewedManifest(manifest)
        let previous = try journal.events(runID: runID)
        try journal.append(JournalEvent(runID: runID,
            sequence: try JournalSequence.next(after: previous.last?.sequence ?? 0),
            phase: .started, operationID: operationID, status: nil, reason: nil))
        return PreparedFilesystemEffect(runID: runID,
            operationID: operationID, binding: binding)
    }

    func execute(_ prepared: PreparedFilesystemEffect,
                 reviewed: ReviewedFileResource,
                 association: ResourceAssociationEvidence,
                 currentProtectedRoots: [String],
                 leaseProvider: any ProducerExclusionLeaseProviding,
                 schedule: FilesystemEffectSchedule,
                 now: Date = Date()) throws -> CompletedFilesystemEffect {
        guard reviewed.identity.manifest?.digest == prepared.binding.manifest.manifestDigest,
              PersistedResourceAssociation(association) == prepared.binding.association else {
            throw JournalError.invalidTransition
        }
        let accumulator = EffectOutcomeProofAccumulator()
        let streamed = try DerivedDataEffectAdapter.streamPersistedReviewed(
            seal: reviewed, reference: prepared.binding.manifest,
            association: association, currentProtectedRoots: currentProtectedRoots,
            leaseProvider: leaseProvider, schedule: schedule,
            forEachBatchReversed: { body in
                try journal.forEachReviewedBatch(prepared.binding.manifest,
                    reversed: true, body)
            }) { try accumulator.append($0) }
        let summary = accumulator.value
        let status: EffectStatus
        if summary.count == 0 {
            status = streamed.stop == .cancelled ? .cancelled : .skipped
        } else if streamed.stop != nil, summary.status == .succeeded {
            status = .partial
        } else {
            status = summary.status
        }
        let proof = try recordTerminal(prepared, summary: summary,
            streamed: streamed, now: now)
        return CompletedFilesystemEffect(proof: proof, streamed: streamed, status: status)
    }

    private func recordTerminal(_ prepared: PreparedFilesystemEffect,
                                summary: EffectOutcomeProofSummary,
                                streamed: StreamedFilesystemEffect,
                                now: Date) throws
        -> EffectProofReference {
        let verified = try CompiledEffectTerminalVerifier.synchronousFilesystem(
            runID: prepared.runID, operationID: prepared.operationID,
            binding: prepared.binding, summary: summary,
            streamed: streamed, now: now)
        let proof = try journal.persistTerminalProof(verified)
        let previous = try journal.events(runID: prepared.runID)
        try journal.append(JournalEvent(runID: prepared.runID,
            sequence: try JournalSequence.next(after: previous.last?.sequence ?? 0),
            phase: .itemTerminal, operationID: prepared.operationID,
            status: verified.archive.terminalStatus,
            reason: streamed.stop.map { "Stopped before next leaf: \($0)" },
            proof: proof))
        return proof
    }

    func finish(runID: UUID) throws { try journal.finish(runID: runID) }
}
