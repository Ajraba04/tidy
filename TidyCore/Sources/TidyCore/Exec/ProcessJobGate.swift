import Foundation

enum ProcessReadAdmissionError: Error, Equatable, Sendable {
    case expired, notReadOnly
}

enum ProcessTerminalVerificationError: Error, Equatable, Sendable {
    case notMutation, reapNotProven, invalidReceipt, wrongGate, notReadOnly
    case expiredOrClosedLease, capacity
}

/// Minted only by the gate after an atomic obligation transfer, or by its
/// isolation-guarded fixture cleanup. Callers cannot mark a session transferred.
struct ProcessMutationTransferAcknowledgement: Sendable {
    private let gateIdentity: ObjectIdentifier
    private let reservation: UUID
    private let sessionID: UUID
    fileprivate init(gate: ProcessJobGate, reservation: UUID, sessionID: UUID) {
        gateIdentity = ObjectIdentifier(gate); self.reservation = reservation; self.sessionID = sessionID
    }
    func matches(gate: ProcessJobGate, reservation: UUID, sessionID: UUID) -> Bool {
        gateIdentity == ObjectIdentifier(gate) && self.reservation == reservation && self.sessionID == sessionID
    }
}

/// A bounded synchronous validity check is used immediately before a terminal
/// read's spawn. Only this file can create or invalidate the epoch.
private final class TerminalVerificationEpoch: @unchecked Sendable {
    let deadline: ContinuousClock.Instant
    private let lock = NSLock()
    private var active = true
    init(deadline: ContinuousClock.Instant) { self.deadline = deadline }
    func check() throws {
        lock.lock(); defer { lock.unlock() }
        guard active, ContinuousClock.now < deadline else { throw ProcessTerminalVerificationError.expiredOrClosedLease }
    }
    func close() { lock.lock(); active = false; lock.unlock() }
}

/// Gate-minted process-budget capability, not a producer terminal proof. The
/// constructor and identifiers are inaccessible to callers, including SPI users.
struct ProcessTerminalVerificationLease: Sendable {
    fileprivate let gateIdentity: ObjectIdentifier
    fileprivate let nonce: UUID
    fileprivate let originReservation: UUID
    let sessionID: UUID
    let ownedIdentity: ProcessInstanceIdentity
    let rawStatus: Int32
    private let epoch: TerminalVerificationEpoch

    fileprivate init(gate: ProcessJobGate, nonce: UUID, originReservation: UUID,
                     sessionID: UUID, ownedIdentity: ProcessInstanceIdentity,
                     rawStatus: Int32, epoch: TerminalVerificationEpoch) {
        gateIdentity = ObjectIdentifier(gate); self.nonce = nonce
        self.originReservation = originReservation; self.sessionID = sessionID; self.epoch = epoch
        self.ownedIdentity = ownedIdentity; self.rawStatus = rawStatus
    }
    func checkValidity() throws { try epoch.check() }
    var expiresAt: ContinuousClock.Instant { epoch.deadline }
    func remainingLifetime() throws -> Duration {
        try epoch.check()
        return ContinuousClock.now.duration(to: epoch.deadline)
    }
}

struct ProcessPolicyRevision: Equatable, Comparable, Sendable {
    let settings: UInt64
    let observation: UInt64

    static func < (lhs: ProcessPolicyRevision, rhs: ProcessPolicyRevision) -> Bool {
        if lhs.settings != rhs.settings { return lhs.settings < rhs.settings }
        return lhs.observation < rhs.observation
    }
}

enum ProcessPolicyUpdateResult: Equatable, Sendable {
    case applied
    case rejectedStale(current: ProcessPolicyRevision)
    case rejectedInvalid
}

struct ProcessGateSnapshot: Equatable, Sendable {
    let active: Int
    let queued: Int
    let activeReaders: Int
    let activeMutators: Int
    let queuedReaders: Int
    let queuedMutators: Int
    let readOnlyCap: Int
    let physicalLimit: Int
    let policyRevision: ProcessPolicyRevision?
    let unresolvedMutations: Int
    let activeVerifiers: Int
    let queuedVerifiers: Int
}

/// The sole production process budget. Reservation transfer happens inside
/// the actor before a waiter resumes. Tests may construct isolated gates, but
/// production launch code can only reach `shared`, whose physical cap is two.
@_spi(TidyCoreTesting) public actor ProcessJobGate {
    private enum Purpose { case production, testing }

    nonisolated static let shared = try! ProcessJobGate(limit: 2, purpose: .production)

    private struct Waiter {
        let id: UUID
        let kind: ProcessRunner.AuthorizedJobKind
        let verificationLeaseID: UUID?
        let admissionDeadline: ContinuousClock.Instant?
        let continuation: CheckedContinuation<UUID, Error>
    }
    private struct VerificationRecord {
        let originReservation: UUID
        let sessionID: UUID
        let epoch: TerminalVerificationEpoch
    }
    private struct MutationObligation {
        let sessionID: UUID
        let identity: ProcessInstanceIdentity
        let rawStatus: Int32
    }

    nonisolated let physicalLimit: Int
    nonisolated let isTestIsolation: Bool
    private let queueLimit: Int
    private var readOnlyCap: Int
    private var policyRevision: ProcessPolicyRevision?
    private var active: [UUID: ProcessRunner.AuthorizedJobKind] = [:]
    private var waiters: [Waiter] = []
    private var admissionExpiryTasks: [UUID: Task<Void, Never>] = [:]
    private var ownedMutationReservations: Set<UUID> = []
    private var obligations: [UUID: MutationObligation] = [:]
    private var verificationLeases: [UUID: VerificationRecord] = [:]
    private var verifierReservations: [UUID: UUID] = [:]
    private var verificationExpiryTasks: [UUID: Task<Void, Never>] = [:]
    private static let maximumUnresolvedObligations = 8
    private static let maximumVerificationLifetime: Duration = .seconds(30)

    private init(limit: Int, queueLimit: Int = 256, purpose: Purpose) throws {
        guard (1...2).contains(limit), (1...256).contains(queueLimit) else {
            throw POSIXError(.EINVAL)
        }
        physicalLimit = limit
        switch purpose {
        case .production: isTestIsolation = false
        case .testing: isTestIsolation = true
        }
        self.queueLimit = queueLimit
        readOnlyCap = limit
    }

    /// Explicit SPI: test fixtures receive an isolated gate that production
    /// launch authority refuses to use as the shared budget.
    @_spi(TidyCoreTesting)
    public nonisolated static func isolatedForTesting(limit: Int, queueLimit: Int = 256) throws
      -> ProcessJobGate {
        try ProcessJobGate(limit: limit, queueLimit: queueLimit, purpose: .testing)
    }

    func applyReadOnlyCap(_ cap: Int, revision candidate: ProcessPolicyRevision)
      -> ProcessPolicyUpdateResult {
        guard (0...2).contains(cap) else { return .rejectedInvalid }
        if let policyRevision, candidate <= policyRevision {
            return .rejectedStale(current: policyRevision)
        }
        policyRevision = candidate
        readOnlyCap = cap
        drainEligibleWaiters()
        return .applied
    }

    func acquire(_ authorization: ProcessRunner.AuthorizedLaunch) async throws -> UUID {
        if let hook = authorization.manualSubmissionHook {
            guard authorization.kind == .mutation else { throw ProcessTerminalVerificationError.notMutation }
            return try await acquire(kind: .mutation, admissionDeadline: hook.deadline,
                effectCancellation: hook.admissionCancellation)
        }
        return try await acquire(kind: authorization.kind)
    }

    func acquireDeadlineBoundRead(_ authorization: ProcessRunner.AuthorizedLaunch,
                                 deadline: ContinuousClock.Instant) async throws -> UUID {
        guard authorization.kind == .readOnly else { throw ProcessReadAdmissionError.notReadOnly }
        return try await acquire(kind: .readOnly, admissionDeadline: deadline)
    }

    func acquireDeadlineBoundReadForTesting(deadline: ContinuousClock.Instant) async throws -> UUID {
        guard isTestIsolation else { throw POSIXError(.EPERM) }
        return try await acquire(kind: .readOnly, admissionDeadline: deadline)
    }

    @_spi(TidyCoreTesting)
    public func acquireForTesting(kind: ProcessTestJobKind = .readOnly) async throws -> UUID {
        guard isTestIsolation else { throw POSIXError(.EPERM) }
        return try await acquire(kind: kind == .readOnly ? .readOnly : .mutation)
    }

    /// Atomic budget transfer follows an owned consuming reap. It deliberately
    /// does not declare the mutation successful or retire its obligation.
    func transferReapedMutation(_ receipt: ReapedMutationReceipt,
                               within lifetime: Duration) throws -> ProcessTerminalVerificationLease {
        let reservation = try receipt.reservationForTransfer(in: self)
        guard lifetime > .zero, lifetime <= Self.maximumVerificationLifetime else {
            throw ProcessTerminalVerificationError.expiredOrClosedLease
        }
        guard active[reservation] == .mutation, ownedMutationReservations.contains(reservation),
              obligations[reservation] == nil else { throw ProcessTerminalVerificationError.invalidReceipt }
        guard obligations.count < Self.maximumUnresolvedObligations else { throw ProcessTerminalVerificationError.capacity }
        let nonce = UUID()
        let epoch = TerminalVerificationEpoch(deadline: ContinuousClock.now.advanced(by: lifetime))
        let lease = ProcessTerminalVerificationLease(gate: self, nonce: nonce,
            originReservation: reservation, sessionID: receipt.sessionID,
            ownedIdentity: receipt.identity, rawStatus: receipt.rawStatus, epoch: epoch)
        obligations[reservation] = MutationObligation(sessionID: receipt.sessionID,
            identity: receipt.identity, rawStatus: receipt.rawStatus)
        verificationLeases[nonce] = VerificationRecord(originReservation: reservation,
            sessionID: receipt.sessionID, epoch: epoch)
        active.removeValue(forKey: reservation)
        ownedMutationReservations.remove(reservation)
        try receipt.acknowledgePhysicalTransfer(ProcessMutationTransferAcknowledgement(
            gate: self, reservation: reservation, sessionID: receipt.sessionID))
        verificationExpiryTasks[nonce] = Task { [weak self] in
            do { try await Task.sleep(until: epoch.deadline, clock: .continuous) }
            catch { return }
            await self?.expireVerification(nonce)
        }
        drainEligibleWaiters()
        return lease
    }

    private func validate(_ lease: ProcessTerminalVerificationLease) throws {
        guard lease.gateIdentity == ObjectIdentifier(self) else { throw ProcessTerminalVerificationError.wrongGate }
        guard let record = verificationLeases[lease.nonce],
              record.originReservation == lease.originReservation, record.sessionID == lease.sessionID,
              obligations[record.originReservation]?.sessionID == record.sessionID else {
            throw ProcessTerminalVerificationError.expiredOrClosedLease
        }
        try lease.checkValidity()
    }

    func acquireTerminalVerification(_ lease: ProcessTerminalVerificationLease,
                                     deadline: ContinuousClock.Instant? = nil) async throws -> UUID {
        try validate(lease)
        return try await acquire(kind: .readOnly, verificationLease: lease, admissionDeadline: deadline)
    }

    private func acquire(kind: ProcessRunner.AuthorizedJobKind,
                         verificationLease: ProcessTerminalVerificationLease? = nil,
                         admissionDeadline: ContinuousClock.Instant? = nil,
                         effectCancellation: EffectCancellationToken? = nil) async throws -> UUID {
        if let admissionDeadline {
            guard ContinuousClock.now < admissionDeadline else { throw ProcessReadAdmissionError.expired }
        }
        if let verificationLease {
            guard kind == .readOnly else { throw ProcessTerminalVerificationError.notReadOnly }
            try validate(verificationLease)
            guard waiters.filter({ $0.verificationLeaseID == verificationLease.nonce }).count < 1 else {
                throw ProcessTerminalVerificationError.capacity
            }
        }
        let verificationLeaseID = verificationLease?.nonce
        let id = UUID()
        let observer = try effectCancellation?.observeCancellation { [weak self] in
            Task { await self?.cancelQueued(id) }
        }
        defer { if let observer { effectCancellation?.removeCancellationObserver(observer) } }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled || effectCancellation?.isCancelled == true {
                    continuation.resume(throwing: CancellationError())
                } else if admissionDeadline.map({ ContinuousClock.now >= $0 }) == true {
                    continuation.resume(throwing: ProcessReadAdmissionError.expired)
                } else if waiters.count >= queueLimit {
                    // A full queue of policy-paused readers must not consume
                    // admission capacity or reject an eligible mutator. No
                    // eligible waiter can remain after the previous drain.
                    if isEligible(kind, verificationLeaseID: verificationLeaseID) {
                        active[id] = kind
                        if let verificationLeaseID { verifierReservations[id] = verificationLeaseID }
                        continuation.resume(returning: id)
                    } else {
                        continuation.resume(throwing: POSIXError(.EAGAIN))
                    }
                } else {
                    waiters.append(Waiter(id: id, kind: kind,
                        verificationLeaseID: verificationLeaseID, admissionDeadline: admissionDeadline,
                        continuation: continuation))
                    if let admissionDeadline {
                        admissionExpiryTasks[id] = Task { [weak self] in
                            do { try await Task.sleep(until: admissionDeadline, clock: .continuous) }
                            catch { return }
                            await self?.expireQueuedAdmission(id)
                        }
                    }
                    drainEligibleWaiters()
                }
            }
        } onCancel: {
            Task { await self.cancelQueued(id) }
        }
    }

    private var activeReaderCount: Int {
        active.reduce(into: 0) { count, entry in
            if entry.value == .readOnly, verifierReservations[entry.key] == nil { count += 1 }
        }
    }

    private func isEligible(_ kind: ProcessRunner.AuthorizedJobKind,
                            verificationLeaseID: UUID? = nil) -> Bool {
        guard active.count < physicalLimit else { return false }
        if let verificationLeaseID {
            guard kind == .readOnly, let record = verificationLeases[verificationLeaseID],
                  (try? record.epoch.check()) != nil else { return false }
            return !verifierReservations.values.contains(verificationLeaseID)
        }
        switch kind {
        case .mutation: return true
        case .readOnly: return activeReaderCount < readOnlyCap
        }
    }

    private func isEligible(_ waiter: Waiter) -> Bool {
        if waiter.admissionDeadline.map({ ContinuousClock.now >= $0 }) == true { return false }
        return isEligible(waiter.kind, verificationLeaseID: waiter.verificationLeaseID)
    }

    /// Strict FIFO among currently eligible work. A cap-zero reader cannot
    /// hold a physical slot hostage from a later mutator; readers retain their
    /// own order and resume in that order when the cap rises.
    private func drainEligibleWaiters() {
        var valid: [Waiter] = []
        for waiter in waiters {
            if let nonce = waiter.verificationLeaseID,
               verificationLeases[nonce].map({ (try? $0.epoch.check()) != nil }) != true {
                admissionExpiryTasks.removeValue(forKey: waiter.id)?.cancel()
                waiter.continuation.resume(throwing: ProcessTerminalVerificationError.expiredOrClosedLease)
            } else if waiter.admissionDeadline.map({ ContinuousClock.now >= $0 }) == true {
                admissionExpiryTasks.removeValue(forKey: waiter.id)?.cancel()
                waiter.continuation.resume(throwing: ProcessReadAdmissionError.expired)
            } else { valid.append(waiter) }
        }
        waiters = valid
        while active.count < physicalLimit,
              let index = waiters.firstIndex(where: isEligible) {
            let next = waiters.remove(at: index)
            admissionExpiryTasks.removeValue(forKey: next.id)?.cancel()
            active[next.id] = next.kind
            if let nonce = next.verificationLeaseID { verifierReservations[next.id] = nonce }
            next.continuation.resume(returning: next.id)
        }
    }

    private func cancelQueued(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        admissionExpiryTasks.removeValue(forKey: id)?.cancel()
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        drainEligibleWaiters()
    }

    private func expireQueuedAdmission(_ id: UUID) {
        admissionExpiryTasks.removeValue(forKey: id)
        guard let index = waiters.firstIndex(where: { $0.id == id }),
              waiters[index].admissionDeadline.map({ ContinuousClock.now >= $0 }) == true else { return }
        waiters.remove(at: index).continuation.resume(throwing: ProcessReadAdmissionError.expired)
        drainEligibleWaiters()
    }

    func release(_ reservation: UUID) {
        // Generic release never discharges production mutation ownership. Owned
        // fixture mutations use the same guard so receipt-possession regression
        // tests exercise this boundary; unowned isolated budget fixtures retain
        // their existing explicit cleanup behavior.
        if active[reservation] == .mutation,
           !isTestIsolation || ownedMutationReservations.contains(reservation) { return }
        guard active.removeValue(forKey: reservation) != nil else { return }
        verifierReservations.removeValue(forKey: reservation)
        drainEligibleWaiters()
    }

    func registerOwnedMutationReservation(_ reservation: UUID) throws {
        guard active[reservation] == .mutation,
              ownedMutationReservations.insert(reservation).inserted else {
            throw ProcessTerminalVerificationError.invalidReceipt
        }
    }

    func rollbackBeforeSpawn(_ receipt: ProcessPreSpawnRollbackReceipt) throws {
        let reservation = try receipt.reservationForRollback(in: self)
        guard active[reservation] == .mutation else { throw ProcessTerminalVerificationError.invalidReceipt }
        active.removeValue(forKey: reservation)
        ownedMutationReservations.remove(reservation)
        drainEligibleWaiters()
    }

    func releaseReapedMutationForTesting(_ reservation: UUID,
                                        sessionID: UUID) throws -> ProcessMutationTransferAcknowledgement {
        guard isTestIsolation else { throw POSIXError(.EPERM) }
        guard active[reservation] == .mutation else { throw ProcessTerminalVerificationError.invalidReceipt }
        active.removeValue(forKey: reservation)
        ownedMutationReservations.remove(reservation)
        drainEligibleWaiters()
        return ProcessMutationTransferAcknowledgement(gate: self, reservation: reservation, sessionID: sessionID)
    }

    private func expireVerification(_ nonce: UUID) {
        verificationLeases[nonce]?.epoch.close()
        verificationExpiryTasks.removeValue(forKey: nonce)
        // Expiry closes admission and wakes queued probes. The mutation remains
        // unresolved; only future compiled adapter proof can retire it.
        drainEligibleWaiters()
    }

    /// A compiled proof alone is insufficient: the journal must have durably
    /// published its terminal event, finished the run and retired the intent.
    /// This route accepts only native simulator evidence, never fixture,
    /// Docker, never-submitted or rejected-spawn evidence.
    func closeTerminalVerification(_ lease: ProcessTerminalVerificationLease,
                                   retirement: DurablyRetiredManualServiceReceipt) throws {
        let archive = retirement.archive
        guard archive.verifier == "tidy.manual-service.simulator-native.v1",
              let service = archive.service, service.kind == .simulatorNative,
              let evidence = service.nativeSimulator,
              CompiledEffectTerminalVerifier.validateHistorical(archive, reference: retirement.proofReference),
              evidence.validate(binding: service.binding),
              evidence.childSessionID == lease.sessionID,
              evidence.childIdentity == lease.ownedIdentity,
              evidence.rawWaitStatus == lease.rawStatus,
              !isTestIsolation else { throw ProcessTerminalVerificationError.invalidReceipt }
        guard lease.gateIdentity == ObjectIdentifier(self) else { throw ProcessTerminalVerificationError.wrongGate }
        guard let record = verificationLeases[lease.nonce],
              record.originReservation == lease.originReservation,
              record.sessionID == lease.sessionID,
              let obligation = obligations[record.originReservation],
              obligation.sessionID == lease.sessionID,
              obligation.identity == lease.ownedIdentity,
              obligation.rawStatus == lease.rawStatus else {
            throw ProcessTerminalVerificationError.expiredOrClosedLease
        }
        guard !verifierReservations.values.contains(lease.nonce),
              !waiters.contains(where: { $0.verificationLeaseID == lease.nonce }) else {
            throw ProcessTerminalVerificationError.capacity
        }
        // Expiry prevents new reads but does not invalidate already durable
        // terminal retirement. Closing never renews or reopens the lease.
        // Removing both records atomically also makes receipt reuse fail.
        record.epoch.close()
        verificationLeases.removeValue(forKey: lease.nonce)
        verificationExpiryTasks.removeValue(forKey: lease.nonce)?.cancel()
        obligations.removeValue(forKey: record.originReservation)
        drainEligibleWaiters()
    }

    func closeTerminalVerificationForTesting(_ lease: ProcessTerminalVerificationLease) throws {
        guard isTestIsolation else { throw POSIXError(.EPERM) }
        guard lease.gateIdentity == ObjectIdentifier(self) else { throw ProcessTerminalVerificationError.wrongGate }
        guard let record = verificationLeases.removeValue(forKey: lease.nonce),
              record.originReservation == lease.originReservation, record.sessionID == lease.sessionID else {
            throw ProcessTerminalVerificationError.expiredOrClosedLease
        }
        record.epoch.close()
        verificationExpiryTasks.removeValue(forKey: lease.nonce)?.cancel()
        obligations.removeValue(forKey: record.originReservation)
        drainEligibleWaiters()
    }

    func snapshot() -> ProcessGateSnapshot {
        let readers = activeReaderCount
        let queuedReaders = waiters.reduce(into: 0) { if $1.kind == .readOnly, $1.verificationLeaseID == nil { $0 += 1 } }
        let queuedVerifiers = waiters.reduce(into: 0) { if $1.verificationLeaseID != nil { $0 += 1 } }
        let mutators = active.values.filter { $0 == .mutation }.count
        return ProcessGateSnapshot(active: active.count, queued: waiters.count,
            activeReaders: readers, activeMutators: mutators,
            queuedReaders: queuedReaders, queuedMutators: waiters.count - queuedReaders - queuedVerifiers,
            readOnlyCap: readOnlyCap, physicalLimit: physicalLimit,
            policyRevision: policyRevision, unresolvedMutations: obligations.count,
            activeVerifiers: verifierReservations.count, queuedVerifiers: queuedVerifiers)
    }
}
