import Foundation
import Testing
@testable import TidyCore

@Suite("CleanCatalog")
struct CleanCatalogTests {
    @Test("every catalog item has a unique id")
    func everyItemHasUniqueID() {
        let ids = CleanCatalog.allItems.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test("every catalog item has a non-empty title")
    func everyItemHasNonEmptyTitle() {
        for item in CleanCatalog.allItems {
            #expect(!item.title.isEmpty)
        }
    }

    @Test("locate and declaredRoot never crash for any item on a scratch home")
    func locateAndDeclaredRootNeverCrash() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let environment = CleanEnvironment(homeDirectory: scratch.path, protectedRoots: [])

        for item in CleanCatalog.allItems {
            _ = item.locate(environment)
            _ = item.declaredRoot(environment)
        }
    }

    @Test("every located filesystem target falls under that item's declared root")
    func everyLocatedFilesystemTargetFallsUnderDeclaredRoot() throws {
        // Run against the real home directory so fixed-path items that
        // actually exist here are exercised, not just the empty case.
        // Approve nothing for simulator deletion (the default) so that
        // code path stays inert here too.
        let environment = CleanEnvironment(
            homeDirectory: NSHomeDirectory(),
            detectedTools: Set(ToolchainID.allCases),
            protectedRoots: []
        )

        for item in CleanCatalog.allItems {
            guard let declaredRoot = item.declaredRoot(environment) else { continue }
            let canonicalRoot = PathGuard.canonicalize(declaredRoot)
            for target in item.locate(environment) where target.isFilesystemPath {
                let canonicalTarget = PathGuard.canonicalize(target.path)
                #expect(
                    PathGuard.isEqualOrDescendant(canonicalTarget, of: canonicalRoot),
                    "\(item.id): \(target.path) is not under its declared root \(declaredRoot)"
                )
            }
        }
    }

    @Test("safe tier contains no custom actions")
    func safeTierHasNoCustomActionsYet() {
        for item in CleanCatalog.items(in: .safe) {
            if case .custom = item.action {
                Issue.record("\(item.id) uses a custom action; Safe tier should only use deletePath/deleteContents/runTool")
            }
        }
    }

    @Test("every custom action referenced by the catalog has a registered executor")
    func everyCustomActionHasARegisteredExecutor() async {
        let engine = CleanEngine(sizeScanner: SizeScanner(cache: SizeCache(fileURL: nil)))
        await DefaultCustomActionExecutors.registerAll(on: engine)

        var referencedOperations: Set<CustomOperationID> = []
        for item in CleanCatalog.allItems {
            if case .custom(let operationID) = item.action {
                referencedOperations.insert(operationID)
            }
        }

        for operationID in referencedOperations {
            let registered = await engine.hasExecutor(for: operationID)
            #expect(registered, "\(operationID.rawValue) is referenced by the catalog but has no registered executor")
        }
    }

    // MARK: - Simulator deletion safety

    @Test("a default environment approves zero simulators for deletion")
    func defaultEnvironmentApprovesNoSimulators() {
        let environment = CleanEnvironment()
        #expect(environment.simulatorsApprovedForDeletion.isEmpty)
    }

    @Test("the simulator deletion catalog item produces zero targets under a default environment, even with real devices present")
    func simulatorDeletionItemIsInertByDefault() throws {
        guard let item = CleanCatalog.allItems.first(where: { $0.id == "deep.simulator.delete-approved" }) else {
            Issue.record("expected a deep.simulator.delete-approved catalog item")
            return
        }

        // A default CleanEnvironment (as a fresh install would have) run
        // against this real machine, which does have real simulators
        // installed, must still resolve zero targets: nothing is approved
        // for deletion, so SimulatorPruner never even lists real devices.
        let environment = CleanEnvironment(homeDirectory: NSHomeDirectory())
        #expect(item.locate(environment).isEmpty)
    }

    @Test("the aggressive git reflog item is Deep-tier and carries a danger note")
    func aggressiveReflogItemIsDeepAndWarned() throws {
        guard let item = CleanCatalog.allItems.first(where: { $0.id == "deep.git.reflog-expire-all" }) else {
            Issue.record("expected a deep.git.reflog-expire-all catalog item")
            return
        }
        #expect(item.tier == .deep)
        #expect(item.dangerNote != nil)
    }
}
