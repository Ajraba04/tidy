import Foundation
import Testing
@testable import TidyCore

/// `makePlan` validated targets against their item's `declaredRoot`, but
/// `execute` re-validated with the generic rules only, so the containment
/// rule unique to this codebase was the one dropped at the moment of
/// deletion. These tests pin the invariant at execute time, where it
/// matters, and pin the system-root denylist that has to exist before any
/// item ever declares a root above `$HOME`.
@Suite("Declared root enforcement")
struct DeclaredRootEnforcementTests {

    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeclaredRootTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("a plan carries the declared root its targets were validated against")
    func planCarriesDeclaredRoot() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let target = scratch.appendingPathComponent("inside", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let item = CleanItem(
            id: "test.declared-root",
            title: "Test",
            tier: .safe,
            declaredRoot: { _ in scratch.path },
            locate: { _ in [TargetPath(path: target.path)] },
            action: .deletePath
        )

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let environment = CleanEnvironment(homeDirectory: scratch.path, protectedRoots: [])
        let plan = await engine.makePlan(items: [item], tier: .safe, environment: environment)

        #expect(plan.plannedItems.first?.declaredRoot == scratch.path)
    }

    /// The regression this whole change exists to prevent: a target that
    /// escapes its declared root between plan time and execute time must be
    /// refused at execute time, not deleted.
    @Test("execute refuses a target that sits outside the item's declared root")
    func executeRefusesEscapedTarget() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let declaredRoot = scratch.appendingPathComponent("declared", isDirectory: true)
        let elsewhere = scratch.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: declaredRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)

        let victim = elsewhere.appendingPathComponent("victim.txt")
        try Data("do not delete me".utf8).write(to: victim)

        // Hand-built to model a plan whose target no longer respects the
        // declared root; `makePlan` would have filtered this at plan time.
        let planned = PlannedItem(
            id: "test.escaped",
            title: "Escaped target",
            tier: .safe,
            dangerNote: nil,
            costNote: nil,
            targets: [TargetPath(path: victim.path)],
            estimatedBytes: 0,
            action: .deletePath,
            declaredRoot: declaredRoot.path
        )

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let environment = CleanEnvironment(homeDirectory: scratch.path, protectedRoots: [])
        let report = await engine.execute(
            plan: CleanPlan(tier: .safe, plannedItems: [planned]),
            environment: environment
        )

        #expect(FileManager.default.fileExists(atPath: victim.path), "execute deleted a target outside its declared root")
        #expect(report.results.first?.succeeded == false)
        #expect(report.results.first?.freedBytes == 0)
    }

    @Test("execute still deletes a target that does respect its declared root")
    func executeDeletesContainedTarget() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let declaredRoot = scratch.appendingPathComponent("declared", isDirectory: true)
        try FileManager.default.createDirectory(at: declaredRoot, withIntermediateDirectories: true)
        let doomed = declaredRoot.appendingPathComponent("doomed.txt")
        try Data("delete me".utf8).write(to: doomed)

        let planned = PlannedItem(
            id: "test.contained",
            title: "Contained target",
            tier: .safe,
            dangerNote: nil,
            costNote: nil,
            targets: [TargetPath(path: doomed.path)],
            estimatedBytes: 0,
            action: .deletePath,
            declaredRoot: declaredRoot.path
        )

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let environment = CleanEnvironment(homeDirectory: scratch.path, protectedRoots: [])
        let report = await engine.execute(
            plan: CleanPlan(tier: .safe, plannedItems: [planned]),
            environment: environment
        )

        #expect(!FileManager.default.fileExists(atPath: doomed.path))
        #expect(report.results.first?.succeeded == true)
    }

    // MARK: - System container denylist

    @Test("refuses every system container path outright", arguments: [
        "/Users", "/System", "/Library", "/Applications", "/usr", "/bin",
        "/sbin", "/etc", "/var", "/private", "/Volumes", "/System/Volumes"
    ])
    func refusesSystemContainers(path: String) {
        let guardian = PathGuard(protectedRoots: [])
        #expect(throws: PathGuardError.self) {
            try guardian.validate(path, home: "/Users/someone")
        }
    }

    @Test("refuses anything inside a SIP-owned subtree")
    func refusesSystemSubtrees() {
        let guardian = PathGuard(protectedRoots: [])
        for path in ["/System/Library/Caches", "/usr/lib/whatever", "/bin/zsh"] {
            #expect(throws: PathGuardError.self) {
                try guardian.validate(path, home: "/Users/someone")
            }
        }
    }

    /// The denylist must not have made legitimate future targets
    /// unreachable: the point is to refuse the container, not its contents.
    @Test("still allows reachable paths inside system containers")
    func allowsPathsInsideSystemContainers() {
        let guardian = PathGuard(protectedRoots: [])
        for path in [
            "/Library/Developer/CoreSimulator/Caches",
            "/private/var/folders/xx/C",
            "/Users/someone/Library/Caches/thing"
        ] {
            #expect(guardian.isSafe(path, home: "/Users/someone"), "\(path) should remain reachable")
        }
    }

    /// Today every catalog item declares a root under `$HOME`. Pinning that
    /// means the first item to declare one above `$HOME` fails this test and
    /// gets a deliberate review, rather than arriving unnoticed.
    @Test("every catalog item declares a root under the home directory")
    func everyDeclaredRootIsUnderHome() {
        let home = NSHomeDirectory()
        let environment = CleanEnvironment(homeDirectory: home, detectedTools: Set(ToolchainID.allCases))

        for item in CleanCatalog.allItems {
            guard let root = item.declaredRoot(environment) else {
                Issue.record("\(item.id) declares no root")
                continue
            }
            #expect(
                PathGuard.isEqualOrDescendant(PathGuard.canonicalize(root), of: PathGuard.canonicalize(home)),
                "\(item.id) declares a root outside $HOME: \(root)"
            )
        }
    }
}
