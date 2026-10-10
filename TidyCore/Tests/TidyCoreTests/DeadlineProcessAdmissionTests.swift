import Foundation
import Testing
@_spi(TidyCoreTesting) @testable import TidyCore

@Suite("Manual read deadline includes gate admission", .serialized)
struct DeadlineProcessAdmissionTests {
    private func request(_ executable: String = "/usr/bin/true", kind: ProcessTestJobKind = .readOnly) -> ProcessTestRequest {
        .init(executable: URL(fileURLWithPath: executable), arguments: [],
              environment: ["PATH": "/usr/bin:/bin", "HOME": "/var/empty"],
              kind: kind, deadline: .seconds(3))
    }
    private func queued(_ gate: ProcessJobGate) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline {
            if await gate.snapshot().queuedReaders == 1 { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw POSIXError(.ETIMEDOUT)
    }

    @Test func capZeroNeverBecomesAvailableButDeadlineRemovesWaiter() async throws {
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        _ = await gate.applyReadOnlyCap(0, revision: .init(settings: 1, observation: 1))
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
        let read = Task { try await ProcessSession.launchDeadlineBoundReadForTesting(request(), gate: gate, deadline: deadline) }
        try await queued(gate)
        await #expect(throws: ProcessReadAdmissionError.expired) { _ = try await read.value }
        let snapshot = await gate.snapshot()
        #expect(snapshot.queued == 0 && snapshot.active == 0 && snapshot.readOnlyCap == 0)
    }

    @Test func occupiedPhysicalSlotsDoNotExtendQueueDeadline() async throws {
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let first = try await gate.acquireForTesting(kind: .mutation)
        let second = try await gate.acquireForTesting(kind: .mutation)
        let read = Task { try await ProcessSession.launchDeadlineBoundReadForTesting(request(), gate: gate,
            deadline: ContinuousClock.now.advanced(by: .milliseconds(300))) }
        try await queued(gate)
        await #expect(throws: ProcessReadAdmissionError.expired) { _ = try await read.value }
        #expect(await gate.snapshot().active == 2)
        #expect(await gate.snapshot().queued == 0)
        await gate.release(first); await gate.release(second)
        #expect(await gate.snapshot().active == 0)
    }

    @Test func childUsesRemainingDeadlineAfterDelayedAdmission() async throws {
        let gate = try ProcessJobGate.isolatedForTesting(limit: 1)
        let held = try await gate.acquireForTesting(kind: .readOnly)
        let started = ContinuousClock.now
        let deadline = started.advanced(by: .milliseconds(700))
        let read = Task { try await ProcessSession.launchDeadlineBoundReadForTesting(request("/bin/cat"), gate: gate, deadline: deadline) }
        try await queued(gate)
        try await Task.sleep(for: .milliseconds(200))
        await gate.release(held)
        let session = try await read.value
        #expect(await session.collect().end == .readOnlyTimedOut)
        let completionDeadline = started.advanced(by: .seconds(2))
        _ = await session.observeOwnedExit(within: max(.zero, ContinuousClock.now.duration(to: completionDeadline)))
        try #require(session.observationSnapshot().consumingReapCount == 1)
        // Owned-exit notification precedes the observation queue's asynchronous
        // gate-release callback. Await that distinct boundary without extending
        // the original total two-second completion allowance.
        while ContinuousClock.now < completionDeadline, await gate.snapshot().active != 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(ContinuousClock.now < completionDeadline,
            "Queue time must not be followed by the original three-second child timeout")
        #expect(await gate.snapshot().active == 0)
    }

    @Test func mutationCannotUseDeadlineBoundReadLane() async throws {
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        await #expect(throws: ProcessReadAdmissionError.notReadOnly) {
            _ = try await ProcessSession.launchDeadlineBoundReadForTesting(request(kind: .mutation), gate: gate,
                deadline: ContinuousClock.now.advanced(by: .seconds(1)))
        }
        #expect(await gate.snapshot().active == 0)
    }
}
