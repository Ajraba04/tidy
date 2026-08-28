import Foundation

public enum SchedulerFeature: String, CaseIterable, Hashable, Sendable {
    case headroom, buildPrep, projects, rescue, ecosystems, budgets, history, maintenance
}

public struct SchedulerRequirements: Hashable, Sendable {
    public let features: Set<SchedulerFeature>
    public init(features: Set<SchedulerFeature>) throws {
        guard !features.isEmpty else { throw WorkSchedulerError.invalidRequirements }
        self.features = features
    }
}

internal struct SchedulerResolutionInputs: Equatable, Sendable {
    let logicalCPUCount: Int
    init(logicalCPUCount: Int) throws {
        guard (1...1_024).contains(logicalCPUCount) else {
            throw WorkSchedulerError.invalidResolutionInputs
        }
        self.logicalCPUCount = logicalCPUCount
    }
}

internal enum SchedulerObservation: Equatable, Sendable {
    case unknown, nominal, constrained, critical
}

public struct WorkSchedulerLimits: Equatable, Sendable {
    let sessions: Int
    let queued: Int
    let queuedPerSession: Int
    let tombstones: Int

    public init(sessions: Int = 64, queued: Int = 256,
                queuedPerSession: Int = 32, tombstones: Int = 64) throws {
        guard (1...64).contains(sessions), (1...256).contains(queued),
              (1...32).contains(queuedPerSession), queuedPerSession <= queued,
              (0...64).contains(tombstones) else { throw WorkSchedulerError.invalidLimits }
        self.sessions = sessions; self.queued = queued
        self.queuedPerSession = queuedPerSession; self.tombstones = tombstones
    }
}

public enum WorkSchedulerError: Error, Equatable, Sendable {
    case invalidResolutionInputs, invalidRequirements, invalidLimits
    case foreignController, foreignCapability, foreignSession
    case admissionUpdating, admissionUnavailable
    case wrongRequirements, staleCapability, disabledFeature
    case queueLimit, sessionQueueLimit, sessionLimit, counterOverflow
}

internal enum SchedulerFailureReason: Error, Equatable, Sendable {
    case invalidActiveProfile, duplicateProfileID, invalidPolicyDocument
    case legacyCompatibilityMismatch, candidateMismatch, envelopeMismatch
    case generationOverflow
}

internal enum SchedulerRejectionReason: Equatable, Sendable {
    case staleRevision(current: UInt64)
    case foreignToken, superseded, consumed
    case firstInstallRequiresInvalidation, notPresentationOnly
    case invalidPolicyDocument, legacyCompatibilityMismatch
}

internal enum SchedulerPrepareResult: Equatable, Sendable {
    case prepared(PreparedSchedulerPolicy, AuthorityEffect)
    case failedClosed(SchedulerFailureReason)
    case rejected(SchedulerRejectionReason)
    var token: PreparedSchedulerPolicy? { if case .prepared(let token, _) = self { return token }; return nil }
    var effect: AuthorityEffect { if case .prepared(_, let effect) = self { return effect }; return .none }
}

internal enum SchedulerPresentationPrepareResult: Equatable, Sendable {
    case prepared(PreparedSchedulerPresentation, AuthorityEffect)
    case rejected(SchedulerRejectionReason)
    var token: PreparedSchedulerPresentation? { if case .prepared(let token, _) = self { return token }; return nil }
    var effect: AuthorityEffect { if case .prepared(_, let effect) = self { return effect }; return .none }
}

internal enum SchedulerCommitResult: Equatable, Sendable {
    case committed(settingsRevision: UInt64)
    case failedClosed(SchedulerFailureReason)
    case rejected(SchedulerRejectionReason)
}
internal enum SchedulerFailResult: Equatable, Sendable { case failedClosed; case rejected(SchedulerRejectionReason) }
internal enum SchedulerPresentationDiscardResult: Equatable, Sendable { case discarded; case rejected(SchedulerRejectionReason) }
internal enum SchedulerObservationResult: Equatable, Sendable {
    case applied
    case rejectedStale(current: UInt64)
    case failedClosed(SchedulerFailureReason)
}

public enum WorkSessionState: Equatable, Sendable { case open, cancelled, finished }
public enum WorkSchedulerAvailability: Equatable, Sendable { case unavailable, available }

public struct WorkSchedulerSnapshot: Equatable, Sendable {
    public let availability: WorkSchedulerAvailability
    public let settingsRevision: UInt64?
    public let generation: UInt64
    public let observationEpoch: UInt64
    public let effectiveWorkers: Int
    public let effectiveReadOnlyProcesses: Int
    public let admission: ScanAdmission
    public let active: Int
    public let queued: Int
    public let liveSessions: Int
    public let tombstones: Int
}

public struct WorkSession: Hashable, Sendable {
    fileprivate let schedulerID: UUID
    fileprivate let id: UUID
}

internal struct SchedulerPolicyControllerCapability: Sendable {
    fileprivate let controllerID: UUID
}
internal struct SchedulerAdmissionTicket: Equatable, Sendable {
    fileprivate let controllerID: UUID
    fileprivate let transition: UInt64
}
/// A controller-issued hold that keeps otherwise-open admission closed across
/// serialized bridge handoffs. Only the owning controller can create or release it.
internal struct SchedulerAdmissionHold: Sendable {
    fileprivate let controllerID: UUID
    fileprivate let id: UUID
}
public struct ExplicitWorkCapability: Sendable {
    fileprivate let schedulerID: UUID
    fileprivate let id: UUID
    fileprivate let use: ExplicitCapabilityUse
    fileprivate let requirements: SchedulerRequirements
    fileprivate let barrierEpoch: UInt64
    fileprivate let epoch: UInt64
    fileprivate let generation: UInt64
}
private final class ExplicitCapabilityUse: @unchecked Sendable {
    private let lock = NSLock(); private var consumed = false
    func consume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !consumed else { return false }; consumed = true; return true
    }
}

internal enum SchedulerTestEvent: Hashable, Sendable {
    case acquiring(UInt64), enqueued(UInt64), granting(UInt64), operationStarting(UInt64)
    case grantedBeforeReturn(UInt64), released(UInt64)
    case presentationPrepared(revision: UInt64)
    case invalidationClaiming(revision: UInt64), invalidationPrepared(revision: UInt64)
}
internal protocol SchedulerTestHook: Sendable { func receive(_ event: SchedulerTestEvent) async }

public actor SchedulerCancellationProbe {
    private var cancelled = false
    fileprivate func cancel() { cancelled = true }
    public func isCancelled() -> Bool { cancelled }
    public func checkCancellation() throws {
        if cancelled { throw CancellationError() }
        try Task.checkCancellation()
    }
}

private enum BarrierState {
    case unavailable, updating(UInt64), preparing(UInt64), committing(UInt64), open(UInt64), presentationCommitting(UInt64)
}
private final class SchedulerAdmissionBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private var state: BarrierState = .unavailable
    private var next: UInt64 = 0
    private var admissionHolds: Set<UUID> = []

    func begin(controllerID: UUID) throws -> SchedulerAdmissionTicket {
        lock.lock(); defer { lock.unlock() }
        if case .committing = state { throw WorkSchedulerError.admissionUpdating }
        if case .preparing = state { throw WorkSchedulerError.admissionUpdating }
        if case .presentationCommitting = state { throw WorkSchedulerError.admissionUpdating }
        let (value, overflow) = next.addingReportingOverflow(1)
        guard !overflow else { state = .unavailable; throw WorkSchedulerError.counterOverflow }
        next = value; state = .updating(value)
        return SchedulerAdmissionTicket(controllerID: controllerID, transition: value)
    }
    func status() -> BarrierState {
        lock.lock(); defer { lock.unlock() }
        guard !admissionHolds.isEmpty else { return state }
        switch state {
        case .open, .presentationCommitting:
            return .updating(next)
        case .unavailable, .updating, .preparing, .committing:
            return state
        }
    }
    func isCurrent(_ ticket: SchedulerAdmissionTicket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if case .updating(ticket.transition) = state { return true }
        if case .preparing(ticket.transition) = state { return true }
        return false
    }
    func openEpoch() -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        guard admissionHolds.isEmpty else { return nil }
        if case .open(let epoch) = state { return epoch }
        if case .presentationCommitting(let epoch) = state { return epoch }
        return nil
    }
    func claim(_ ticket: SchedulerAdmissionTicket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if case .updating(ticket.transition) = state {
            state = .committing(ticket.transition); return true
        }
        if case .preparing(ticket.transition) = state {
            state = .committing(ticket.transition); return true
        }
        return false
    }
    func claimPreparation(_ ticket: SchedulerAdmissionTicket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard case .updating(ticket.transition) = state else { return false }
        state = .preparing(ticket.transition); return true
    }
    func finish(_ ticket: SchedulerAdmissionTicket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard case .committing(ticket.transition) = state else { return false }
        state = .open(ticket.transition); return true
    }
    func claimPresentation(_ epoch: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard case .open(epoch) = state else { return false }
        state = .presentationCommitting(epoch); return true
    }
    func finishPresentation(_ epoch: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard case .presentationCommitting(epoch) = state else { return false }
        state = .open(epoch); return true
    }
    func acquireAdmissionHold(_ id: UUID) {
        lock.lock(); admissionHolds.insert(id); lock.unlock()
    }
    func releaseAdmissionHold(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard admissionHolds.remove(id) != nil, admissionHolds.isEmpty else { return false }
        if case .open = state { return true }
        if case .presentationCommitting = state { return true }
        return false
    }
    func unavailable() {
        lock.lock(); state = .unavailable; admissionHolds.removeAll(); lock.unlock()
    }
}

private struct SchedulerResolution: Equatable, Sendable {
    let policy: EffectivePolicy
    let features: Set<SchedulerFeature>
    let workers: Int
    let processes: Int
    let admission: ScanAdmission
    let slice: Int
    let rate: Int
    var identity: SchedulerIdentity { SchedulerIdentity(features: features, workers: workers,
        processes: processes, admission: admission, slice: slice) }
}
private struct SchedulerIdentity: Equatable, Sendable {
    let features: Set<SchedulerFeature>; let workers: Int; let processes: Int
    let admission: ScanAdmission; let slice: Int
}

internal struct PreparedSchedulerPolicy: Equatable, Sendable {
    fileprivate let controllerID: UUID; fileprivate let id: UUID
    fileprivate let generation: UInt64; fileprivate let candidate: SettingsEnvelope
    fileprivate let resolution: SchedulerResolution; fileprivate let ticket: SchedulerAdmissionTicket
}
internal struct PreparedSchedulerPresentation: Equatable, Sendable {
    fileprivate let controllerID: UUID; fileprivate let id: UUID
    fileprivate let candidate: SettingsEnvelope; fileprivate let resolution: SchedulerResolution
    fileprivate let epoch: UInt64; fileprivate let barrierEpoch: UInt64
}

public actor WorkScheduler {
    private struct SessionRecord {
        let requirements: SchedulerRequirements; let discretionary: Bool
        var state: WorkSessionState = .open; var active = 0; var queued = 0
        var probes: [UUID: SchedulerCancellationProbe] = [:]
    }
    private struct Waiter {
        let id: UInt64; let sessionID: UUID; let probe: SchedulerCancellationProbe
        let continuation: CheckedContinuation<Void, Error>
    }

    private let schedulerID: UUID
    private let barrier: SchedulerAdmissionBarrier
    private let limits: WorkSchedulerLimits
    private let hook: (any SchedulerTestHook)?
    private var availability: WorkSchedulerAvailability = .unavailable
    private var revision: UInt64?
    private var generation: UInt64
    private var epoch: UInt64
    private var workers = 0
    private var processes = 0
    private var admission: ScanAdmission = .paused
    private var features: Set<SchedulerFeature> = []
    private var sessions: [UUID: SessionRecord] = [:]
    private var tombstoneOrder: [UUID] = []
    private var tombstones: [UUID: WorkSessionState] = [:]
    private var queue: [Waiter] = []
    private var activeCount = 0
    private var waiterID: UInt64

    fileprivate init(id: UUID, barrier: SchedulerAdmissionBarrier, limits: WorkSchedulerLimits,
                     generation: UInt64, epoch: UInt64, waiterID: UInt64,
                     hook: (any SchedulerTestHook)?) {
        schedulerID = id; self.barrier = barrier; self.limits = limits
        self.generation = generation; self.epoch = epoch; self.waiterID = waiterID; self.hook = hook
    }

    private func checkBarrier() throws {
        switch barrier.status() {
        case .open, .presentationCommitting: return
        case .updating, .preparing, .committing: throw WorkSchedulerError.admissionUpdating
        case .unavailable: throw WorkSchedulerError.admissionUnavailable
        }
    }

    public func beginSession(requirements: SchedulerRequirements,
                             capability: ExplicitWorkCapability) async throws -> WorkSession {
        try checkBarrier()
        guard capability.schedulerID == schedulerID else { throw WorkSchedulerError.foreignCapability }
        guard capability.requirements == requirements else { throw WorkSchedulerError.wrongRequirements }
        guard capability.use.consume() else { throw WorkSchedulerError.staleCapability }
        guard capability.barrierEpoch == barrier.openEpoch(), capability.epoch == epoch,
              capability.generation == generation else { throw WorkSchedulerError.staleCapability }
        guard requirements.features.isSubset(of: features) else { throw WorkSchedulerError.disabledFeature }
        guard sessions.count < limits.sessions else { throw WorkSchedulerError.sessionLimit }
        try checkBarrier()
        let session = WorkSession(schedulerID: schedulerID, id: UUID())
        sessions[session.id] = SessionRecord(requirements: requirements, discretionary: false)
        return session
    }

    fileprivate func beginDiscretionary(_ requirements: SchedulerRequirements) throws -> WorkSession {
        try checkBarrier(); guard admission == .discretionaryAllowed else { throw WorkSchedulerError.admissionUnavailable }
        guard requirements.features.isSubset(of: features) else { throw WorkSchedulerError.disabledFeature }
        guard sessions.count < limits.sessions else { throw WorkSchedulerError.sessionLimit }
        let session = WorkSession(schedulerID: schedulerID, id: UUID())
        sessions[session.id] = SessionRecord(requirements: requirements, discretionary: true)
        return session
    }

    public func withPermit<T: Sendable>(session: WorkSession,
        operation: @Sendable (SchedulerCancellationProbe) async throws -> T) async throws -> T {
        let (id, probe) = try await acquire(session)
        do {
            try checkBarrier()
            try Task.checkCancellation()
            try await probe.checkCancellation()
            let value = try await operation(probe)
            await releasePermit(id: id, sessionID: session.id, probe: probe)
            return value
        } catch {
            await releasePermit(id: id, sessionID: session.id, probe: probe)
            throw error
        }
    }

    private func acquire(_ session: WorkSession) async throws -> (UInt64, SchedulerCancellationProbe) {
        try checkBarrier()
        guard session.schedulerID == schedulerID else { throw WorkSchedulerError.foreignSession }
        guard let record = sessions[session.id], record.state == .open else { throw WorkSchedulerError.foreignSession }
        let (next, overflow) = waiterID.addingReportingOverflow(1)
        guard !overflow else { availability = .unavailable; barrier.unavailable(); throw WorkSchedulerError.counterOverflow }
        waiterID = next
        let probe = SchedulerCancellationProbe()
        await hook?.receive(.acquiring(next))
        if Task.isCancelled { await hook?.receive(.released(next)); throw CancellationError() }
        try checkBarrier()
        if queue.isEmpty, activeCount < workers, admission != .paused {
            await hook?.receive(.granting(next))
            if Task.isCancelled { await hook?.receive(.released(next)); throw CancellationError() }
            try checkBarrier()
            await hook?.receive(.operationStarting(next))
            if Task.isCancelled { await hook?.receive(.released(next)); throw CancellationError() }
            try checkBarrier()
            activeCount += 1
            sessions[session.id]?.active += 1
            let probeID = UUID(); sessions[session.id]?.probes[probeID] = probe
            await hook?.receive(.grantedBeforeReturn(next))
            if Task.isCancelled {
                await releasePermit(id: next, sessionID: session.id, probe: probe)
                throw CancellationError()
            }
            try checkBarrier()
            return (next, probe)
        }
        guard queue.count < limits.queued else { throw WorkSchedulerError.queueLimit }
        guard record.queued < limits.queuedPerSession else { throw WorkSchedulerError.sessionQueueLimit }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sessions[session.id]?.queued += 1
                queue.append(Waiter(id: next, sessionID: session.id, probe: probe,
                                    continuation: continuation))
                if let hook {
                    Task { await hook.receive(.enqueued(next)) }
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(next) }
        }
        return (next, probe)
    }

    private func cancelWaiter(_ id: UInt64) async {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let waiter = queue.remove(at: index)
        sessions[waiter.sessionID]?.queued -= 1
        await hook?.receive(.released(id))
        waiter.continuation.resume(throwing: CancellationError())
        await drain()
    }

    private func releasePermit(id: UInt64, sessionID: UUID,
                               probe: SchedulerCancellationProbe) async {
        await hook?.receive(.released(id))
        activeCount = max(0, activeCount - 1)
        if var record = sessions[sessionID] {
            record.active = max(0, record.active - 1)
            record.probes = record.probes.filter { $0.value !== probe }
            sessions[sessionID] = record
            reapIfTerminal(sessionID)
        }
        await drain()
    }

    private func drain() async {
        while activeCount < workers, admission != .paused, !queue.isEmpty {
            guard barrier.openEpoch() != nil else { return }
            let waiter = queue[0]
            guard let record = sessions[waiter.sessionID], record.state == .open else {
                queue.removeFirst(); sessions[waiter.sessionID]?.queued = max(0, (sessions[waiter.sessionID]?.queued ?? 1) - 1)
                await hook?.receive(.released(waiter.id)); waiter.continuation.resume(throwing: CancellationError()); continue
            }
            await hook?.receive(.granting(waiter.id))
            guard queue.first?.id == waiter.id, barrier.openEpoch() != nil else { return }
            await hook?.receive(.operationStarting(waiter.id))
            guard queue.first?.id == waiter.id, barrier.openEpoch() != nil else { return }
            queue.removeFirst(); sessions[waiter.sessionID]?.queued -= 1
            activeCount += 1; sessions[waiter.sessionID]?.active += 1
            sessions[waiter.sessionID]?.probes[UUID()] = waiter.probe
            await hook?.receive(.grantedBeforeReturn(waiter.id))
            waiter.continuation.resume()
        }
    }

    public func cancel(session: WorkSession) async {
        guard session.schedulerID == schedulerID, var record = sessions[session.id] else { return }
        record.state = .cancelled; sessions[session.id] = record
        for probe in record.probes.values { await probe.cancel() }
        await removeQueued(sessionID: session.id)
        reapIfTerminal(session.id); await drain()
    }

    public func finish(session: WorkSession) async {
        guard session.schedulerID == schedulerID, var record = sessions[session.id] else { return }
        record.state = .finished; sessions[session.id] = record
        for probe in record.probes.values { await probe.cancel() }
        await removeQueued(sessionID: session.id)
        reapIfTerminal(session.id); await drain()
    }

    private func removeQueued(sessionID: UUID) async {
        let removed = queue.filter { $0.sessionID == sessionID }
        queue.removeAll { $0.sessionID == sessionID }
        sessions[sessionID]?.queued = 0
        for waiter in removed {
            await hook?.receive(.released(waiter.id)); waiter.continuation.resume(throwing: CancellationError())
        }
    }

    private func reapIfTerminal(_ id: UUID) {
        guard let record = sessions[id], record.state != .open,
              record.active == 0, record.queued == 0 else { return }
        sessions.removeValue(forKey: id); addTombstone(id, record.state)
    }
    private func addTombstone(_ id: UUID, _ state: WorkSessionState) {
        guard limits.tombstones > 0 else { return }
        tombstones[id] = state; tombstoneOrder.append(id)
        while tombstoneOrder.count > limits.tombstones {
            tombstones.removeValue(forKey: tombstoneOrder.removeFirst())
        }
    }

    public func state(of session: WorkSession) -> WorkSessionState? {
        guard session.schedulerID == schedulerID else { return nil }
        return sessions[session.id]?.state ?? tombstones[session.id]
    }
    public func snapshot() -> WorkSchedulerSnapshot {
        WorkSchedulerSnapshot(availability: availability, settingsRevision: revision,
            generation: generation, observationEpoch: epoch, effectiveWorkers: workers,
            effectiveReadOnlyProcesses: processes, admission: admission,
            active: activeCount, queued: queue.count, liveSessions: sessions.count,
            tombstones: tombstones.count)
    }

    fileprivate func install(_ resolution: SchedulerResolution, revision: UInt64,
                             generation: UInt64, epoch: UInt64) async {
        self.revision = revision; self.generation = generation; self.epoch = epoch
        workers = resolution.workers; processes = resolution.processes
        admission = resolution.admission; features = resolution.features
        availability = .available
        await drain()
    }
    fileprivate func markUnavailable() { availability = .unavailable }
    fileprivate func admissionOpened() async { await drain() }
    fileprivate func prepareInvalidation(from old: SchedulerResolution?, to new: SchedulerResolution) async {
        guard let old else { return }
        let lost = old.features.subtracting(new.features)
        let sliceChanged = old.slice != new.slice
        let narrowed = old.admission == .discretionaryAllowed && new.admission != .discretionaryAllowed
        for (id, record) in sessions {
            if sliceChanged || !record.requirements.features.isDisjoint(with: lost) || (narrowed && record.discretionary) {
                for probe in record.probes.values { await probe.cancel() }
                if var changed = sessions[id] { changed.state = .cancelled; sessions[id] = changed }
                await removeQueued(sessionID: id); reapIfTerminal(id)
            }
        }
    }
}

internal actor SchedulerPolicyController {
    nonisolated private let controllerID: UUID
    nonisolated private let schedulerID: UUID
    nonisolated private let barrier: SchedulerAdmissionBarrier
    private let inputs: SchedulerResolutionInputs
    private let scheduler: WorkScheduler
    private let hook: (any SchedulerTestHook)?
    private var acknowledged: SettingsEnvelope?
    private var operative: SchedulerResolution?
    private var generation: UInt64
    private var epoch: UInt64
    private var currentInvalidating: UUID?
    private var currentPresentation: UUID?
    private var consumed: Set<UUID> = []
    private var consumedOrder: [UUID] = []

    private init(inputs: SchedulerResolutionInputs, limits: WorkSchedulerLimits,
                 generation: UInt64, epoch: UInt64, waiterID: UInt64,
                 hook: (any SchedulerTestHook)?) {
        controllerID = UUID(); schedulerID = UUID(); barrier = SchedulerAdmissionBarrier()
        self.inputs = inputs; self.generation = generation; self.epoch = epoch; self.hook = hook
        scheduler = WorkScheduler(id: schedulerID, barrier: barrier, limits: limits,
            generation: generation, epoch: epoch, waiterID: waiterID, hook: hook)
    }

    internal static func make(inputs: SchedulerResolutionInputs,
                              limits: WorkSchedulerLimits = try! .init()) throws
      -> (controller: SchedulerPolicyController, scheduler: WorkScheduler,
          capability: SchedulerPolicyControllerCapability) {
        let controller = SchedulerPolicyController(inputs: inputs, limits: limits,
            generation: 0, epoch: 0, waiterID: 0, hook: nil)
        return (controller, controller.scheduler,
                SchedulerPolicyControllerCapability(controllerID: controller.controllerID))
    }
    internal static func makeForTesting(inputs: SchedulerResolutionInputs,
        limits: WorkSchedulerLimits, initialGeneration: UInt64,
        initialObservationEpoch: UInt64, initialWaiterID: UInt64,
        hook: any SchedulerTestHook) throws
      -> (controller: SchedulerPolicyController, scheduler: WorkScheduler,
          capability: SchedulerPolicyControllerCapability) {
        let controller = SchedulerPolicyController(inputs: inputs, limits: limits,
            generation: initialGeneration, epoch: initialObservationEpoch,
            waiterID: initialWaiterID, hook: hook)
        return (controller, controller.scheduler,
                SchedulerPolicyControllerCapability(controllerID: controller.controllerID))
    }

    nonisolated func beginAdmissionTransition(
        using capability: SchedulerPolicyControllerCapability) throws -> SchedulerAdmissionTicket {
        guard capability.controllerID == controllerID else { throw WorkSchedulerError.foreignController }
        return try barrier.begin(controllerID: controllerID)
    }

    nonisolated func acquireAdmissionHold(
        using capability: SchedulerPolicyControllerCapability) throws -> SchedulerAdmissionHold {
        guard capability.controllerID == controllerID else { throw WorkSchedulerError.foreignController }
        let hold = SchedulerAdmissionHold(controllerID: controllerID, id: UUID())
        barrier.acquireAdmissionHold(hold.id)
        return hold
    }

    internal func releaseAdmissionHold(_ hold: SchedulerAdmissionHold,
                                       using capability: SchedulerPolicyControllerCapability) async {
        guard capability.controllerID == controllerID, hold.controllerID == controllerID else { return }
        if barrier.releaseAdmissionHold(hold.id) { await scheduler.admissionOpened() }
    }

    internal func prepare(_ admission: SchedulerAdmissionTicket,
        candidate: SettingsEnvelope, observation: SchedulerObservation,
        using capability: SchedulerPolicyControllerCapability) async -> SchedulerPrepareResult {
        guard capability.controllerID == controllerID, admission.controllerID == controllerID else {
            return .rejected(.foreignToken)
        }
        guard barrier.isCurrent(admission) else { return .rejected(.superseded) }
        if let revision = acknowledged?.revision, candidate.revision <= revision {
            barrier.unavailable(); await scheduler.markUnavailable()
            return .rejected(.staleRevision(current: revision))
        }
        let resolved: SchedulerResolution
        do { resolved = try resolve(candidate, observation: observation) }
        catch let reason as SchedulerFailureReason {
            barrier.unavailable(); await scheduler.markUnavailable(); return .failedClosed(reason)
        } catch {
            barrier.unavailable(); await scheduler.markUnavailable(); return .failedClosed(.invalidPolicyDocument)
        }
        let (next, overflow) = generation.addingReportingOverflow(1)
        guard !overflow else {
            barrier.unavailable(); await scheduler.markUnavailable(); return .failedClosed(.generationOverflow)
        }
        generation = next
        let effect: AuthorityEffect
        if let acknowledged {
            do { effect = try PreferencesDocumentEffect.classify(before: acknowledged, after: candidate) }
            catch {
                if legacyProjectionChanged(before: acknowledged, after: candidate) { effect = .invalidate }
                else { barrier.unavailable(); await scheduler.markUnavailable(); return .failedClosed(.invalidPolicyDocument) }
            }
        } else { effect = .invalidate }
        let id = UUID(); currentInvalidating = id; currentPresentation = nil
        let token = PreparedSchedulerPolicy(controllerID: controllerID, id: id,
            generation: generation, candidate: candidate, resolution: resolved, ticket: admission)
        await hook?.receive(.invalidationClaiming(revision: candidate.revision))
        guard barrier.claimPreparation(admission) else {
            if currentInvalidating == id { currentInvalidating = nil }
            return .rejected(.superseded)
        }
        await scheduler.prepareInvalidation(from: operative, to: resolved)
        await hook?.receive(.invalidationPrepared(revision: candidate.revision))
        guard barrier.isCurrent(admission) else {
            if currentInvalidating == id { currentInvalidating = nil }
            return .rejected(.superseded)
        }
        return .prepared(token, effect)
    }

    internal func preparePresentation(candidate: SettingsEnvelope,
        observation: SchedulerObservation,
        using capability: SchedulerPolicyControllerCapability) async
      -> SchedulerPresentationPrepareResult {
        guard capability.controllerID == controllerID else { return .rejected(.foreignToken) }
        guard let acknowledged, let operative else { return .rejected(.firstInstallRequiresInvalidation) }
        guard let openEpoch = barrier.openEpoch() else { return .rejected(.superseded) }
        guard candidate.revision > acknowledged.revision else {
            return .rejected(.staleRevision(current: acknowledged.revision))
        }
        let resolved: SchedulerResolution
        do { resolved = try resolve(candidate, observation: observation) }
        catch SchedulerFailureReason.legacyCompatibilityMismatch { return .rejected(.legacyCompatibilityMismatch) }
        catch { return .rejected(.invalidPolicyDocument) }
        let effect: AuthorityEffect
        do { effect = try PreferencesDocumentEffect.classify(before: acknowledged, after: candidate) }
        catch { return .rejected(.invalidPolicyDocument) }
        guard effect == .none, resolved.identity == operative.identity else { return .rejected(.notPresentationOnly) }
        let id = UUID(); currentPresentation = id
        let token = PreparedSchedulerPresentation(controllerID: controllerID, id: id,
            candidate: candidate, resolution: resolved, epoch: epoch, barrierEpoch: openEpoch)
        await hook?.receive(.presentationPrepared(revision: candidate.revision))
        guard barrier.openEpoch() == openEpoch else { return .rejected(.superseded) }
        return .prepared(token, effect)
    }

    internal func commit(_ prepared: PreparedSchedulerPolicy,
        acknowledgedEnvelope: SettingsEnvelope,
        using capability: SchedulerPolicyControllerCapability) async -> SchedulerCommitResult {
        guard capability.controllerID == controllerID else { return .rejected(.foreignToken) }
        guard prepared.controllerID == controllerID else { return .rejected(.foreignToken) }
        if consumed.contains(prepared.id) { return .rejected(.consumed) }
        guard currentInvalidating == prepared.id else { return .rejected(.superseded) }
        guard barrier.isCurrent(prepared.ticket) else { return .rejected(.superseded) }
        guard acknowledgedEnvelope == prepared.candidate else {
            recordConsumed(prepared.id); currentInvalidating = nil
            barrier.unavailable(); await scheduler.markUnavailable(); return .failedClosed(.candidateMismatch)
        }
        guard barrier.claim(prepared.ticket) else { return .rejected(.superseded) }
        recordConsumed(prepared.id); currentInvalidating = nil
        acknowledged = acknowledgedEnvelope; operative = prepared.resolution
        await scheduler.install(prepared.resolution, revision: acknowledgedEnvelope.revision,
            generation: prepared.generation, epoch: epoch)
        guard barrier.finish(prepared.ticket) else { await scheduler.markUnavailable(); return .rejected(.superseded) }
        await scheduler.admissionOpened()
        return .committed(settingsRevision: acknowledgedEnvelope.revision)
    }

    internal func fail(_ prepared: PreparedSchedulerPolicy,
        using capability: SchedulerPolicyControllerCapability) async -> SchedulerFailResult {
        guard capability.controllerID == controllerID, prepared.controllerID == controllerID else {
            return .rejected(.foreignToken)
        }
        if consumed.contains(prepared.id) { return .rejected(.consumed) }
        guard currentInvalidating == prepared.id else { return .rejected(.superseded) }
        guard barrier.isCurrent(prepared.ticket) else { return .rejected(.superseded) }
        recordConsumed(prepared.id); currentInvalidating = nil; barrier.unavailable()
        await scheduler.markUnavailable(); return .failedClosed
    }

    internal func commitPresentation(_ prepared: PreparedSchedulerPresentation,
        acknowledgedEnvelope: SettingsEnvelope,
        using capability: SchedulerPolicyControllerCapability) async -> SchedulerCommitResult {
        guard capability.controllerID == controllerID, prepared.controllerID == controllerID else {
            return .rejected(.foreignToken)
        }
        if consumed.contains(prepared.id) { return .rejected(.consumed) }
        guard currentPresentation == prepared.id else { return .rejected(.superseded) }
        guard barrier.openEpoch() == prepared.barrierEpoch else { return .rejected(.superseded) }
        guard acknowledgedEnvelope == prepared.candidate else {
            recordConsumed(prepared.id); currentPresentation = nil
            return .failedClosed(.candidateMismatch)
        }
        guard prepared.epoch == epoch else { return .rejected(.superseded) }
        guard barrier.claimPresentation(prepared.barrierEpoch) else { return .rejected(.superseded) }
        recordConsumed(prepared.id); currentPresentation = nil
        acknowledged = acknowledgedEnvelope; operative = prepared.resolution
        await scheduler.install(prepared.resolution, revision: acknowledgedEnvelope.revision,
            generation: generation, epoch: epoch)
        guard barrier.finishPresentation(prepared.barrierEpoch) else { return .rejected(.superseded) }
        return .committed(settingsRevision: acknowledgedEnvelope.revision)
    }

    internal func discardPresentation(_ prepared: PreparedSchedulerPresentation,
        using capability: SchedulerPolicyControllerCapability) async -> SchedulerPresentationDiscardResult {
        guard capability.controllerID == controllerID, prepared.controllerID == controllerID else {
            return .rejected(.foreignToken)
        }
        if consumed.contains(prepared.id) { return .rejected(.consumed) }
        guard currentPresentation == prepared.id else { return .rejected(.superseded) }
        guard barrier.openEpoch() == prepared.barrierEpoch else { return .rejected(.superseded) }
        recordConsumed(prepared.id); currentPresentation = nil; return .discarded
    }

    internal func updateObservation(epoch newEpoch: UInt64,
        observation: SchedulerObservation, acknowledgedEnvelope: SettingsEnvelope,
        using capability: SchedulerPolicyControllerCapability) async -> SchedulerObservationResult {
        guard capability.controllerID == controllerID, let acknowledged,
              acknowledged == acknowledgedEnvelope else { return .failedClosed(.envelopeMismatch) }
        guard currentInvalidating == nil, currentPresentation == nil,
              barrier.openEpoch() != nil else { return .failedClosed(.envelopeMismatch) }
        guard newEpoch > epoch else { return .rejectedStale(current: epoch) }
        let resolved: SchedulerResolution
        do { resolved = try resolve(acknowledgedEnvelope, observation: observation) }
        catch let reason as SchedulerFailureReason { return .failedClosed(reason) }
        catch { return .failedClosed(.invalidPolicyDocument) }
        epoch = newEpoch; operative = resolved
        await scheduler.install(resolved, revision: acknowledgedEnvelope.revision,
            generation: generation, epoch: newEpoch)
        return .applied
    }

    internal func issueExplicitCapability(requirements: SchedulerRequirements,
        using capability: SchedulerPolicyControllerCapability) async throws -> ExplicitWorkCapability {
        guard capability.controllerID == controllerID else { throw WorkSchedulerError.foreignController }
        guard acknowledged != nil, let operative else { throw WorkSchedulerError.admissionUnavailable }
        guard operative.admission != .paused else { throw WorkSchedulerError.admissionUnavailable }
        guard requirements.features.isSubset(of: operative.features) else { throw WorkSchedulerError.disabledFeature }
        guard let barrierEpoch = barrier.openEpoch() else { throw WorkSchedulerError.admissionUnavailable }
        return ExplicitWorkCapability(schedulerID: schedulerID, id: UUID(), use: ExplicitCapabilityUse(), requirements: requirements,
            barrierEpoch: barrierEpoch, epoch: epoch, generation: generation)
    }
    internal func beginDiscretionarySession(requirements: SchedulerRequirements,
        using capability: SchedulerPolicyControllerCapability) async throws -> WorkSession {
        guard capability.controllerID == controllerID else { throw WorkSchedulerError.foreignController }
        return try await scheduler.beginDiscretionary(requirements)
    }
    internal func resolvedPolicyForTesting(
        using capability: SchedulerPolicyControllerCapability) -> EffectivePolicy? {
        guard capability.controllerID == controllerID else { return nil }; return operative?.policy
    }
    internal func replayCountForTesting() -> Int { consumed.count }
    private func recordConsumed(_ id: UUID) {
        consumed.insert(id); consumedOrder.append(id)
        while consumedOrder.count > 64 { consumed.remove(consumedOrder.removeFirst()) }
    }

    private func resolve(_ envelope: SettingsEnvelope,
                         observation: SchedulerObservation) throws -> SchedulerResolution {
        guard envelope.schemaVersion == TidyConfig.currentSchemaVersion, envelope.revision > 0 else {
            throw SchedulerFailureReason.invalidPolicyDocument
        }
        let profiles = envelope.preferences?.profiles ?? []
        guard Set(profiles.map(\.id)).count == profiles.count else { throw SchedulerFailureReason.duplicateProfileID }
        let profile: SavedProfile?
        if let active = envelope.activeProfileID {
            guard let found = profiles.first(where: { $0.id == active }) else {
                throw SchedulerFailureReason.invalidActiveProfile
            }
            profile = found
        } else { profile = nil }
        try validateCompatibility(envelope)
        do {
            try SettingsTransfer.validatePersistedState(.init(
                preferences: envelope.preferences ?? .init(), inertImports: envelope.inertImports))
        } catch { throw SchedulerFailureReason.invalidPolicyDocument }
        var layers: [PolicyLayer: PolicyValues] = [.global: envelope.preferences?.global ?? .init()]
        if let profile { layers[.profile] = profile.values }
        let low: Bool; let thermal: Bool; let critical: Bool
        switch observation {
        case .nominal, .unknown: low = false; thermal = false; critical = false
        case .constrained: low = true; thermal = true; critical = false
        case .critical: low = true; thermal = true; critical = true
        }
        let policy: EffectivePolicy
        do {
            policy = try PolicyResolver.resolve(.init(layers: layers, selectedVolumeID: nil,
                approvedVolumeIDs: [], capacityBytes: nil, logicalCPUCount: inputs.logicalCPUCount,
                lowPower: low, seriousThermal: thermal, critical: critical,
                mandatoryExclusions: []))
        } catch { throw SchedulerFailureReason.invalidPolicyDocument }
        var workers = policy.walkWorkers
        var admission = policy.scanAdmission
        if observation == .unknown, admission != .paused {
            workers = min(1, workers); admission = .userRequestedOnly
        }
        let features = Set(policy.allowedFeatures.compactMap(SchedulerFeature.init(rawValue:)))
        guard features.count == policy.allowedFeatures.count else { throw SchedulerFailureReason.invalidPolicyDocument }
        guard case .stored(.integer(let sliceValue))? = policy.fields[SettingID(rawValue: "scan.sliceSeconds")]?.value,
              case .stored(.integer(let rateValue))? = policy.fields[SettingID(rawValue: "scan.uiBatchesPerSecond")]?.value,
              let slice = Int(exactly: sliceValue), let rate = Int(exactly: rateValue),
              (30...1_800).contains(slice), (1...4).contains(rate) else {
            throw SchedulerFailureReason.invalidPolicyDocument
        }
        return SchedulerResolution(policy: policy, features: features, workers: workers,
            processes: observation == .unknown && admission == .paused ? 0 : policy.readOnlyProcesses,
            admission: admission, slice: slice, rate: rate)
    }

    private func validateCompatibility(_ envelope: SettingsEnvelope) throws {
        let fields = envelope.preferences?.global.fields ?? [:]
        let canonicalDefaults = TidyConfig(schemaVersion: TidyConfig.currentSchemaVersion)
        let projected = PolicyPreferences.project(legacy: envelope.config, saved: nil)
        let ids = ["browsers.keepCookieDomains", "cleanup.transcriptDays",
            "item.normal.extras.stale-node-modules.inactiveDays", "rescue.showAdvancedMemoryActions"]
        for raw in ids {
            let id = SettingID(rawValue: raw)
            let expected = projected.global.fields[id] ?? PolicyValidator.definition(for: id)?.defaultValue
            guard fields[id] == projected.global.fields[id] || fields[id] == expected else {
                throw SchedulerFailureReason.legacyCompatibilityMismatch
            }
        }
        let reversed = LegacyCompatibilityProjection.reverseProject(canonicalDefaults,
            replacing: nil, with: envelope.preferences?.global ?? .init())
        guard reversed.keepCookieDomains == envelope.config.keepCookieDomains,
              reversed.transcriptAgeThresholdDays == envelope.config.transcriptAgeThresholdDays,
              reversed.staleNodeModulesThresholdDays == envelope.config.staleNodeModulesThresholdDays,
              reversed.allowRestartToReclaimSwap == envelope.config.allowRestartToReclaimSwap else {
            throw SchedulerFailureReason.legacyCompatibilityMismatch
        }
    }

    private func legacyProjectionChanged(before: SettingsEnvelope, after: SettingsEnvelope) -> Bool {
        before.config.keepCookieDomains != after.config.keepCookieDomains ||
        before.config.transcriptAgeThresholdDays != after.config.transcriptAgeThresholdDays ||
        before.config.staleNodeModulesThresholdDays != after.config.staleNodeModulesThresholdDays ||
        before.config.allowRestartToReclaimSwap != after.config.allowRestartToReclaimSwap
    }
}
