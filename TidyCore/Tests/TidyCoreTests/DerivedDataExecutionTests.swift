import Foundation
import Darwin
import Testing
@testable import TidyCore

/// End-to-end fixture coverage for the first accepted production effect:
/// `safe.xcode.derived-data` / `.deleteContents`, dispatched through the
/// real sealed path (`ExecutionCoordinator.execute` ->
/// `DerivedDataEffectAdapter` -> `GuardedFileDeleter`). Every fixture lives
/// under a generated UUID scratch directory; none of these tests touch the
/// real user home.
private struct DerivedDataScratch {
    let root: URL
    let home: URL
    let journal: URL
    let derivedData: URL
    let outsideSentinel: URL
    init() throws {
        guard let canonical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw ResourceCaptureError.unavailable
        }
        defer { free(canonical) }
        root = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
            .appendingPathComponent("T0X-derived-data-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        journal = root.appendingPathComponent("journal", isDirectory: true)
        derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        outsideSentinel = home.appendingPathComponent("Library/Developer/Xcode/sentinel")
        try FileManager.default.createDirectory(at: derivedData, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Data("keep me".utf8).write(to: outsideSentinel)
    }
    func populateFixtureProject() throws -> (buildArtifact: URL, nestedFile: URL) {
        let project = derivedData.appendingPathComponent("MyApp-abcdef", isDirectory: true)
        let build = project.appendingPathComponent("Build/Products/Debug", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        let artifact = build.appendingPathComponent("MyApp.app.o")
        try Data(repeating: 0x42, count: 32_768).write(to: artifact)
        let nested = project.appendingPathComponent("Logs/note.txt")
        try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("build log".utf8).write(to: nested)
        return (artifact, nested)
    }
    var environment: CleanEnvironment {
        CleanEnvironment(homeDirectory: home.path, detectedTools: [.xcode], protectedRoots: [])
    }
    func coordinator() -> ExecutionCoordinator {
        ExecutionCoordinator(environment: environment, journalDirectory: journal)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func sentinelIntact() throws {
        #expect(try Data(contentsOf: outsideSentinel) == Data("keep me".utf8))
    }
}

private func interruptedDerivedDataIntent(runID: UUID = UUID()) -> PendingEffectIntent {
    PendingEffectIntent(
        runID: runID, operationID: UUID(), adapterID: "legacy.unreconciled",
        bootID: UUID(), executablePath: "/unavailable/previous-run",
        executableDevice: 99, executableInode: 123,
        childPID: nil, childStartSeconds: nil, childStartMicroseconds: nil,
        phase: .submitted)
}

@Suite("Derived data execution")
struct DerivedDataExecutionTests {
    @Test("Confirmed execution really deletes DerivedData contents, keeps the directory, and reports real free-space deltas")
    func realDeletionSucceeds() async throws {
        let s = try DerivedDataScratch(); defer { s.cleanup() }
        let (artifact, nested) = try s.populateFixtureProject()
        let c = s.coordinator()
        let review = try await c.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                               tier: .safe, selectDefaults: false)
        let row = try #require(review.plan.reviewItems.first { $0.id == "safe.xcode.derived-data" })
        #expect(row.review.isSelectable, "denialReason must return nil for the accepted item/action")
        let selected = try await c.setSelection(planID: review.binding.planID, selectedIDs: [row.id])
        let token = try await c.confirm(binding: selected.binding)

        let report = await c.execute(token, currentPolicyRevision: review.binding.policyRevision)

        #expect(report.disposition == .completed)
        #expect(report.coordinatorMeasurementsAvailable == true)
        #expect(report.freeSpaceBeforeBytes >= 0 && report.freeSpaceAfterBytes >= 0)
        let result = try #require(report.results.first { $0.id == "safe.xcode.derived-data" })
        #expect(result.succeeded)
        #expect(result.effectStatus == .succeeded)
        #expect(result.freedBytes > 0)

        #expect(!FileManager.default.fileExists(atPath: artifact.path))
        #expect(!FileManager.default.fileExists(atPath: nested.path))
        var isDirectory: ObjCBool = false
        let stillThere = FileManager.default.fileExists(atPath: s.derivedData.path, isDirectory: &isDirectory)
        #expect(stillThere && isDirectory.boolValue, "deleteContents keeps the directory itself")
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.derivedData.path).isEmpty)
        try s.sentinelIntact()

        // Diagnostic journal recorded the confirmed intent to run. Per-operation
        // started/itemTerminal is deliberately not recorded here: RunJournal's
        // `.started` transition requires a durably persisted `PendingEffectIntent`,
        // and no accepted API removes one afterward, so recording it would
        // permanently block every future mutation after this one real run.
        let names = try FileManager.default.contentsOfDirectory(atPath: s.journal.path)
        let journalName = try #require(names.first { $0.hasPrefix("run-") && $0.hasSuffix(".journal") })
        let runID = try #require(UUID(uuidString: String(journalName.dropFirst(4).dropLast(8))))
        let store = try MutationAdmissionStore(directory: s.journal)
        #expect(store.acquire() == .ready)
        defer { store.release() }
        let journal = try RunJournal(store: store, storage: try DurableJournalStorage(directory: s.journal))
        let phases = try journal.events(runID: runID).map(\.phase)
        #expect(phases == [.planned, .confirmed])

        // The tool must stay usable: no unfinished intent was left behind.
        #expect(store.readAdmissionWhileLocked() == .ready)
    }

    @Test("A second real run after a successful one still works: the capability is not one-shot")
    func repeatedRunsRemainAvailable() async throws {
        let s = try DerivedDataScratch(); defer { s.cleanup() }
        _ = try s.populateFixtureProject()
        let c = s.coordinator()
        func runOnce() async throws -> RunReport {
            let review = try await c.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                                   tier: .safe, selectDefaults: false)
            let row = try #require(review.plan.reviewItems.first { $0.id == "safe.xcode.derived-data" })
            let selected = try await c.setSelection(planID: review.binding.planID, selectedIDs: [row.id])
            let token = try await c.confirm(binding: selected.binding)
            return await c.execute(token, currentPolicyRevision: review.binding.policyRevision)
        }
        let first = try await runOnce()
        #expect(first.disposition == .completed)
        _ = try s.populateFixtureProject()
        let second = try await runOnce()
        #expect(second.disposition == .completed)
        #expect(second.results.first?.effectStatus == .succeeded)
        try s.sentinelIntact()
    }

    @Test("Every catalog item except the one accepted pair stays denied")
    func denialRemainsMandatoryForEverythingElse() throws {
        for item in CleanCatalog.allItems {
            if item.id == "safe.xcode.derived-data" {
                if case .deleteContents = item.action {
                    #expect(CapabilityRegistry.denialReason(for: item.action, itemID: item.id) == nil)
                }
            } else {
                #expect(CapabilityRegistry.denialReason(for: item.action, itemID: item.id) != nil,
                       "\(item.id) must remain denied")
            }
        }
        #expect(CapabilityRegistry.denialReason(for: .deletePath, itemID: "safe.xcode.derived-data") != nil)
        #expect(CapabilityRegistry.denialReason(for: .unavailable(reason: "x"), itemID: "safe.xcode.derived-data") != nil)
    }

    @Test("A prior unresolved intent blocks the accepted item too, without touching its files")
    func priorUncertaintyBlocksRealExecution() async throws {
        let s = try DerivedDataScratch(); defer { s.cleanup() }
        let (artifact, _) = try s.populateFixtureProject()
        let c = s.coordinator()
        let review = try await c.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                               tier: .safe, selectDefaults: false)
        let row = try #require(review.plan.reviewItems.first { $0.id == "safe.xcode.derived-data" })
        let selected = try await c.setSelection(planID: review.binding.planID, selectedIDs: [row.id])
        let token = try await c.confirm(binding: selected.binding)

        // Simulate a crash: some earlier effect left an unresolved intent in
        // the same mandatory ledger this coordinator borrows.
        let writer = try MutationAdmissionStore(directory: s.journal)
        #expect(writer.acquire() == .ready)
        try writer.persistIntentWhileLocked(interruptedDerivedDataIntent())
        writer.release()

        let report = await c.execute(token, currentPolicyRevision: review.binding.policyRevision)
        #expect(report.disposition == .recoveryBlocked)
        #expect(report.results.isEmpty)
        #expect(FileManager.default.fileExists(atPath: artifact.path), "no deletion may occur while uncertain")

        // The same relaunch-shaped check the rest of the app relies on.
        let relaunched = s.coordinator()
        #expect(await relaunched.mutationAdmission() == .uncertainAndPossiblyRunning)
        #expect(RecoveryDecision.forUnfinishedEffect(quiescenceProven: false) == .blockMutations)
        try s.sentinelIntact()
    }
}
