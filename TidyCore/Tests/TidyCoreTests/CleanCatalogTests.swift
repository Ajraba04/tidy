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
        let scratch = URL(fileURLWithPath: "/private/tmp/Catalog-Roots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let environment = CleanEnvironment(
            homeDirectory: scratch.path,
            detectedTools: Set(ToolchainID.allCases),
            protectedRoots: []
        )

        // Populate declared roots in our owned fixture rather than inspecting
        // the developer's SDKs, browsers, repositories or simulator instances.
        for item in CleanCatalog.allItems {
            if let root = item.declaredRoot(environment), root.hasPrefix(scratch.path + "/") {
                try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
            }
        }

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

    @Test("Android system-image discovery rejects a child symlink outside its declared root")
    func androidSystemImageSymlinkEscapeIsExcluded() throws {
        let scratch = URL(fileURLWithPath: "/private/tmp/Catalog-Android-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let home = scratch.appendingPathComponent("home")
        let images = home.appendingPathComponent("Library/Android/sdk/system-images")
        let outside = scratch.appendingPathComponent("outside-image")
        for directory in [images.appendingPathComponent("owned-image"), outside] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: images.appendingPathComponent("escaped-image"),
            withDestinationURL: outside)
        let item = try #require(CleanCatalog.allItems.first { $0.id == "deep.android.system-images" })
        let targets = item.locate(CleanEnvironment(homeDirectory: home.path,
            detectedTools: [.android], protectedRoots: []))
        #expect(targets.map(\.path) == [images.appendingPathComponent("owned-image").path])
        #expect(FileManager.default.fileExists(atPath: outside.path))
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
        let engine = CleanEngine(sizeScanner: SizeScanner())
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
