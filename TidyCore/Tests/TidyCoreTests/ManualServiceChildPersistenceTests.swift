import Darwin
import Foundation
import Testing
@_spi(TidyCoreTesting) @testable import TidyCore

@Suite("Owned schema-three service child persistence", .serialized)
struct ManualServiceChildPersistenceTests {
    @Test func rawJournalCannotPersistSyntacticallyValidUnownedChildTuple() throws {
        let f = try ChildPersistenceFixture(); defer { f.remove() }
        let (store, journal) = try f.open(); defer { store.release() }
        let runID = UUID(), operationID = UUID()
        let submission = try f.prepare(journal, runID: runID, operationID: operationID)
        _ = try submission.beginSubmission()
        let forged = try unownedIntent(f, runID: runID, operationID: operationID)
        let before = try Data(contentsOf: f.journalURL.appendingPathComponent("unfinished-effects.json"))
        #expect(throws: Error.self) { try journal.recordManualServiceChild(forged) }
        #expect(try Data(contentsOf: f.journalURL.appendingPathComponent("unfinished-effects.json")) == before)
        #expect(try store.unfinishedIntentsWhileLocked().first?.childPID == nil)
    }

    @Test func rawStoreCannotCaptureUnownedTupleOrIntroduceChildAtSubmissionBoundary() throws {
        let f = try ChildPersistenceFixture(); defer { f.remove() }
        let (store, journal) = try f.open(); defer { store.release() }
        let runID = UUID(), operationID = UUID()
        let submission = try f.prepare(journal, runID: runID, operationID: operationID)
        let forged = try unownedIntent(f, runID: runID, operationID: operationID)
        #expect(throws: Error.self) { try store.persistIntentWhileLocked(forged, update: .serviceSubmission) }
        let captureRunID = UUID(), captureOperationID = UUID()
        let capture = try f.prepare(journal, runID: captureRunID, operationID: captureOperationID)
        _ = try capture.beginSubmission()
        let captureForgery = try unownedIntent(f, runID: captureRunID, operationID: captureOperationID)
        let before = try Data(contentsOf: f.journalURL.appendingPathComponent("unfinished-effects.json"))
        #expect(throws: Error.self) { try store.persistIntentWhileLocked(captureForgery, update: .serviceChildCapture) }
        #expect(try Data(contentsOf: f.journalURL.appendingPathComponent("unfinished-effects.json")) == before)
        #expect(try store.unfinishedIntentsWhileLocked().first(where: { $0.operationID == captureOperationID })?.childPID == nil)
        _ = submission // The raw submission attempt must not grant child-capture evidence.
    }

    @Test func exactOwnedTupleSurvivesReopenButDoesNotProveTerminalState() async throws {
        let f = try ChildPersistenceFixture(); defer { f.remove() }
        let (admission, journal) = try f.open()
        defer { admission.release() }
        let runID = UUID(), operationID = UUID()
        let submission = try f.prepare(journal, runID: runID, operationID: operationID)
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let stored = try await withOwnedLaunch(submission, gate: gate) { launch in
            let identity = try #require(launch.session.identity)
            try submission.recordOwnedChild(launch)
            let stored = try #require(admission.unfinishedIntentsWhileLocked().first)
            #expect(stored.schemaVersion == 3 && stored.phase == .submitted)
            #expect(stored.runID == runID && stored.operationID == operationID)
            #expect(stored.binding == .service(f.binding))
            #expect(stored.bootID == identity.bootID && stored.childPID == identity.pid)
            #expect(stored.childStartSeconds == identity.startSeconds && stored.childStartMicroseconds == identity.startMicroseconds)
            #expect(stored.executablePath == identity.executablePath)
            #expect(stored.executableDevice == identity.executableDevice && stored.executableInode == identity.executableInode)
            let beforeRepeat = try Data(contentsOf: f.journalURL.appendingPathComponent("unfinished-effects.json"))
            try submission.recordOwnedChild(launch)
            #expect(try Data(contentsOf: f.journalURL.appendingPathComponent("unfinished-effects.json")) == beforeRepeat)
            return stored
        }
        admission.release()
        let (reopened, reopenedJournal) = try f.open(); defer { reopened.release() }
        #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
        #expect(try reopened.unfinishedIntentsWhileLocked() == [stored])
        #expect(try reopenedJournal.reconcileTerminalRun(runID: runID) == false)
        #expect(try reopened.unfinishedIntentsWhileLocked().count == 1)
    }

    @Test func captureWindowWithoutDurableTupleStaysBlockedAfterOwnedExit() async throws {
        let f = try ChildPersistenceFixture(); defer { f.remove() }
        let (admission, journal) = try f.open(); defer { admission.release() }
        let runID = UUID(), operationID = UUID()
        let submission = try f.prepare(journal, runID: runID, operationID: operationID)
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        try await withOwnedLaunch(submission, gate: gate) { launch in
            // A real child exists; simulate interruption before recordOwnedChild.
            try #require(launch.session.identity != nil)
        }
        admission.release()
        let (reopened, reopenedJournal) = try f.open(); defer { reopened.release() }
        #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
        let pending = try #require(reopened.unfinishedIntentsWhileLocked().first)
        #expect(pending.schemaVersion == 3 && pending.phase == .submitted)
        #expect(pending.bootID == nil && pending.childPID == nil && pending.executablePath == nil)
        #expect(try reopenedJournal.reconcileTerminalRun(runID: runID) == false)
    }

    @Test func metadataEqualLaunchFromAnotherSubmissionCannotCaptureOrSubstituteChild() async throws {
        let f = try ChildPersistenceFixture(); defer { f.remove() }
        let (firstStore, firstJournal) = try f.open(); defer { firstStore.release() }
        let foreignURL = f.root.appendingPathComponent("foreign-execution")
        let (foreignStore, foreignJournal) = try f.open(at: foreignURL); defer { foreignStore.release() }
        let runID = UUID(), operationID = UUID()
        let first = try f.prepare(firstJournal, runID: runID, operationID: operationID)
        let foreign = try f.prepare(foreignJournal, runID: runID, operationID: operationID)
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let foreignGate = try ProcessJobGate.isolatedForTesting(limit: 2)
        try await withOwnedLaunch(first, gate: gate) { ownLaunch in
            try await withOwnedLaunch(foreign, gate: foreignGate) { foreignLaunch in
                #expect(ownLaunch.invocation.binding == foreignLaunch.invocation.binding)
                #expect(ownLaunch.invocation.runID == foreignLaunch.invocation.runID)
                #expect(ownLaunch.invocation.operationID == foreignLaunch.invocation.operationID)
                #expect(throws: Error.self) { try first.recordOwnedChild(foreignLaunch) }
                #expect(try firstStore.unfinishedIntentsWhileLocked().first?.childPID == nil)
                try first.recordOwnedChild(ownLaunch)
                let captured = try #require(firstStore.unfinishedIntentsWhileLocked().first)
                #expect(throws: Error.self) { try first.recordOwnedChild(foreignLaunch) }
                #expect(try firstStore.unfinishedIntentsWhileLocked().first == captured)
                #expect(throws: Error.self) { try firstJournal.recordChild(captured) }
                try foreign.recordOwnedChild(foreignLaunch)
            }
        }
    }

    @Test func preparedDockerPartialOrSchemaTwoChildEncodingCannotEnterLedger() async throws {
        let f = try ChildPersistenceFixture(); defer { f.remove() }
        let (admission, journal) = try f.open(); defer { admission.release() }
        let submission = try f.prepare(journal, runID: UUID(), operationID: UUID())
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        try await withOwnedLaunch(submission, gate: gate) { launch in
            try submission.recordOwnedChild(launch)
            let captured = try #require(admission.unfinishedIntentsWhileLocked().first)
            for mutation in ["prepared", "schemaTwo", "partial", "wrongExecutable", "docker"] {
                var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(captured)) as! [String: Any]
                encoded["operationID"] = UUID().uuidString
                switch mutation {
                case "prepared": encoded["phase"] = "prepared"
                case "schemaTwo": encoded["schemaVersion"] = 2
                case "partial": encoded.removeValue(forKey: "childStartMicroseconds")
                case "wrongExecutable": encoded["executableInode"] = (captured.executableInode ?? 0) + 1
                case "docker":
                    let docker = try f.dockerBinding(identity: #require(launch.session.identity))
                    let empty = PendingEffectIntent(runID: UUID(), operationID: UUID(), service: docker, phase: .submitted)
                    let dockerJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(empty)) as! [String: Any]
                    encoded["binding"] = dockerJSON["binding"]
                    encoded["adapterID"] = docker.operation.adapter.rawValue
                default: break
                }
                let hostile = try JSONDecoder().decode(PendingEffectIntent.self,
                    from: JSONSerialization.data(withJSONObject: encoded))
                #expect(throws: Error.self) { try admission.persistIntentWhileLocked(hostile) }
                #expect(try admission.unfinishedIntentsWhileLocked() == [captured])
            }
        }
    }

    private func withOwnedLaunch<T>(_ submission: ManualServiceSubmission, gate: ProcessJobGate,
                                   body: (ManualSimulatorOwnedLaunch) async throws -> T) async throws -> T {
        let launch = try await ProcessRunner.launchManualSimulatorFixtureForTesting(submission: submission,
            gate: gate, deadline: ContinuousClock.now.advanced(by: .seconds(10)))
        do {
            let result = try await body(launch)
            try await finish(launch, gate: gate)
            return result
        } catch {
            // Cleanup is cooperative and own-reap-bound; never force-kill a
            // mutation or substitute a process-absence claim for ownership.
            try? await finish(launch, gate: gate)
            throw error
        }
    }

    private func unownedIntent(_ fixture: ChildPersistenceFixture, runID: UUID,
                               operationID: UUID) throws -> PendingEffectIntent {
        guard case .appleSimulator(let producer) = fixture.binding.operation.producer else {
            throw JournalError.invalidTransition
        }
        // Deliberately well-formed data only. No process or owned launch exists.
        let child = ProcessInstanceIdentity(bootID: UUID(), pid: 123_456,
            startSeconds: 0, startMicroseconds: 0, executablePath: producer.simctl.canonicalPath,
            executableDevice: producer.simctl.device, executableInode: producer.simctl.inode)
        return PendingEffectIntent(runID: runID, operationID: operationID,
            service: fixture.binding, phase: .submitted, child: child)
    }

    private func finish(_ launch: ManualSimulatorOwnedLaunch, gate: ProcessJobGate) async throws {
        if launch.session.observationSnapshot().consumingReapCount == 0 {
            try? launch.session.releaseStartByte()
        }
        _ = await launch.session.collect()
        _ = await launch.session.observeOwnedExit(within: .seconds(2))
        try #require(launch.session.observationSnapshot().consumingReapCount == 1)
        if launch.session.identity == nil {
            try await launch.session.releaseReapedMutationForTesting()
            return
        }
        let receipt = try launch.session.reapedMutationReceipt()
        try #require(receipt.rawStatus == 0)
        let lease = try await launch.session.transferReapedMutationToTerminalVerification(within: .seconds(1))
        try await gate.closeTerminalVerificationForTesting(lease)
        #expect(await gate.snapshot().unresolvedMutations == 0)
    }
}

private struct ChildPersistenceFixture {
    let root: URL
    let journalURL: URL
    let binding: ManualServiceEffectBinding
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/Tidy-ServiceChild-\(UUID().uuidString)")
        journalURL = root.appendingPathComponent("execution")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let directory = try LocalRootApproval.verify(directory: root)
        let cat = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/bin/cat"))
        let producer = AppleSimulatorProducerIdentity(resolver: cat, simctl: cat,
            developerDirectory: directory, deviceSet: directory, xcodeVersion: "27.0",
            xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        let object = ManualSimulatorObject(udid: UUID(), runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            name: "Owned cooperative protocol; no device shutdown", state: .booted, isAvailable: true)
        binding = try ManualServiceEffectBinding(reviewID: UUID(), coordinatorID: UUID(), policyRevision: 1,
            authorityRevision: 1, installation: LocalInstallationIdentity.verify(directory: root),
            operation: ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
                object: .simulator(object), producer: .appleSimulator(producer)))
    }
    func open(at path: URL? = nil) throws -> (MutationAdmissionStore, RunJournal) {
        let url = path ?? journalURL
        let store = try MutationAdmissionStore(directory: url)
        _ = store.acquire()
        return (store, try RunJournal(store: store, storage: DurableJournalStorage(directory: url)))
    }
    func prepare(_ journal: RunJournal, runID: UUID, operationID: UUID) throws -> ManualServiceSubmission {
        try journal.append(.init(runID: runID, sequence: 1, phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(.init(runID: runID, sequence: 2, phase: .confirmed, operationID: nil, status: nil, reason: nil))
        return try ManualServiceSubmission.prepare(runID: runID, operationID: operationID, binding: binding, journal: journal)
    }
    func dockerBinding(identity: ProcessInstanceIdentity) throws -> ManualServiceEffectBinding {
        let producer = DockerProducerIdentity(socket: .init(canonicalPath: root.appendingPathComponent("metadata-only.sock").path,
            device: 1, inode: 2, ownerUID: geteuid()), peerPID: identity.pid, peerUID: geteuid(),
            peerBootID: identity.bootID, peerStartSeconds: identity.startSeconds, peerStartMicroseconds: identity.startMicroseconds,
            peerExecutable: .init(canonicalPath: identity.executablePath, device: identity.executableDevice, inode: identity.executableInode),
            providerIdentifier: "metadata-only", daemonID: "not-a-connected-daemon", version: .init(engineVersion: "28.0.0",
                apiVersion: "1.51", minimumAPIVersion: "1.44", operatingSystem: "linux", architecture: "arm64"))
        let object = ManualDockerContainerObject(id: String(repeating: "a", count: 64), name: "/metadata-only",
            created: "2026-10-10T00:00:00Z", imageID: "sha256:" + String(repeating: "b", count: 64),
            writableLayerBytes: nil, configurationDigest: Data(repeating: 0, count: 32), labelKeys: [])
        return try ManualServiceEffectBinding(reviewID: UUID(), coordinatorID: UUID(), policyRevision: 1,
            authorityRevision: 1, installation: binding.installation,
            operation: ManualServiceOperationBinding(adapter: .dockerStoppedContainerRemovalV1,
                object: .container(object), producer: .docker(producer)))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
