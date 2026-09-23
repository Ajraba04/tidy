import Foundation
import Testing
@testable import TidyCore

private actor RescueTerminatorProbe: GracefulApplicationTerminating {
    var observation: GracefulTerminationObservation
    private(set) var requested: [WorkloadIdentity] = []
    init(_ observation: GracefulTerminationObservation) { self.observation = observation }
    func requestGracefulTermination(of workload: WorkloadIdentity,
                                    timeoutSeconds: Int,
                                    authorization: GracefulTerminationAuthorization) async
        -> GracefulTerminationObservation {
        requested.append(workload)
        return observation
    }
    var count: Int { requested.count }
}

@Suite("Instance-bound rescue", .serialized)
struct RescuePlannerTests {
    @Test("review is initially unselected and PID reuse never transfers consent")
    func selectionAndPIDReuse() async throws {
        let terminator = RescueTerminatorProbe(.exited)
        let planner = RescuePlanner(terminator: terminator,
                                    livePolicy: { rescueLivePolicy() })
        let fixture = try RescueFixture(pid: 42, start: 1)
        defer { fixture.cleanup() }
        let original = fixture.workload
        let review = try await planner.beginReview(workload: original,
            approval: fixture.approval, authority: fixture.authority,
            owner: owner, nowMonotonicNanoseconds: 1)
        #expect(!review.isSelected)
        await #expect(throws: RescueDenial.notSelected) {
            _ = try await planner.requestGracefulTermination(review.token, owner: owner,
                currentIdentity: original, nowMonotonicNanoseconds: 2,
                timeoutSeconds: 15)
        }
        _ = try await planner.select(review.token, owner: owner,
                                     nowMonotonicNanoseconds: 3)
        let reused = try fixture.identity(pid: 42, start: 2)
        await #expect(throws: RescueDenial.identityChanged) {
            _ = try await planner.requestGracefulTermination(review.token, owner: owner,
                currentIdentity: reused, nowMonotonicNanoseconds: 4,
                timeoutSeconds: 15)
        }
        #expect(await terminator.count == 0)
    }

    @Test("refusal and timeout remain refusal and timeout, with one-shot reviews")
    func truthfulTermination() async throws {
        let terminator = RescueTerminatorProbe(.refused)
        let planner = RescuePlanner(terminator: terminator,
                                    livePolicy: { rescueLivePolicy() })
        let fixture = try RescueFixture(pid: 10, start: 20)
        defer { fixture.cleanup() }
        let target = fixture.workload
        let review = try await planner.beginReview(workload: target,
            approval: fixture.approval, authority: fixture.authority,
            owner: owner, nowMonotonicNanoseconds: 1)
        _ = try await planner.select(review.token, owner: owner,
                                     nowMonotonicNanoseconds: 2)
        let result = try await planner.requestGracefulTermination(review.token,
            owner: owner, currentIdentity: target, nowMonotonicNanoseconds: 3,
            timeoutSeconds: 15)
        #expect(result.termination == .refused)
        await #expect(throws: RescueDenial.unknownReview) {
            _ = try await planner.requestGracefulTermination(review.token,
                owner: owner, currentIdentity: target,
                nowMonotonicNanoseconds: 4, timeoutSeconds: 15)
        }
    }

    @Test("an already exited application is observed without invoking termination")
    func alreadyExited() async throws {
        let terminator = RescueTerminatorProbe(.exited)
        let planner = RescuePlanner(terminator: terminator,
                                    livePolicy: { rescueLivePolicy() })
        let fixture = try RescueFixture(pid: 10, start: 20)
        defer { fixture.cleanup() }
        let target = fixture.workload
        let review = try await planner.beginReview(workload: target,
            approval: fixture.approval, authority: fixture.authority,
            owner: owner, nowMonotonicNanoseconds: 1)
        _ = try await planner.select(review.token, owner: owner,
                                     nowMonotonicNanoseconds: 2)
        let result = try await planner.requestGracefulTermination(review.token,
            owner: owner, currentIdentity: nil, nowMonotonicNanoseconds: 3,
            timeoutSeconds: 15)
        #expect(result.termination == .alreadyExited)
        #expect(await terminator.count == 0)
    }

    @Test("system memory delta is signed noisy observation, never attributed reclaim")
    func noisyDelta() throws {
        let fixture = try RescueFixture(pid: 10, start: 20)
        defer { fixture.cleanup() }
        let target = fixture.workload
        let result = RescueOutcome(workload: target, termination: .exited)
            .recordingSystemObservation(beforeAvailableBytes: 100,
                                        afterAvailableBytes: 80)
        #expect(result.memory.noisyAvailableByteDelta == -20)
        let unavailable = RescueMemoryObservation(beforeAvailableBytes: -1,
                                                   afterAvailableBytes: 100)
        #expect(unavailable.noisyAvailableByteDelta == nil)
    }

    @Test("pending reviews are bounded and expired reviews are reaped")
    func boundedPendingReviews() async throws {
        let fixture = try RescueFixture(pid: 10, start: 20)
        defer { fixture.cleanup() }
        let planner = RescuePlanner(terminator: RescueTerminatorProbe(.exited),
                                    livePolicy: { rescueLivePolicy() })
        for _ in 0..<64 {
            _ = try await planner.beginReview(workload: fixture.workload,
                approval: fixture.approval, authority: fixture.authority,
                owner: UUID(), nowMonotonicNanoseconds: 1,
                validityNanoseconds: 10)
        }
        await #expect(throws: RescueDenial.capacityExceeded) {
            _ = try await planner.beginReview(workload: fixture.workload,
                approval: fixture.approval, authority: fixture.authority,
                owner: UUID(), nowMonotonicNanoseconds: 2,
                validityNanoseconds: 10)
        }
        _ = try await planner.beginReview(workload: fixture.workload,
            approval: fixture.approval, authority: fixture.authority,
            owner: UUID(), nowMonotonicNanoseconds: 12,
            validityNanoseconds: 10)
    }

    @Test("revoking captured app authority after review blocks dispatch")
    func revokedAuthorityBlocksDispatch() async throws {
        let fixture = try RescueFixture(pid: 10, start: 20)
        defer { fixture.cleanup() }
        let epoch = LocalAuthorityEpoch(revision: 1)
        let authority = LocalAuthoritySnapshot(revision: 1,
            installation: fixture.authority.installation,
            scopes: [.rescueApplication(fixture.approval)], epoch: epoch)
        let terminator = RescueTerminatorProbe(.exited)
        let planner = RescuePlanner(terminator: terminator,
                                    livePolicy: { rescueLivePolicy() })
        let review = try await planner.beginReview(workload: fixture.workload,
            approval: fixture.approval, authority: authority,
            owner: owner, nowMonotonicNanoseconds: 1)
        epoch.invalidate()
        await #expect(throws: RescueDenial.notApproved) {
            _ = try await planner.select(review.token, owner: owner,
                                         nowMonotonicNanoseconds: 2)
        }
        #expect(await terminator.count == 0)
    }

    @Test("effective policy revision change invalidates an open review")
    @MainActor func policyChangeBlocksDispatch() async throws {
        let fixture = try RescueFixture(pid: 10, start: 20)
        defer { fixture.cleanup() }
        let policy = RescuePolicyBox(rescueLivePolicy())
        let terminator = RescueTerminatorProbe(.exited)
        let planner = RescuePlanner(terminator: terminator,
                                    livePolicy: { policy.value })
        let review = try await planner.beginReview(workload: fixture.workload,
            approval: fixture.approval, authority: fixture.authority,
            owner: owner, nowMonotonicNanoseconds: 1)
        policy.value = rescueLivePolicy(revision: 2)
        await #expect(throws: RescueDenial.policyChanged) {
            _ = try await planner.select(review.token, owner: owner,
                                         nowMonotonicNanoseconds: 2)
        }
        #expect(await terminator.count == 0)
    }

    private var owner: UUID { UUID(uuidString: "33333333-3333-3333-3333-333333333333")! }
}

@MainActor
private final class RescuePolicyBox {
    var value: RescueLivePolicy
    init(_ value: RescueLivePolicy) { self.value = value }
}

private func rescueLivePolicy(revision: UInt64 = 1,
                              enabled: Bool = true) -> RescueLivePolicy {
    RescueLivePolicy(revision: revision, policy: EffectivePolicy(
        fields: [:], allowedFeatures: enabled ? ["rescue"] : [],
        walkWorkers: 1, readOnlyProcesses: 1,
        scanAdmission: .discretionaryAllowed,
        manualBatchBytes: 1, manualBatchItems: 1, exclusions: []))
}

private struct RescueFixture {
    let root: URL
    let app: URL
    let approval: RescueApplicationApproval
    let workload: WorkloadIdentity
    let authority: LocalAuthoritySnapshot

    init(pid: Int32, start: UInt64) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tidy-rescue-\(UUID().uuidString)", isDirectory: true)
        app = root.appendingPathComponent("Fixture.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true)
        approval = try RescueApplicationApproval(bundleURL: app,
                                                  bundleIdentifier: "com.example.fixture")
        workload = try WorkloadIdentity(bundleURL: app,
            bundleIdentifier: "com.example.fixture",
            bootID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            pid: pid, startedAtTicks: start,
            executablePath: app.appendingPathComponent("Contents/MacOS/Fixture").path,
            executableDevice: 1, executableInode: 2)
        authority = LocalAuthoritySnapshot(revision: 1,
            installation: .init(canonicalDirectoryPath: root.path, volumeDevice: 1,
                                directoryInode: 2, ownerUID: 501),
            scopes: [.rescueApplication(approval)])
    }

    func identity(pid: Int32, start: UInt64) throws -> WorkloadIdentity {
        try WorkloadIdentity(bundleURL: app, bundleIdentifier: "com.example.fixture",
            bootID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            pid: pid, startedAtTicks: start,
            executablePath: app.appendingPathComponent("Contents/MacOS/Fixture").path,
            executableDevice: 1, executableInode: 2)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
