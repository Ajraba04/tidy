import Foundation
import Testing
@testable import TidyCore

@Suite("Project marker inventory")
struct ProjectInventoryTests {
    @Test @MainActor
    func boundedInventoryRecognizesNestedAndIndirectGitWithoutFollowingLinks() async throws {
        let rig = try await TraversalBridgeRig.make()
        do {
            let root = rig.root.appendingPathComponent("projects")
            let repo = root.appendingPathComponent("-option-like-project")
            let nested = repo.appendingPathComponent("nested")
            let dependency = repo.appendingPathComponent("node_modules/dependency")
            let protected = root.appendingPathComponent("protected")
            for directory in [nested, dependency, protected] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: false)
            let indirection = Data("gitdir: /outside/never-followed\n".utf8)
            try indirection.write(to: nested.appendingPathComponent(".git"))
            try Data("not evaluated".utf8).write(to: dependency.appendingPathComponent("package.json"))
            try Data("{}".utf8).write(to: protected.appendingPathComponent("package.json"))
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: protected)
            let context = try await CoreOrchestrationContext.make(sessions: rig.sessions,
                session: rig.session, sessionID: UUID())
            let environment = CleanEnvironment(homeDirectory: rig.root.path, gitRoots: [root.path],
                protectedRoots: [protected.path])
            let result = await ProjectInventory.scan(root: root.path, context: context, environment: environment)
            #expect(Set(result.records.map(\.path)) == [repo.path, nested.path])
            #expect(result.records.first(where: { $0.path == nested.path })?.gitLayout == .indirection)
            #expect(result.records.allSatisfy { $0.activity == .unknown })
            #expect(try Data(contentsOf: nested.appendingPathComponent(".git")) == indirection)
            await rig.cleanup()
        } catch {
            await rig.cleanup()
            throw error
        }
    }

    @Test func pinsProtectLocationsWithoutBecomingOwnershipProof() {
        let path = "/fixture/project"
        let marker = TraversalRecord(path: path + "/package.json", relativePath: "project/package.json",
            depth: 2, bytes: 0, kind: .regularFile, modifiedAt: nil)
        let result = ProjectInventory.summarize(records: [marker], root: "/fixture",
            coverage: .init(isComplete: true, reasons: []), pinnedIDs: [ProjectInventory.locationID(path: path)])
        #expect(result.records.first?.activity == .pinned)
        #expect(result.records.first?.activity.blocksRecommendation == true)
    }
}

@Suite("Ownership evidence eligibility")
struct OwnershipEvidenceTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func evidence(observedOwners: Set<String> = ["producer", "shared"], age: TimeInterval = 0,
                  complete: Bool = true, lease: Bool = true) -> OwnershipEvidence {
        OwnershipEvidence(resourceIdentity: "volume:inode:generation", adapterVersion: "fixture-v1", policyRevision: 3,
            owners: ["producer", "shared"], observedOwners: observedOwners, quiescentOwners: ["producer", "shared"],
            observedAt: now.addingTimeInterval(-age), associationObservedAt: now,
            leaseValidUntil: lease ? now.addingTimeInterval(5) : nil,
            enumerationComplete: complete, immutableCompletedObject: true)
    }
    func resolve(_ evidence: OwnershipEvidence?, pinned: Bool = false, running: Bool = false,
                 recent: Bool = false) -> ActivityEvidence {
        ActivityResolver.resolve(evidence: evidence, resourceIdentity: "volume:inode:generation",
            policyRevision: 3, pinned: pinned, running: running, recent: recent, now: now)
    }
    @Test func onlyCompleteFreshHeldEvidenceSupportsInactivity() {
        #expect(resolve(evidence()) == .inactiveConfirmed)
        #expect(resolve(evidence(observedOwners: ["producer"])) == .unknown)
        #expect(resolve(evidence(complete: false)) == .unknown)
        #expect(resolve(evidence(lease: false)) == .unknown)
        #expect(resolve(evidence(age: 5)) == .unknown)
        #expect(resolve(evidence(age: -1)) == .unknown)
        #expect(resolve(nil) == .unknown)
        #expect(resolve(evidence(), pinned: true) == .pinned)
        #expect(resolve(evidence(), running: true) == .running)
        #expect(resolve(evidence(), recent: true) == .recent)
    }
    @Test func resourceOrPolicyReplacementInvalidatesEvidence() {
        #expect(ActivityResolver.resolve(evidence: evidence(), resourceIdentity: "replacement", policyRevision: 3,
            pinned: false, running: false, recent: false, now: now) == .unknown)
        #expect(ActivityResolver.resolve(evidence: evidence(), resourceIdentity: "volume:inode:generation", policyRevision: 4,
            pinned: false, running: false, recent: false, now: now) == .unknown)
    }
}
