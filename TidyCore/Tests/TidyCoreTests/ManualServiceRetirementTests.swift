import Darwin
import Foundation
import Testing
@_spi(TidyCoreTesting) @testable import TidyCore

private actor RetirementProofReader: ManualSimulatorReading {
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

@Suite("Durable manual service retirement capability", .serialized)
struct ManualServiceRetirementTests {
    @Test("fixture retirement never closes a production obligation; publication gaps mint no receipt",
          arguments: [0, 1, 2])
    func durableRetirementBoundary(failedJournalWrite: Int) async throws {
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
        let storage = try RetirementFailureStorage(directory: directory)
        let journal = try RunJournal(store: store, storage: storage)
        let runID = UUID(), operationID = UUID()
        try journal.append(.init(runID: runID, sequence: 1, phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(.init(runID: runID, sequence: 2, phase: .confirmed, operationID: nil, status: nil, reason: nil))
        let submission = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID, binding: binding, journal: journal)
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let launch = try await ProcessRunner.launchManualSimulatorFixtureForTesting(submission: submission, gate: gate,
            deadline: ContinuousClock.now.advanced(by: .seconds(5)))
        try submission.recordOwnedChild(launch)
        try launch.session.releaseStartByte()
        let client = try ManualSimulatorClient.forTesting(producer: producer, reader: RetirementProofReader(object.udid))
        let receipt = try await client.terminalReceiptForTesting(launch: launch)
        let proof = try CompiledEffectTerminalVerifier.manualSimulatorFixtureReceipt(receipt)
        let intent = try #require(store.unfinishedIntentsWhileLocked().first)
        #expect(CompiledEffectTerminalVerifier.validate(proof.archive, intent: intent))
        #expect(proof.archive.verifier == "tidy.manual-service.simulator-owned-fixture.v1")
        #expect(proof.archive.terminalStatus == .succeeded)
        #expect(proof.archive.outcomeCount == 1)
        #expect(ManualServiceAcceptanceRegistry.denial(for: binding.operation) != nil)
        storage.failReplacement(number: failedJournalWrite)
        var retirement: DurablyRetiredManualServiceReceipt?
        do {
            retirement = try journal.finishManualService(proof: proof)
            #expect(failedJournalWrite == 0)
        } catch JournalError.unavailable {
            #expect(failedJournalWrite != 0)
        }
        #expect(await gate.snapshot().unresolvedMutations == 1)
        if failedJournalWrite == 0 {
            let finished = try #require(retirement)
            #expect(try journal.events(runID: runID).last?.phase == .finished)
            #expect(try store.unfinishedIntentsWhileLocked().isEmpty)
            do {
                try await gate.closeTerminalVerification(receipt.terminalVerificationLease, retirement: finished)
                Issue.record("A fixture retirement closed the production-only process obligation")
            } catch ProcessTerminalVerificationError.invalidReceipt { }
            #expect(await gate.snapshot().unresolvedMutations == 1)
            // Repeating journal finish cannot reconstruct another opaque token
            // after its exact outstanding intent has already been retired.
            #expect(throws: JournalError.invalidTransition) {
                _ = try journal.finishManualService(proof: proof)
            }
        } else {
            #expect(retirement == nil)
            store.release()
            let reopened = try MutationAdmissionStore(directory: directory)
            #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
            defer { reopened.release() }
            let recovered = try RunJournal(store: reopened, storage: DurableJournalStorage(directory: directory))
            let pending = try #require(reopened.unfinishedIntentsWhileLocked().first)
            #expect(try ReviewedManifestStore(admission: reopened).findServiceProof(for: pending) != nil)
            let events = try recovered.events(runID: runID)
            #expect(events.filter { $0.phase == .itemTerminal }.count == (failedJournalWrite == 1 ? 0 : 1))
            #expect(events.last?.phase != .finished)
            #expect(try recovered.reconcileTerminalRun(runID: runID))
            #expect(try reopened.unfinishedIntentsWhileLocked().isEmpty)
            // Durable recovery returns no transient close capability. The
            // in-process obligation remains unresolved until fixture cleanup.
            #expect(await gate.snapshot().unresolvedMutations == 1)
        }
        // This proof has an explicit fixture verifier and grants no production
        // obligation release. Restore only the isolated test's resource budget.
        try await gate.closeTerminalVerificationForTesting(receipt.terminalVerificationLease)
        #expect(await gate.snapshot().unresolvedMutations == 0)
    }
}

/// Fail the itemTerminal or finished publication after the proof archive has
/// been durably published. The wrapper delegates all other storage semantics.
private final class RetirementFailureStorage: JournalStorage, @unchecked Sendable {
    private let base: DurableJournalStorage
    private let lock = NSLock()
    private var failure = 0
    private var replacements = 0
    init(directory: URL) throws { base = try DurableJournalStorage(directory: directory) }
    func failReplacement(number: Int) {
        lock.lock(); defer { lock.unlock() }
        failure = number; replacements = 0
    }
    func replace(name: String, bytes: Data) throws {
        lock.lock()
        replacements += 1
        let reject = failure > 0 && replacements == failure
        lock.unlock()
        if reject { throw JournalError.unavailable }
        try base.replace(name: name, bytes: bytes)
    }
    func read(name: String) throws -> Data { try base.read(name: name) }
    func directoryIdentity() throws -> JournalDirectoryIdentity { try base.directoryIdentity() }
    func journalEntries() throws -> [JournalStorageEntry] { try base.journalEntries() }
    func removeJournal(_ entry: JournalStorageEntry) throws { try base.removeJournal(entry) }
}
