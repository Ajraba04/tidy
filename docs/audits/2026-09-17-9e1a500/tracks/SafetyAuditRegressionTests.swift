import Darwin
import Foundation
import Testing
@testable import TidyCore

// AUDIT ARTIFACT ONLY. Copy to an isolated package test target to execute.
// All effects and cleanup are confined to a freshly allocated canonical UUID root.
private struct SafetyAuditScratch {
    let root: URL
    let home: URL
    let journal: URL
    let target: URL
    let witness: URL
    init() throws {
        guard let canonical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw ResourceCaptureError.unavailable
        }
        defer { free(canonical) }
        root = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
            .appendingPathComponent("tidy-safety-audit-\(UUID())", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        journal = root.appendingPathComponent("journal", isDirectory: true)
        target = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        witness = root.appendingPathComponent("outside-witness")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try Data("outside remains".utf8).write(to: witness)
        try Data("reviewed".utf8).write(to: target.appendingPathComponent("original"))
    }
    func coordinator(protectedRoots: [String] = []) -> ExecutionCoordinator {
        ExecutionCoordinator(environment: CleanEnvironment(homeDirectory: home.path,
            detectedTools: [.xcode], protectedRoots: protectedRoots), journalDirectory: journal)
    }
    func confirm(_ coordinator: ExecutionCoordinator) async throws -> (ConfirmedPlan, UInt64) {
        let review = try await coordinator.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                                        tier: .safe, selectDefaults: false)
        let selected = try await coordinator.setSelection(planID: review.binding.planID,
                                                          selectedIDs: ["safe.xcode.derived-data"])
        return (try await coordinator.confirm(binding: selected.binding), review.binding.policyRevision)
    }
    func verifyWitness() throws {
        #expect(try Data(contentsOf: witness) == Data("outside remains".utf8))
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Safety audit regression", .serialized)
struct SafetyAuditRegressionTests {
    @Test("A descendant created after confirmation cannot gain delete authority")
    func postConfirmationChildSurvives() async throws {
        let s = try SafetyAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let (token, revision) = try await s.confirm(c)
        let late = s.target.appendingPathComponent("not-reviewed")
        try Data("new content".utf8).write(to: late)
        _ = await c.execute(token, currentPolicyRevision: revision)
        #expect(FileManager.default.fileExists(atPath: late.path))
        try s.verifyWitness()
    }

    @Test("A reviewed descendant that grows after confirmation is withheld")
    func postConfirmationGrowthSurvives() async throws {
        let s = try SafetyAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let (token, revision) = try await s.confirm(c)
        let leaf = s.target.appendingPathComponent("original")
        try Data(repeating: 0x41, count: 32768).write(to: leaf)
        _ = await c.execute(token, currentPolicyRevision: revision)
        #expect(FileManager.default.fileExists(atPath: leaf.path))
        try s.verifyWitness()
    }

    @Test("A root replaced after confirmation cannot inherit the old root authority")
    func replacedRootSurvives() async throws {
        let s = try SafetyAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let (token, revision) = try await s.confirm(c)
        let moved = s.root.appendingPathComponent("reviewed-old-root")
        try FileManager.default.moveItem(at: s.target, to: moved)
        try FileManager.default.createDirectory(at: s.target, withIntermediateDirectories: false)
        let leaf = s.target.appendingPathComponent("replacement-witness")
        try Data("replacement".utf8).write(to: leaf)
        _ = await c.execute(token, currentPolicyRevision: revision)
        #expect(FileManager.default.fileExists(atPath: leaf.path))
        #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("original").path))
        try s.verifyWitness()
    }

    @Test("A protected descendant remains protected when its parent is selected")
    func protectedDescendantSurvives() async throws {
        let s = try SafetyAuditScratch(); defer { s.cleanup() }
        let protected = s.target.appendingPathComponent("protected-subtree", isDirectory: true)
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: false)
        let leaf = protected.appendingPathComponent("keep")
        try Data("protected".utf8).write(to: leaf)
        let c = s.coordinator(protectedRoots: [protected.path])
        let (token, revision) = try await s.confirm(c)
        _ = await c.execute(token, currentPolicyRevision: revision)
        #expect(FileManager.default.fileExists(atPath: leaf.path))
        try s.verifyWitness()
    }

    @Test("No owner mapping or quiescence evidence means no eligible mutation")
    func missingOwnershipEvidenceWithholdsEffect() async throws {
        let s = try SafetyAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        // Only a tool-presence bit and path exist; no producer/owner/lease proof was supplied.
        let (token, revision) = try await s.confirm(c)
        _ = await c.execute(token, currentPolicyRevision: revision)
        #expect(FileManager.default.fileExists(atPath: s.target.appendingPathComponent("original").path))
        try s.verifyWitness()
    }

    @Test("A real successful effect has durable started, terminal and finished events")
    func realEffectIsDurablyRecorded() async throws {
        let s = try SafetyAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let (token, revision) = try await s.confirm(c)
        let report = await c.execute(token, currentPolicyRevision: revision)
        #expect(report.results.first?.succeeded == true)
        let names = try FileManager.default.contentsOfDirectory(atPath: s.journal.path)
        let name = try #require(names.first { $0.hasPrefix("run-") && $0.hasSuffix(".journal") })
        let runID = try #require(UUID(uuidString: String(name.dropFirst(4).dropLast(8))))
        let store = try MutationAdmissionStore(directory: s.journal)
        #expect(store.acquire() == .ready)
        defer { store.release() }
        let journal = try RunJournal(store: store, storage: try DurableJournalStorage(directory: s.journal))
        let phases = try journal.events(runID: runID).map(\.phase)
        #expect(phases.contains(.started))
        #expect(phases.contains(.itemTerminal))
        #expect(phases.contains(.finished))
        try s.verifyWitness()
    }

    @Test("Successful completed runs release their bounded active journal slots")
    func nineSequentialRunsDoNotExhaustActiveSlots() async throws {
        let s = try SafetyAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        for index in 1...9 {
            try Data("run \(index)".utf8).write(to: s.target.appendingPathComponent("original"))
            let (token, revision) = try await s.confirm(c)
            let report = await c.execute(token, currentPolicyRevision: revision)
            #expect(report.disposition == .completed, "Completed run \(index) must release active storage")
            #expect(report.results.first?.succeeded == true)
        }
        try s.verifyWitness()
    }
}
