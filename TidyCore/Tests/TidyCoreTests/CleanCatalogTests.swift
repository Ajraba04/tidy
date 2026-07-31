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

    @Test("locate and declaredRoot never crash for any safe-tier item on a scratch home")
    func locateAndDeclaredRootNeverCrash() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let environment = CleanEnvironment(homeDirectory: scratch.path, protectedRoots: [])

        for item in CleanCatalog.items(in: .safe) {
            _ = item.locate(environment)
            _ = item.declaredRoot(environment)
        }
    }

    @Test("every located target for a safe item falls under that item's declared root")
    func everyLocatedTargetFallsUnderDeclaredRoot() throws {
        // Run against the real home directory so fixed-path items that
        // actually exist here are exercised, not just the empty case.
        let environment = CleanEnvironment(
            homeDirectory: NSHomeDirectory(),
            detectedTools: Set(ToolchainID.allCases),
            protectedRoots: []
        )

        for item in CleanCatalog.items(in: .safe) {
            guard let declaredRoot = item.declaredRoot(environment) else { continue }
            let canonicalRoot = PathGuard.canonicalize(declaredRoot)
            for target in item.locate(environment) {
                let canonicalTarget = PathGuard.canonicalize(target.path)
                #expect(
                    PathGuard.isEqualOrDescendant(canonicalTarget, of: canonicalRoot),
                    "\(item.id): \(target.path) is not under its declared root \(declaredRoot)"
                )
            }
        }
    }

    @Test("safe tier contains no custom actions requiring Phase 5/6 handlers")
    func safeTierHasNoCustomActionsYet() {
        for item in CleanCatalog.items(in: .safe) {
            if case .custom = item.action {
                Issue.record("\(item.id) uses a custom action; Safe tier should only use deletePath/deleteContents/runTool")
            }
        }
    }
}
