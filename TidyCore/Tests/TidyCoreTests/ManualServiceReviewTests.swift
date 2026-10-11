import Darwin
import Foundation
import Testing
import Dispatch
@testable import TidyCore

@Suite("Store-bound manual service reviews", .serialized)
struct ManualServiceReviewTests {
    @Test @MainActor func coordinatorConsumesUsingFreshClockAfterQueuedValidation() async throws {
        let clock = ManualReviewTestClock(now: DispatchTime.now().uptimeNanoseconds)
        let f = try await ManualReviewFixture.make(clock: clock); defer { f.remove() }
        let facade = f.bridge.manualServices(authority: f.authority)
        let review = try await facade.prepare(binding: f.binding)
        // The bridge has no access to this clock. Its next read occurs at the
        // coordinator's consumption boundary, after the actor hop and scope I/O.
        clock.advanceOnNextRead(by: 61_000_000_000)
        await #expect(throws: ManualServiceReviewError.expiredReview) {
            _ = try await facade.confirm(review)
        }
        #expect(clock.readCount >= 2, "Issuance and consumption must sample the coordinator clock")
        await #expect(throws: ManualServiceReviewError.unknownReview) {
            _ = try await facade.confirm(review)
        }
    }

    @Test @MainActor func disabledDefaultsAndMissingConsentCannotPrepareReview() async throws {
        let disabled = try await ManualReviewFixture.make(enabled: false, grantConsent: true)
        defer { disabled.remove() }
        let facade = disabled.bridge.manualServices(authority: disabled.authority)
        await #expect(throws: ManualServiceReviewError.policyDisabled) {
            _ = try await facade.prepare(binding: disabled.binding)
        }
        let missing = try await ManualReviewFixture.make(enabled: true, grantConsent: false)
        defer { missing.remove() }
        await #expect(throws: ManualServiceReviewError.authorityDenied) {
            _ = try await missing.bridge.manualServices(authority: missing.authority).prepare(binding: missing.binding)
        }
    }

    @Test @MainActor func candidateIsDataAndProductionConfirmationConsumesThenDenies() async throws {
        let f = try await ManualReviewFixture.make(); defer { f.remove() }
        let facade = f.bridge.manualServices(authority: f.authority)
        let review = try await facade.prepare(binding: f.binding)
        #expect(review.requiresProducerReinspection)
        #expect(review.summary.binding == f.binding)
        let expectedBindingDigest = try f.binding.canonicalDigest()
        #expect(review.summary.bindingDigest == expectedBindingDigest)
        #expect(review.summary.expiresAtMonotonicNanoseconds - review.summary.issuedAtMonotonicNanoseconds <= 60_000_000_000)
        await #expect(throws: ManualServiceReviewError.providerUnavailable) {
            _ = try await facade.confirm(review)
        }
        await #expect(throws: ManualServiceReviewError.unknownReview) {
            _ = try await facade.confirm(review)
        }
        #expect(f.coordinator.policyAdmission() == .ready(revision: 1))
    }

    @Test @MainActor func anotherOwnerOrCoordinatorCannotConfirmOrCancelReview() async throws {
        let f = try await ManualReviewFixture.make(); defer { f.remove() }
        let owner = f.bridge.manualServices(authority: f.authority)
        let other = f.bridge.manualServices(authority: f.authority)
        let review = try await owner.prepare(binding: f.binding)
        await #expect(throws: ManualServiceReviewError.wrongOwner) { _ = try await other.confirm(review) }
        await #expect(throws: ManualServiceReviewError.wrongOwner) { try await other.cancelReview(review) }
        let coordinator = ExecutionCoordinator(environment: .init(homeDirectory: f.root.path), journalDirectory: f.journal)
        let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: f.settings,
            loaded: await f.settings.load(), homeDirectory: f.root.path, detectedTools: [])
        await bridge.drain()
        await #expect(throws: ManualServiceReviewError.wrongCoordinator) {
            _ = try await bridge.manualServices(authority: f.authority).confirm(review)
        }
        await #expect(throws: ManualServiceReviewError.providerUnavailable) { _ = try await owner.confirm(review) }
    }

    @Test @MainActor func wrongInstallationRealAuthorityActorCannotSupplyConsent() async throws {
        let f = try await ManualReviewFixture.make(); defer { f.remove() }
        let directory = f.root.appendingPathComponent("other-authority", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let other = try LocalAuthorityStore(directory: directory,
            installation: LocalInstallationIdentity.verify(directory: directory))
        await #expect(throws: ManualServiceReviewError.wrongInstallation) {
            _ = try await f.bridge.manualServices(authority: other).prepare(binding: f.binding)
        }
    }

    @Test @MainActor func exactFeatureInventoryAndActiveProfileRestrictionsDenyCandidates() async throws {
        for id in ["feature.ecosystems", "ecosystem.apple.inventory", "ecosystem.apple.manualActions"] {
            let f = try await ManualReviewFixture.make(extraFields: [.init(rawValue: id): .bool(false)])
            defer { f.remove() }
            await #expect(throws: ManualServiceReviewError.policyDisabled) {
                _ = try await f.bridge.manualServices(authority: f.authority).prepare(binding: f.binding)
            }
        }
        let restricted = try await ManualReviewFixture.make(profileRestricts: true)
        defer { restricted.remove() }
        await #expect(throws: ManualServiceReviewError.policyDisabled) {
            _ = try await restricted.bridge.manualServices(authority: restricted.authority).prepare(binding: restricted.binding)
        }
    }

    @Test @MainActor func dockerRealSocketGrantStillCannotActivateUnacceptedProvider() async throws {
        let f = try await ManualReviewFixture.make(); defer { f.remove() }
        let socketPath = f.root.appendingPathComponent("docker.sock").path
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(socketPath.utf8) + [UInt8(0)]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: bytes) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw POSIXError(.EIO) }
        let socket = try LocalSocketApproval.verify(socket: URL(fileURLWithPath: socketPath))
        let owner = LocalAuthorityOwner()
        let consent = try await f.authority.beginReview(scope: .localSocket(socket), owner: owner, nowMonotonicNanoseconds: 1)
        _ = try await f.authority.confirm(consent, owner: owner, nowMonotonicNanoseconds: 2)
        let producer = DockerProducerIdentity(socket: socket, peerPID: getpid(), peerUID: geteuid(),
            peerBootID: UUID(), peerStartSeconds: 1, peerStartMicroseconds: 2,
            peerExecutable: f.producer.simctl, providerIdentifier: "unaccepted-local",
            daemonID: "uninspected-fixture-daemon", version: .init(engineVersion: "28.0.0",
                apiVersion: "1.51", minimumAPIVersion: "1.44", operatingSystem: "linux", architecture: "arm64"))
        let object = ManualDockerContainerObject(id: String(repeating: "a", count: 64), name: "/uninspected",
            created: "2026-10-10T00:00:00Z", imageID: "sha256:" + String(repeating: "b", count: 64),
            writableLayerBytes: nil, configurationDigest: Data(repeating: 0, count: 32), labelKeys: [])
        let binding = try ManualServiceOperationBinding(adapter: .dockerStoppedContainerRemovalV1,
            object: .container(object), producer: .docker(producer))
        let facade = f.bridge.manualServices(authority: f.authority)
        let review = try await facade.prepare(binding: binding)
        await #expect(throws: ManualServiceReviewError.providerUnavailable) { _ = try await facade.confirm(review) }
        await #expect(throws: ManualServiceReviewError.unknownReview) { _ = try await facade.confirm(review) }
    }

    @Test @MainActor func revokedConsentAndChangedRootRejectBeforeProviderAdmission() async throws {
        let f = try await ManualReviewFixture.make(); defer { f.remove() }
        let facade = f.bridge.manualServices(authority: f.authority)
        let review = try await facade.prepare(binding: f.binding)
        _ = try await f.authority.revoke(.localRoot(f.producer.deviceSet))
        await #expect(throws: ManualServiceReviewError.authorityDenied) { _ = try await facade.confirm(review) }
        try await facade.cancelReview(review)
        let changed = try await ManualReviewFixture.make(); defer { changed.remove() }
        let second = changed.bridge.manualServices(authority: changed.authority)
        let before = try await second.prepare(binding: changed.binding)
        try FileManager.default.moveItem(atPath: changed.producer.deviceSet.canonicalPath,
            toPath: changed.producer.deviceSet.canonicalPath + "-retained")
        try FileManager.default.createDirectory(atPath: changed.producer.deviceSet.canonicalPath,
                                              withIntermediateDirectories: false)
        await #expect(throws: ManualServiceReviewError.authorityDenied) { _ = try await second.confirm(before) }
    }

    @Test @MainActor func presentationSavePreservesReviewButInvalidatingUpdateRejectsImmediately() async throws {
        let f = try await ManualReviewFixture.make(); defer { f.remove() }
        let facade = f.bridge.manualServices(authority: f.authority)
        let review = try await facade.prepare(binding: f.binding)
        var envelope = try #require(f.bridge.acknowledgedEnvelope)
        let presentation = f.bridge.submit(global: .init(baseRevision: envelope.revision,
            id: .init(rawValue: "scan.uiBatchesPerSecond"), baseValue: nil, editedValue: .integer(2)))
        guard case .accepted(_, let saved) = presentation else { Issue.record("Presentation save rejected"); return }
        _ = await saved.value
        #expect(f.coordinator.policyAdmission() == .ready(revision: 1))
        await #expect(throws: ManualServiceReviewError.providerUnavailable) { _ = try await facade.confirm(review) }
        let next = try await facade.prepare(binding: f.binding)
        envelope = try #require(f.bridge.acknowledgedEnvelope)
        let change = f.bridge.submit(global: .init(baseRevision: envelope.revision,
            id: .init(rawValue: "feature.ecosystems"), baseValue: nil, editedValue: .bool(false)))
        guard case .accepted(_, let pending) = change else { Issue.record("Invalidating save rejected"); return }
        await #expect(throws: ManualServiceReviewError.stalePolicy) { _ = try await facade.confirm(next) }
        _ = await pending.value
    }

    @Test @MainActor func supersessionAndCancellationRemovePendingReview() async throws {
        let f = try await ManualReviewFixture.make(); defer { f.remove() }
        let facade = f.bridge.manualServices(authority: f.authority)
        let first = try await facade.prepare(binding: f.binding)
        let second = try await facade.prepare(binding: f.binding)
        await #expect(throws: ManualServiceReviewError.unknownReview) { _ = try await facade.confirm(first) }
        try await facade.cancelReview(second)
        await #expect(throws: ManualServiceReviewError.unknownReview) { _ = try await facade.confirm(second) }
    }

    @Test @MainActor func ledgerConsumptionIsBoundedOwnerRevisionAndClockBoundDataOnly() async throws {
        let f = try await ManualReviewFixture.make(); defer { f.remove() }
        let authority = try await f.authority.snapshot()
        var ledger = ManualServiceReviewLedger()
        let owner = UUID(), coordinator = UUID(), bridge = UUID()
        let record = try ledger.insert(binding: f.binding, ownerID: owner, coordinatorID: coordinator,
            bridgeID: bridge, policyRevision: 1, authority: authority, now: 100, lifetime: 10)
        #expect(throws: ManualServiceReviewError.wrongOwner) {
            _ = try ledger.take(reviewID: record.summary.reviewID, ownerID: UUID(), coordinatorID: coordinator,
                bridgeID: bridge, policyRevision: 1, now: 101)
        }
        let taken = try ledger.take(reviewID: record.summary.reviewID, ownerID: owner, coordinatorID: coordinator,
            bridgeID: bridge, policyRevision: 1, now: 101)
        #expect(taken.summary.binding == f.binding, "Taking ledger data never creates a confirmed effect token")
        #expect(throws: ManualServiceReviewError.unknownReview) {
            _ = try ledger.take(reviewID: record.summary.reviewID, ownerID: owner, coordinatorID: coordinator,
                bridgeID: bridge, policyRevision: 1, now: 102)
        }
        let expired = try ledger.insert(binding: f.binding, ownerID: owner, coordinatorID: coordinator,
            bridgeID: bridge, policyRevision: 1, authority: authority, now: 200, lifetime: 10)
        #expect(throws: ManualServiceReviewError.expiredReview) {
            _ = try ledger.take(reviewID: expired.summary.reviewID, ownerID: owner, coordinatorID: coordinator,
                bridgeID: bridge, policyRevision: 1, now: 210)
        }
        let stale = try ledger.insert(binding: f.binding, ownerID: owner, coordinatorID: coordinator,
            bridgeID: bridge, policyRevision: 1, authority: authority, now: 220, lifetime: 10)
        #expect(throws: ManualServiceReviewError.stalePolicy) {
            _ = try ledger.take(reviewID: stale.summary.reviewID, ownerID: owner, coordinatorID: coordinator,
                bridgeID: bridge, policyRevision: 2, now: 221)
        }
        let clock = try ledger.insert(binding: f.binding, ownerID: owner, coordinatorID: coordinator,
            bridgeID: bridge, policyRevision: 1, authority: authority, now: 250, lifetime: 10)
        #expect(throws: ManualServiceReviewError.expiredReview) {
            _ = try ledger.take(reviewID: clock.summary.reviewID, ownerID: owner, coordinatorID: coordinator,
                bridgeID: bridge, policyRevision: 1, now: 249)
        }
        for _ in 0..<32 {
            _ = try ledger.insert(binding: f.binding, ownerID: UUID(), coordinatorID: coordinator,
                bridgeID: bridge, policyRevision: 1, authority: authority, now: 300, lifetime: 10)
        }
        #expect(ledger.count == 32)
        #expect(throws: ManualServiceReviewError.capacity) {
            _ = try ledger.insert(binding: f.binding, ownerID: UUID(), coordinatorID: coordinator,
                bridgeID: bridge, policyRevision: 1, authority: authority, now: 301, lifetime: 10)
        }
    }
}

@MainActor private struct ManualReviewFixture {
    let root: URL
    let journal: URL
    let settings: SettingsStore
    let authority: LocalAuthorityStore
    let coordinator: ExecutionCoordinator
    let bridge: ExecutionPolicyBridge
    let producer: AppleSimulatorProducerIdentity
    let binding: ManualServiceOperationBinding

    static func make(enabled: Bool = true, grantConsent: Bool = true,
                     extraFields: [SettingID: SettingValue] = [:], profileRestricts: Bool = false,
                     clock: ManualReviewTestClock? = nil) async throws -> Self {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("Tidy-ManualReview-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let authorityDirectory = support.appendingPathComponent("authority", isDirectory: true)
        let developer = root.appendingPathComponent("developer", isDirectory: true)
        let set = root.appendingPathComponent("devices", isDirectory: true)
        for directory in [root, support, authorityDirectory, developer, set] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
        }
        var fields: [SettingID: SettingValue] = enabled ? [
            .init(rawValue: "ecosystem.apple.manualActions"): .bool(true),
            .init(rawValue: "ecosystem.docker.manualActions"): .bool(true)] : [:]
        fields.merge(extraFields) { _, replacement in replacement }
        let profile = SavedProfile(id: UUID(), name: "Restrictive profile",
            values: .init(fields: [.init(rawValue: "ecosystem.apple.manualActions"): .bool(false)]))
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 1, config: TidyConfig(schemaVersion: 2),
            preferences: .init(global: .init(fields: fields), profiles: profileRestricts ? [profile] : []),
            activeProfileID: profileRestricts ? profile.id : nil)
        let configURL = support.appendingPathComponent("config.json")
        try JSONEncoder().encode(envelope).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        let settings = SettingsStore(url: configURL)
        let loaded = await settings.load()
        let journal = support.appendingPathComponent("execution", isDirectory: true)
        let coordinator: ExecutionCoordinator
        if let clock {
            coordinator = ExecutionCoordinator(environment: .init(homeDirectory: root.path),
                journalDirectory: journal, manualServiceNowNanoseconds: { clock.now() })
        } else {
            coordinator = ExecutionCoordinator(environment: .init(homeDirectory: root.path), journalDirectory: journal)
        }
        let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: settings, loaded: loaded,
            homeDirectory: root.path, detectedTools: [])
        await bridge.drain()
        let authority = try LocalAuthorityStore(directory: authorityDirectory,
            installation: LocalInstallationIdentity.verify(directory: authorityDirectory))
        let tool = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/usr/bin/true"))
        let producer = AppleSimulatorProducerIdentity(resolver: tool, simctl: tool,
            developerDirectory: try LocalRootApproval.verify(directory: developer),
            deviceSet: try LocalRootApproval.verify(directory: set), xcodeVersion: "27.0",
            xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        if grantConsent {
            let owner = LocalAuthorityOwner()
            for scope in [LocalAuthorityScope.localExecutable(tool), .localRoot(producer.developerDirectory), .localRoot(producer.deviceSet)] {
                let token = try await authority.beginReview(scope: scope, owner: owner, nowMonotonicNanoseconds: 1)
                _ = try await authority.confirm(token, owner: owner, nowMonotonicNanoseconds: 2)
            }
        }
        let object = ManualSimulatorObject(udid: UUID(), runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17", name: "Uninspected fixture candidate",
            state: .booted, isAvailable: true)
        let binding = try ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(object), producer: .appleSimulator(producer))
        return Self(root: root, journal: journal, settings: settings, authority: authority,
            coordinator: coordinator, bridge: bridge, producer: producer, binding: binding)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class ManualReviewTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64
    private var nextAdvance: UInt64 = 0
    private var reads = 0
    init(now: UInt64) { value = now }
    func advanceOnNextRead(by nanoseconds: UInt64) {
        lock.lock(); defer { lock.unlock() }; nextAdvance = nanoseconds
    }
    func now() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        value += nextAdvance; nextAdvance = 0; reads += 1
        return value
    }
    var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }
}
