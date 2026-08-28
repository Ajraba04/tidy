import Foundation
import Testing
@testable import TidyCore

private actor BudgetReceipt {
    private var values: [Int] = []
    func append(_ value: Int) { values.append(value) }
    func snapshot() -> [Int] { values }
}

private func waitForBudgetQueue(_ gate: ProcessJobGate, readers: Int? = nil,
                                mutators: Int? = nil) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < deadline {
        let snapshot = await gate.snapshot()
        if readers.map({ snapshot.queuedReaders == $0 }) ?? true,
           mutators.map({ snapshot.queuedMutators == $0 }) ?? true { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("process-budget queue did not reach the expected state")
}

@Suite(.serialized)
struct ProcessBudgetIntegrationTests {
    @Test func productionRunnerAndSchedulerPolicyShareOnePhysicalGate() async throws {
        #expect(ProcessRunner.productionGateIdentity == ObjectIdentifier(ProcessJobGate.shared))
        #expect(ProcessRunner.productionPhysicalLimit == 2)

        func schedulerSnapshot(cap: Int, observation: UInt64) -> WorkSchedulerSnapshot {
            WorkSchedulerSnapshot(availability: .available, settingsRevision: UInt64.max - 1,
                generation: 1, observationEpoch: observation, effectiveWorkers: 1,
                effectiveReadOnlyProcesses: cap, admission: .userRequestedOnly,
                active: 0, queued: 0, liveSessions: 0, tombstones: 0)
        }
        let paused = schedulerSnapshot(cap: 0, observation: 1)
        #expect(await ProcessRunner.applySchedulerObservation(
            settingsRevision: paused.settingsRevision,
            observationEpoch: paused.observationEpoch,
            resolvedReadOnlyCap: paused.effectiveReadOnlyProcesses) == .applied)
        #expect(await ProcessJobGate.shared.snapshot().readOnlyCap == 0)
        let recovered = schedulerSnapshot(cap: 2, observation: 2)
        #expect(await ProcessRunner.applySchedulerObservation(
            settingsRevision: recovered.settingsRevision,
            observationEpoch: recovered.observationEpoch,
            resolvedReadOnlyCap: recovered.effectiveReadOnlyProcesses) == .applied)
        #expect(await ProcessJobGate.shared.snapshot().readOnlyCap == 2)

        let gate = try ProcessJobGate(limit: 2)
        let first = ProcessPolicyRevision(settings: 7, observation: 3)
        #expect(await gate.applyReadOnlyCap(0, revision: first) == .applied)
        #expect(await gate.applyReadOnlyCap(1, revision: first) == .rejectedStale(current: first))
        #expect(await gate.applyReadOnlyCap(2,
            revision: .init(settings: 7, observation: 2)) == .rejectedStale(current: first))
        #expect(await gate.applyReadOnlyCap(3,
            revision: .init(settings: 8, observation: 0)) == .rejectedInvalid)
        let snapshot = await gate.snapshot()
        #expect(snapshot.physicalLimit == 2)
        #expect(snapshot.readOnlyCap == 0)
        #expect(snapshot.policyRevision == first)
    }

    @Test func zeroPausesReadersWithoutRevokingWorkOrChangingMutatorOwnership() async throws {
        let gate = try ProcessJobGate(limit: 2)
        let runningReader = try await gate.acquire(kind: .readOnly)
        #expect(await gate.applyReadOnlyCap(0,
            revision: .init(settings: 1, observation: 1)) == .applied)

        let queuedReader = Task { try await gate.acquire(kind: .readOnly) }
        try await waitForBudgetQueue(gate, readers: 1)
        let mutator = try await gate.acquire(kind: .mutation)
        var snapshot = await gate.snapshot()
        #expect(snapshot.activeReaders == 1)
        #expect(snapshot.activeMutators == 1)
        #expect(snapshot.queuedReaders == 1)

        await gate.release(runningReader)
        await gate.release(mutator)
        snapshot = await gate.snapshot()
        #expect(snapshot.active == 0)
        #expect(snapshot.queuedReaders == 1)

        #expect(await gate.applyReadOnlyCap(1,
            revision: .init(settings: 1, observation: 2)) == .applied)
        let resumed = try await queuedReader.value
        snapshot = await gate.snapshot()
        #expect(snapshot.activeReaders == 1)
        #expect(snapshot.queuedReaders == 0)
        await gate.release(resumed)
    }

    @Test func aggregateTwoAndReaderOneCapsComposeWithoutASecondGate() async throws {
        let gate = try ProcessJobGate(limit: 2)
        let readerA = try await gate.acquire(kind: .readOnly)
        let readerB = try await gate.acquire(kind: .readOnly)
        let mutatorTask = Task { try await gate.acquire(kind: .mutation) }
        try await waitForBudgetQueue(gate, mutators: 1)
        await gate.release(readerA)
        let mutator = try await mutatorTask.value
        var snapshot = await gate.snapshot()
        #expect(snapshot.activeReaders == 1 && snapshot.activeMutators == 1)
        await gate.release(readerB)
        await gate.release(mutator)

        #expect(await gate.applyReadOnlyCap(1,
            revision: .init(settings: 1, observation: 0)) == .applied)
        let serializedA = try await gate.acquire(kind: .readOnly)
        let serializedBTask = Task { try await gate.acquire(kind: .readOnly) }
        try await waitForBudgetQueue(gate, readers: 1)
        let concurrentMutator = try await gate.acquire(kind: .mutation)
        snapshot = await gate.snapshot()
        #expect(snapshot.activeReaders == 1 && snapshot.activeMutators == 1)
        #expect(snapshot.queuedReaders == 1)
        await gate.release(serializedA)
        let serializedB = try await serializedBTask.value
        await gate.release(serializedB)
        await gate.release(concurrentMutator)
    }

    @Test func cancelledReaderLeavesEligibleFIFOOrderExact() async throws {
        let gate = try ProcessJobGate(limit: 2)
        #expect(await gate.applyReadOnlyCap(0,
            revision: .init(settings: 1, observation: 0)) == .applied)
        let receipt = BudgetReceipt()
        let tasks: [Task<UUID?, Never>] = (0..<3).map { value in
            Task<UUID?, Never> {
                do {
                    let reservation = try await gate.acquire(kind: .readOnly)
                    await receipt.append(value)
                    return reservation
                } catch { return nil }
            }
        }
        try await waitForBudgetQueue(gate, readers: 3)
        tasks[1].cancel()
        try await waitForBudgetQueue(gate, readers: 2)
        #expect(await gate.applyReadOnlyCap(1,
            revision: .init(settings: 1, observation: 1)) == .applied)
        let first = try #require(await tasks[0].value)
        #expect(await receipt.snapshot() == [0])
        await gate.release(first)
        let third = try #require(await tasks[2].value)
        #expect(await receipt.snapshot() == [0, 2])
        await gate.release(third)
        #expect(await tasks[1].value == nil)
        #expect(await gate.snapshot().active == 0)
        #expect(await gate.snapshot().queued == 0)
    }

    @Test func undeclaredForgedAndNestedLaunchesRejectBeforeGateActivity() async throws {
        let before = await ProcessRunner.jobSnapshot()
        do {
            _ = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["no"])
            Issue.record("unknown command unexpectedly launched")
        } catch let error as ProcessRunnerError {
            #expect(error == .undeclaredInvocation)
        }
        #expect(throws: ProcessRunnerError.needExceedsCompiledDescriptor) {
            try ProcessRunner.validateNeedForTesting(
                executableURL: URL(fileURLWithPath: "/bin/echo"),
                arguments: ["safe"], claimedDescendants: 1)
        }
        do {
            _ = try await ProcessRunner.runInsideNestedScopeForTesting(
                executableURL: URL(fileURLWithPath: "/bin/echo"), arguments: ["safe"])
            Issue.record("nested command unexpectedly launched")
        } catch let error as ProcessRunnerError {
            #expect(error == .nestedLaunch)
        }
        #expect(await ProcessRunner.jobSnapshot() == before)
    }

    @Test func twentyDirectChildCyclesReturnEveryLeaseAndOwnedDescriptor() async throws {
        let gate = try ProcessJobGate(limit: 2)
        for _ in 0..<20 {
            let request = ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/true"),
                arguments: [], environment: ProcessRunner.minimalEnvironment,
                kind: .readOnly, deadline: .seconds(5))
            let session = try await ProcessSession.launch(request, gate: gate)
            #expect(await session.collect().end == .exited(0))
            #expect(session.retainedDescriptorCountForTesting() == 0)
            #expect(await gate.snapshot().active == 0)
        }
        #expect(await gate.snapshot().queued == 0)
    }

    @Test func discoverySourcesHaveNoPrivateProcessOrWaitEscape() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sources = tests.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TidyCore")
        let converted = [
            "Exec/ToolLocator.swift", "Detect/ToolchainDetector.swift",
            "Detect/SimctlClient.swift", "Detect/SnapshotLister.swift"
        ]
        for relative in converted {
            let source = try String(contentsOf: sources.appendingPathComponent(relative), encoding: .utf8)
            for forbidden in ["Process()", "waitUntilExit", "DispatchSemaphore"] {
                #expect(!source.contains(forbidden), "discovery escape in \(relative): \(forbidden)")
            }
        }
        let runner = try String(contentsOf: sources.appendingPathComponent("Exec/ProcessRunner.swift"),
                                encoding: .utf8)
        let gate = try String(contentsOf: sources.appendingPathComponent("Exec/ProcessJobGate.swift"),
                              encoding: .utf8)
        #expect(runner.contains("ProcessJobGate.shared"))
        #expect(!runner.contains("ProcessJobGate(limit:"))
        #expect(gate.contains("static let shared"))
        #expect(!runner.contains("descendantsBounded:"))
    }
}
