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

/// Internal mechanics use disposable fixtures; this does not enable the production capability.
@Suite("Derived data guarded mechanics and production quarantine")
struct DerivedDataExecutionTests {
    private func runFixture(_ s: DerivedDataScratch) throws -> DerivedDataEffectAdapter.Effect {
        let store = try MutationAdmissionStore(directory: s.journal)
        try #require(store.acquire() == .ready)
        defer { store.release() }
        let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: s.journal))
        let run = UUID(), operation = UUID()
        try journal.append(JournalEvent(runID: run, sequence: 1, phase: .planned,
            operationID: nil, status: nil, reason: nil))
        try journal.append(JournalEvent(runID: run, sequence: 2, phase: .confirmed,
            operationID: nil, status: nil, reason: nil))
        let tree = try ReviewedTree.capture(anchor: DirectoryAnchor.open(path: s.derivedData.path), excluding: [])
        let effect = try DerivedDataEffectAdapter.execute(itemID: "safe.xcode.derived-data", action: .deleteContents,
            target: TargetPath(path: s.derivedData.path), reviewedTree: tree, operationID: operation) {
                try journal.persistIntent(PendingEffectIntent(runID: run, operationID: operation,
                    adapterID: "safe.xcode.derived-data", bootID: UUID(), executablePath: "",
                    executableDevice: 0, executableInode: 0, childPID: nil, childStartSeconds: nil,
                    childStartMicroseconds: nil, phase: .prepared))
                try journal.append(JournalEvent(runID: run, sequence: 3, phase: .started,
                    operationID: operation, status: nil, reason: nil))
            }
        try journal.completeFilesystemEffect(effect, runID: run, sequence: 4)
        try journal.finish(runID: run)
        #expect(try journal.events(runID: run).map(\.phase) == [.planned, .confirmed, .started, .itemTerminal, .finished])
        #expect(store.readAdmissionWhileLocked() == .ready)
        return effect
    }

    @Test("Synchronous fixture effects close their journal and survive more than eight runs")
    func repeatedRunsRemainAvailable() throws {
        let s = try DerivedDataScratch(); defer { s.cleanup() }
        for _ in 0..<10 {
            let (artifact, nested) = try s.populateFixtureProject()
            let effect = try runFixture(s)
            #expect(EffectAccounting.aggregateStatus(effect.outcomes) == .succeeded)
            #expect(!FileManager.default.fileExists(atPath: artifact.path))
            #expect(!FileManager.default.fileExists(atPath: nested.path))
            try s.sentinelIntact()
        }
    }

    @Test("Changed root or expanded scope cannot inherit the original manifest")
    func staleManifestRefusesEffect() throws {
        let s = try DerivedDataScratch(); defer { s.cleanup() }
        _ = try s.populateFixtureProject()
        let tree = try ReviewedTree.capture(anchor: DirectoryAnchor.open(path: s.derivedData.path), excluding: [])
        let original = s.derivedData.appendingPathExtension("old")
        try FileManager.default.moveItem(at: s.derivedData, to: original)
        try FileManager.default.createDirectory(at: s.derivedData, withIntermediateDirectories: true)
        let replacement = s.derivedData.appendingPathComponent("must-survive")
        try Data("new".utf8).write(to: replacement)
        #expect(throws: (any Error).self) {
            _ = try DerivedDataEffectAdapter.execute(itemID: "safe.xcode.derived-data", action: .deleteContents,
                target: TargetPath(path: s.derivedData.path), reviewedTree: tree, operationID: UUID()) {
                    Issue.record("A stale manifest must fail before recording any effect intent")
                }
        }
        #expect(try Data(contentsOf: replacement) == Data("new".utf8))
        try s.sentinelIntact()
    }

    @Test("Production discovery never establishes producer quiescence or cleanup authority")
    func productionRemainsQuarantined() async throws {
        let s = try DerivedDataScratch(); defer { s.cleanup() }
        let (artifact, _) = try s.populateFixtureProject()
        let c = s.coordinator()
        let review = try await c.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                               tier: .safe, selectDefaults: true)
        #expect(review.selection.selectedIDs.isEmpty)
        for item in CleanCatalog.allItems {
            #expect(CapabilityRegistry.denialReason(for: item.action, itemID: item.id) != nil)
        }
        let token = try await c.confirm(binding: review.binding)
        #expect(await c.execute(token, currentPolicyRevision: review.binding.policyRevision).disposition == .noWork)
        #expect(FileManager.default.fileExists(atPath: artifact.path))
    }

    @Test("Unknown process intents remain blocked after launch reconciliation")
    func priorUncertaintyBlocksRealExecution() async throws {
        let s = try DerivedDataScratch(); defer { s.cleanup() }
        let store = try MutationAdmissionStore(directory: s.journal)
        #expect(store.acquire() == .ready)
        try store.persistIntentWhileLocked(interruptedDerivedDataIntent())
        store.release()
        let admission = await s.coordinator().mutationAdmission()
        #expect(admission == .storageUnavailable || admission == .uncertainAndPossiblyRunning)
    }
}
