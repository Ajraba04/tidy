import Foundation
import Darwin
import Testing
@testable import TidyCore

private struct ExecutionScratch {
    let root: URL
    let home: URL
    let journal: URL
    let leaf: URL
    init() throws {
        guard let canonical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw ResourceCaptureError.unavailable
        }
        defer { free(canonical) }
        root = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
            .appendingPathComponent("T02-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        journal = root.appendingPathComponent("journal", isDirectory: true)
        leaf = home.appendingPathComponent("sentinel")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try Data("preserve me".utf8).write(to: leaf)
    }
    var environment: CleanEnvironment {
        CleanEnvironment(homeDirectory: home.path, detectedTools: [], protectedRoots: [])
    }
    func coordinator() -> ExecutionCoordinator {
        ExecutionCoordinator(environment: environment, journalDirectory: journal)
    }
    func intact() throws { #expect(try Data(contentsOf: leaf) == Data("preserve me".utf8)) }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private func review(_ coordinator: ExecutionCoordinator) async throws -> RegisteredReview {
    try await coordinator.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                         tier: .deep, selectDefaults: false)
}

private func persistPolicy(_ coordinator: ExecutionCoordinator,
                           scratch: ExecutionScratch) async throws -> UInt64 {
    let ticket = try coordinator.beginPolicyUpdate()
    try ConfigStore.save(TidyConfig(), to: scratch.home.appendingPathComponent("config.json"))
    let commit = try await coordinator.commitPolicyUpdate(ticket, environment: scratch.environment)
    guard case .applied(let revision) = commit else {
        throw ConfirmationError.stalePolicy
    }
    return revision
}

private func expectConfirmationError(
    _ expected: ConfirmationError,
    _ operation: () async throws -> Void
) async {
    do { try await operation(); Issue.record("Expected \(expected)") }
    catch let error as ConfirmationError { #expect(error == expected) }
    catch { Issue.record("Wrong error: \(error)") }
}

private func interruptedIntent(phase: SubmissionPhase) -> PendingEffectIntent {
    PendingEffectIntent(
        runID: UUID(), operationID: UUID(), adapterID: "legacy.unreconciled",
        bootID: UUID(), executablePath: "/unavailable/previous-child",
        executableDevice: 99, executableInode: 123,
        childPID: nil, childStartSeconds: nil, childStartMicroseconds: nil,
        phase: phase)
}

@Suite("Confirmed execution")
struct ConfirmedExecutionTests {
    @Test("FIFO metadata fails promptly, preserves storage and releases the installation lock",
          arguments: ["bootstrap.json", "unfinished-effects.json"])
    func fifoMetadataBlocksPromptly(name: String) async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        #expect(await c.mutationAdmission() == .ready)
        let names = try FileManager.default.contentsOfDirectory(atPath: s.journal.path).sorted()
        let target = s.journal.appendingPathComponent(name)
        let backup = s.root.appendingPathComponent("original-" + name)
        let targetBytes = try Data(contentsOf: target)
        var otherBytes: [String: Data] = [:]
        for other in names where other != name {
            otherBytes[other] = try Data(contentsOf: s.journal.appendingPathComponent(other))
        }
        try FileManager.default.moveItem(at: target, to: backup) // Exact UUID-owned fixture only.
        #expect(mkfifo(target.path, 0o600) == 0)
        var before = stat()
        try #require(lstat(target.path, &before) == 0)
        try #require(before.st_mode & S_IFMT == S_IFIFO)
        try #require(before.st_mode & 0o777 == 0o600)
        let lockFD = open(s.journal.appendingPathComponent("mutation.lock").path,
                          O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        try #require(lockFD >= 0)
        defer { close(lockFD) }

        let watchdog = try FIFOReadWatchdog(fifo: target)
        // No throwing assertion, cancellation race or early return between start and drain.
        let admission = await c.mutationAdmission()
        let watchdogFired = watchdog.finishAndDrain()

        #expect(admission == .storageUnavailable)
        #expect(!watchdogFired, "Admission needed the FIFO rescue writer after five seconds")
        let lockResult = flock(lockFD, LOCK_EX | LOCK_NB)
        #expect(lockResult == 0, "Coordinator must release its transient lease on storage failure")
        if lockResult == 0 { _ = flock(lockFD, LOCK_UN) }
        // Keep the coordinator alive through the lock assertion: deinit must not prove release.
        withExtendedLifetime(c) {}
        var after = stat()
        try #require(lstat(target.path, &after) == 0)
        #expect(after.st_mode & S_IFMT == S_IFIFO)
        #expect(after.st_dev == before.st_dev)
        #expect(after.st_ino == before.st_ino)
        #expect(after.st_mode == before.st_mode)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.journal.path).sorted() == names)
        #expect(try Data(contentsOf: backup) == targetBytes)
        for (other, bytes) in otherBytes {
            #expect(try Data(contentsOf: s.journal.appendingPathComponent(other)) == bytes)
        }
        try s.intact()
    }

    @Test("Journal parent symlink is rejected before bootstrap writes")
    func symlinkedJournalParent() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let alias = s.root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: s.root)
        let c = ExecutionCoordinator(environment: s.environment,
            journalDirectory: alias.appendingPathComponent("journal"))
        #expect(await c.mutationAdmission() == .storageUnavailable)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.journal.path).isEmpty)
    }

    @Test("New confirmation revokes the older token and discard removes authority")
    func reconfirmAndDiscard() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let first = try await c.confirm(binding: r.binding)
        let second = try await c.confirm(binding: r.binding)
        #expect(await c.execute(first, currentPolicyRevision: 1).disposition == .staleReview)
        await c.discardReview(planID: r.binding.planID)
        #expect(await c.execute(second, currentPolicyRevision: 1).disposition == .invalidToken)
        await expectConfirmationError(.unknownPlan) { _ = try await c.confirm(binding: r.binding) }
    }

    @Test("Legacy reports decode missing admission fields without inventing measurements")
    func legacyReportDecoding() throws {
        let legacy = RunReport(tier: .safe, results: [], startedAt: Date(), finishedAt: Date(),
                               freeSpaceBeforeBytes: 1, freeSpaceAfterBytes: 2)
        let data = try JSONEncoder().encode(legacy)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "disposition")
        object.removeValue(forKey: "coordinatorMeasurementsAvailable")
        let decoded = try JSONDecoder().decode(RunReport.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.disposition == .completed)
        #expect(decoded.coordinatorMeasurementsAvailable == nil)
        #expect(decoded.freeSpaceAfterBytes == 2)
    }

    @Test("Unsafe bootstrap inputs cannot create ready admission",
          arguments: ["unrelated", "lock-only", "symlink", "permissions"])
    func unsafeBootstrap(kind: String) async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        switch kind {
        case "unrelated":
            try Data("preserve".utf8).write(to: s.journal.appendingPathComponent("unrelated"))
        case "lock-only":
            let lock = s.journal.appendingPathComponent("mutation.lock")
            try Data().write(to: lock)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lock.path)
        case "symlink":
            let moved = s.root.appendingPathComponent("actual-journal")
            try FileManager.default.moveItem(at: s.journal, to: moved)
            try FileManager.default.createSymbolicLink(at: s.journal, withDestinationURL: moved)
        default:
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.journal.path)
        }
        #expect(await s.coordinator().mutationAdmission() == .storageUnavailable)
        try s.intact()
    }

    @Test("Store rejects relocation of its directory rather than leasing an orphaned lock")
    func relocatedJournal() throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let original = try MutationAdmissionStore(directory: s.journal)
        #expect(original.acquire() == .ready); original.release()
        try FileManager.default.moveItem(at: s.journal, to: s.root.appendingPathComponent("moved-journal"))
        try FileManager.default.createDirectory(at: s.journal, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        #expect(original.acquire() == .storageUnavailable)
        original.release()
    }

    @Test("Invalid initialization markers preserve exact bytes",
          arguments: [Data(), Data("{\"schema\":1,\"storeID\":\"00000000-0000-0000-0000-000000000000\",\"state\":\"initializing\"}".utf8)])
    func invalidMarker(bytes: Data) async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        #expect(await s.coordinator().mutationAdmission() == .ready)
        let marker = s.journal.appendingPathComponent("bootstrap.json")
        try bytes.write(to: marker)
        #expect(await s.coordinator().mutationAdmission() == .storageUnavailable)
        #expect(try Data(contentsOf: marker) == bytes)
    }

    @Test("Unknown review cannot mint a token")
    func unknownReview() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let b = ReviewBinding(planID: UUID(), planRevision: 1,
                              policyRevision: 1, selectedIDs: [])
        await expectConfirmationError(.unknownPlan) { _ = try await c.confirm(binding: b) }
        try s.intact()
    }

    @Test("Binding must equal the registered selection, not merely its plan ID")
    func forgedBindingAndUnknownSelection() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let forged = ReviewBinding(planID: r.binding.planID,
            planRevision: r.binding.planRevision, policyRevision: r.binding.policyRevision,
            selectedIDs: ["caller.added.effect"])
        await expectConfirmationError(.staleReview) { _ = try await c.confirm(binding: forged) }
        await expectConfirmationError(.unknownSelectedID) {
            _ = try await c.setSelection(planID: r.binding.planID,
                                         selectedIDs: ["caller.added.effect"])
        }
        let token = try await c.confirm(binding: r.binding)
        let report = await c.execute(token, currentPolicyRevision: r.binding.policyRevision)
        #expect(report.disposition == .noWork)
        #expect(report.results.isEmpty)
        #expect(report.coordinatorMeasurementsAvailable == false)
        try s.intact()
    }

    @Test("Actual quarantined catalog item cannot become selected")
    func productionDenialRemainsMandatory() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let row = try #require(r.plan.reviewItems.first { $0.id == "deep.simulator.erase-all" })
        #expect(!row.review.isSelectable)
        await expectConfirmationError(.unavailableSelection) {
            _ = try await c.setSelection(planID: r.binding.planID, selectedIDs: [row.id])
        }
        let token = try await c.confirm(binding: r.binding)
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .noWork)
        try s.intact()
    }

    @Test("Real no-op token is single-use, and cross-coordinator use cannot consume its owner")
    func tokenReplayAndIssuer() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let owner = s.coordinator(); let other = s.coordinator()
        let r = try await review(owner)
        let token = try await owner.confirm(binding: r.binding)
        #expect(await other.execute(token, currentPolicyRevision: 1).disposition == .invalidToken)
        #expect(await owner.execute(token, currentPolicyRevision: 1).disposition == .noWork)
        #expect(await owner.execute(token, currentPolicyRevision: 1).disposition == .invalidToken)
        try s.intact()
    }

    @Test("Concurrent copies of one genuine no-op token cannot both complete")
    func concurrentTokenCopies() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let dispositions = await withTaskGroup(of: RunDisposition.self) { group in
            for _ in 0..<2 {
                group.addTask { await c.execute(token, currentPolicyRevision: 1).disposition }
            }
            var output: [RunDisposition] = []
            for await disposition in group { output.append(disposition) }
            return output
        }
        #expect(dispositions.filter { $0 == .noWork }.count == 1)
        #expect(dispositions.allSatisfy { [.noWork, .busy, .invalidToken].contains($0) })
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .invalidToken)
        // One-use concurrency only, not positive mutation serialization.
        try s.intact()
    }

    @Test("Selection revision revokes earlier real token and old confirmation binding")
    func changedSelectionRevision() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let old = try await review(c)
        let token = try await c.confirm(binding: old.binding)
        let new = try await c.setSelection(planID: old.binding.planID, selectedIDs: [])
        #expect(new.binding.planRevision == old.binding.planRevision + 1)
        await expectConfirmationError(.staleReview) { _ = try await c.confirm(binding: old.binding) }
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .staleReview)
        let fresh = try await c.confirm(binding: new.binding)
        #expect(await c.execute(fresh, currentPolicyRevision: 1).disposition == .noWork)
    }

    @Test("Actual coordinator policy update invalidates reviews even when old hint is supplied")
    func changedPolicy() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let revision = try await persistPolicy(c, scratch: s)
        #expect(revision == 2)
        await expectConfirmationError(.stalePolicy) { _ = try await c.confirm(binding: r.binding) }
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
        let current = try await review(c)
        let second = try await c.confirm(binding: current.binding)
        #expect(await c.execute(second, currentPolicyRevision: 1).disposition == .stalePolicy)
        #expect(await c.execute(second, currentPolicyRevision: 2).disposition == .invalidToken)
        try s.intact()
    }

    @Test("Separate engines share coordinator registration and token ownership")
    func twoEnginesOneCoordinator() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let a = try await review(c); let b = try await review(c)
        #expect(a.binding.planID != b.binding.planID)
        let ta = try await c.confirm(binding: a.binding)
        let tb = try await c.confirm(binding: b.binding)
        let ra = await c.execute(ta, currentPolicyRevision: 1)
        let rb = await c.execute(tb, currentPolicyRevision: 1)
        #expect(ra.disposition == .noWork && rb.disposition == .noWork)
        // Lifecycle evidence only: no await-spanning mutation happened here.
        try s.intact()
    }

    @Test("Changed and symlink-replaced resource fails real identity probe")
    func changedResourceIdentity() throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let original = try ResourcePreflight.captureFile(at: s.leaf.path)
        #expect(ResourcePreflight.unchanged(original))
        try Data("larger changed payload".utf8).write(to: s.leaf)
        #expect(!ResourcePreflight.unchanged(original))
        let moved = s.home.appendingPathComponent("original")
        try FileManager.default.moveItem(at: s.leaf, to: moved)
        try FileManager.default.createSymbolicLink(at: s.leaf, withDestinationURL: moved)
        #expect(!ResourcePreflight.unchanged(original))
        #expect(throws: (any Error).self) { try ResourcePreflight.captureFile(at: s.leaf.path) }
        #expect(try Data(contentsOf: moved) == Data("larger changed payload".utf8))
    }

    @Test("Stable advisory lock contends across independent store descriptors")
    func instanceLockDescriptors() throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let a = try MutationAdmissionStore(directory: s.journal)
        let b = try MutationAdmissionStore(directory: s.journal)
        defer { a.release(); b.release() }
        #expect(a.acquire() == .ready)
        #expect(b.acquire() == .busy)
        a.release()
        #expect(b.acquire() == .ready)
        // Not claimed as second-process/child-survival verification.
    }

    @Test("Coordinator honors occupied installation lock without consuming the token")
    func coordinatorHonorsInstanceLock() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let holder = try MutationAdmissionStore(directory: s.journal)
        defer { holder.release() }
        #expect(holder.acquire() == .ready)
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .busy)
        holder.release()
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .noWork)
        try s.intact()
    }

    @Test("Unfinished intent survives free lock, new coordinator and policy reset",
          arguments: [SubmissionPhase.prepared, .submitted, .uncertainAndPossiblyRunning])
    func durableUncertainty(phase: SubmissionPhase) async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let writer = try MutationAdmissionStore(directory: s.journal)
        #expect(writer.acquire() == .ready)
        try writer.persistIntentWhileLocked(interruptedIntent(phase: phase))
        writer.release()
        let c = s.coordinator()
        #expect(await c.mutationAdmission() == .uncertainAndPossiblyRunning)
        _ = try await persistPolicy(c, scratch: s)
        #expect(await c.mutationAdmission() == .uncertainAndPossiblyRunning)
        await expectConfirmationError(.recoveryBlocked) { _ = try await review(c) }
        let relaunched = s.coordinator()
        #expect(await relaunched.mutationAdmission() == .uncertainAndPossiblyRunning)
        try s.intact()
    }

    @Test("Uncertainty created after confirmation blocks even a real no-op token")
    func uncertaintyBeforeExecution() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let writer = try MutationAdmissionStore(directory: s.journal)
        #expect(writer.acquire() == .ready)
        try writer.persistIntentWhileLocked(interruptedIntent(phase: .prepared))
        writer.release()
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .recoveryBlocked)
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .invalidToken)
        try s.intact()
    }

    @Test("First bootstrap persists initialized identity and a valid empty envelope")
    func firstInitialization() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        #expect(await c.mutationAdmission() == .ready)
        let markerData = try Data(contentsOf: s.journal.appendingPathComponent("bootstrap.json"))
        let ledgerData = try Data(contentsOf: s.journal.appendingPathComponent("unfinished-effects.json"))
        let marker = try #require(try JSONSerialization.jsonObject(with: markerData) as? [String: Any])
        let ledger = try #require(try JSONSerialization.jsonObject(with: ledgerData) as? [String: Any])
        #expect(marker["schema"] as? Int == 1)
        #expect(marker["state"] as? String == "initialized")
        let storeID = try #require(marker["storeID"] as? String)
        #expect(UUID(uuidString: storeID) != nil)
        #expect(ledger["storeID"] as? String == storeID)
        #expect(ledger["schema"] as? Int == 1)
        #expect((ledger["unfinished"] as? [Any])?.isEmpty == true)
        #expect(await s.coordinator().mutationAdmission() == .ready)
        try s.intact()
    }

    @Test("Deleting an initialized unfinished ledger never bootstraps an empty replacement")
    func missingInitializedLedgerBlocksRelaunch() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let writer = try MutationAdmissionStore(directory: s.journal)
        #expect(writer.acquire() == .ready)
        try writer.persistIntentWhileLocked(interruptedIntent(phase: .submitted))
        writer.release()
        let marker = s.journal.appendingPathComponent("bootstrap.json")
        let markerBytes = try Data(contentsOf: marker)
        let ledger = s.journal.appendingPathComponent("unfinished-effects.json")
        try FileManager.default.removeItem(at: ledger) // exact disposable fixture only
        let relaunched = s.coordinator()
        #expect(await relaunched.mutationAdmission() == .storageUnavailable)
        _ = try await persistPolicy(relaunched, scratch: s)
        #expect(await relaunched.mutationAdmission() == .storageUnavailable)
        await expectConfirmationError(.storageUnavailable) { _ = try await review(relaunched) }
        #expect(!FileManager.default.fileExists(atPath: ledger.path))
        #expect(try Data(contentsOf: marker) == markerBytes)
        try s.intact()
    }

    @Test("Zero-byte ledger and unknown schema remain blocked and byte-preserved",
          arguments: [Data(), Data("{\"schema\":99,\"unfinished\":[]}".utf8)])
    func invalidInitializedLedger(bytes: Data) async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        #expect(await s.coordinator().mutationAdmission() == .ready)
        let ledger = s.journal.appendingPathComponent("unfinished-effects.json")
        try bytes.write(to: ledger)
        let relaunched = s.coordinator()
        #expect(await relaunched.mutationAdmission() == .storageUnavailable)
        await expectConfirmationError(.storageUnavailable) { _ = try await review(relaunched) }
        #expect(try Data(contentsOf: ledger) == bytes)
        try s.intact()
    }

    @Test("Real settings persistence error leaves production app bridge disabled with error")
    @MainActor
    func settingsSaveFailureBlocksBridge() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let blocker = s.home.appendingPathComponent("not-a-directory")
        let blockerBytes = Data("preserve blocking file".utf8)
        try blockerBytes.write(to: blocker)
        let impossibleConfigURL = blocker.appendingPathComponent("config.json")
        #expect(throws: ConfigSaveError.directoryCreationFailed) {
            try ConfigStore.save(TidyConfig(), to: impossibleConfigURL)
        }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let bridge = ExecutionPolicyBridge(coordinator: c, configURL: impossibleConfigURL,
                                           homeDirectory: s.home.path, detectedTools: [])
        var config = TidyConfig()
        config.transcriptAgeThresholdDays = 90
        let update = bridge.submit(config: config)
        #expect(!bridge.isExecutionEnabled)
        #expect(bridge.policyUpdatePending)
        // No await since submit: the coordinator barrier is already invalidated,
        // independently of whether the persistence Task has started.
        #expect(c.policyAdmission() == .updating(revision: 2))
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
        await update.value
        #expect(!bridge.isExecutionEnabled)
        #expect(!bridge.policyUpdatePending)
        #expect(bridge.persistenceError == "Settings could not be saved. Cleanup remains disabled. Fix the settings storage location and save again.")
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .invalidToken)
        await expectConfirmationError(.stalePolicy) { _ = try await review(c) }
        #expect(try Data(contentsOf: blocker) == blockerBytes)
        #expect(!FileManager.default.fileExists(atPath: impossibleConfigURL.path))
        try s.intact()
    }

    @Test("Policy projection copies explicit metadata and restrictions without discovery")
    func purePolicyProjection() throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        var config = TidyConfig()
        config.gitRoots = [s.home.appendingPathComponent("project").path]
        config.keepCookieDomains = ["example.invalid"]
        config.simulatorsApprovedForDeletion = ["inert legacy name"]
        config.appsApprovedForQuit = ["inert legacy app name"]
        config.allowRestartToReclaimSwap = true
        config.staleNodeModulesThresholdDays = 90
        config.transcriptAgeThresholdDays = 120
        let unknown = config.makePolicyEnvironment(homeDirectory: s.home.path, detectedTools: [])
        #expect(unknown.detectedTools.isEmpty)
        #expect(!unknown.hasTool(.git))
        let metadataOnly = config.makePolicyEnvironment(homeDirectory: s.home.path,
                                                        detectedTools: [.git])
        #expect(metadataOnly.detectedTools == [.git])
        #expect(metadataOnly.homeDirectory == s.home.path)
        #expect(metadataOnly.gitRoots == config.gitRoots)
        #expect(metadataOnly.keepCookieDomains == config.keepCookieDomains)
        #expect(metadataOnly.simulatorsApprovedForDeletion == config.simulatorsApprovedForDeletion)
        #expect(metadataOnly.appsApprovedForQuit == config.appsApprovedForQuit)
        #expect(metadataOnly.allowRestartToReclaimSwap)
        #expect(metadataOnly.staleNodeModulesThresholdDays == 90)
        #expect(metadataOnly.transcriptAgeThresholdDays == 120)
        #expect(metadataOnly.protectedRoots == CleanEnvironment.defaultProtectedRoots(homeDirectory: s.home.path))
        // This tests value projection only. A supplied tool ID is not an accepted adapter.
        try s.intact()
    }

    @Test("Two synchronous settings submissions invalidate before queued persistence runs")
    @MainActor
    func settingsSubmissionHasNoDiscoveryPhase() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let url = s.home.appendingPathComponent("config.json")
        let bridge = ExecutionPolicyBridge(coordinator: c, configURL: url,
                                           homeDirectory: s.home.path, detectedTools: [])
        var first = TidyConfig(); first.transcriptAgeThresholdDays = 60
        var second = first; second.transcriptAgeThresholdDays = 90
        let a = bridge.submit(config: first)
        #expect(c.policyAdmission() == .updating(revision: 2))
        let b = bridge.submit(config: second)
        #expect(c.policyAdmission() == .updating(revision: 3))
        #expect(!bridge.isExecutionEnabled && bridge.policyUpdatePending)
        // No await above: production MainActor persistence tasks cannot yet run.
        // The next main-actor statement is reachable without a discovery completion.
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
        await a.value; await b.value
        #expect(ConfigStore.load(from: url) == second)
        #expect(c.policyAdmission() == .ready(revision: 3))
        #expect(bridge.isExecutionEnabled && !bridge.policyUpdatePending)
        #expect(bridge.persistenceError == nil)
        let fresh = try await review(c)
        #expect(fresh.binding.policyRevision == 3)
        let denied = try #require(fresh.plan.reviewItems.first { $0.id == "deep.simulator.erase-all" })
        #expect(!denied.review.isSelectable)
        await expectConfirmationError(.unavailableSelection) {
            _ = try await c.setSelection(planID: fresh.binding.planID, selectedIDs: [denied.id])
        }
        try s.intact()
    }

    @Test("Older persisted update cannot reopen admission while a newer ticket is pending")
    func overlappingPolicyUpdates() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let old = try await review(c)
        let token = try await c.confirm(binding: old.binding)
        let first = try c.beginPolicyUpdate()
        let second = try c.beginPolicyUpdate()
        #expect(c.policyAdmission() == .updating(revision: 3))
        var firstConfig = TidyConfig()
        firstConfig.transcriptAgeThresholdDays = 60
        let configURL = s.home.appendingPathComponent("config.json")
        try ConfigStore.save(firstConfig, to: configURL)
        #expect(try await c.commitPolicyUpdate(first, environment: s.environment) == .superseded)
        // Deterministic interleaving: second persistence/commit has not happened.
        #expect(c.policyAdmission() == .updating(revision: 3))
        await expectConfirmationError(.stalePolicy) { _ = try await review(c) }
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
        var secondConfig = TidyConfig()
        secondConfig.transcriptAgeThresholdDays = 90
        try ConfigStore.save(secondConfig, to: configURL)
        #expect(try await c.commitPolicyUpdate(second, environment: s.environment) == .applied(revision: 3))
        #expect(c.policyAdmission() == .ready(revision: 3))
        #expect(ConfigStore.load(from: configURL) == secondConfig)
        #expect(try await c.commitPolicyUpdate(first, environment: s.environment) == .superseded)
        #expect(c.policyAdmission() == .ready(revision: 3))
        let fresh = try await review(c)
        #expect(fresh.binding.policyRevision == 3)
        let freshToken = try await c.confirm(binding: fresh.binding)
        #expect(await c.execute(freshToken, currentPolicyRevision: 3).disposition == .noWork)
        try s.intact()
    }

    @Test("Corrupt mandatory ledger is not silently reset")
    func corruptLedger() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        #expect(await s.coordinator().mutationAdmission() == .ready)
        let path = s.journal.appendingPathComponent("unfinished-effects.json")
        let corrupt = Data("{\"schema\":1,\"unfinished\":[".utf8)
        try corrupt.write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        let c = s.coordinator()
        #expect(await c.mutationAdmission() == .storageUnavailable)
        await expectConfirmationError(.storageUnavailable) { _ = try await review(c) }
        #expect(try Data(contentsOf: path) == corrupt)
        try s.intact()
    }
}
