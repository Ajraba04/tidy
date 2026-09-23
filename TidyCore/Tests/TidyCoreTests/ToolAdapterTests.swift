import Darwin
import Foundation
import Testing
@testable import TidyCore

struct AdapterTestFixture {
    let root: URL
    let home: URL
    let projects: URL

    init() throws {
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("Tidy-Adapters-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        projects = home.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    }

    func directory(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func project(_ relative: String, toolchains: Set<ProjectToolchain> = [],
                 git: ProjectGitMetadata? = nil) throws -> ProjectInventoryRecord {
        let url = try directory("Projects/" + relative)
        let identity = try ResourcePreflight.captureFile(at: url.path)
        return ProjectInventoryRecord(id: InventoryFilesystem.stableID(
            adapterID: "project", identity: identity), canonicalRoot: url.path,
            rootIdentity: identity, git: git, manifests: [], toolchains: toolchains,
            capability: .inventoryOnly, confidence: .partial, activity: .unknown,
            recommendationEligible: false, reasons: ["fixture"])
    }

    func context(projects records: [ProjectInventoryRecord] = []) -> ToolAdapterContext {
        let coverage = ProjectInventoryCoverage(isComplete: true, reasons: [],
            visitedNodes: 0, omittedPaths: [])
        return ToolAdapterContext(roots: [home.path], excludedRoots: [],
            environment: CleanEnvironment(homeDirectory: home.path, protectedRoots: []),
            projects: ProjectInventorySnapshot(records: records, coverage: coverage,
                                               observedAt: Date(timeIntervalSince1970: 1)),
            now: Date(timeIntervalSince1970: 1), scopeID: "fixture",
            budget: InventoryAllocationBudget(maximumNodes: 50_000,
                deadline: ContinuousClock.now.advanced(by: .seconds(30))))
    }

    func socket(_ relative: String) throws -> (URL, Int32, LocalSocketApproval) {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(url.path.utf8)
        guard path.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor); throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: path)
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno; close(descriptor)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
        return (url, descriptor, try LocalSocketApproval.verify(socket: url))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private actor RecordingLocalToolProbe: LocalToolProbe {
    private var operations: [String] = []
    func read(_ operation: LocalToolReadOperation) async throws -> Data {
        switch operation {
        case .appleSimctlDevices: operations.append("apple")
        case .dockerImages: operations.append("docker-images")
        case .dockerContainers: operations.append("docker-containers")
        }
        return Data(#"{"devices":{}}"#.utf8)
    }
    func count() -> Int { operations.count }
}

private struct AdapterServiceRig {
    let root: URL
    let home: URL
    let environment: CleanEnvironment
    let authority: ScanScopeAuthority
    let ownerID = UUID()

    @MainActor
    static func make(disabledID: String) async throws -> Self {
        let fixture = try AdapterTestFixture()
        let settings = SettingsStore(url: fixture.root.appendingPathComponent("settings/config.json"))
        _ = await settings.load()
        var config = TidyConfig(schemaVersion: 2)
        config.gitRoots = [fixture.projects.path]
        _ = try await settings.update(expectedRevision: 0,
            change: .legacyPreferences(config))
        let fields = PolicyValues(fields: [
            SettingID(rawValue: "scan.defaultScope"): .choice("selectedProjects"),
            SettingID(rawValue: disabledID): .bool(false)
        ])
        _ = try await settings.update(expectedRevision: 1,
            change: .preferences(.init(global: fields)))
        let loaded = await settings.load()
        let environment = CleanEnvironment(homeDirectory: fixture.home.path,
            gitRoots: [fixture.projects.path], protectedRoots: [])
        let coordinator = ExecutionCoordinator(environment: environment,
            journalDirectory: fixture.root.appendingPathComponent("journal"))
        let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: settings,
            loaded: loaded, homeDirectory: fixture.home.path, detectedTools: [])
        await bridge.drain()
        return Self(root: fixture.root, home: fixture.home, environment: environment,
            authority: ScanScopeAuthority(bridge: bridge, homeDirectory: fixture.home.path))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Tool adapter boundary", .serialized)
struct ToolAdapterTests {
    @Test("captured context rejects arbitrary outside roots and records stay inventory only")
    func contextDoesNotWidenAuthority() throws {
        let fixture = try AdapterTestFixture(); defer { fixture.remove() }
        let inside = try fixture.directory("Library/Caches/fixture")
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let context = fixture.context()
        let first = context.entry(adapterID: "fixture", adapterVersion: "1",
            path: inside.path, kind: "cache", disposition: .reportOnly,
            reason: "fixture")
        #expect(first?.record.capability == .inventoryOnly)
        let shared = context.entry(adapterID: "fixture.other", adapterVersion: "1",
            path: inside.path, kind: "cache", disposition: .reportOnly,
            reason: "fixture")
        #expect(first?.record.allocatedBytes != nil)
        #expect(shared?.record.allocatedBytes == nil)
        #expect(shared?.record.reason.contains("shared") == true)
        #expect(context.entry(adapterID: "fixture", adapterVersion: "1",
            path: outside.path, kind: "cache", disposition: .reportOnly,
            reason: "fixture") == nil)
    }

    @Test("allocation walk stops at an excluded descendant and reports partial bytes")
    func excludedDescendantIsNeverCounted() throws {
        let fixture = try AdapterTestFixture(); defer { fixture.remove() }
        let cache = try fixture.directory("Library/Caches/bounded")
        let excluded = cache.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 4_096)
            .write(to: excluded.appendingPathComponent("secret"))
        let base = fixture.context()
        let context = ToolAdapterContext(roots: base.roots,
            excludedRoots: [excluded.path], environment: base.environment,
            projects: base.projects, now: base.now, scopeID: base.scopeID,
            budget: InventoryAllocationBudget(maximumNodes: 100,
                deadline: ContinuousClock.now.advanced(by: .seconds(30))))
        let entry = try #require(context.entry(adapterID: "fixture",
            adapterVersion: "1", path: cache.path, kind: "cache",
            disposition: .reportOnly, reason: "fixture"))
        #expect(entry.record.allocatedBytes == nil)
        #expect(entry.record.reason.contains("partial"))
    }

    @Test("global and Apple inventory disables produce zero tool reads",
          arguments: ["feature.ecosystems", "ecosystem.apple.inventory"])
    @MainActor
    func disabledAppleInventoryMakesNoProbeCall(_ disabledID: String) async throws {
        let rig = try await AdapterServiceRig.make(disabledID: disabledID)
        defer { rig.remove() }
        let probe = RecordingLocalToolProbe()
        let request = DeveloperInventoryRequest(apple: try .nativeXcrun())
        let snapshot = try await DeveloperInventoryService.scan(
            scope: rig.authority.authorizePolicyDefault(ownerID: rig.ownerID),
            ownerID: rig.ownerID, environment: rig.environment,
            request: request, probe: probe)
        #expect(await probe.count() == 0)
        #expect(!snapshot.records.contains { $0.kind == "apple-simulator" })
    }

    @Test("disabled projects perform zero project metadata visits")
    @MainActor
    func disabledProjectsDoNotScanRoots() async throws {
        let rig = try await AdapterServiceRig.make(disabledID: "feature.projects")
        defer { rig.remove() }
        try Data("{}".utf8).write(to: rig.home.appendingPathComponent("Projects/package.json"))
        let snapshot = try await DeveloperInventoryService.scan(
            scope: rig.authority.authorizePolicyDefault(ownerID: rig.ownerID),
            ownerID: rig.ownerID, environment: rig.environment)
        #expect(snapshot.projects.records.isEmpty)
        #expect(snapshot.projects.coverage.visitedNodes == 0)
    }
}
