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
        let bootID = UUID()
        let notice = try await authorization.notification(for: grant,
            candidate: candidate(for: grant), authority: authority,
            featureEnabled: true, currentPolicyRevision: 7,
            bootID: bootID, nowMonotonicNanoseconds: 10,
            nowWallDate: Date(timeIntervalSince1970: 1_000))
        #expect(notice.navigation == .reviewCache)
        #expect(notice.observedBytes == 1_024)
    }

    @Test("unknown or active evidence cannot produce even a maintenance notice")
    func unknownActivityBlocks() async throws {
        let grant = try makeGrant(mode: .notifyOnly)
        let authorization = MaintenanceAuthorization()
        let bootID = UUID()
        let unknown = candidate(for: grant, activity: .unknown)
        await #expect(throws: MaintenanceDenial.activeOrUnknown) {
            _ = try await authorization.notification(for: grant, candidate: unknown,
                authority: snapshot(.maintenanceNotifyOnly(grant)), featureEnabled: true,
                currentPolicyRevision: 7, bootID: bootID,
                nowMonotonicNanoseconds: 10,
                nowWallDate: Date(timeIntervalSince1970: 1_000))
        }
    }

    @Test("unknown owner evidence cannot produce a maintenance notice")
    func unknownOwnerBlocks() async throws {
        let grant = try makeGrant(mode: .notifyOnly)
        let authorization = MaintenanceAuthorization()
        await #expect(throws: MaintenanceDenial.ownerUnknown) {
            _ = try await authorization.notification(for: grant,
                candidate: candidate(for: grant, ownerEvidenceKnown: false),
                authority: snapshot(.maintenanceNotifyOnly(grant)),
                featureEnabled: true, currentPolicyRevision: 7,
                bootID: UUID(), nowMonotonicNanoseconds: 10,
                nowWallDate: Date(timeIntervalSince1970: 1_000))
        }
    }

    @Test("notify-only interval survives restart and wall rollback denies across boots")
    func notificationIntervalPersists() async throws {
        let grant = try makeGrant(mode: .notifyOnly)
        let firstBoot = UUID(), secondBoot = UUID()
        let wall = Date(timeIntervalSince1970: 100_000)
        let record = MaintenanceScheduleRecord(ruleID: grant.ruleID, bootID: firstBoot,
            monotonicNanoseconds: 1_000, wallDate: wall)
        let restored = MaintenanceAuthorization(scheduleRecords: [record])
        await #expect(throws: MaintenanceDenial.frequencyLimited) {
            _ = try await restored.notification(for: grant,
                candidate: candidate(for: grant, validUntil: UInt64.max),
                authority: snapshot(.maintenanceNotifyOnly(grant)),
                featureEnabled: true, currentPolicyRevision: 7,
                bootID: firstBoot,
                nowMonotonicNanoseconds: 1_000 + 23 * 3_600 * 1_000_000_000,
                nowWallDate: wall.addingTimeInterval(48 * 3_600))
        }
        await #expect(throws: MaintenanceDenial.clockDiscontinuity) {
            _ = try await restored.notification(for: grant,
                candidate: candidate(for: grant, validUntil: UInt64.max),
                authority: snapshot(.maintenanceNotifyOnly(grant)),
                featureEnabled: true, currentPolicyRevision: 7,
                bootID: secondBoot, nowMonotonicNanoseconds: 500,
                nowWallDate: wall.addingTimeInterval(-1))
        }
        _ = try await restored.notification(for: grant,
            candidate: candidate(for: grant, validUntil: UInt64.max),
            authority: snapshot(.maintenanceNotifyOnly(grant)),
            featureEnabled: true, currentPolicyRevision: 7,
            bootID: secondBoot, nowMonotonicNanoseconds: 500,
            nowWallDate: wall.addingTimeInterval(24 * 3_600))
    }

    @Test("notification state written before maintenance schedules still decodes")
    func legacyNotificationStateDecodes() throws {
        let current = try NotificationDedupState().encoded()
        var object = try #require(JSONSerialization.jsonObject(with: current)
            as? [String: Any])
        object.removeValue(forKey: "maintenanceRecords")
        let legacy = try JSONSerialization.data(withJSONObject: object,
            options: [.sortedKeys])
        let restored = try NotificationDedupState.decode(legacy)
        #expect(restored.maintenanceScheduleRecords.isEmpty)
    }

    @Test("maintenance schedule round-trips and quiet suppression records nothing")
    func maintenanceNotificationStateRoundTripAndQuietHours() throws {
        let grant = try makeGrant(mode: .notifyOnly)
        let authority = snapshotWithNotifications(grant)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let wall = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 1, day: 1, hour: 23)))
        let quiet = NotificationConfiguration.resolve(policy: try notificationPolicy([
            "notifications.quietHoursEnabled": .bool(true),
            "notifications.quietStart": .choice("22:00"),
            "notifications.quietEnd": .choice("08:00")
        ]), authority: authority)
        var state = NotificationDedupState()
        let suppressed = state.decideMaintenance(grant: grant, navigation: .reviewCache,
            configuration: quiet, permission: .authorized, bootID: UUID(),
            nowMonotonicNanoseconds: 1, nowWallDate: wall, calendar: calendar)
        #expect(suppressed == .suppress(.quietHours))
        #expect(state.maintenanceScheduleRecords.isEmpty)

        let allowed = NotificationConfiguration.resolve(
            policy: try notificationPolicy([:]), authority: authority)
        let delivered = state.decideMaintenance(grant: grant, navigation: .reviewCache,
            configuration: allowed, permission: .authorized, bootID: UUID(),
            nowMonotonicNanoseconds: 2, nowWallDate: wall, calendar: calendar)
        #expect(delivered == .deliver(.maintenance(.reviewCache)))
        let restored = try NotificationDedupState.decode(state.encoded())
        #expect(restored == state)
        #expect(restored.maintenanceScheduleRecords.count == 1)
    }

    @Test("maintenance capacity denial leaves shared notification state encodable")
    func maintenanceScheduleCapacityIsLocal() throws {
        let authority = LocalAuthoritySnapshot(revision: 1,
            installation: .init(canonicalDirectoryPath: "/fixture", volumeDevice: 1,
                                directoryInode: 2, ownerUID: 501),
            scopes: [.notifications])
        let configuration = NotificationConfiguration.resolve(
            policy: try notificationPolicy([:]), authority: authority)
        let wall = Date(timeIntervalSince1970: 100_000)
        let calendar = Calendar(identifier: .gregorian)
        var state = NotificationDedupState(), sawCapacity = false
        for index in 0..<256 {
            let grant = try makeGrant(mode: .notifyOnly, ruleID: UUID())
            let decision = state.decideMaintenance(grant: grant,
                navigation: .reviewCache, configuration: configuration,
                permission: .authorized, bootID: UUID(),
                nowMonotonicNanoseconds: UInt64(index + 1),
                nowWallDate: wall, calendar: calendar)
            if decision == .suppress(.maintenanceScheduleCapacity) {
                sawCapacity = true
                break
            }
        }
        #expect(sawCapacity)
        #expect(state.maintenanceScheduleRecords.count < 256)
        _ = try NotificationDedupState.decode(state.encoded())
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

    private func makeGrant(mode: MaintenanceMode,
                           ruleID: UUID = UUID()) throws -> MaintenanceGrant {
        let capability = MaintenanceCapabilityID.appleDerivedData
        return try MaintenanceGrant(ruleID: ruleID, mode: mode, capabilityID: capability,
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
                           ownerEvidenceKnown: Bool = true,
                           immutable: Bool = false) -> MaintenanceCandidate {
        MaintenanceCandidate(capabilityID: grant.capabilityID, root: grant.root,
            allocatedBytes: bytes, itemCount: 1, ageDays: 31, activity: activity,
            evidenceOrigin: origin, ownerEvidenceKnown: ownerEvidenceKnown,
            evidenceValidUntilMonotonicNanoseconds: validUntil,
            immutableOrQuiescentScopeHeld: immutable, ruleVersion: grant.ruleVersion,
            policyRevision: grant.policyRevision)
    }

    private func snapshot(_ scope: LocalAuthorityScope) -> LocalAuthoritySnapshot {
        LocalAuthoritySnapshot(revision: 1,
            installation: .init(canonicalDirectoryPath: "/fixture", volumeDevice: 1,
                                directoryInode: 2, ownerUID: 501), scopes: [scope])
    }

    private func snapshotWithNotifications(_ grant: MaintenanceGrant)
        -> LocalAuthoritySnapshot {
        LocalAuthoritySnapshot(revision: 1,
            installation: .init(canonicalDirectoryPath: "/fixture", volumeDevice: 1,
                                directoryInode: 2, ownerUID: 501),
            scopes: [.notifications, .maintenanceNotifyOnly(grant)])
    }

    private func notificationPolicy(_ fields: [String: SettingValue]) throws
        -> EffectivePolicy {
        let values = Dictionary(uniqueKeysWithValues: fields.map {
            (SettingID(rawValue: $0.key), $0.value)
        })
        return try PolicyResolver.resolve(PolicyInputs(
            layers: [.global: PolicyValues(fields: values)], selectedVolumeID: volume,
            approvedVolumeIDs: [volume], capacityBytes: 200 * 1_024 * 1_024 * 1_024,
            logicalCPUCount: 8, lowPower: false, seriousThermal: false,
            critical: false, mandatoryExclusions: []))
    }
}
