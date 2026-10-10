import Foundation
import Testing
@testable import TidyCore

private struct ServiceJournalFixture {
    let root: URL
    let journalURL: URL
    let binding: ManualServiceEffectBinding
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/Tidy-ServiceJournal-\(UUID().uuidString)")
        journalURL = root.appendingPathComponent("execution")
        let authority = root.appendingPathComponent("authority")
        for path in [root, authority] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        let directory = try LocalRootApproval.verify(directory: root)
        let executable = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/usr/bin/true"))
        let producer = AppleSimulatorProducerIdentity(resolver: executable, simctl: executable,
            developerDirectory: directory, deviceSet: directory,
            xcodeVersion: "27.0", xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        let object = ManualSimulatorObject(udid: UUID(),
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            name: "Owned fixture data; never executed", state: .booted, isAvailable: true)
        binding = try ManualServiceEffectBinding(reviewID: UUID(), coordinatorID: UUID(),
            policyRevision: 1, authorityRevision: 1,
            installation: LocalInstallationIdentity.verify(directory: authority),
            operation: ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
                object: .simulator(object), producer: .appleSimulator(producer)))
    }
    func open() throws -> (MutationAdmissionStore, RunJournal) {
        let admission = try MutationAdmissionStore(directory: journalURL)
        _ = admission.acquire()
        return (admission, try RunJournal(store: admission, storage: DurableJournalStorage(directory: journalURL)))
    }
    func begin(_ journal: RunJournal, runID: UUID) throws {
        try journal.append(.init(runID: runID, sequence: 1, phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(.init(runID: runID, sequence: 2, phase: .confirmed, operationID: nil, status: nil, reason: nil))
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Durable manual service admission", .serialized)
struct ManualServiceJournalTests {
    @Test("coordinator relaunch reconciles only a stored service proof and requires fresh review")
    func coordinatorReopensServiceProof() async throws {
        let fixture = try ServiceJournalFixture(); defer { fixture.cleanup() }
        let (admission, journal) = try fixture.open()
        let runID = UUID(), operationID = UUID()
        try fixture.begin(journal, runID: runID)
        let submission = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID,
            binding: fixture.binding, journal: journal)
        _ = try journal.persistTerminalProof(submission.cancelBeforeSubmission())
        admission.release()
        let coordinator = ExecutionCoordinator(environment: CleanEnvironment(homeDirectory: fixture.root.path,
            detectedTools: [], protectedRoots: []), journalDirectory: fixture.journalURL)
        let first = await coordinator.reconcileUnfinishedEffects()
        #expect(first.disposition == .requireFreshReview)
        #expect(first.inspectedEffects == 1 && first.reconciledEffects == 1)
        #expect(await coordinator.mutationAdmission() == .ready)
        #expect(await coordinator.reconcileUnfinishedEffects().disposition == .noUnfinishedEffects)
    }

    @Test("service intent schema and full binding survive reopening without granting execution")
    func serviceSchemaRoundTrip() throws {
        let fixture = try ServiceJournalFixture(); defer { fixture.cleanup() }
        let bytes = try JSONEncoder().encode(fixture.binding)
        #expect(try JSONDecoder().decode(ManualServiceEffectBinding.self, from: bytes) == fixture.binding)
        var unknown = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        unknown["schema"] = 99
        #expect(throws: Error.self) {
            try JSONDecoder().decode(ManualServiceEffectBinding.self,
                from: JSONSerialization.data(withJSONObject: unknown))
        }
        let (admission, journal) = try fixture.open()
        let runID = UUID(), operationID = UUID()
        try fixture.begin(journal, runID: runID)
        _ = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID,
            binding: fixture.binding, journal: journal)
        let stored = try #require(admission.unfinishedIntentsWhileLocked().first)
        #expect(stored.schemaVersion == 3)
        #expect(stored.binding == .service(fixture.binding))
        admission.release()
        let (reopened, reopenedJournal) = try fixture.open(); defer { reopened.release() }
        #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
        #expect(try reopenedJournal.reconcileTerminalRun(runID: runID) == false)
        #expect(try reopened.unfinishedIntentsWhileLocked().count == 1)
    }

    @Test("a durable never-submitted proof recovers the publication-before-event crash gap")
    func recoverPublishedProofBeforeTerminalEvent() throws {
        let fixture = try ServiceJournalFixture(); defer { fixture.cleanup() }
        let (admission, journal) = try fixture.open()
        let runID = UUID(), operationID = UUID()
        try fixture.begin(journal, runID: runID)
        let submission = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID,
            binding: fixture.binding, journal: journal)
        let proof = try submission.cancelBeforeSubmission()
        let reference = try journal.persistTerminalProof(proof)
        #expect(reference.id == operationID)
        #expect(throws: JournalError.invalidTransition) { try submission.beginSubmission() }
        admission.release()
        let (reopened, recovered) = try fixture.open(); defer { reopened.release() }
        #expect(try recovered.reconcileTerminalRun(runID: runID))
        #expect(reopened.acquire() == .ready)
        let events = try recovered.events(runID: runID)
        #expect(events.filter { $0.phase == .itemTerminal }.count == 1)
        #expect(events.last?.phase == .finished)
        #expect(try recovered.reconcileTerminalRun(runID: runID))
    }

    @Test("possible submission cannot be converted to a no-effect proof or replayed")
    func submittedIntentRemainsUncertain() throws {
        let fixture = try ServiceJournalFixture(); defer { fixture.cleanup() }
        let (admission, journal) = try fixture.open(); defer { admission.release() }
        let runID = UUID(), operationID = UUID()
        try fixture.begin(journal, runID: runID)
        let submission = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID,
            binding: fixture.binding, journal: journal)
        _ = try submission.beginSubmission()
        #expect(throws: JournalError.invalidTransition) { try submission.cancelBeforeSubmission() }
        #expect(throws: JournalError.invalidTransition) { try submission.beginSubmission() }
        #expect(try admission.unfinishedIntentsWhileLocked().first?.phase == .submitted)
        #expect(try journal.reconcileTerminalRun(runID: runID) == false)
        #expect(admission.acquire() == .uncertainAndPossiblyRunning)
    }
}
