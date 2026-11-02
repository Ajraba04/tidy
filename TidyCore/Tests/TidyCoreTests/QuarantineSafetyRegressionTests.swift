import Darwin
import Foundation
import Testing
@testable import TidyCore

/// R01 adaptations of the historical audit probes. The original audit artifact
/// remains under `docs/audits`; these tests assert the containment behavior that
/// applies while all mutation capabilities are quarantined.
private struct QuarantineAuditScratch {
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
            .appendingPathComponent("tidy-r01-audit-\(UUID())", isDirectory: true)
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

    func assertSelectionDenied(_ coordinator: ExecutionCoordinator,
        expectedReason: String = CapabilityRegistry.quarantineReason) async throws -> RegisteredReview {
        let review = try await coordinator.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                                         tier: .safe, selectDefaults: false)
        let row = try #require(review.plan.reviewItems.first { $0.id == "safe.xcode.derived-data" })
        #expect(!row.review.isSelectable)
        #expect(row.review.reason == expectedReason)
        await #expect(throws: ConfirmationError.unavailableSelection) {
            _ = try await coordinator.setSelection(planID: review.binding.planID,
                                                   selectedIDs: [row.id])
        }
        return review
    }

    func executeEmptyConfirmation(_ review: RegisteredReview,
                                  coordinator: ExecutionCoordinator) async throws {
        let token = try await coordinator.confirm(binding: review.binding)
        let report = await coordinator.execute(token,
            currentPolicyRevision: review.binding.policyRevision)
        #expect(report.disposition == .noWork)
        #expect(report.results.isEmpty)
    }

    func verifyWitness() throws {
        #expect(try Data(contentsOf: witness) == Data("outside remains".utf8))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@Suite("R01 quarantine safety regressions", .serialized)
struct QuarantineSafetyRegressionTests {
    @Test("Public coordinator denies every catalog mutation and forged identifier")
    func coordinatorDeniesCatalogAndForgedSelections() async throws {
        let s = try QuarantineAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let review = try await c.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                               tier: .deep, selectDefaults: false)
        #expect(review.plan.reviewItems.count == CleanCatalog.allItems.count)
        for row in review.plan.reviewItems {
            guard case .unavailable = row.action else {
                #expect(!row.review.isSelectable, "\(row.id) unexpectedly became selectable")
                await #expect(throws: ConfirmationError.unavailableSelection) {
                    _ = try await c.setSelection(planID: review.binding.planID,
                                                 selectedIDs: [row.id])
                }
                continue
            }
        }
        await #expect(throws: ConfirmationError.unknownSelectedID) {
            _ = try await c.setSelection(planID: review.binding.planID,
                                         selectedIDs: ["forged.catalog.id"])
        }
        let forged = ReviewBinding(planID: UUID(), planRevision: 1,
            policyRevision: review.binding.policyRevision,
            selectedIDs: ["safe.xcode.derived-data"])
        await #expect(throws: ConfirmationError.unknownPlan) {
            _ = try await c.confirm(binding: forged)
        }
        #expect(await c.mutationAdmission() == .ready)
        try s.verifyWitness()
    }

    @Test("A descendant created after denied selection survives an empty confirmation")
    func postConfirmationChildSurvives() async throws {
        let s = try QuarantineAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let review = try await s.assertSelectionDenied(c)
        let late = s.target.appendingPathComponent("not-reviewed")
        try Data("new content".utf8).write(to: late)
        try await s.executeEmptyConfirmation(review, coordinator: c)
        #expect(try Data(contentsOf: late) == Data("new content".utf8))
        try s.verifyWitness()
    }

    @Test("A descendant that grows after denied selection survives")
    func postConfirmationGrowthSurvives() async throws {
        let s = try QuarantineAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let review = try await s.assertSelectionDenied(c)
        let leaf = s.target.appendingPathComponent("original")
        let grown = Data(repeating: 0x41, count: 32_768)
        try grown.write(to: leaf)
        try await s.executeEmptyConfirmation(review, coordinator: c)
        #expect(try Data(contentsOf: leaf) == grown)
        try s.verifyWitness()
    }

    @Test("A replacement root cannot gain authority from a denied review")
    func replacedRootSurvives() async throws {
        let s = try QuarantineAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let review = try await s.assertSelectionDenied(c)
        let moved = s.root.appendingPathComponent("reviewed-old-root")
        try FileManager.default.moveItem(at: s.target, to: moved)
        try FileManager.default.createDirectory(at: s.target, withIntermediateDirectories: false)
        let replacement = s.target.appendingPathComponent("replacement-witness")
        try Data("replacement".utf8).write(to: replacement)
        try await s.executeEmptyConfirmation(review, coordinator: c)
        #expect(try Data(contentsOf: replacement) == Data("replacement".utf8))
        #expect(try Data(contentsOf: moved.appendingPathComponent("original")) == Data("reviewed".utf8))
        try s.verifyWitness()
    }

    @Test("A protected descendant survives while its parent row is quarantined")
    func protectedDescendantSurvives() async throws {
        let s = try QuarantineAuditScratch(); defer { s.cleanup() }
        let protected = s.target.appendingPathComponent("protected-subtree", isDirectory: true)
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: false)
        let leaf = protected.appendingPathComponent("keep")
        try Data("protected".utf8).write(to: leaf)
        let c = s.coordinator(protectedRoots: [protected.path])
        let review = try await s.assertSelectionDenied(c,
            expectedReason: "One or more targets failed path protection checks.")
        #expect(await c.reviewedFilesystemIdentities(planID: review.binding.planID,
            itemID: "safe.xcode.derived-data").isEmpty)
        try await s.executeEmptyConfirmation(review, coordinator: c)
        #expect(try Data(contentsOf: leaf) == Data("protected".utf8))
        try s.verifyWitness()
    }

    @Test("Missing ownership evidence leaves the quarantined payload untouched")
    func missingOwnershipEvidenceWithholdsEffect() async throws {
        let s = try QuarantineAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let review = try await s.assertSelectionDenied(c)
        try await s.executeEmptyConfirmation(review, coordinator: c)
        #expect(try Data(contentsOf: s.target.appendingPathComponent("original"))
                == Data("reviewed".utf8))
        try s.verifyWitness()
    }

    @Test("Denied selection writes no run journal or effect intent")
    func deniedSelectionHasNoEffectJournal() async throws {
        let s = try QuarantineAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        _ = try await s.assertSelectionDenied(c)
        let names = try FileManager.default.contentsOfDirectory(atPath: s.journal.path)
        #expect(!names.contains { $0.hasPrefix("run-") && $0.hasSuffix(".journal") })
        let store = try MutationAdmissionStore(directory: s.journal)
        #expect(store.acquire() == .ready)
        defer { store.release() }
        #expect(store.readAdmissionWhileLocked() == .ready)
        try s.verifyWitness()
    }

    @Test("Nine denied attempts do not consume active journal slots")
    func nineSequentialAttemptsRemainDenied() async throws {
        let s = try QuarantineAuditScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        for index in 1...9 {
            let bytes = Data("run \(index)".utf8)
            try bytes.write(to: s.target.appendingPathComponent("original"))
            _ = try await s.assertSelectionDenied(c)
            #expect(try Data(contentsOf: s.target.appendingPathComponent("original")) == bytes)
            #expect(await c.mutationAdmission() == .ready)
        }
        try s.verifyWitness()
    }
}
