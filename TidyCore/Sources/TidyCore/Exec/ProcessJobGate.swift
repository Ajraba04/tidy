import Foundation

struct ProcessGateSnapshot: Sendable {
    let active: Int
    let queued: Int
}

/// Reservation transfer happens inside the actor, before a waiter resumes.
actor ProcessJobGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<UUID, Error>
    }
    private let limit: Int
    private var active: Set<UUID> = []
    private var waiters: [Waiter] = []

    init(limit: Int) throws {
        guard (1...2).contains(limit) else { throw POSIXError(.EINVAL) }
        self.limit = limit
    }

    func acquire() async throws -> UUID {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if active.count < limit {
                    active.insert(id)
                    continuation.resume(returning: id)
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelQueued(id) }
        }
    }

    private func cancelQueued(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    func release(_ reservation: UUID) {
        guard active.remove(reservation) != nil else { return }
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            active.insert(next.id)
            next.continuation.resume(returning: next.id)
        }
    }

    func snapshot() -> ProcessGateSnapshot {
        ProcessGateSnapshot(active: active.count, queued: waiters.count)
    }
}
