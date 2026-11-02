import Foundation
import Testing
@_spi(TidyCoreTesting) @testable import TidyCore

@Suite("Final manual submission cancellation", .serialized)
struct ManualSimulatorFinalCancellationTests {
    @Test(arguments: ["task", "app"])
    func cancellationDuringFinalValidatorDoesNotCommitOrSpawn(origin: String) async throws {
        let root = URL(fileURLWithPath: "/private/tmp/Tidy-FinalValidationCancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let approved = try LocalRootApproval.verify(directory: root)
        let cat = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/bin/cat"))
        let producer = AppleSimulatorProducerIdentity(resolver: cat, simctl: cat,
            developerDirectory: approved, deviceSet: approved, xcodeVersion: "27.0",
            xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        let object = ManualSimulatorObject(udid: UUID(), runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            name: "Fixed cooperative fixture only", state: .booted, isAvailable: true)
        let binding = try ManualServiceEffectBinding(reviewID: UUID(), coordinatorID: UUID(),
            policyRevision: 1, authorityRevision: 1, installation: LocalInstallationIdentity.verify(directory: root),
            operation: ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
                object: .simulator(object), producer: .appleSimulator(producer)))
        let directory = root.appendingPathComponent("execution")
        let admission = try MutationAdmissionStore(directory: directory)
        try #require(admission.acquire() == .ready)
        defer { admission.release() }
        let journal = try RunJournal(store: admission, storage: DurableJournalStorage(directory: directory))
        let runID = UUID(), operationID = UUID()
        try journal.append(.init(runID: runID, sequence: 1, phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(.init(runID: runID, sequence: 2, phase: .confirmed, operationID: nil, status: nil, reason: nil))
        let submission = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID,
            binding: binding, journal: journal)
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let pause = ManualSimulatorFinalValidationPause()
        let appCancellation = EffectCancellationToken()
        let launch = Task {
            try await ProcessRunner.launchManualSimulatorHookFixtureForTesting(submission: submission,
                gate: gate, deadline: ContinuousClock.now.advanced(by: .seconds(10)), finalValidationPause: pause, effectCancellation: appCancellation)
        }
        do {
            try await pause.waitUntilHeld()
            #expect(pause.validationCount == 3)
            #expect(pause.submissionHookAttempts == 0)
            #expect(try admission.unfinishedIntentsWhileLocked().first?.phase == .prepared)
            if origin == "task" { launch.cancel() } else { appCancellation.cancel() }
            pause.resume()
            await #expect(throws: CancellationError.self) { _ = try await launch.value }
        } catch {
            launch.cancel(); pause.resume()
            await cleanupUnexpectedLaunch(launch, gate: gate)
            throw error
        }
        // Clean up an unexpected child if the regression fails; never force-kill
        // a mutating child or leave an owned fixture without its consuming reap.
        await cleanupUnexpectedLaunch(launch, gate: gate)
        let pending = try #require(admission.unfinishedIntentsWhileLocked().first)
        #expect(pending.phase == .prepared)
        #expect(pending.childPID == nil && pending.bootID == nil)
        #expect(pause.submissionHookAttempts == 0)
        let snapshot = await gate.snapshot()
        #expect(snapshot.active == 0 && snapshot.queued == 0 && snapshot.unresolvedMutations == 0)
    }

    private func cleanupUnexpectedLaunch(_ task: Task<ManualSimulatorNativeLaunchOutcome, Error>,
                                         gate: ProcessJobGate) async {
        guard let outcome = try? await task.value, case .launched(let launch) = outcome else { return }
        try? launch.session.releaseStartByte()
        _ = await launch.session.collect()
        _ = await launch.session.observeOwnedExit(within: .seconds(2))
        if let lease = try? await launch.session.transferReapedMutationToTerminalVerification(within: .seconds(1)) {
            try? await gate.closeTerminalVerificationForTesting(lease)
        } else { try? await launch.session.releaseReapedMutationForTesting() }
    }
}
