import Foundation
import Testing
@testable import TidyCore

@Suite("Bounded maintenance")
struct MaintenanceRulesTests {
    private let volume = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    @Test("notify-only returns review navigation for exact fresh idle evidence")
    func notifyOnlyIsUsefulWithoutMutation() async throws {
        let grant = try makeGrant(mode: .notifyOnly)
        let authority = snapshot(.maintenanceNotifyOnly(grant))
        let authorization = MaintenanceAuthorization()
        let notice = try await authorization.notification(for: grant,
            candidate: candidate(for: grant), authority: authority,
            featureEnabled: true, currentPolicyRevision: 7,
            nowMonotonicNanoseconds: 10)
        #expect(notice.navigation == .reviewCache)
        #expect(notice.observedBytes == 1_024)
    }

    @Test("unknown or active evidence cannot produce even a maintenance notice")
    func unknownActivityBlocks() async throws {
        let grant = try makeGrant(mode: .notifyOnly)
        let authorization = MaintenanceAuthorization()
        let unknown = candidate(for: grant, activity: .unknown)
        await #expect(throws: MaintenanceDenial.activeOrUnknown) {
            _ = try await authorization.notification(for: grant, candidate: unknown,
                authority: snapshot(.maintenanceNotifyOnly(grant)), featureEnabled: true,
                currentPolicyRevision: 7, nowMonotonicNanoseconds: 10)
        }
    }

    @Test("the source-closed unattended allowlist is empty")
    func unattendedStartsEmpty() async throws {
        #expect(MaintenanceRules.unattendedCapabilityIDs.isEmpty)
        let grant = try makeGrant(mode: .authorizedCaches)
        let authorization = MaintenanceAuthorization()
        await #expect(throws: MaintenanceDenial.capabilityNotAllowlisted) {
            _ = try await authorization.beginReview(grant: grant,
                candidate: candidate(for: grant, immutable: true),
                authority: snapshot(.maintenanceCaches(grant)), featureEnabled: true,
                currentPolicyRevision: 7, bootID: UUID(),
                nowMonotonicNanoseconds: 10, nowWallDate: Date())
        }
    }

    @Test("imports, stale evidence, wrong policy, and caps fail closed")
    func unsafeEvidenceDenied() throws {
        let grant = try makeGrant(mode: .notifyOnly)
        #expect(throws: MaintenanceDenial.importedOrManualEvidence) {
            try MaintenanceRules.validate(grant: grant,
                candidate: candidate(for: grant, origin: .imported), featureEnabled: true,
                currentPolicyRevision: 7, nowMonotonicNanoseconds: 10,
                requireImmutableScope: false)
        }
        #expect(throws: MaintenanceDenial.staleEvidence) {
            try MaintenanceRules.validate(grant: grant,
                candidate: candidate(for: grant, validUntil: 9), featureEnabled: true,
                currentPolicyRevision: 7, nowMonotonicNanoseconds: 10,
                requireImmutableScope: false)
        }
        #expect(throws: MaintenanceDenial.policyChanged) {
            try MaintenanceRules.validate(grant: grant, candidate: candidate(for: grant),
                featureEnabled: true, currentPolicyRevision: 8,
                nowMonotonicNanoseconds: 10, requireImmutableScope: false)
        }
        #expect(throws: MaintenanceDenial.capExceeded) {
            try MaintenanceRules.validate(grant: grant,
                candidate: candidate(for: grant, bytes: grant.maxBytes + 1),
                featureEnabled: true, currentPolicyRevision: 7,
                nowMonotonicNanoseconds: 10, requireImmutableScope: false)
        }
    }

    @Test("hard automatic bounds reject oversized grants")
    func grantBounds() throws {
        let capability = MaintenanceCapabilityID.appleDerivedData
        let root = LocalRootApproval(canonicalPath: "/fixture/cache", volumeID: volume,
                                     device: 1, inode: 2)
        #expect(throws: MaintenanceRuleError.invalidBounds) {
            _ = try MaintenanceGrant(mode: .authorizedCaches, capabilityID: capability,
                root: root, maxBytes: 5 * 1_024 * 1_024 * 1_024 + 1,
                maxItems: 20, deadlineSeconds: 120, minimumAgeDays: 30,
                minimumIntervalHours: 24, ruleVersion: 1, policyRevision: 7)
        }
    }

    private func makeGrant(mode: MaintenanceMode) throws -> MaintenanceGrant {
        let capability = MaintenanceCapabilityID.appleDerivedData
        return try MaintenanceGrant(mode: mode, capabilityID: capability,
            root: LocalRootApproval(canonicalPath: "/fixture/cache", volumeID: volume,
                                    device: 1, inode: 2),
            maxBytes: 1_024 * 1_024, maxItems: 2, deadlineSeconds: 60,
            minimumAgeDays: 30, minimumIntervalHours: 24,
            ruleVersion: 1, policyRevision: 7)
    }

    private func candidate(for grant: MaintenanceGrant,
                           activity: MaintenanceActivity = .knownIdle,
                           origin: MaintenanceEvidenceOrigin = .supportedAdapter,
                           validUntil: UInt64 = 100,
                           bytes: Int64 = 1_024,
                           immutable: Bool = false) -> MaintenanceCandidate {
        MaintenanceCandidate(capabilityID: grant.capabilityID, root: grant.root,
            allocatedBytes: bytes, itemCount: 1, ageDays: 31, activity: activity,
            evidenceOrigin: origin, evidenceValidUntilMonotonicNanoseconds: validUntil,
            immutableOrQuiescentScopeHeld: immutable, ruleVersion: grant.ruleVersion,
            policyRevision: grant.policyRevision)
    }

    private func snapshot(_ scope: LocalAuthorityScope) -> LocalAuthoritySnapshot {
        LocalAuthoritySnapshot(revision: 1,
            installation: .init(canonicalDirectoryPath: "/fixture", volumeDevice: 1,
                                directoryInode: 2, ownerUID: 501), scopes: [scope])
    }
}
