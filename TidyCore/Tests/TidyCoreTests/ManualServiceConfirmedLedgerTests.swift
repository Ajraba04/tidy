import Foundation
import Testing
@testable import TidyCore

@Suite("Confirmed manual service data ledger", .serialized)
struct ManualServiceConfirmedLedgerTests {
    @Test func foreignOwnershipDoesNotConsumeAndOwnedAttemptIsOneUse() async throws {
        let f = try await ConfirmedLedgerFixture.make(); defer { f.remove() }
        var ledger = ManualServiceConfirmedLedger()
        let entry = try ledger.insert(f.record, now: 101)
        for (owner, coordinator, bridge, error) in [
            (UUID(), f.record.coordinatorID, f.record.bridgeID, ManualServiceReviewError.wrongOwner),
            (f.record.ownerID, UUID(), f.record.bridgeID, .wrongCoordinator),
            (f.record.ownerID, f.record.coordinatorID, UUID(), .wrongOwner)
        ] {
            #expect(throws: error) {
                _ = try ledger.take(nonce: entry.nonce, ownerID: owner, coordinatorID: coordinator,
                    bridgeID: bridge, bindingDigest: f.record.summary.bindingDigest,
                    policyRevision: 1, authority: f.record.authority, now: 102)
            }
            #expect(ledger.count == 1)
        }
        let consumed = try f.take(&ledger, nonce: entry.nonce, now: 109)
        #expect(consumed.summary == f.record.summary, "Data consumption never mints confirmed authority")
        #expect(ledger.count == 0)
        #expect(throws: ManualServiceReviewError.unknownReview) {
            _ = try f.take(&ledger, nonce: entry.nonce, now: 109)
        }
    }

    @Test func originalExpiryAndOwnedDenialsCannotBeReplayed() async throws {
        let f = try await ConfirmedLedgerFixture.make(); defer { f.remove() }
        for (now, revision, digest, expected) in [
            (UInt64(110), UInt64(1), f.record.summary.bindingDigest, ManualServiceReviewError.expiredReview),
            (99, 1, f.record.summary.bindingDigest, .expiredReview),
            (109, 2, f.record.summary.bindingDigest, .stalePolicy),
            (109, 1, Data(repeating: 0, count: 32), .bindingMismatch)
        ] {
            var ledger = ManualServiceConfirmedLedger()
            let entry = try ledger.insert(f.record, now: 101)
            #expect(entry.record.summary.expiresAtMonotonicNanoseconds == 110)
            #expect(throws: expected) {
                _ = try f.take(&ledger, nonce: entry.nonce, now: now,
                    revision: revision, digest: digest)
            }
            #expect(throws: ManualServiceReviewError.unknownReview) {
                _ = try f.take(&ledger, nonce: entry.nonce, now: 109)
            }
        }
        var ledger = ManualServiceConfirmedLedger()
        #expect(throws: ManualServiceReviewError.expiredReview) {
            _ = try ledger.insert(f.record, now: 110)
        }
        #expect(ledger.count == 0)
    }

    @Test func revokedLiveAuthorityConsumesOwnedAttemptWithoutMintingAuthority() async throws {
        let f = try await ConfirmedLedgerFixture.make(); defer { f.remove() }
        var ledger = ManualServiceConfirmedLedger()
        let entry = try ledger.insert(f.record, now: 101)
        _ = try await f.authority.revoke(.localRoot(f.rootApproval))
        #expect(throws: ManualServiceReviewError.authorityDenied) {
            _ = try f.take(&ledger, nonce: entry.nonce, now: 102)
        }
        #expect(ledger.count == 0)
    }

    @Test func capacityIs32AndExpiredEntriesArePrunedWithoutExtendingExpiry() async throws {
        let f = try await ConfirmedLedgerFixture.make(); defer { f.remove() }
        var ledger = ManualServiceConfirmedLedger()
        for _ in 0..<32 { _ = try ledger.insert(f.record, now: 101) }
        #expect(ledger.count == 32)
        #expect(throws: ManualServiceReviewError.capacity) { _ = try ledger.insert(f.record, now: 102) }
        var reviews = ManualServiceReviewLedger()
        let fresh = try reviews.insert(binding: f.record.summary.binding, ownerID: f.record.ownerID,
            coordinatorID: f.record.coordinatorID, bridgeID: f.record.bridgeID, policyRevision: 1,
            authority: f.record.authority, now: 110, lifetime: 10)
        let entry = try ledger.insert(fresh, now: 111)
        #expect(ledger.count == 1)
        #expect(entry.record.summary.expiresAtMonotonicNanoseconds == 120)
    }
}

private struct ConfirmedLedgerFixture {
    let root: URL
    let rootApproval: LocalRootApproval
    let authority: LocalAuthorityStore
    let record: ManualServiceReviewLedger.Record
    static func make() async throws -> Self {
        let root = URL(fileURLWithPath: "/private/tmp/Tidy-ConfirmedLedger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let approval = try LocalRootApproval.verify(directory: root)
        let authorityDirectory = root.appendingPathComponent("authority")
        try FileManager.default.createDirectory(at: authorityDirectory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let authority = try LocalAuthorityStore(directory: authorityDirectory,
            installation: LocalInstallationIdentity.verify(directory: authorityDirectory))
        let owner = LocalAuthorityOwner()
        let consent = try await authority.beginReview(scope: .localRoot(approval), owner: owner,
            nowMonotonicNanoseconds: 1)
        _ = try await authority.confirm(consent, owner: owner, nowMonotonicNanoseconds: 2)
        let tool = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/usr/bin/true"))
        let producer = AppleSimulatorProducerIdentity(resolver: tool, simctl: tool,
            developerDirectory: approval, deviceSet: approval, xcodeVersion: "27.0",
            xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        let object = ManualSimulatorObject(udid: UUID(), runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17", name: "Data only",
            state: .booted, isAvailable: true)
        let binding = try ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(object), producer: .appleSimulator(producer))
        var reviews = ManualServiceReviewLedger()
        let record = try reviews.insert(binding: binding, ownerID: UUID(), coordinatorID: UUID(),
            bridgeID: UUID(), policyRevision: 1, authority: await authority.snapshot(), now: 100, lifetime: 10)
        return Self(root: root, rootApproval: approval, authority: authority, record: record)
    }
    func take(_ ledger: inout ManualServiceConfirmedLedger, nonce: UUID, now: UInt64,
              revision: UInt64 = 1, digest: Data? = nil) throws -> ManualServiceReviewLedger.Record {
        try ledger.take(nonce: nonce, ownerID: record.ownerID, coordinatorID: record.coordinatorID,
            bridgeID: record.bridgeID, bindingDigest: digest ?? record.summary.bindingDigest,
            policyRevision: revision, authority: record.authority, now: now)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
