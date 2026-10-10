import Darwin
import Foundation
import Testing
@_spi(TidyCoreTesting) @testable import TidyCore

private struct NativeHookFixture {
    let root: URL
    let admission: MutationAdmissionStore
    let journal: RunJournal
    let submission: ManualServiceSubmission
    let binding: ManualServiceEffectBinding
    let runID = UUID()
    let operationID = UUID()
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/TidyNativeHook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let rootApproval = try LocalRootApproval.verify(directory: root)
        let cat = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/bin/cat"))
        let producer = AppleSimulatorProducerIdentity(resolver: cat, simctl: cat,
            developerDirectory: rootApproval, deviceSet: rootApproval,
            xcodeVersion: "27.0", xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        let object = ManualSimulatorObject(udid: UUID(), runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            name: "Owned hook fixture", state: .booted, isAvailable: true)
        binding = try ManualServiceEffectBinding(reviewID: UUID(), coordinatorID: UUID(), policyRevision: 1,
            authorityRevision: 1, installation: LocalInstallationIdentity.verify(directory: root),
            operation: ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
                object: .simulator(object), producer: .appleSimulator(producer)))
        let directory = root.appendingPathComponent("journal")
        admission = try MutationAdmissionStore(directory: directory)
        guard admission.acquire() == .ready else { throw JournalError.unavailable }
        journal = try RunJournal(store: admission, storage: DurableJournalStorage(directory: directory))
        try journal.append(.init(runID: runID, sequence: 1, phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(.init(runID: runID, sequence: 2, phase: .confirmed, operationID: nil, status: nil, reason: nil))
        submission = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID, binding: binding, journal: journal)
    }
    func finish() {
        admission.release()
        try? FileManager.default.removeItem(at: root)
    }
}

private actor NativeHookStartGate {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { released = true; waiter?.resume(); waiter = nil }
}

@Suite("Fixed native submission hook boundary", .serialized)
struct ManualSimulatorNativeHookTests {
    @Test("compiled native producer denial leaves the exact intent prepared")
    func nativeProducerRemainsDenied() throws {
        let fixture = try NativeHookFixture(); defer { fixture.finish() }
        #expect(throws: ManualServiceReviewError.providerUnavailable) {
            try AppleSimulatorOperation.requireAcceptedProducer(for: fixture.binding.operation)
        }
        #expect(try fixture.admission.unfinishedIntentsWhileLocked().first?.phase == .prepared)
    }

    @Test("the shared hook plumbing commits exactly once before returning a real owned cat")
    func hookCommitsOnceBeforeChild() async throws {
        let fixture = try NativeHookFixture(); defer { fixture.finish() }
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let outcome = try await ProcessRunner.launchManualSimulatorHookFixtureForTesting(submission: fixture.submission,
            gate: gate, deadline: ContinuousClock.now.advanced(by: .seconds(2)))
        guard case .launched(let launch) = outcome else {
            Issue.record("The fixed cat fixture did not launch"); return
        }
        #expect(launch.submissionHookAttempts == 1)
        #expect(launch.invocation.origin == .cooperativeFixture)
        #expect(launch.invocation.binding == fixture.binding)
        #expect(launch.invocation.runID == fixture.runID && launch.invocation.operationID == fixture.operationID)
        #expect(try fixture.admission.unfinishedIntentsWhileLocked().first?.phase == .submitted)
        #expect(launch.session.identity != nil)
        try launch.session.releaseStartByte()
        _ = await launch.session.observeOwnedExit(within: .seconds(2))
        let lease = try await launch.session.transferReapedMutationToTerminalVerification(within: .seconds(1))
        try await gate.closeTerminalVerificationForTesting(lease)
        // Duplicate begin errors are not proof that the original attempt never
        // spawned. The API must throw, never return a .notSpawned receipt.
        await #expect(throws: Error.self) {
            try await ProcessRunner.launchManualSimulatorHookFixtureForTesting(submission: fixture.submission,
                gate: gate, deadline: ContinuousClock.now.advanced(by: .seconds(1)))
        }
    }

    @Test("a caller cancelled before the fixed hook cannot submit")
    func cancellationBeforeHook() async throws {
        let fixture = try NativeHookFixture(); defer { fixture.finish() }
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let start = NativeHookStartGate(), submission = fixture.submission
        let task = Task {
            await start.wait()
            return try await ProcessRunner.launchManualSimulatorHookFixtureForTesting(submission: submission,
                gate: gate, deadline: ContinuousClock.now.advanced(by: .seconds(1)))
        }
        task.cancel(); await start.release()
        await #expect(throws: Error.self) { try await task.value }
        #expect(try fixture.admission.unfinishedIntentsWhileLocked().first?.phase == .prepared)
        #expect(await gate.snapshot().active == 0)
    }

    @Test("a hook that cannot return a durable permit never produces a no-spawn receipt")
    func missingJournalLockIsNotNoSpawnProof() async throws {
        let fixture = try NativeHookFixture(); defer { fixture.finish() }
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        fixture.admission.release()
        await #expect(throws: Error.self) {
            try await ProcessRunner.launchManualSimulatorHookFixtureForTesting(submission: fixture.submission,
                gate: gate, deadline: ContinuousClock.now.advanced(by: .seconds(1)))
        }
        _ = fixture.admission.acquire()
        #expect(try fixture.admission.unfinishedIntentsWhileLocked().first?.phase == .prepared)
        #expect(await gate.snapshot().active == 0)
    }

    @Test("only an observed rejected posix_spawn after a returned permit supplies bound no-spawn evidence")
    func rejectedSpawnHasPrivateContextReceipt() async throws {
        let fixture = try NativeHookFixture(); defer { fixture.finish() }
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let outcome = try await ProcessRunner.rejectManualSimulatorSpawnFixtureForTesting(submission: fixture.submission,
            gate: gate, deadline: ContinuousClock.now.advanced(by: .seconds(2)))
        guard case .notSpawned(let receipt) = outcome else {
            Issue.record("A compiled missing-executable fixture unexpectedly launched"); return
        }
        #expect(receipt.binding == fixture.binding)
        #expect(receipt.runID == fixture.runID && receipt.operationID == fixture.operationID)
        #expect(receipt.invocationDigest.count == 32)
        #expect(receipt.submissionHookAttempts == 1)
        #expect(receipt.posixErrorCode == ENOENT)
        #expect(receipt.attemptedExecutablePath.hasPrefix(fixture.binding.installation.canonicalDirectoryPath + "/"))
        #expect(try fixture.admission.unfinishedIntentsWhileLocked().first?.phase == .submitted)
        #expect(await gate.snapshot().active == 0)
        #expect(throws: Error.self) { try fixture.submission.cancelBeforeSubmission() }
        // It is launcher evidence only: this fixture does not retire the intent
        // or fabricate producer success from the thrown errno.
    }
}

extension ManualSimulatorNativeHookTests {
    @Test("rejected-spawn proof survives publication before its terminal event without becoming native acceptance")
    func rejectedSpawnProofPublicationGap() async throws {
        let fixture = try NativeHookFixture(); defer { fixture.finish() }
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let outcome = try await ProcessRunner.rejectManualSimulatorSpawnFixtureForTesting(
            submission: fixture.submission, gate: gate,
            deadline: ContinuousClock.now.advanced(by: .seconds(2)))
        guard case .notSpawned(let receipt) = outcome else { Issue.record("Expected rejected spawn"); return }
        let proof = try CompiledEffectTerminalVerifier.manualSimulatorNeverSpawned(receipt)
        let intent = try #require(fixture.admission.unfinishedIntentsWhileLocked().first)
        #expect(CompiledEffectTerminalVerifier.validate(proof.archive, intent: intent))
        #expect(proof.archive.terminalStatus == .failed && proof.archive.outcomeCount == 0)
        #expect(proof.archive.verifier == "tidy.manual-service.simulator-fixture-never-spawned.v1")
        let reference = try fixture.journal.persistTerminalProof(proof)
        #expect(reference.id == fixture.operationID)
        fixture.admission.release()
        let directory = fixture.root.appendingPathComponent("journal")
        let reopened = try MutationAdmissionStore(directory: directory)
        #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
        defer { reopened.release() }
        let journal = try RunJournal(store: reopened, storage: DurableJournalStorage(directory: directory))
        #expect(try journal.reconcileTerminalRun(runID: fixture.runID))
        #expect(reopened.acquire() == .ready)
        #expect(try journal.events(runID: fixture.runID).filter { $0.phase == .itemTerminal }.count == 1)
        #expect(try journal.reconcileTerminalRun(runID: fixture.runID))
        #expect(ManualServiceAcceptanceRegistry.denial(for: fixture.binding.operation) != nil)
        #expect(await gate.snapshot().active == 0)
    }

    @Test("rejected-spawn archives reject changed origin, errno, declaration, hook count and proof identity")
    func rejectedSpawnArchiveCannotBeReinterpreted() async throws {
        let fixture = try NativeHookFixture(); defer { fixture.finish() }
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let outcome = try await ProcessRunner.rejectManualSimulatorSpawnFixtureForTesting(
            submission: fixture.submission, gate: gate,
            deadline: ContinuousClock.now.advanced(by: .seconds(2)))
        guard case .notSpawned(let receipt) = outcome else { Issue.record("Expected rejected spawn"); return }
        let proof = try CompiledEffectTerminalVerifier.manualSimulatorNeverSpawned(receipt)
        let intent = try #require(fixture.admission.unfinishedIntentsWhileLocked().first)
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proof.archive)) as? [String: Any])
        func invalid(_ mutate: (inout [String: Any]) -> Void) throws {
            var value = original; mutate(&value)
            let decoded = try JSONDecoder().decode(EffectTerminalProofArchive.self,
                from: JSONSerialization.data(withJSONObject: value))
            #expect(!CompiledEffectTerminalVerifier.validate(decoded, intent: intent))
        }
        try invalid { $0["verifier"] = "tidy.manual-service.simulator-never-spawned.v1" }
        try invalid { $0["operationID"] = UUID().uuidString }
        let mutations: [(String, Any)] = [
            ("posixErrorCode", 0), ("posixErrorCode", -1), ("submissionHookAttempts", 2),
            ("attemptedExecutablePath", "/bin/cat"), ("invocationOrigin", "nativeShutdown")
        ]
        for (key, value) in mutations {
            try invalid {
                var service = $0["service"] as! [String: Any]
                var rejected = service["rejectedSpawn"] as! [String: Any]
                rejected[key] = value; service["rejectedSpawn"] = rejected; $0["service"] = service
            }
        }
        let withChild = PendingEffectIntent(runID: intent.runID, operationID: intent.operationID,
            service: fixture.binding, phase: .submitted,
            child: ProcessInstanceIdentity(bootID: UUID(), pid: 123, startSeconds: 1, startMicroseconds: 0,
                executablePath: "/bin/cat", executableDevice: 1, executableInode: 1))
        #expect(!CompiledEffectTerminalVerifier.validate(proof.archive, intent: withChild))
    }
}

extension ManualSimulatorNativeHookTests {
    @Test("occupied slots cannot extend mutation admission or hide shared app cancellation", arguments: ["deadline", "app"])
    func queuedMutationEndsBeforeSubmissionWhileSlotsStayOccupied(origin: String) async throws {
        let fixture = try NativeHookFixture(); defer { fixture.finish() }
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let first = try await gate.acquireForTesting(kind: .readOnly)
        let second = try await gate.acquireForTesting(kind: .readOnly)
        let cancellation = EffectCancellationToken()
        let started = ContinuousClock.now
        let deadline = started.advanced(by: origin == "deadline" ? .milliseconds(300) : .seconds(5))
        let launch = Task {
            try await ProcessRunner.launchQueuedManualSimulatorHookFixtureForTesting(submission: fixture.submission,
                gate: gate, deadline: deadline, effectCancellation: cancellation)
        }
        // If the regression is broken, cancel only this still-unsubmitted
        // fixture waiter. This watchdog does not free either outside slot.
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { launch.cancel() }
        }
        defer { watchdog.cancel() }
        let queuedDeadline = started.advanced(by: .seconds(1))
        while ContinuousClock.now < queuedDeadline, await gate.snapshot().queuedMutators == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await gate.snapshot().queuedMutators == 1)
        if origin == "app" {
            cancellation.cancel()
            await #expect(throws: CancellationError.self) { _ = try await launch.value }
        } else {
            await #expect(throws: ProcessReadAdmissionError.expired) { _ = try await launch.value }
        }
        if let unexpected = try? await launch.value, case .launched(let child) = unexpected {
            try? child.session.releaseStartByte()
            _ = await child.session.observeOwnedExit(within: .seconds(2))
            if let lease = try? await child.session.transferReapedMutationToTerminalVerification(within: .seconds(1)) {
                try? await gate.closeTerminalVerificationForTesting(lease)
            }
            Issue.record("An occupied queue unexpectedly spawned the mutation fixture")
        }
        #expect(ContinuousClock.now < started.advanced(by: .seconds(1)))
        let snapshot = await gate.snapshot()
        #expect(snapshot.active == 2 && snapshot.queued == 0 && snapshot.unresolvedMutations == 0)
        let pending = try #require(fixture.admission.unfinishedIntentsWhileLocked().first)
        #expect(pending.phase == .prepared && pending.childPID == nil && pending.bootID == nil)
        // The coordinator may now publish its sealed no-submission proof.
        let proof = try fixture.submission.cancelBeforeSubmission()
        _ = try fixture.journal.finishManualService(proof: proof)
        #expect(try fixture.admission.unfinishedIntentsWhileLocked().isEmpty)
        await gate.release(first); await gate.release(second)
        #expect(await gate.snapshot().active == 0)
    }
}
