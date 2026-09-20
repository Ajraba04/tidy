import Darwin
import Foundation
import Testing
@testable import TidyCore

private final class ProjectFixtureLease: ProducerExclusionLease, @unchecked Sendable {
    let proof: RuntimeProducerProof
    let acquiredAt: ContinuousClock.Instant
    let deadline: ContinuousClock.Instant

    init(proof: RuntimeProducerProof, acquiredAt: ContinuousClock.Instant,
         deadline: ContinuousClock.Instant) {
        self.proof = proof
        self.acquiredAt = acquiredAt
        self.deadline = deadline
    }
}

private struct ProjectInventoryRig {
    let root: URL
    let home: URL
    let projects: URL
    let excluded: URL
    let outside: URL
    let environment: CleanEnvironment
    let authority: ScanScopeAuthority
    let ownerID = UUID()

    @MainActor
    static func make() async throws -> Self {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("Tidy-ProjectInventory-\(UUID().uuidString)",
                                    isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let projects = home.appendingPathComponent("Projects", isDirectory: true)
        let excluded = projects.appendingPathComponent("Excluded", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        for directory in [projects, excluded, outside] {
            try FileManager.default.createDirectory(at: directory,
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        let settings = SettingsStore(url: root.appendingPathComponent("settings/config.json"))
        _ = await settings.load()
        var config = TidyConfig(schemaVersion: 2)
        config.gitRoots = [projects.path]
        _ = try await settings.update(expectedRevision: 0,
            change: .legacyPreferences(config))
        let fields = PolicyValues(fields: [
            SettingID(rawValue: "scan.defaultScope"): .choice("selectedProjects"),
            SettingID(rawValue: "scope.excludedRoots"): .strings([excluded.path])
        ])
        _ = try await settings.update(expectedRevision: 1,
            change: .preferences(.init(global: fields)))
        let loaded = await settings.load()
        let environment = CleanEnvironment(homeDirectory: home.path,
            gitRoots: [projects.path], protectedRoots: [])
        let coordinator = ExecutionCoordinator(environment: environment,
            journalDirectory: root.appendingPathComponent("journal"))
        let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: settings,
            loaded: loaded, homeDirectory: home.path, detectedTools: [])
        await bridge.drain()
        return Self(root: root, home: home, projects: projects, excluded: excluded,
            outside: outside, environment: environment,
            authority: ScanScopeAuthority(bridge: bridge, homeDirectory: home.path))
    }

    @MainActor
    func scope() throws -> AuthorizedScanScope {
        try authority.authorizePolicyDefault(ownerID: ownerID)
    }

    func directory(_ relative: String) throws -> URL {
        let url = projects.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Project inventory", .serialized)
struct ProjectInventoryTests {
    @Test("authorized root nested repositories worktrees exclusions and option-like names are data")
    @MainActor
    func discoversRootNestedAndLinkedWorktreeWithoutScopeExpansion() async throws {
        let rig = try await ProjectInventoryRig.make(); defer { rig.remove() }
        let rootGit = try rig.directory(".git")
        try rig.write(#"{"name":"root","scripts":{"postinstall":"touch SHOULD-NOT-EXIST"}}"#,
                      to: rig.projects.appendingPathComponent("package.json"))

        let nested = try rig.directory("packages/Nested")
        _ = try rig.directory("packages/Nested/.git")
        try rig.write("// manifest data only\n",
                      to: nested.appendingPathComponent("Package.swift"))

        let optionNamed = try rig.directory("--upload-pack=evil")
        _ = try rig.directory("--upload-pack=evil/.git")
        let worktreeGit = try rig.directory(".git/worktrees/linked")
        try rig.write("../..\n", to: worktreeGit.appendingPathComponent("commondir"))
        let linked = try rig.directory("Linked")
        try rig.write("gitdir: ../.git/worktrees/linked\n",
                      to: linked.appendingPathComponent(".git"))
        _ = try FileManager.default.createDirectory(
            at: rig.excluded.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try rig.write("sentinel", to: rig.outside.appendingPathComponent("SHOULD-NOT-EXIST"))

        let authorization = try rig.scope()
        let snapshot = try await ProjectInventory.scan(scope: authorization,
            ownerID: rig.ownerID, environment: rig.environment,
            now: Date(timeIntervalSince1970: 1_000))

        let roots = Set(snapshot.records.map(\.canonicalRoot))
        #expect(roots.contains(PathGuard.canonicalize(rig.projects.path)))
        #expect(roots.contains(PathGuard.canonicalize(nested.path)))
        #expect(roots.contains(PathGuard.canonicalize(linked.path)))
        #expect(roots.contains(PathGuard.canonicalize(optionNamed.path)))
        #expect(!roots.contains(PathGuard.canonicalize(rig.excluded.path)))
        #expect(snapshot.coverage.reasons.contains(.excluded))
        let root = try #require(snapshot.records.first {
            $0.canonicalRoot == PathGuard.canonicalize(rig.projects.path)
        })
        #expect(root.toolchains.contains(.node))
        #expect(root.activity == .unknown)
        #expect(root.capability == .inventoryOnly)
        #expect(root.git?.dirtyState == .unknown)
        #expect(root.git?.untrackedState == .unknown)
        let linkedRecord = try #require(snapshot.records.first {
            $0.canonicalRoot == PathGuard.canonicalize(linked.path)
        })
        #expect(linkedRecord.git?.layout == .linkedWorktree)
        #expect(linkedRecord.git?.gitDirectoryIdentity?.canonicalPath
                == PathGuard.canonicalize(worktreeGit.path))
        #expect(linkedRecord.git?.commonDirectoryIdentity?.canonicalPath
                == PathGuard.canonicalize(rootGit.path))
        #expect(!FileManager.default.fileExists(
            atPath: rig.projects.appendingPathComponent("SHOULD-NOT-EXIST").path))

        await #expect(throws: ScanScopeAuthorizationError.consumedConsent) {
            _ = try await ProjectInventory.scan(scope: authorization,
                ownerID: rig.ownerID, environment: rig.environment)
        }
    }

    @Test("hostile manifests symlinks and external Git metadata stay bounded and partial")
    @MainActor
    func rejectsOversizedDeepInvalidSymlinkAndExternalMetadata() async throws {
        let rig = try await ProjectInventoryRig.make(); defer { rig.remove() }
        let oversized = try rig.directory("Oversized")
        try Data(repeating: 0x61, count: 1_048_577)
            .write(to: oversized.appendingPathComponent("package.json"))
        let deep = try rig.directory("Deep")
        try rig.write(String(repeating: "{\"x\":", count: 6)
            + "0" + String(repeating: "}", count: 6),
            to: deep.appendingPathComponent("package.json"))
        let invalid = try rig.directory("Invalid")
        try Data([0xFF, 0xFE]).write(to: invalid.appendingPathComponent("package.json"))
        let symlinked = try rig.directory("Symlinked")
        let outsideManifest = rig.outside.appendingPathComponent("package.json")
        try rig.write("{\"name\":\"outside-secret\"}", to: outsideManifest)
        try FileManager.default.createSymbolicLink(
            at: symlinked.appendingPathComponent("package.json"),
            withDestinationURL: outsideManifest)
        let external = try rig.directory("ExternalGit")
        let externalGit = rig.outside.appendingPathComponent("gitdir", isDirectory: true)
        try FileManager.default.createDirectory(at: externalGit, withIntermediateDirectories: true)
        try rig.write("gitdir: ../../outside/gitdir\n",
                      to: external.appendingPathComponent(".git"))

        let snapshot = try await ProjectInventory.scan(scope: rig.scope(),
            ownerID: rig.ownerID, environment: rig.environment,
            limits: .init(maximumJSONDepth: 4))
        func record(_ url: URL) throws -> ProjectInventoryRecord {
            try #require(snapshot.records.first {
                $0.canonicalRoot == PathGuard.canonicalize(url.path)
            })
        }
        #expect(try #require(record(oversized).manifests.first).status == .oversized)
        #expect(try #require(record(deep).manifests.first).status == .invalidData)
        #expect(try #require(record(invalid).manifests.first).status == .invalidData)
        #expect(try #require(record(symlinked).manifests.first).status
                == .symbolicLinkRejected)
        let externalRecord = try record(external)
        #expect(externalRecord.git?.layout == .invalid)
        #expect(externalRecord.git?.gitDirectoryIdentity == nil)
        #expect(externalRecord.git?.commonDirectoryIdentity == nil)
        #expect(externalRecord.confidence == .unknown)
        #expect(!snapshot.coverage.isComplete)
        #expect(snapshot.coverage.reasons.contains(.symbolicLinkSkipped))
    }

    @Test("only complete fresh held producer proof confirms inactivity")
    func activityRequiresCompleteOwnershipAndLease() throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("Tidy-ProjectActivity-\(UUID().uuidString)",
                                    isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let resource = ResourceIdentity.filesystem(
            try ResourcePreflight.captureFile(at: directory.path))
        let now = Date(timeIntervalSince1970: 10_000)
        let association = ResourceAssociationEvidence(adapterID: "fixture.projects",
            adapterVersion: "1", resource: resource,
            producerIDs: ["fixture.builder"], ownerIDs: ["project.one"],
            sharedOwnerIDs: [], completeness: .complete, observedAt: now,
            validUntil: now.addingTimeInterval(60), method: .producerManifest)
        let acquired = ContinuousClock.now
        let proof = RuntimeProducerProof(adapterID: "fixture.projects",
            adapterVersion: "1", resource: resource,
            producerIDs: association.producerIDs, ownerIDs: association.ownerIDs,
            sharedOwnerIDs: [], completeness: .complete, observedAt: now,
            validUntil: now.addingTimeInterval(5), method: .producerExclusionLease)
        let lease = ProjectFixtureLease(proof: proof, acquiredAt: acquired,
            deadline: acquired.advanced(by: .seconds(5)))

        let positive = ActivityResolver.resolve(resource: resource,
            adapterID: "fixture.projects", adapterVersion: "1",
            association: association, lease: lease, pinned: false, current: false,
            now: now, monotonicNow: acquired)
        #expect(positive.activity == .inactiveConfirmed)
        #expect(positive.recommendationEligible)

        let sharedUnknown = ResourceAssociationEvidence(adapterID: "fixture.projects",
            adapterVersion: "1", resource: resource,
            producerIDs: ["fixture.builder"], ownerIDs: ["project.one"],
            sharedOwnerIDs: ["project.unobserved"], completeness: .complete,
            observedAt: now, validUntil: now.addingTimeInterval(60),
            method: .producerManifest)
        let negative = ActivityResolver.resolve(resource: resource,
            adapterID: "fixture.projects", adapterVersion: "1",
            association: sharedUnknown, lease: lease, pinned: false, current: false,
            now: now, monotonicNow: acquired)
        #expect(negative.activity == .unknown)
        #expect(!negative.recommendationEligible)
        #expect(ActivityResolver.resolve(resource: resource,
            adapterID: "fixture.projects", adapterVersion: "1",
            association: nil, lease: nil, pinned: false, current: false,
            now: now, monotonicNow: acquired).activity == .unknown)
        #expect(ActivityResolver.inventory(projectID: "p", pinnedProjectIDs: ["p"],
            currentProjectID: nil).activity == .pinned)
    }
}
