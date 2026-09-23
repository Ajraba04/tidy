import Darwin
import Foundation
import Testing
@testable import TidyCore

@Suite("Local authority store", .serialized)
struct LocalAuthorityStoreTests {
    @Test("review tokens are owner-bound, explicit, expiring, and revoked by generation")
    func tokenLifecycle() async throws {
        let scratch = try authorityScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let identity = try LocalInstallationIdentity.verify(directory: scratch)
        let store = try LocalAuthorityStore(directory: scratch, installation: identity)
        let owner = LocalAuthorityOwner(), other = LocalAuthorityOwner()
        let token = try await store.beginReview(scope: .notifications, owner: owner,
            nowMonotonicNanoseconds: 10, validityNanoseconds: 100)
        await #expect(throws: LocalAuthorityError.wrongOwner) {
            _ = try await store.confirm(token, owner: other, nowMonotonicNanoseconds: 11)
        }
        #expect(!(try await store.snapshot()).permits(.notifications))
        let confirmed = try await store.confirm(token, owner: owner,
            nowMonotonicNanoseconds: 12)
        #expect(confirmed.permits(.notifications))
        #expect(confirmed.revision == 1)

        let stale = try await store.beginReview(scope: .notifications, owner: owner,
            nowMonotonicNanoseconds: 20, validityNanoseconds: 100)
        let revoked = try await store.revoke(.notifications)
        #expect(!revoked.permits(.notifications))
        #expect(!confirmed.isCurrent)
        #expect(!confirmed.permits(.notifications))
        await #expect(throws: LocalAuthorityError.unknownReview) {
            _ = try await store.confirm(stale, owner: owner, nowMonotonicNanoseconds: 21)
        }

        let expired = try await store.beginReview(scope: .backgroundSignals,
            owner: owner, nowMonotonicNanoseconds: 100, validityNanoseconds: 10)
        await #expect(throws: LocalAuthorityError.expiredReview) {
            _ = try await store.confirm(expired, owner: owner, nowMonotonicNanoseconds: 111)
        }

        let cancelled = try await store.beginReview(scope: .backgroundSignals,
            owner: owner, nowMonotonicNanoseconds: 200)
        try await store.cancel(cancelled, owner: owner)
        await #expect(throws: LocalAuthorityError.unknownReview) {
            _ = try await store.confirm(cancelled, owner: owner,
                                        nowMonotonicNanoseconds: 201)
        }

        let login = try await store.beginReview(scope: .launchAtLogin,
            owner: owner, nowMonotonicNanoseconds: 300)
        let loginSnapshot = try await store.confirm(login, owner: owner,
            nowMonotonicNanoseconds: 301)
        #expect(loginSnapshot.permits(.launchAtLogin))
        let loginRevoked = try await store.revoke(.launchAtLogin)
        #expect(!loginRevoked.permits(.launchAtLogin))
    }

    @Test("durable ledger starts empty and remains owner-private")
    func durablePrivateLedger() async throws {
        let scratch = try authorityScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let identity = try LocalInstallationIdentity.verify(directory: scratch)
        let store = try LocalAuthorityStore(directory: scratch, installation: identity)
        #expect((try await store.snapshot()).scopes.isEmpty)
        let owner = LocalAuthorityOwner()
        let token = try await store.beginReview(scope: .backgroundSignals, owner: owner,
            nowMonotonicNanoseconds: 1)
        _ = try await store.confirm(token, owner: owner, nowMonotonicNanoseconds: 2)

        let ledger = scratch.appendingPathComponent("local-authority-v1.json")
        var info = stat()
        #expect(lstat(ledger.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFREG)
        #expect(info.st_mode & 0o777 == 0o600)
        #expect(info.st_uid == geteuid())
        let bytes = try Data(contentsOf: ledger)
        #expect(bytes.count <= 128 * 1_024)
        #expect(String(decoding: bytes, as: UTF8.self).contains("backgroundSignals"))
    }

    @Test("installation binding rejects a different local directory")
    func installationBinding() throws {
        let first = try authorityScratch(), second = try authorityScratch()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let identity = try LocalInstallationIdentity.verify(directory: first)
        #expect(throws: LocalAuthorityError.unsafeLocation) {
            _ = try LocalAuthorityStore(directory: second, installation: identity)
        }
    }

    @Test("a missing approved root becomes stale without bricking revoke or other grants")
    func staleRootIsRevocable() async throws {
        let scratch = try authorityScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let approvedDirectory = scratch.deletingLastPathComponent()
            .appendingPathComponent("Tidy-approved-root-\(UUID().uuidString)",
                                    isDirectory: true)
        defer { try? FileManager.default.removeItem(at: approvedDirectory) }
        try FileManager.default.createDirectory(at: approvedDirectory,
                                                withIntermediateDirectories: false)
        let root = try LocalRootApproval.verify(directory: approvedDirectory)
        let scope = LocalAuthorityScope.localRoot(root)
        let store = try LocalAuthorityStore(directory: scratch,
            installation: LocalInstallationIdentity.verify(directory: scratch))
        let owner = LocalAuthorityOwner()
        let token = try await store.beginReview(scope: scope, owner: owner,
            nowMonotonicNanoseconds: 1)
        let active = try await store.confirm(token, owner: owner,
                                             nowMonotonicNanoseconds: 2)
        #expect(active.permits(scope))

        try FileManager.default.removeItem(at: approvedDirectory)
        let stale = try await store.snapshot()
        #expect(!stale.permits(scope))
        #expect(stale.staleScopes.contains(scope))
        #expect(stale.recordedScopes.contains(scope))
        let revoked = try await store.revoke(scope)
        #expect(!revoked.recordedScopes.contains(scope))
    }

    private func authorityScratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tidy-authority-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        guard chmod(url.path, 0o700) == 0 else { throw POSIXError(.EACCES) }
        return url
    }
}
