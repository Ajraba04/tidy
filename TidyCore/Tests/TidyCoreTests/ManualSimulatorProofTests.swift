import Darwin
import Foundation
import Testing
@_spi(TidyCoreTesting) @testable import TidyCore

private actor SimulatorProofReader: ManualSimulatorReading {
    let id: UUID
    init(_ id: UUID) { self.id = id }
    func read(_ request: ManualSimulatorReadRequest, terminalLease: ProcessTerminalVerificationLease?) async throws -> Data {
        switch request.component {
        case .devices: return Data("{\"devices\":{\"com.apple.CoreSimulator.SimRuntime.iOS-27-0\":[{\"udid\":\"\(id.uuidString)\",\"name\":\"Owned proof fixture\",\"state\":\"Shutdown\",\"isAvailable\":true,\"deviceTypeIdentifier\":\"com.apple.CoreSimulator.SimDeviceType.iPhone-17\"}]}}".utf8)
        case .runtimes: return Data(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","buildversion":"24A434","isAvailable":true,"supportedDeviceTypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17"}]}]}"#.utf8)
        case .pairs: return Data(#"{"pairs":{}}"#.utf8)
        }
    }
}

@Suite("Compiled owned simulator fixture terminal proof", .serialized)
struct ManualSimulatorProofTests {
    @Test func proofPublicationGapReopensWithoutReplayingAndPreservesFixtureOrigin() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/TidySimulatorProof-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let approved = try LocalRootApproval.verify(directory: root)
        let cat = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/bin/cat"))
        let producer = AppleSimulatorProducerIdentity(resolver: cat, simctl: cat,
            developerDirectory: approved, deviceSet: approved, xcodeVersion: "27.0", xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        let object = ManualSimulatorObject(udid: UUID(), runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17", name: "Owned proof fixture", state: .booted, isAvailable: true)
        let binding = try ManualServiceEffectBinding(reviewID: UUID(), coordinatorID: UUID(), policyRevision: 1, authorityRevision: 1,
            installation: LocalInstallationIdentity.verify(directory: root),
            operation: ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1, object: .simulator(object), producer: .appleSimulator(producer)))
        let directory = root.appendingPathComponent("execution")
        let store = try MutationAdmissionStore(directory: directory)
        #expect(store.acquire() == .ready)
        defer { store.release() }
        let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: directory))
        let runID = UUID(), operationID = UUID()
        try journal.append(.init(runID: runID, sequence: 1, phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(.init(runID: runID, sequence: 2, phase: .confirmed, operationID: nil, status: nil, reason: nil))
        let submission = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID, binding: binding, journal: journal)
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let launch = try await ProcessRunner.launchManualSimulatorFixtureForTesting(submission: submission, gate: gate,
            deadline: ContinuousClock.now.advanced(by: .seconds(5)))
        try submission.recordOwnedChild(launch)
        try launch.session.releaseStartByte()
        let client = try ManualSimulatorClient.forTesting(producer: producer, reader: SimulatorProofReader(object.udid))
        let receipt = try await client.terminalReceiptForTesting(launch: launch)
        let proof = try CompiledEffectTerminalVerifier.manualSimulatorFixtureReceipt(receipt)
        let intent = try #require(store.unfinishedIntentsWhileLocked().first)
        #expect(CompiledEffectTerminalVerifier.validate(proof.archive, intent: intent))
        #expect(proof.archive.verifier == "tidy.manual-service.simulator-owned-fixture.v1")
        #expect(proof.archive.terminalStatus == .succeeded)
        #expect(proof.archive.outcomeCount == 1)
        #expect(ManualServiceAcceptanceRegistry.denial(for: binding.operation) != nil)
        var data = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proof.archive)) as? [String: Any])
        data["verifier"] = "tidy.manual-service.simulator-native.v1"
        #expect(!CompiledEffectTerminalVerifier.validate(try JSONDecoder().decode(EffectTerminalProofArchive.self,
            from: JSONSerialization.data(withJSONObject: data)), intent: intent))
        let reference = try journal.persistTerminalProof(proof)
        #expect(reference.id == operationID)
        store.release()
        let reopened = try MutationAdmissionStore(directory: directory)
        #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
        defer { reopened.release() }
        let recovered = try RunJournal(store: reopened, storage: DurableJournalStorage(directory: directory))
        #expect(try recovered.reconcileTerminalRun(runID: runID))
        #expect(reopened.acquire() == .ready)
        #expect(try recovered.events(runID: runID).filter { $0.phase == .itemTerminal }.count == 1)
        #expect(try recovered.reconcileTerminalRun(runID: runID))
        // This proof has an explicit fixture verifier and grants no production
        // obligation release. Restore only the isolated test's resource budget.
        try await gate.closeTerminalVerificationForTesting(receipt.terminalVerificationLease)
        #expect(await gate.snapshot().unresolvedMutations == 0)
    }
}
