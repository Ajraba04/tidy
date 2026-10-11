import CryptoKit
import Foundation

/// Persisted provenance, not authority. Legacy records keep their old schemas.
struct ManualServiceEffectBinding: Codable, Equatable, Sendable {
    static let schemaVersion: UInt32 = 1
    let schema: UInt32
    let reviewID: UUID
    let coordinatorID: UUID
    let policyRevision: UInt64
    let authorityRevision: UInt64
    let installation: LocalInstallationIdentity
    let operation: ManualServiceOperationBinding

    init(reviewID: UUID, coordinatorID: UUID, policyRevision: UInt64,
         authorityRevision: UInt64, installation: LocalInstallationIdentity,
         operation: ManualServiceOperationBinding) throws {
        schema = Self.schemaVersion; self.reviewID = reviewID; self.coordinatorID = coordinatorID
        self.policyRevision = policyRevision; self.authorityRevision = authorityRevision
        self.installation = installation; self.operation = operation
        try validate()
    }
    func validate() throws {
        guard schema == Self.schemaVersion, policyRevision > 0, authorityRevision > 0,
              installation.directoryInode > 0 else { throw JournalError.corrupt }
        try ManualServiceValueBounds.path(installation.canonicalDirectoryPath)
        _ = try operation.canonicalDigest()
    }
    func canonicalDigest() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= 65_536 else { throw JournalError.capacity }
        return Data(SHA256.hash(data: bytes))
    }
}

extension ManualServiceEffectBinding {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(UInt32.self, forKey: .schema)
        reviewID = try c.decode(UUID.self, forKey: .reviewID)
        coordinatorID = try c.decode(UUID.self, forKey: .coordinatorID)
        policyRevision = try c.decode(UInt64.self, forKey: .policyRevision)
        authorityRevision = try c.decode(UInt64.self, forKey: .authorityRevision)
        installation = try c.decode(LocalInstallationIdentity.self, forKey: .installation)
        operation = try c.decode(ManualServiceOperationBinding.self, forKey: .operation)
        try validate()
    }
}

struct ManualServiceTerminalArchive: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case neverSubmitted, dockerRemoval, simulatorOwnedFixture, simulatorNeverSpawned, simulatorNative }
    let schema: UInt32
    let binding: ManualServiceEffectBinding
    let bindingDigest: Data
    let kind: Kind
    var docker: DockerServiceTerminalEvidence? = nil
    var simulator: SimulatorFixtureTerminalEvidence? = nil
    var rejectedSpawn: SimulatorNeverSpawnedEvidence? = nil
    var nativeSimulator: SimulatorNativeTerminalEvidence? = nil
    func validate() -> Bool {
        guard schema == 1, (try? binding.canonicalDigest()) == bindingDigest else { return false }
        switch kind {
        case .neverSubmitted: return docker == nil && simulator == nil && rejectedSpawn == nil && nativeSimulator == nil
        case .dockerRemoval: return simulator == nil && rejectedSpawn == nil && nativeSimulator == nil && docker?.validate(binding: binding) == true
        case .simulatorOwnedFixture: return docker == nil && rejectedSpawn == nil && nativeSimulator == nil && simulator?.validate(binding: binding) == true
        case .simulatorNeverSpawned: return docker == nil && simulator == nil && nativeSimulator == nil && rejectedSpawn?.validate(binding: binding) == true
        case .simulatorNative: return docker == nil && simulator == nil && rejectedSpawn == nil && nativeSimulator?.validate(binding: binding) == true
        }
    }
}

/// The native verifier reconstructs the fixed shutdown declaration rather than
/// accepting the cooperative fixture's command digest or current device state.
struct SimulatorNativeTerminalEvidence: Codable, Equatable, Sendable {
    let runID: UUID
    let operationID: UUID
    let invocationDigest: Data
    let childSessionID: UUID
    let childIdentity: ProcessInstanceIdentity
    let rawWaitStatus: Int32
    let observedDevice: ManualSimulatorObject
    let postconditionDigest: Data

    init(receipt: NativeSimulatorServiceReceipt) {
        runID = receipt.runID; operationID = receipt.operationID
        invocationDigest = receipt.invocationDigest; childSessionID = receipt.childSessionID
        childIdentity = receipt.childIdentity; rawWaitStatus = receipt.rawWaitStatus
        observedDevice = receipt.observedDevice; postconditionDigest = receipt.postconditionDigest
    }
    func validate(binding: ManualServiceEffectBinding) -> Bool {
        guard let (reviewed, producer) = try? ManualSimulatorShutdownInvocation.simulatorBinding(binding),
              let invocation = try? ManualSimulatorShutdownInvocation.describe(binding: binding,
                runID: runID, operationID: operationID), invocation.invocationDigest == invocationDigest,
              rawWaitStatus == 0, childIdentity.pid > 0, childIdentity.startSeconds >= 0,
              (0..<1_000_000).contains(childIdentity.startMicroseconds),
              childIdentity.executablePath == producer.simctl.canonicalPath,
              childIdentity.executableDevice == producer.simctl.device,
              childIdentity.executableInode == producer.simctl.inode,
              postconditionDigest.count == SHA256.Digest.byteCount,
              observedDevice.udid == reviewed.udid, observedDevice.runtimeIdentifier == reviewed.runtimeIdentifier,
              observedDevice.deviceTypeIdentifier == reviewed.deviceTypeIdentifier,
              observedDevice.name == reviewed.name, observedDevice.isAvailable, observedDevice.state == .shutdown else { return false }
        return true
    }
    func matchesChild(_ intent: PendingEffectIntent) -> Bool {
        intent.bootID == childIdentity.bootID && intent.childPID == childIdentity.pid
            && intent.childStartSeconds == childIdentity.startSeconds
            && intent.childStartMicroseconds == childIdentity.startMicroseconds
            && intent.executablePath == childIdentity.executablePath
            && intent.executableDevice == childIdentity.executableDevice
            && intent.executableInode == childIdentity.executableInode
    }
}

/// Persisted observation of the sole launcher receiving a rejected posix_spawn.
/// The sealed receipt is required to create a proof; decoding this data does not
/// grant that authority. Fixture and native origin remain distinct forever.
struct SimulatorNeverSpawnedEvidence: Codable, Equatable, Sendable {
    let runID: UUID
    let operationID: UUID
    let invocationDigest: Data
    let invocationOrigin: ManualSimulatorSubmissionHook.Origin
    let attemptedExecutablePath: String
    let submissionHookAttempts: Int
    let posixErrorCode: Int32

    init(receipt: ManualSimulatorNeverSpawnedReceipt) {
        runID = receipt.runID; operationID = receipt.operationID
        invocationDigest = receipt.invocationDigest; invocationOrigin = receipt.invocationOrigin
        attemptedExecutablePath = receipt.attemptedExecutablePath
        submissionHookAttempts = receipt.submissionHookAttempts; posixErrorCode = receipt.posixErrorCode
    }
    var isFixture: Bool { invocationOrigin != .nativeShutdown }
    func validate(binding: ManualServiceEffectBinding) -> Bool {
        guard submissionHookAttempts == 1, posixErrorCode > 0, posixErrorCode <= 4095,
              let (_, producer) = try? ManualSimulatorShutdownInvocation.simulatorBinding(binding) else { return false }
        let declaration: ManualSimulatorShutdownInvocation?
        switch invocationOrigin {
        case .nativeShutdown:
            guard attemptedExecutablePath == producer.simctl.canonicalPath else { return false }
            declaration = try? .describe(binding: binding, runID: runID, operationID: operationID)
        case .cooperativeFixture, .rejectedSpawnFixture:
            let fixedPath = invocationOrigin == .cooperativeFixture ? "/bin/cat"
                : binding.installation.canonicalDirectoryPath + "/.tidy-fixed-absent-executable"
            guard attemptedExecutablePath == fixedPath else { return false }
            declaration = try? .cooperativeFixture(binding: binding, runID: runID,
                operationID: operationID, executable: producer.simctl)
        }
        guard let declaration else { return false }
        return invocationDigest == (try? ManualSimulatorSubmissionCommit.digest(
            declarationDigest: declaration.invocationDigest, origin: invocationOrigin,
            attemptedExecutablePath: attemptedExecutablePath))
    }
    func matchesUnspawnedIntent(_ intent: PendingEffectIntent) -> Bool {
        intent.bootID == nil && intent.childPID == nil && intent.childStartSeconds == nil
            && intent.childStartMicroseconds == nil && intent.executablePath == nil
            && intent.executableDevice == nil && intent.executableInode == nil
    }
}

/// Only bounded digests and compiled result categories are persisted. Producer
/// error text is intentionally absent from the durable proof.
struct DockerServiceTerminalEvidence: Codable, Equatable, Sendable {
    let kind: BoundDockerServiceReceipt.Kind
    let requestDigest: Data
    let responseStatus: Int
    let responseBodyDigest: Data
    let postconditionStatus: Int?
    let postconditionBodyDigest: Data?
    let observedPeer: ProcessInstanceIdentity
    let observedSocket: LocalSocketApproval

    init(receipt: BoundDockerServiceReceipt) {
        kind = receipt.kind; requestDigest = receipt.requestDigest
        responseStatus = receipt.responseStatus; responseBodyDigest = receipt.responseBodyDigest
        postconditionStatus = receipt.postconditionStatus
        postconditionBodyDigest = receipt.postconditionBodyDigest
        observedPeer = receipt.observedPeer; observedSocket = receipt.observedSocket
    }
    var terminalStatus: EffectStatus {
        switch kind { case .removed: return .succeeded; case .refused: return .failed; case .alreadyAbsent: return .skipped }
    }
    var outcomeCount: Int { kind == .removed ? 1 : 0 }
    func validate(binding: ManualServiceEffectBinding) -> Bool {
        guard binding.operation.adapter == .dockerStoppedContainerRemovalV1,
              case .container(let object) = binding.operation.object,
              case .docker(let producer) = binding.operation.producer,
              observedSocket == producer.socket, observedSocket.ownerUID == producer.peerUID,
              observedPeer.pid == producer.peerPID, observedPeer.bootID == producer.peerBootID,
              observedPeer.startSeconds == producer.peerStartSeconds,
              observedPeer.startMicroseconds == producer.peerStartMicroseconds,
              observedPeer.executablePath == producer.peerExecutable.canonicalPath,
              observedPeer.executableDevice == producer.peerExecutable.device,
              observedPeer.executableInode == producer.peerExecutable.inode,
              let request = try? DockerHTTPRequest.removeContainer(apiVersion: producer.version.apiVersion, id: object.id),
              requestDigest == Data(SHA256.hash(data: request)),
              responseBodyDigest.count == SHA256.Digest.byteCount else { return false }
        switch kind {
        case .removed:
            return responseStatus == 204 && responseBodyDigest == Data(SHA256.hash(data: Data()))
                && postconditionStatus == 404 && postconditionBodyDigest?.count == SHA256.Digest.byteCount
        case .refused:
            return responseStatus == 409 && postconditionStatus == nil && postconditionBodyDigest == nil
        case .alreadyAbsent:
            return responseStatus == 404 && postconditionStatus == nil && postconditionBodyDigest == nil
        }
    }
}

/// Explicit cooperative-fixture evidence. Its verifier identity and fixed cat
/// invocation cannot be interpreted as a native simulator contract or activation.
struct SimulatorFixtureTerminalEvidence: Codable, Equatable, Sendable {
    let runID: UUID
    let operationID: UUID
    let invocationDigest: Data
    let childSessionID: UUID
    let childIdentity: ProcessInstanceIdentity
    let rawWaitStatus: Int32
    let observedDevice: ManualSimulatorObject
    let postconditionDigest: Data

    init(receipt: BoundSimulatorServiceReceipt) {
        runID = receipt.runID; operationID = receipt.operationID
        invocationDigest = receipt.invocationDigest; childSessionID = receipt.childSessionID
        childIdentity = receipt.childIdentity; rawWaitStatus = receipt.rawWaitStatus
        observedDevice = receipt.observedDevice; postconditionDigest = receipt.postconditionDigest
    }
    func validate(binding: ManualServiceEffectBinding) -> Bool {
        guard binding.operation.adapter == .appleSimulatorShutdownV1,
              case .simulator(let reviewed) = binding.operation.object,
              case .appleSimulator(let producer) = binding.operation.producer,
              producer.simctl.canonicalPath == "/bin/cat",
              let invocation = try? ManualSimulatorShutdownInvocation.cooperativeFixture(binding: binding,
                runID: runID, operationID: operationID, executable: producer.simctl),
              invocationDigest == invocation.invocationDigest,
              rawWaitStatus == 0, childIdentity.pid > 0, childIdentity.startSeconds >= 0,
              (0..<1_000_000).contains(childIdentity.startMicroseconds),
              childIdentity.executablePath == producer.simctl.canonicalPath,
              childIdentity.executableDevice == producer.simctl.device,
              childIdentity.executableInode == producer.simctl.inode,
              postconditionDigest.count == SHA256.Digest.byteCount,
              observedDevice.udid == reviewed.udid,
              observedDevice.runtimeIdentifier == reviewed.runtimeIdentifier,
              observedDevice.deviceTypeIdentifier == reviewed.deviceTypeIdentifier,
              observedDevice.name == reviewed.name, observedDevice.isAvailable,
              observedDevice.state == .shutdown else { return false }
        return true
    }
    func matchesChild(_ intent: PendingEffectIntent) -> Bool {
        intent.bootID == childIdentity.bootID && intent.childPID == childIdentity.pid
            && intent.childStartSeconds == childIdentity.startSeconds
            && intent.childStartMicroseconds == childIdentity.startMicroseconds
            && intent.executablePath == childIdentity.executablePath
            && intent.executableDevice == childIdentity.executableDevice
            && intent.executableInode == childIdentity.executableInode
    }
}

/// Only the current in-memory submission owner can mint this observation.
/// Loading a prepared intent cannot reconstruct it after a crash.
final class ManualNeverSubmittedReceipt: Sendable {
    let runID: UUID
    let operationID: UUID
    let binding: ManualServiceEffectBinding
    fileprivate init(runID: UUID, operationID: UUID, binding: ManualServiceEffectBinding) {
        self.runID = runID; self.operationID = operationID; self.binding = binding
    }
}

/// A durable submission boundary, not producer acceptance. Typed clients must
/// additionally require the coordinator's accepted operation and live grant.
final class ManualServiceDispatchPermit: Sendable {
    let runID: UUID
    let operationID: UUID
    let binding: ManualServiceEffectBinding
    fileprivate init(runID: UUID, operationID: UUID, binding: ManualServiceEffectBinding) {
        self.runID = runID; self.operationID = operationID; self.binding = binding
    }
}

/// An ephemeral, non-Codable observation minted only by the submission's owned
/// launch validation below. Raw intent data cannot create capture authority.
struct OwnedServiceChildCaptureReceipt: Sendable {
    let runID: UUID
    let operationID: UUID
    let binding: ManualServiceEffectBinding
    let child: ProcessInstanceIdentity
    private let journalIdentity: ObjectIdentifier
    private let storeIdentity: ObjectIdentifier

    fileprivate init(runID: UUID, operationID: UUID, binding: ManualServiceEffectBinding,
                     child: ProcessInstanceIdentity, journal: RunJournal) {
        self.runID = runID; self.operationID = operationID
        self.binding = binding; self.child = child
        journalIdentity = ObjectIdentifier(journal)
        storeIdentity = journal.serviceChildCaptureStoreIdentity
    }
    func requireJournal(_ journal: RunJournal) throws {
        guard journalIdentity == ObjectIdentifier(journal) else { throw JournalError.invalidTransition }
    }
    func requireStore(_ store: MutationAdmissionStore) throws {
        guard storeIdentity == ObjectIdentifier(store) else { throw JournalError.invalidTransition }
    }
    func intent(phase: SubmissionPhase) -> PendingEffectIntent {
        PendingEffectIntent(runID: runID, operationID: operationID,
            service: binding, phase: phase, child: child)
    }
}

final class ManualServiceSubmission: @unchecked Sendable {
    private enum State { case prepared, possiblySubmitted, cancelled }
    private let lock = NSLock()
    private var state: State = .prepared
    private let intent: PendingEffectIntent
    private let binding: ManualServiceEffectBinding
    private let journal: RunJournal
    var effectBinding: ManualServiceEffectBinding { binding }
    var runID: UUID { intent.runID }
    var operationID: UUID { intent.operationID }
    private init(intent: PendingEffectIntent, binding: ManualServiceEffectBinding, journal: RunJournal) {
        self.intent = intent; self.binding = binding; self.journal = journal
    }
    static func prepare(runID: UUID, operationID: UUID, binding: ManualServiceEffectBinding,
                        journal: RunJournal) throws -> ManualServiceSubmission {
        try binding.validate()
        let prior = try journal.events(runID: runID)
        guard prior.count == 2, prior.last?.phase == .confirmed else { throw JournalError.invalidTransition }
        let intent = PendingEffectIntent(runID: runID, operationID: operationID, service: binding)
        try journal.persistIntent(intent)
        try journal.append(.init(runID: runID, sequence: 3, phase: .started,
            operationID: operationID, status: nil, reason: nil))
        return ManualServiceSubmission(intent: intent, binding: binding, journal: journal)
    }
    func beginSubmission() throws -> ManualServiceDispatchPermit {
        lock.lock(); defer { lock.unlock() }
        guard state == .prepared else { throw JournalError.invalidTransition }
        // Ambiguous storage failure must not restore a no-effect state.
        state = .possiblySubmitted
        try journal.markManualServiceSubmission(intent)
        return ManualServiceDispatchPermit(runID: intent.runID, operationID: intent.operationID, binding: binding)
    }

    /// Records only the captured instance from this submission's opaque owned
    /// launch. It grants no terminal status and does not release admission.
    func recordOwnedChild(_ launch: ManualSimulatorOwnedLaunch) throws {
        lock.lock(); defer { lock.unlock() }
        guard state == .possiblySubmitted else { throw JournalError.invalidTransition }
        try launch.requireIssuingSubmission(self)
        let invocation = launch.invocation
        guard invocation.binding == binding, invocation.runID == intent.runID,
              invocation.operationID == intent.operationID,
              binding.operation.adapter == .appleSimulatorShutdownV1,
              case .appleSimulator(let producer) = binding.operation.producer,
              invocation.executable == producer.simctl,
              let child = launch.session.identity,
              child.pid > 0, child.startSeconds >= 0, (0..<1_000_000).contains(child.startMicroseconds),
              child.executablePath == producer.simctl.canonicalPath,
              child.executableDevice == producer.simctl.device, child.executableInode == producer.simctl.inode,
              invocation.operationBindingDigest == (try binding.operation.canonicalDigest()) else {
            throw JournalError.invalidTransition
        }
        let captured = OwnedServiceChildCaptureReceipt(runID: intent.runID, operationID: intent.operationID,
            binding: binding, child: child, journal: journal)
        try journal.recordOwnedServiceChild(captured)
    }
    func cancelBeforeSubmission() throws -> VerifiedEffectTerminalProof {
        lock.lock(); defer { lock.unlock() }
        guard state == .prepared else { throw JournalError.invalidTransition }
        try journal.requireExactManualServiceIntent(intent)
        state = .cancelled
        return try CompiledEffectTerminalVerifier.manualNeverSubmitted(
            ManualNeverSubmittedReceipt(runID: intent.runID, operationID: intent.operationID, binding: binding))
    }
}
