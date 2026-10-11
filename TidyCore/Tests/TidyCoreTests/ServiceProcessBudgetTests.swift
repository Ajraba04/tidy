import Foundation
import Testing
@_spi(TidyCoreTesting) @testable import TidyCore

@Suite("Reaped service mutation terminal-read budget", .serialized)
struct ServiceProcessBudgetTests {
    private func request(_ kind: ProcessTestJobKind = .readOnly, seconds: String = "0.15") -> ProcessTestRequest {
        ProcessTestRequest(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: [seconds],
            environment: ["PATH": "/usr/bin:/bin", "HOME": "/var/empty"],
            kind: kind, deadline: .seconds(3))
    }

    private func reapedMutation(_ gate: ProcessJobGate,
                                identityCapture: ProcessIdentityCapture = .system) async throws -> ProcessSession {
        let session = try await ProcessSession.launchForTesting(gatedMutationRequest(), gate: gate,
            identityCapture: identityCapture)
        try session.releaseStartByte()
        _ = await session.collect()
        let observation = session.observationSnapshot()
        try #require(observation.consumingReapCount == 1)
        return session
    }

    private func gatedMutationRequest() -> ProcessTestRequest {
        ProcessTestRequest(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [],
            environment: ["PATH": "/usr/bin:/bin", "HOME": "/var/empty"],
            kind: .mutation, deadline: .seconds(10))
    }

    private func wait(_ gate: ProcessJobGate, until predicate: (ProcessGateSnapshot) -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if predicate(await gate.snapshot()) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw POSIXError(.ETIMEDOUT)
    }

    @Test func ownedReapTransfersPhysicalSlotButRetainsMutationObligation() async throws {
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let mutation = try await reapedMutation(gate)
        try #require(mutation.identity != nil)
        #expect(await gate.snapshot().activeMutators == 1)
        let lease = try await mutation.transferReapedMutationToTerminalVerification(within: .seconds(2))
        #expect(lease.ownedIdentity == mutation.identity)
        #expect(lease.rawStatus == 0)
        var snapshot = await gate.snapshot()
        #expect(snapshot.active == 0)
        #expect(snapshot.unresolvedMutations == 1)
        #expect(await gate.applyReadOnlyCap(0, revision: .init(settings: 1, observation: 1)) == .applied)
        let other = try await gate.acquireForTesting(kind: .mutation)
        let ordinary = Task { try await ProcessSession.launchForTesting(request(), gate: gate) }
        try await wait(gate) { $0.queuedReaders == 1 }
        let verifier = try await ProcessSession.launchTerminalVerificationForTesting(request(), gate: gate, lease: lease)
        snapshot = await gate.snapshot()
        #expect(snapshot.active == 2 && snapshot.activeVerifiers == 1)
        #expect(snapshot.activeMutators == 1 && snapshot.queuedReaders == 1)
        #expect(await verifier.collect().end == .exited(0))
        #expect(await gate.snapshot().unresolvedMutations == 1)
        ordinary.cancel()
        await #expect(throws: CancellationError.self) { _ = try await ordinary.value }
        await gate.release(other)
        try await gate.closeTerminalVerificationForTesting(lease)
        snapshot = await gate.snapshot()
        #expect(snapshot.active == 0 && snapshot.queued == 0 && snapshot.unresolvedMutations == 0)
    }

    @Test func runningChildMissingIdentityAndReadOnlyChildCannotMintReceipt() async throws {
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let running = try await ProcessSession.launchForTesting(gatedMutationRequest(), gate: gate)
        #expect(throws: ProcessTerminalVerificationError.reapNotProven) { _ = try running.reapedMutationReceipt() }
        try running.releaseStartByte()
        _ = await running.collect()
        let lease = try await running.transferReapedMutationToTerminalVerification(within: .seconds(2))
        try await gate.closeTerminalVerificationForTesting(lease)
        let missing = try await reapedMutation(gate, identityCapture: .failClosed)
        #expect(throws: ProcessTerminalVerificationError.reapNotProven) { _ = try missing.reapedMutationReceipt() }
        try await missing.releaseReapedMutationForTesting()
        let reader = try await ProcessSession.launchForTesting(request(), gate: gate)
        _ = await reader.collect()
        #expect(throws: ProcessTerminalVerificationError.notMutation) { _ = try reader.reapedMutationReceipt() }
        #expect(await gate.snapshot().active == 0)
    }

    @Test func laneIsSerialAndQueuedCancellationPreservesSharedPhysicalLimit() async throws {
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let mutation = try await reapedMutation(gate)
        let lease = try await mutation.transferReapedMutationToTerminalVerification(within: .seconds(2))
        _ = await gate.applyReadOnlyCap(0, revision: .init(settings: 1, observation: 1))
        let other = try await gate.acquireForTesting(kind: .mutation)
        let first = try await ProcessSession.launchTerminalVerificationForTesting(request(seconds: "0.3"), gate: gate, lease: lease)
        let queued = Task { try await ProcessSession.launchTerminalVerificationForTesting(request(), gate: gate, lease: lease) }
        try await wait(gate) { $0.queuedVerifiers == 1 }
        let snapshot = await gate.snapshot()
        #expect(snapshot.active == 2 && snapshot.activeVerifiers == 1 && snapshot.queuedVerifiers == 1)
        await #expect(throws: ProcessTerminalVerificationError.capacity) {
            _ = try await ProcessSession.launchTerminalVerificationForTesting(request(), gate: gate, lease: lease)
        }
        queued.cancel()
        await #expect(throws: CancellationError.self) { _ = try await queued.value }
        try await wait(gate) { $0.queuedVerifiers == 0 }
        #expect(await first.collect().end == .exited(0))
        await gate.release(other)
        try await gate.closeTerminalVerificationForTesting(lease)
        #expect(await gate.snapshot().active == 0)
    }

    @Test func expiredLeaseRejectsNewWorkAndWakesQueuedVerifierWithoutRetiringObligation() async throws {
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let mutation = try await reapedMutation(gate)
        let lease = try await mutation.transferReapedMutationToTerminalVerification(within: .milliseconds(500))
        let first = try await gate.acquireForTesting(kind: .mutation)
        let second = try await gate.acquireForTesting(kind: .mutation)
        let queued = Task { try await ProcessSession.launchTerminalVerificationForTesting(request(), gate: gate, lease: lease) }
        try await wait(gate) { $0.queuedVerifiers == 1 }
        await #expect(throws: ProcessTerminalVerificationError.expiredOrClosedLease) { _ = try await queued.value }
        #expect(await gate.snapshot().unresolvedMutations == 1)
        await #expect(throws: ProcessTerminalVerificationError.expiredOrClosedLease) {
            _ = try await ProcessSession.launchTerminalVerificationForTesting(request(), gate: gate, lease: lease)
        }
        await gate.release(first); await gate.release(second)
        try await gate.closeTerminalVerificationForTesting(lease)
        #expect(await gate.snapshot().active == 0)
    }

    @Test func wrongGateMutationRequestAndReceiptReplayCannotUseLane() async throws {
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let other = try ProcessJobGate.isolatedForTesting(limit: 2)
        let mutation = try await reapedMutation(gate)
        let receipt = try mutation.reapedMutationReceipt()
        await #expect(throws: ProcessTerminalVerificationError.wrongGate) {
            _ = try await other.transferReapedMutation(receipt, within: .seconds(2))
        }
        let lease = try await gate.transferReapedMutation(receipt, within: .seconds(2))
        await #expect(throws: ProcessTerminalVerificationError.invalidReceipt) {
            _ = try await gate.transferReapedMutation(receipt, within: .seconds(2))
        }
        await #expect(throws: ProcessTerminalVerificationError.wrongGate) {
            _ = try await ProcessSession.launchTerminalVerificationForTesting(request(), gate: other, lease: lease)
        }
        await #expect(throws: ProcessTerminalVerificationError.notReadOnly) {
            _ = try await ProcessSession.launchTerminalVerificationForTesting(request(.mutation), gate: gate, lease: lease)
        }
        try await gate.closeTerminalVerificationForTesting(lease)
        await #expect(throws: ProcessTerminalVerificationError.expiredOrClosedLease) {
            _ = try await ProcessSession.launchTerminalVerificationForTesting(request(), gate: gate, lease: lease)
        }
        await #expect(throws: POSIXError.self) { try await ProcessJobGate.shared.closeTerminalVerificationForTesting(lease) }
        #expect(await gate.snapshot().unresolvedMutations == 0)
        #expect(await other.snapshot().active == 0)
    }

    @Test func ordinaryMutationKeepsItsReservationUnlessExplicitTransferIsInvoked() async throws {
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let mutation = try await reapedMutation(gate)
        let snapshot = await gate.snapshot()
        #expect(snapshot.activeMutators == 1 && snapshot.unresolvedMutations == 0)
        try await mutation.releaseReapedMutationForTesting()
        #expect(await gate.snapshot().active == 0)
    }

    @Test func possessionOfReapReceiptCannotReleaseOwnedMutationWithoutObligation() async throws {
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let mutation = try await reapedMutation(gate)
        let receipt = try mutation.reapedMutationReceipt()
        try await receipt.attemptGenericReleaseForTesting()
        let protected = await gate.snapshot()
        #expect(protected.activeMutators == 1 && protected.unresolvedMutations == 0)
        let lease = try await gate.transferReapedMutation(receipt, within: .seconds(2))
        #expect(await gate.snapshot().active == 0)
        #expect(await gate.snapshot().unresolvedMutations == 1)
        try await gate.closeTerminalVerificationForTesting(lease)

        let invalid = ProcessTestRequest(executable: URL(fileURLWithPath: "/private/does-not-exist-Tidy-fixture"),
            arguments: [], environment: ["PATH": "/usr/bin:/bin", "HOME": "/var/empty"],
            kind: .mutation, deadline: .seconds(1))
        await #expect(throws: POSIXError.self) { _ = try await ProcessSession.launchForTesting(invalid, gate: gate) }
        #expect(await gate.snapshot().active == 0, "Proven pre-spawn failure must release through constrained rollback")
    }
}
