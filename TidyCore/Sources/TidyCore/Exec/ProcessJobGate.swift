import Foundation

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
}

/// The sole production process budget. Reservation transfer happens inside
/// the actor before a waiter resumes. Tests may construct isolated gates, but
/// production launch code can only reach `shared`, whose physical cap is two.
actor ProcessJobGate {
    nonisolated static let shared = try! ProcessJobGate(limit: 2)

    private struct Waiter {
        let id: UUID
        let kind: ProcessJobKind
        let continuation: CheckedContinuation<UUID, Error>
    }

    nonisolated let physicalLimit: Int
    private let queueLimit: Int
    private var readOnlyCap: Int
    private var policyRevision: ProcessPolicyRevision?
    private var active: [UUID: ProcessJobKind] = [:]
    private var waiters: [Waiter] = []

    init(limit: Int, queueLimit: Int = 256) throws {
        guard (1...2).contains(limit), (1...256).contains(queueLimit) else {
            throw POSIXError(.EINVAL)
        }
        physicalLimit = limit
        self.queueLimit = queueLimit
        readOnlyCap = limit
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

    func acquire(kind: ProcessJobKind = .readOnly) async throws -> UUID {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if waiters.count >= queueLimit {
                    continuation.resume(throwing: POSIXError(.EAGAIN))
                } else {
                    waiters.append(Waiter(id: id, kind: kind, continuation: continuation))
                    drainEligibleWaiters()
                }
            }
        } onCancel: {
            Task { await self.cancelQueued(id) }
        }
    }

    private var activeReaderCount: Int {
        active.values.reduce(into: 0) { if $1 == .readOnly { $0 += 1 } }
    }

    private func isEligible(_ waiter: Waiter) -> Bool {
        guard active.count < physicalLimit else { return false }
        switch waiter.kind {
        case .mutation: return true
        case .readOnly: return activeReaderCount < readOnlyCap
        }
    }

    /// Strict FIFO among currently eligible work. A cap-zero reader cannot
    /// hold a physical slot hostage from a later mutator; readers retain their
    /// own order and resume in that order when the cap rises.
    private func drainEligibleWaiters() {
        while active.count < physicalLimit,
              let index = waiters.firstIndex(where: isEligible) {
            let next = waiters.remove(at: index)
            active[next.id] = next.kind
            next.continuation.resume(returning: next.id)
        }
    }

    private func cancelQueued(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        drainEligibleWaiters()
    }

    func release(_ reservation: UUID) {
        guard active.removeValue(forKey: reservation) != nil else { return }
        drainEligibleWaiters()
    }

    func snapshot() -> ProcessGateSnapshot {
        let readers = activeReaderCount
        let queuedReaders = waiters.reduce(into: 0) { if $1.kind == .readOnly { $0 += 1 } }
        return ProcessGateSnapshot(active: active.count, queued: waiters.count,
            activeReaders: readers, activeMutators: active.count - readers,
            queuedReaders: queuedReaders, queuedMutators: waiters.count - queuedReaders,
            readOnlyCap: readOnlyCap, physicalLimit: physicalLimit,
            policyRevision: policyRevision)
    }
}
