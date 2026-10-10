import Foundation
import XCTest
@testable import TidyCore

@MainActor
final class ManualServiceReviewModelTests: XCTestCase {
    func testNewSelectionStartsUnselectedAndUnacknowledged() {
        let model = ManualServiceReviewModel()
        XCTAssertFalse(model.isSelected)
        XCTAssertFalse(model.consequencesAcknowledged)
        XCTAssertFalse(model.canExecute)
        XCTAssertNil(model.candidate)
    }

    func testDisplayDataCannotEnableExecutionAndDismissResetsChoices() throws {
        let model = ManualServiceReviewModel()
        let root = URL(fileURLWithPath: "/private/tmp/TidyManualReviewModel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let approval = try LocalRootApproval.verify(directory: root)
        let tool = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/usr/bin/true"))
        let producer = AppleSimulatorProducerIdentity(resolver: tool, simctl: tool,
            developerDirectory: approval, deviceSet: approval, xcodeVersion: "27.0",
            xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        let object = ManualSimulatorObject(udid: UUID(), runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17", name: "Owned fixture",
            state: .booted, isAvailable: true)
        let binding = try ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(object), producer: .appleSimulator(producer))
        model.inspect(binding)
        XCTAssertEqual(model.candidate, binding)
        XCTAssertFalse(model.isSelected)
        model.isSelected = true
        model.consequencesAcknowledged = true
        XCTAssertFalse(model.canExecute)
        XCTAssertNotNil(model.unavailableReason)
        model.dismiss()
        XCTAssertNil(model.candidate)
        XCTAssertFalse(model.isSelected)
        XCTAssertFalse(model.consequencesAcknowledged)
        XCTAssertFalse(model.canExecute)
    }
    func testLateInventoryCannotRepopulateAfterScopeInvalidation() async throws {
        let gate = ManualCandidateReadGate()
        let model = ManualServiceReviewModel(candidateReader: {
            await gate.wait()
            throw ManualServiceReviewError.authorityDenied
        })
        let task = try XCTUnwrap(model.refreshCandidates())
        XCTAssertNil(model.refreshCandidates(), "A second refresh must not start another read")
        model.invalidateCandidates()
        await gate.open()
        await task.value
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertNil(model.candidate)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertFalse(model.canExecute)
        let readCount = await gate.readCount()
        XCTAssertEqual(readCount, 1)
    }

    func testRealOwnerBoundReviewCanBeCancelledAndReopenedWithoutDispatch() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/TidyManualModelOwner-\(UUID().uuidString)")
        let support = root.appendingPathComponent("support")
        let authorityDirectory = support.appendingPathComponent("authority")
        let developer = root.appendingPathComponent("developer")
        let devices = root.appendingPathComponent("devices")
        for path in [root, support, authorityDirectory, developer, devices] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 1, config: TidyConfig(schemaVersion: 2),
            preferences: .init(global: .init(fields: [.init(rawValue: "ecosystem.apple.manualActions"): .bool(true)])))
        let configURL = support.appendingPathComponent("config.json")
        try JSONEncoder().encode(envelope).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        let settings = SettingsStore(url: configURL)
        let coordinator = ExecutionCoordinator(environment: .init(homeDirectory: root.path),
            journalDirectory: support.appendingPathComponent("execution"))
        let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: settings,
            loaded: await settings.load(), homeDirectory: root.path, detectedTools: [])
        await bridge.drain()
        let authority = try LocalAuthorityStore(directory: authorityDirectory,
            installation: LocalInstallationIdentity.verify(directory: authorityDirectory))
        let tool = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/usr/bin/true"))
        let producer = AppleSimulatorProducerIdentity(resolver: tool, simctl: tool,
            developerDirectory: try LocalRootApproval.verify(directory: developer),
            deviceSet: try LocalRootApproval.verify(directory: devices), xcodeVersion: "27.0",
            xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        let owner = LocalAuthorityOwner()
        for scope in [LocalAuthorityScope.localExecutable(tool), .localRoot(producer.developerDirectory), .localRoot(producer.deviceSet)] {
            let token = try await authority.beginReview(scope: scope, owner: owner, nowMonotonicNanoseconds: 1)
            _ = try await authority.confirm(token, owner: owner, nowMonotonicNanoseconds: 2)
        }
        let object = ManualSimulatorObject(udid: UUID(), runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17", name: "Owned model fixture",
            state: .booted, isAvailable: true)
        let binding = try ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(object), producer: .appleSimulator(producer))
        let facade = bridge.manualServices(authority: authority)
        let model = ManualServiceReviewModel(facadeProvider: { facade })
        model.inspect(binding); model.isSelected = true; model.consequencesAcknowledged = true
        let first = try XCTUnwrap(model.prepareReview())
        XCTAssertNil(model.prepareReview(), "Double-click must not register another pending review")
        await first.value
        let oldID = try XCTUnwrap(model.reviewSummary?.reviewID)
        XCTAssertFalse(model.canExecute)
        model.cancelReview()
        XCTAssertNil(model.reviewSummary)
        XCTAssertFalse(model.isSelected)
        XCTAssertFalse(model.consequencesAcknowledged)
        model.inspect(binding); model.isSelected = true
        let reopened = try XCTUnwrap(model.prepareReview())
        await reopened.value
        XCTAssertNotEqual(model.reviewSummary?.reviewID, oldID)
        XCTAssertFalse(model.canExecute)
        let admission = await coordinator.mutationAdmission()
        XCTAssertEqual(admission, .ready)
        model.dismiss()
    }

    func testDeniedPreparedCandidateCannotDispatchDespiteAcknowledgements() async throws {
        let fixture = try await ManualExecutionAppFixture.make()
        defer { fixture.services.disposeMonitoring(); try? FileManager.default.removeItem(at: fixture.root) }
        var dispatches = 0
        let model = ManualServiceReviewModel(facadeProvider: { fixture.facade }, executionStarter: { _, _ in
            dispatches += 1
            throw ManualServiceReviewError.providerUnavailable
        }, executionOwnerAvailable: { true })
        model.inspect(fixture.binding)
        model.isSelected = true; model.consequencesAcknowledged = true
        let preparation = try XCTUnwrap(model.prepareReview())
        await preparation.value
        XCTAssertNotNil(model.reviewSummary)
        XCTAssertFalse(model.canExecute)
        XCTAssertNil(model.execute())
        XCTAssertEqual(dispatches, 0)
        model.dismiss()
    }

    func testLateCandidateCompletionCannotReplaceFreshInspectedCandidate() async throws {
        let fixture = try await ManualExecutionAppFixture.make()
        defer { fixture.services.disposeMonitoring(); try? FileManager.default.removeItem(at: fixture.root) }
        let gate = ManualCandidateReadGate()
        let model = ManualServiceReviewModel(candidateReader: {
            await gate.wait()
            return [fixture.binding]
        })
        let reading = try XCTUnwrap(model.refreshCandidates())
        let freshObject = ManualSimulatorObject(udid: UUID(),
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            name: "Fresh owned candidate", state: .booted, isAvailable: true)
        let fresh = try ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(freshObject), producer: fixture.binding.producer)
        model.inspect(fresh)
        await gate.open(); await reading.value
        XCTAssertEqual(model.candidate, fresh)
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertFalse(model.isExecuting)
    }

    func testAppReservationPrecedesAwaitJoinsExactReviewAndClearsAfterRealDenial() async throws {
        let fixture = try await ManualExecutionAppFixture.make()
        defer { fixture.services.disposeMonitoring(); try? FileManager.default.removeItem(at: fixture.root) }
        let review = try await fixture.facade.prepare(binding: fixture.binding)
        // A newer review by the same owner intentionally supersedes the first.
        // Use a distinct window owner to test contention without invalidating it.
        let otherReview = try await fixture.competingFacade.prepare(binding: fixture.binding)
        let first = try fixture.services.startManualServiceExecution(facade: fixture.facade, review: review)
        XCTAssertTrue(fixture.services.hasActiveConfirmedExecution)
        XCTAssertTrue(fixture.services.isManualServiceExecutionActive)
        let joined = try fixture.services.startManualServiceExecution(facade: fixture.facade, review: review)
        XCTAssertThrowsError(try fixture.services.startManualServiceExecution(facade: fixture.facade, review: otherReview)) {
            XCTAssertEqual($0 as? ManualServiceReviewError, .busy)
        }
        for task in [first, joined] {
            do {
                _ = try await task.value
                XCTFail("Denied producer unexpectedly executed")
            } catch {
                XCTAssertEqual(error as? ManualServiceReviewError, .providerUnavailable)
            }
        }
        XCTAssertFalse(fixture.services.hasActiveConfirmedExecution)
        XCTAssertFalse(fixture.services.isManualServiceExecutionActive)
        let admission = await fixture.services.coordinator.mutationAdmission()
        XCTAssertEqual(admission, .ready)
        try await fixture.competingFacade.cancelReview(otherReview)
    }

    func testGlobalCancelBeforeTaskEntryReleasesReservationWithoutEffect() async throws {
        let fixture = try await ManualExecutionAppFixture.make()
        defer { fixture.services.disposeMonitoring(); try? FileManager.default.removeItem(at: fixture.root) }
        let review = try await fixture.facade.prepare(binding: fixture.binding)
        let execution = try fixture.services.startManualServiceExecution(facade: fixture.facade, review: review)
        fixture.services.cancelConfirmedExecution()
        do { _ = try await execution.value; XCTFail("Cancelled task unexpectedly executed") }
        catch is CancellationError { }
        XCTAssertFalse(fixture.services.hasActiveConfirmedExecution)
        let admission = await fixture.services.coordinator.mutationAdmission()
        XCTAssertEqual(admission, .ready)
    }

}


private actor ManualCandidateReadGate {
    private var opened = false
    private var count = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        count += 1
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() { opened = true; continuation?.resume(); continuation = nil }
    func readCount() -> Int { count }
}

@MainActor
private struct ManualExecutionAppFixture {
    let root: URL
    let services: AppExecutionServices
    let facade: BridgeManualServices
    let competingFacade: BridgeManualServices
    let binding: ManualServiceOperationBinding

    static func make() async throws -> Self {
        let root = URL(fileURLWithPath: "/private/tmp/TidyManualExecutionModel-\(UUID().uuidString)")
        let support = root.appendingPathComponent("support")
        let authorityDirectory = support.appendingPathComponent("authority")
        let developer = root.appendingPathComponent("developer")
        let devices = root.appendingPathComponent("devices")
        for path in [root, support, authorityDirectory, developer, devices] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 1, config: TidyConfig(schemaVersion: 2),
            preferences: .init(global: .init(fields: [.init(rawValue: "ecosystem.apple.manualActions"): .bool(true)])))
        let config = support.appendingPathComponent("config.json")
        try JSONEncoder().encode(envelope).write(to: config)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        let services = await AppExecutionServices.bootstrap(paths: .init(home: root, settings: config,
            journal: support.appendingPathComponent("execution")))
        await services.policyBridge.drain()
        let authority = try LocalAuthorityStore(directory: authorityDirectory,
            installation: LocalInstallationIdentity.verify(directory: authorityDirectory))
        let tool = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/usr/bin/true"))
        let producer = AppleSimulatorProducerIdentity(resolver: tool, simctl: tool,
            developerDirectory: try LocalRootApproval.verify(directory: developer),
            deviceSet: try LocalRootApproval.verify(directory: devices), xcodeVersion: "27.0",
            xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        let owner = LocalAuthorityOwner()
        for scope in [LocalAuthorityScope.localExecutable(tool), .localRoot(producer.developerDirectory), .localRoot(producer.deviceSet)] {
            let token = try await authority.beginReview(scope: scope, owner: owner, nowMonotonicNanoseconds: 1)
            _ = try await authority.confirm(token, owner: owner, nowMonotonicNanoseconds: 2)
        }
        let object = ManualSimulatorObject(udid: UUID(), runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17", name: "Owned app task fixture",
            state: .booted, isAvailable: true)
        let binding = try ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(object), producer: .appleSimulator(producer))
        return Self(root: root, services: services,
            facade: services.policyBridge.manualServices(authority: authority),
            competingFacade: services.policyBridge.manualServices(authority: authority), binding: binding)
    }
}
