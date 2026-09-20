import Foundation
import Testing
@testable import TidyCore

@Suite("Budgets and notification policy")
struct BudgetEvaluatorTests {
    private let volume = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let gib: Int64 = 1_024 * 1_024 * 1_024

    @Test("templates remain off until effective policy enables an exact volume budget")
    func disabledTemplate() throws {
        #expect(BudgetEvaluator.templates.allSatisfy { !$0.enabledByDefault })
        let result = BudgetEvaluator.evaluate(policy: try policy([:]), volumeID: volume,
            measurements: [.init(budgetID: .docker, volumeID: volume,
                                 allocatedBytes: 100 * gib)])
        #expect(result.statuses[.docker]?.state == .disabled)
    }

    @Test("known allocations use high and low hysteresis without overlap summing")
    func hysteresis() throws {
        let effective = try policy([
            "budget.docker.enabled": .bool(true),
            "budget.docker.highGiB": .integer(10),
            "budget.docker.lowGiB": .integer(8)
        ])
        let high = BudgetEvaluator.evaluate(policy: effective, volumeID: volume,
            measurements: [.init(budgetID: .docker, volumeID: volume,
                                 allocatedBytes: 10 * gib)])
        #expect(high.statuses[.docker]?.state == .alerting)
        let held = BudgetEvaluator.evaluate(policy: effective, volumeID: volume,
            measurements: [.init(budgetID: .docker, volumeID: volume,
                                 allocatedBytes: 9 * gib)], previous: high)
        #expect(held.statuses[.docker]?.state == .alerting)
        let cleared = BudgetEvaluator.evaluate(policy: effective, volumeID: volume,
            measurements: [.init(budgetID: .docker, volumeID: volume,
                                 allocatedBytes: 8 * gib)], previous: held)
        #expect(cleared.statuses[.docker]?.state == .withinBudget)
    }

    @Test("missing or duplicate measurements preserve a latched warning as unknown")
    func missingDoesNotClear() throws {
        let effective = try policy([
            "budget.docker.enabled": .bool(true),
            "budget.docker.highGiB": .integer(10),
            "budget.docker.lowGiB": .integer(8)
        ])
        let prior = BudgetEvaluator.evaluate(policy: effective, volumeID: volume,
            measurements: [.init(budgetID: .docker, volumeID: volume,
                                 allocatedBytes: 11 * gib)])
        let missing = BudgetEvaluator.evaluate(policy: effective, volumeID: volume,
            measurements: [], previous: prior)
        #expect(missing.statuses[.docker]?.state == .unknown)
        #expect(missing.statuses[.docker]?.alertLatched == true)
        let duplicate = BudgetEvaluator.evaluate(policy: effective, volumeID: volume,
            measurements: [
                .init(budgetID: .docker, volumeID: volume, allocatedBytes: 1),
                .init(budgetID: .docker, volumeID: volume, allocatedBytes: 2)
            ], previous: prior)
        #expect(duplicate.statuses[.docker]?.alertLatched == true)
    }

    @Test("wrapped quiet hours use local civil time across the DST transition")
    func quietHoursAndDST() throws {
        let effective = try policy([
            "notifications.quietHoursEnabled": .bool(true),
            "notifications.quietStart": .choice("22:00"),
            "notifications.quietEnd": .choice("08:00")
        ])
        let authority = LocalAuthoritySnapshot(revision: 1,
            installation: .init(canonicalDirectoryPath: "/fixture", volumeDevice: 1,
                                directoryInode: 2, ownerUID: 501),
            scopes: [.notifications])
        let configuration = NotificationConfiguration.resolve(policy: effective,
                                                               authority: authority)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let spring = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 8, hour: 3, minute: 30)))
        #expect(configuration.isQuiet(at: spring, calendar: calendar))
        let day = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 8, hour: 9, minute: 0)))
        #expect(!configuration.isQuiet(at: day, calendar: calendar))
    }

    @Test("dedup uses monotonic time, survives encoding, and only returns navigation")
    func monotonicCooldown() throws {
        let effective = try policy(["notifications.cooldownMinutes": .integer(15)])
        let authority = LocalAuthoritySnapshot(revision: 1,
            installation: .init(canonicalDirectoryPath: "/fixture", volumeDevice: 1,
                                directoryInode: 2, ownerUID: 501),
            scopes: [.notifications])
        let configuration = NotificationConfiguration.resolve(policy: effective,
                                                               authority: authority)
        let boot = UUID(), now = Date(timeIntervalSince1970: 1_000)
        var state = NotificationDedupState()
        let first = state.decide(event: .pressure, navigation: .headroomReview,
            eligible: true, configuration: configuration, permission: .authorized,
            bootID: boot, nowMonotonicNanoseconds: 1_000_000_000,
            nowWallDate: now, calendar: Calendar(identifier: .gregorian))
        #expect(first == .deliver(.headroomReview))
        let duplicate = state.decide(event: .pressure, navigation: .headroomReview,
            eligible: true, configuration: configuration, permission: .authorized,
            bootID: boot, nowMonotonicNanoseconds: 2_000_000_000,
            nowWallDate: now.addingTimeInterval(100_000),
            calendar: Calendar(identifier: .gregorian))
        #expect(duplicate == .suppress(.cooldown))
        let restored = try NotificationDedupState.decode(state.encoded())
        #expect(restored == state)
        var rollback = restored
        let discontinuity = rollback.decide(event: .pressure, navigation: .headroomReview,
            eligible: true, configuration: configuration, permission: .authorized,
            bootID: boot, nowMonotonicNanoseconds: 1,
            nowWallDate: now.addingTimeInterval(200_000),
            calendar: Calendar(identifier: .gregorian))
        #expect(discontinuity == .suppress(.monotonicDiscontinuity))
    }

    @Test("pressure must remain sustained and unknown data cannot clear an alert")
    func pressureSustainAndRecovery() throws {
        let effective = try policy([
            "notifications.pressureSustainSeconds": .integer(60),
            "notifications.recoverySeconds": .integer(120)
        ])
        let authority = LocalAuthoritySnapshot(revision: 1,
            installation: .init(canonicalDirectoryPath: "/fixture", volumeDevice: 1,
                                directoryInode: 2, ownerUID: 501),
            scopes: [.notifications])
        let configuration = NotificationConfiguration.resolve(policy: effective,
                                                               authority: authority)
        let boot = UUID()
        var state = PressureNotificationState()
        let initial = state.observe(.warning, configuration: configuration,
            bootID: boot, nowMonotonicNanoseconds: 0)
        #expect(!initial)
        let notSustained = state.observe(.warning, configuration: configuration,
            bootID: boot, nowMonotonicNanoseconds: 59_000_000_000)
        #expect(!notSustained)
        let sustained = state.observe(.warning, configuration: configuration,
            bootID: boot, nowMonotonicNanoseconds: 60_000_000_000)
        #expect(sustained)
        let unknown = state.observe(.unknown, configuration: configuration,
            bootID: boot, nowMonotonicNanoseconds: 61_000_000_000)
        #expect(unknown)
        let recovering = state.observe(.normal, configuration: configuration,
            bootID: boot, nowMonotonicNanoseconds: 62_000_000_000)
        #expect(!recovering)
        #expect(state.isAlerting)
        let recovered = state.observe(.normal, configuration: configuration,
            bootID: boot, nowMonotonicNanoseconds: 182_000_000_000)
        #expect(!recovered)
        #expect(!state.isAlerting)
    }

    @Test("a prepared notification configuration observes later authority revoke")
    func notificationRevocationIsLive() throws {
        let epoch = LocalAuthorityEpoch(revision: 1)
        let authority = LocalAuthoritySnapshot(revision: 1,
            installation: .init(canonicalDirectoryPath: "/fixture", volumeDevice: 1,
                                directoryInode: 2, ownerUID: 501),
            scopes: [.notifications], epoch: epoch)
        let configuration = NotificationConfiguration.resolve(
            policy: try policy([:]), authority: authority)
        #expect(configuration.enabled)
        epoch.invalidate()
        #expect(!configuration.enabled)
        var state = NotificationDedupState()
        let decision = state.decide(event: .pressure, navigation: .headroomReview,
            eligible: true, configuration: configuration, permission: .authorized,
            bootID: UUID(), nowMonotonicNanoseconds: 1,
            nowWallDate: Date(), calendar: Calendar(identifier: .gregorian))
        #expect(decision == .suppress(.disabled))
    }

    private func policy(_ fields: [String: SettingValue]) throws -> EffectivePolicy {
        let values = Dictionary(uniqueKeysWithValues: fields.map {
            (SettingID(rawValue: $0.key), $0.value)
        })
        return try PolicyResolver.resolve(PolicyInputs(
            layers: [.global: PolicyValues(fields: values)], selectedVolumeID: volume,
            approvedVolumeIDs: [volume], capacityBytes: 200 * gib,
            logicalCPUCount: 8, lowPower: false, seriousThermal: false,
            critical: false, mandatoryExclusions: []))
    }
}
