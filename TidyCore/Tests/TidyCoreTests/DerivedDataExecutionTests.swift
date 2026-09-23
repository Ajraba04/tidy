import Foundation
import Darwin
import Testing
@testable import TidyCore

/// Quarantine coverage for the retained DerivedData inventory row. Every
/// fixture lives under a generated UUID scratch directory; none of these
/// tests touch the real user home.
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

@Suite("Derived data quarantine")
struct DerivedDataExecutionTests {
    @Test("DerivedData remains visible with an explicit quarantine reason and cannot be selected")
    func inventoryVisibleButSelectionDenied() async throws {
        let s = try DerivedDataScratch(); defer { s.cleanup() }
        let (artifact, nested) = try s.populateFixtureProject()
        let c = s.coordinator()
        let review = try await c.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                               tier: .safe, selectDefaults: false)
        let row = try #require(review.plan.reviewItems.first { $0.id == "safe.xcode.derived-data" })
        #expect(!row.review.isSelectable)
        #expect(row.review.reason == CapabilityRegistry.quarantineReason)
        await #expect(throws: ConfirmationError.unavailableSelection) {
            _ = try await c.setSelection(planID: review.binding.planID, selectedIDs: [row.id])
        }
        #expect(FileManager.default.fileExists(atPath: artifact.path))
        #expect(FileManager.default.fileExists(atPath: nested.path))
        try s.sentinelIntact()
        let journalNames = try FileManager.default.contentsOfDirectory(atPath: s.journal.path)
        #expect(!journalNames.contains { $0.hasPrefix("run-") && $0.hasSuffix(".journal") })
    }

    @Test("Repeated selection attempts remain denied without changing admission or fixture bytes")
    func repeatedAttemptsRemainDenied() async throws {
        let s = try DerivedDataScratch(); defer { s.cleanup() }
        let (artifact, _) = try s.populateFixtureProject()
        let original = try Data(contentsOf: artifact)
        let c = s.coordinator()
        for _ in 0..<2 {
            let review = try await c.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                                   tier: .safe, selectDefaults: false)
            let row = try #require(review.plan.reviewItems.first { $0.id == "safe.xcode.derived-data" })
            await #expect(throws: ConfirmationError.unavailableSelection) {
                _ = try await c.setSelection(planID: review.binding.planID, selectedIDs: [row.id])
            }
        }
        #expect(await c.mutationAdmission() == .ready)
        #expect(try Data(contentsOf: artifact) == original)
        try s.sentinelIntact()
    }

    @Test("Every catalog item including DerivedData stays denied while quarantine is active")
    func denialRemainsMandatoryForEveryCatalogItem() throws {
        for item in CleanCatalog.allItems {
            #expect(CapabilityRegistry.denialReason(for: item.action, itemID: item.id)
                    == CapabilityRegistry.quarantineReason,
                    "\(item.id) must remain denied")
        }
        #expect(CapabilityRegistry.denialReason(for: .deletePath, itemID: "safe.xcode.derived-data") != nil)
        #expect(CapabilityRegistry.denialReason(for: .unavailable(reason: "x"), itemID: "safe.xcode.derived-data") != nil)
    }

}
