import Darwin
import Foundation
import Testing
@_spi(TidyCoreTesting) @testable import TidyCore

private actor NativeReceiptReaderWitness: ManualSimulatorReading {
    private var calls = 0
    func read(_ request: ManualSimulatorReadRequest,
              terminalLease: ProcessTerminalVerificationLease?) async throws -> Data {
        calls += 1
        return Data("{}".utf8)
    }
    func count() -> Int { calls }
}

@Suite("Native simulator receipt isolation", .serialized)
struct ManualSimulatorNativeClientTests {
    @Test("cooperative launch and injected readers cannot become native terminal proof",
          arguments: ["fixture", "inventoryOnly"])
    func fixtureCannotProduceNativeReceipt(clientMode: String) async throws {
        let root = URL(fileURLWithPath: "/private/tmp/TidyNativeReceipt-\(UUID().uuidString)")
        let authorityDirectory = root.appendingPathComponent("authority")
        for directory in [root, authorityDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let set = try LocalRootApproval.verify(directory: root)
        let cat = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/bin/cat"))
        let authority = try LocalAuthorityStore(directory: authorityDirectory,
            installation: LocalInstallationIdentity.verify(directory: authorityDirectory))
        let owner = LocalAuthorityOwner()
        for scope in [LocalAuthorityScope.localExecutable(cat), .localRoot(set)] {
            let token = try await authority.beginReview(scope: scope, owner: owner, nowMonotonicNanoseconds: 1)
            _ = try await authority.confirm(token, owner: owner, nowMonotonicNanoseconds: 2)
        }
        let snapshot = try await authority.snapshot()
        let producer = AppleSimulatorProducerIdentity(resolver: cat, simctl: cat,
            developerDirectory: set, deviceSet: set, xcodeVersion: "27.0", xcodeBuild: "27A266a",
            coreSimulatorVersion: "1171.7")
        let object = ManualSimulatorObject(udid: UUID(),
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            name: "Owned receipt isolation fixture", state: .booted, isAvailable: true)
        let binding = try ManualServiceEffectBinding(reviewID: UUID(), coordinatorID: UUID(),
            policyRevision: 1, authorityRevision: snapshot.revision, installation: snapshot.installation,
            operation: ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
                object: .simulator(object), producer: .appleSimulator(producer)))
        let journalDirectory = root.appendingPathComponent("journal")
        let admission = try MutationAdmissionStore(directory: journalDirectory)
        #expect(admission.acquire() == .ready)
        defer { admission.release() }
        let journal = try RunJournal(store: admission, storage: DurableJournalStorage(directory: journalDirectory))
        let runID = UUID(), operationID = UUID()
        try journal.append(.init(runID: runID, sequence: 1, phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(.init(runID: runID, sequence: 2, phase: .confirmed, operationID: nil, status: nil, reason: nil))
        let submission = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID,
            binding: binding, journal: journal)
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let launch = try await ProcessRunner.launchManualSimulatorFixtureForTesting(submission: submission,
            gate: gate, deadline: ContinuousClock.now.advanced(by: .seconds(2)))
        let reader = NativeReceiptReaderWitness()
        let client = clientMode == "fixture"
            ? try ManualSimulatorClient.forTesting(producer: producer, reader: reader)
            : try ManualSimulatorClient.inventoryOnly(producer: producer, reader: reader, authority: snapshot)
        let ledger = journalDirectory.appendingPathComponent("unfinished-effects.json")
        let before = try Data(contentsOf: ledger)
        do {
            let _: NativeSimulatorServiceReceipt = try await client.terminalReceipt(launch: launch, within: .seconds(1))
            Issue.record("An isolated fixture was promoted to native terminal proof")
        } catch ManualSimulatorClientError.fixtureOnly {
            // A native-only receipt cannot consume a cooperative launch even
            // when all ordinary local read grants exist.
        }
        #expect(await reader.count() == 0)
        #expect(launch.session.observationSnapshot().consumingReapCount == 0)
        #expect(try Data(contentsOf: ledger) == before)
        #expect(try admission.unfinishedIntentsWhileLocked().first?.phase == .submitted)
        #expect(ManualServiceAcceptanceRegistry.denial(for: binding.operation) == .producerAcceptanceMissing)
        try launch.session.releaseStartByte()
        _ = await launch.session.observeOwnedExit(within: .seconds(2))
        let lease = try await launch.session.transferReapedMutationToTerminalVerification(within: .seconds(1))
        try await gate.closeTerminalVerificationForTesting(lease)
    }
}
