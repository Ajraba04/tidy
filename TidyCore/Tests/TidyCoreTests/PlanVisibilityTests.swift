import Foundation
import Testing
@testable import TidyCore

@Suite("Plan visibility")
struct PlanVisibilityTests {
    @Test("Actual targetless tool, zero-byte memory, missing path and tombstone remain visible")
    func productionRowsRemainVisible() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("T01-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ids: Set<String> = ["safe.tool.npm-cache-clean", "deep.memory.purge-inactive", "safe.cache.swiftpm-cache", "deep.simulator.erase-all"]
        let items = CleanCatalog.allItems.filter { ids.contains($0.id) }
        #expect(items.count == 4)
        let env = CleanEnvironment(homeDirectory: root.path, detectedTools: [.npm], protectedRoots: [])
        let plan = await CleanEngine(sizeScanner: SizeScanner()).makePlan(items: items, tier: .deep, environment: env)
        #expect(Set(plan.reviewItems.map(\.id)) == ids)
        let tool = try #require(plan.reviewItems.first { $0.id == "safe.tool.npm-cache-clean" })
        #expect(tool.targets.isEmpty)
        #expect(tool.review.status == .unavailable)
        #expect(!tool.review.reason.isEmpty)
        let memory = try #require(plan.reviewItems.first { $0.id == "deep.memory.purge-inactive" })
        #expect(memory.estimatedBytes == 0)
        #expect(memory.review.status == .unavailable)
        #expect(memory.review.requiresPerRunOptIn)
        let missing = try #require(plan.reviewItems.first { $0.id == "safe.cache.swiftpm-cache" })
        #expect(missing.review.status == .noWork)
        #expect(missing.review.reason == "No matching path exists.")
        let erased = try #require(plan.reviewItems.first { $0.id == "deep.simulator.erase-all" })
        #expect(erased.review.status == .unavailable)
        if case .unavailable = erased.action {} else { Issue.record("erase-all still has an executable action") }
        for defaults in [false, true] {
            var selection = PlanSelection(plan: plan, selectDefaults: defaults)
            selection.applyPresetIDs(ids.union(["unknown.preset.id"]))
            for id in ids { selection.setSelected(true, id: id) }
            #expect(selection.reviewItems.map(\.id) == plan.reviewItems.map(\.id))
            #expect(selection.selectedIDs.isEmpty)
            #expect(selection.selectedItems.isEmpty)
            #expect(selection.selectedCount == 0)
            #expect(selection.selectedEstimatedBytes == 0)
            #expect(selection.selectedPlan.plannedItems.isEmpty)
            #expect(selection.selectedPlan.generatedAt == plan.generatedAt)
        }
    }

    @Test("Missing required tool is an unavailable row, not silently hidden")
    func missingToolIsVisible() async throws {
        let item = try #require(CleanCatalog.allItems.first { $0.id == "safe.tool.npm-cache-clean" })
        let plan = await CleanEngine(sizeScanner: SizeScanner()).makePlan(items: [item], tier: .safe,
            environment: CleanEnvironment(homeDirectory: "/fixture-not-used", protectedRoots: []))
        #expect(plan.reviewItems.count == 1)
        #expect(plan.reviewItems.first?.review.status == .unavailable)
        #expect(plan.reviewItems.first?.review.reason == "Required toolchain is not available.")
    }

    @Test("Erase-all tombstone retains its permanent reason without Xcode")
    func eraseAllTombstoneIsIndependentOfToolDiscovery() async throws {
        let item = try #require(CleanCatalog.allItems.first { $0.id == "deep.simulator.erase-all" })
        #expect(item.requires == nil)
        let plan = await CleanEngine(sizeScanner: SizeScanner()).makePlan(items: [item], tier: .deep,
            environment: CleanEnvironment(homeDirectory: "/fixture-not-used", protectedRoots: []))
        #expect(plan.reviewItems.first?.review.reason == "Broad simulator erase-all is unavailable. Review individual devices when supported.")
    }

    @Test("Protected targets show blocked with reason rather than vanish")
    func protectedTargetIsBlocked() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("T01-protected-\(UUID().uuidString)")
        let protected = root.appendingPathComponent("protected")
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = CleanItem(id: "untrusted.path", title: "Protected", tier: .safe,
            declaredRoot: { _ in root.path }, locate: { _ in [TargetPath(path: protected.path)] }, action: .deletePath)
        let env = CleanEnvironment(homeDirectory: root.path, protectedRoots: [protected.path])
        let plan = await CleanEngine(sizeScanner: SizeScanner()).makePlan(items: [item], tier: .safe, environment: env)
        #expect(plan.reviewItems.count == 1)
        #expect(plan.reviewItems.first?.review.status == .blocked)
        #expect(plan.reviewItems.first?.review.reason == "One or more targets failed path protection checks.")
        #expect(FileManager.default.fileExists(atPath: protected.path))
    }

    @Test("Caller-supplied available descriptors and duplicate IDs cannot grant selection")
    func forgedAvailabilityCannotGrantSelection() {
        let row = PlannedItem(id: "safe.tool.npm-cache-clean", title: "Forged", tier: .safe,
            dangerNote: "Risk", costNote: "Cost", targets: [], estimatedBytes: 500,
            action: .runTool(ToolCommand(.npm, ["cache", "clean", "--force"])),
            review: ActionDescriptor(id: "safe.tool.npm-cache-clean", status: .available,
                                     reason: "Forged assertion", requiresPerRunOptIn: false))
        for rows in [[row], [row, row]] {
            var selection = PlanSelection(plan: CleanPlan(tier: .safe, plannedItems: rows), selectDefaults: true)
            selection.setSelected(true, id: row.id)
            selection.applyPresetIDs([row.id])
            #expect(selection.selectedCount == 0)
            #expect(selection.selectedPlan.plannedItems.isEmpty)
            #expect(selection.reviewItems.count == rows.count)
        }
    }
}
