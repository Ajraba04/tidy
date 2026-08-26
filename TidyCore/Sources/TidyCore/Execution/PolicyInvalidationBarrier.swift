import Foundation
public struct PolicyUpdateTicket: Sendable {
    internal let coordinatorID: UUID
    internal let revision: UInt64
    internal let nonce: UUID
    fileprivate init(coordinatorID: UUID, revision: UInt64, nonce: UUID) {
        self.coordinatorID = coordinatorID; self.revision = revision; self.nonce = nonce
    }
}
public enum PolicyAdmission: Equatable, Sendable {
    case ready(revision: UInt64), updating(revision: UInt64), unavailable
}
internal enum PolicyCommit: Equatable, Sendable {
    case applied(revision: UInt64), superseded
}
final class PolicyInvalidationBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private let coordinatorID: UUID
    private var revision: UInt64 = 1
    private var pending: PolicyUpdateTicket?
    private var failed = false
    init(coordinatorID: UUID) { self.coordinatorID = coordinatorID }
    func beginUpdate() throws -> PolicyUpdateTicket {
        lock.lock(); defer { lock.unlock() }
        guard !failed, revision < UInt64.max else {
            failed = true; pending = nil
            throw ConfirmationError.stalePolicy
        }
        revision += 1
        let ticket = PolicyUpdateTicket(coordinatorID: coordinatorID, revision: revision, nonce: UUID())
        pending = ticket
        return ticket
    }
    func snapshot() -> PolicyAdmission {
        lock.lock(); defer { lock.unlock() }
        if failed { return .unavailable }
        return pending == nil ? .ready(revision: revision) : .updating(revision: revision)
    }
    func commit<Result>(_ ticket: PolicyUpdateTicket, install: () throws -> Result) throws -> Result? {
        lock.lock(); defer { lock.unlock() }
        guard !failed, let pending, ticket.coordinatorID == coordinatorID,
              ticket.revision == revision, ticket.nonce == pending.nonce else { return nil }
        let result = try install()
        self.pending = nil
        return result
    }
    func withCurrentPolicy<Result>(revision: UInt64, body: () throws -> Result) throws -> Result {
        lock.lock(); defer { lock.unlock() }
        guard !failed, pending == nil, self.revision == revision else { throw ConfirmationError.stalePolicy }
        return try body()
    }
}
