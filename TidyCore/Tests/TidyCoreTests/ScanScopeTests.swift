import Foundation
import Testing
@testable import TidyCore

@Suite("Production scan scope authorization", .serialized)
struct ScanScopeTests {
    @Test("selected-project scope with no acknowledged roots performs zero metadata visits")
    @MainActor
    func selectedProjectsWithoutRootsVisitsNothing() async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "selectedProjects", gitRoots: [])
        defer { rig.remove() }
        let witness = rig.home.appendingPathComponent("Documents/witness.bin")
        try FileManager.default.createDirectory(at: witness.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4_096).write(to: witness)

        let authorization = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        #expect(authorization.roots.isEmpty)
        let visits = ScanMetadataVisitRecorder()
        let result = try await rig.run(authorization: authorization, visits: visits)

        #expect(result.coverage.isComplete)
        #expect(await visits.paths().isEmpty)
    }

    @Test("quick scope visits catalog roots but never unrelated Documents")
    @MainActor
    func quickScopeDoesNotExpandToHome() async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [])
        defer { rig.remove() }
        let cache = rig.home.appendingPathComponent("Library/Caches/typescript", isDirectory: true)
        let unrelatedCache = rig.home.appendingPathComponent(
            "Library/Caches/credential-store", isDirectory: true)
        let documents = rig.home.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelatedCache, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_024).write(to: cache.appendingPathComponent("cache.bin"))
        try Data(repeating: 2, count: 1_024).write(to: documents.appendingPathComponent("private.bin"))
        try Data(repeating: 3, count: 1_024).write(to: unrelatedCache.appendingPathComponent("secret.bin"))

        let authorization = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        let visits = ScanMetadataVisitRecorder()
        _ = try await rig.run(authorization: authorization, visits: visits)
        let visited = await visits.paths()

        #expect(visited.contains { PathGuard.isEqualOrDescendant($0, of: cache.path) })
        #expect(!visited.contains { PathGuard.isEqualOrDescendant($0, of: documents.path) })
        #expect(!visited.contains { PathGuard.isEqualOrDescendant($0, of: unrelatedCache.path) })
    }

    @Test("full-home consent is owner-bound and single-use")
    @MainActor
    func fullHomeConsentCannotTransferOrReplay() async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [])
        defer { rig.remove() }
        let consent = try rig.scopeAuthority.issueFullHomeConsent(ownerID: rig.ownerID)

        #expect(throws: ScanScopeAuthorizationError.self) {
            try rig.scopeAuthority.authorizeFullHome(consent: consent, ownerID: UUID())
        }
        let authorization = try rig.scopeAuthority.authorizeFullHome(
            consent: consent, ownerID: rig.ownerID)
        #expect(authorization.roots == [PathGuard.canonicalize(rig.home.path)])
        #expect(throws: ScanScopeAuthorizationError.self) {
            try rig.scopeAuthority.authorizeFullHome(consent: consent, ownerID: rig.ownerID)
        }
    }

    @Test("authorized scope is owner-bound, expires, and can start exactly once")
    @MainActor
    func authorizedScopeIsConsumedAtEngineStart() async throws {
        let clock = ScanScopeTestClock()
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [], clock: clock)
        defer { rig.remove() }
        let cache = rig.home.appendingPathComponent("Library/Caches/typescript", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let foreign = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        await #expect(throws: ScanScopeAuthorizationError.foreignConsent) {
            _ = try await rig.run(authorization: foreign,
                visits: ScanMetadataVisitRecorder(), ownerID: UUID())
        }
        _ = try await rig.run(authorization: foreign, visits: ScanMetadataVisitRecorder())
        await #expect(throws: ScanScopeAuthorizationError.consumedConsent) {
            _ = try await rig.run(authorization: foreign, visits: ScanMetadataVisitRecorder())
        }

        let expired = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        clock.advance(nanoseconds: 11)
        await #expect(throws: ScanScopeAuthorizationError.expiredConsent) {
            _ = try await rig.run(authorization: expired, visits: ScanMetadataVisitRecorder())
        }
    }

    @Test("full-home traversal unions mandatory protected descendants")
    @MainActor
    func fullHomeDoesNotVisitMandatoryProtectedRoots() async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [])
        defer { rig.remove() }
        let protected = rig.home.appendingPathComponent(
            "Library/CloudStorage/Provider/private.bin")
        try FileManager.default.createDirectory(at: protected.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 4, count: 1_024).write(to: protected)
        let consent = try rig.scopeAuthority.issueFullHomeConsent(ownerID: rig.ownerID)
        let authorization = try rig.scopeAuthority.authorizeFullHome(
            consent: consent, ownerID: rig.ownerID)
        #expect(authorization.excludedRoots.contains(PathGuard.canonicalize(
            rig.home.appendingPathComponent("Library/CloudStorage").path)))
        let visits = ScanMetadataVisitRecorder()
        _ = try await rig.run(authorization: authorization, visits: visits)
        #expect(!(await visits.paths()).contains {
            PathGuard.isEqualOrDescendant($0,
                of: rig.home.appendingPathComponent("Library/CloudStorage").path)
        })
    }

    @Test("manual Continue consumes bounded cursors and converges without scope expansion")
    @MainActor
    func continueConvergesWithinAuthorizedRoot() async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [])
        defer { rig.remove() }
        let cache = rig.home.appendingPathComponent("Library/Caches/typescript", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for index in 0..<8 {
            try Data(repeating: UInt8(index), count: 1_024)
                .write(to: cache.appendingPathComponent("f\(index).bin"))
        }
        let outside = rig.home.appendingPathComponent("Documents/outside.bin")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 99, count: 1_024).write(to: outside)
        let authorization = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        let visits = ScanMetadataVisitRecorder()
        let result = try await rig.runToCompletion(authorization: authorization,
            visits: visits, limits: try TraversalLimits(resultRecords: 2))

        #expect(result.coverage.isComplete)
        #expect(!result.continuationAvailable)
        #expect(!(await visits.paths()).contains {
            PathGuard.isEqualOrDescendant($0, of: outside.deletingLastPathComponent().path)
        })
    }
}

private actor ScanMetadataVisitRecorder {
    private var visited: [String] = []
    func record(_ path: String) { visited.append(PathGuard.canonicalize(path)) }
    func paths() -> [String] { visited }
}

private final class ScanScopeTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func now() -> UInt64 { lock.withLock { value } }
    func advance(nanoseconds: UInt64) { lock.withLock { value += nanoseconds } }
}

private struct ScanScopeRig {
    let root: URL
    let home: URL
    let settings: SettingsStore
    let bridge: ExecutionPolicyBridge
    let scopeAuthority: ScanScopeAuthority
    let ownerID = UUID()

    @MainActor
    static func make(defaultScope: String, gitRoots: [String],
                     clock: ScanScopeTestClock? = nil) async throws -> Self {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("TidyR06Scope-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let settings = SettingsStore(url: root.appendingPathComponent("settings/config.json"))
        _ = await settings.load()
        var config = TidyConfig(schemaVersion: 2)
        config.gitRoots = gitRoots
        _ = try await settings.update(expectedRevision: 0, change: .legacyPreferences(config))
        let scope = SettingID(rawValue: "scan.defaultScope")
        _ = try await settings.update(expectedRevision: 1,
            change: .preferences(.init(global: .init(fields: [scope: .choice(defaultScope)]))))
        let acknowledged = await settings.load()
        let environment = config.makePolicyEnvironment(homeDirectory: home.path, detectedTools: [])
        let coordinator = ExecutionCoordinator(environment: environment,
            journalDirectory: root.appendingPathComponent("journal"))
        let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: settings,
            loaded: acknowledged, homeDirectory: home.path, detectedTools: [])
        await bridge.drain()
        let authority = clock.map { testClock in
            ScanScopeAuthority(bridge: bridge, homeDirectory: home.path,
                consentLifetimeNanoseconds: 10, nowNanoseconds: { testClock.now() })
        } ?? ScanScopeAuthority(bridge: bridge, homeDirectory: home.path)
        return Self(root: root, home: home, settings: settings, bridge: bridge,
            scopeAuthority: authority)
    }

    @MainActor
    func run(authorization: AuthorizedScanScope,
             visits: ScanMetadataVisitRecorder,
             ownerID: UUID? = nil) async throws -> CoreScanResult {
        let environment = bridge.acknowledgedEnvelope!.config.makePolicyEnvironment(
            homeDirectory: home.path, detectedTools: [])
        let sessions = bridge.explicitSessions
        let work = try await sessions.beginSession(
            requirements: try SchedulerRequirements(features: [.headroom]))
        defer { Task { await sessions.finish(session: work) } }
        let registry = ScanSessionRegistry()
        let handle = try await ScanEngine.start(environment: environment,
            authorization: authorization, ownerID: ownerID ?? self.ownerID, registry: registry,
            sessions: sessions, session: work,
            dependencies: CoreScanDependencies(processProbe: { _, _ in .availableEmpty },
                testHook: nil, metadataVisit: { path in await visits.record(path) }))
        let subscription = try await registry.subscribe(sessionID: handle.sessionID)
        for await event in subscription.stream where event.terminal != nil { break }
        return try #require(await handle.latestResult())
    }

    @MainActor
    func runToCompletion(authorization: AuthorizedScanScope,
                         visits: ScanMetadataVisitRecorder,
                         limits: TraversalLimits) async throws -> CoreScanResult {
        let environment = bridge.acknowledgedEnvelope!.config.makePolicyEnvironment(
            homeDirectory: home.path, detectedTools: [])
        let sessions = bridge.explicitSessions
        let work = try await sessions.beginSession(
            requirements: try SchedulerRequirements(features: [.headroom]))
        defer { Task { await sessions.finish(session: work) } }
        let registry = ScanSessionRegistry()
        let dependencies = CoreScanDependencies(processProbe: { _, _ in .availableEmpty },
            testHook: nil, metadataVisit: { path in await visits.record(path) })
        var handle = try await ScanEngine.start(environment: environment,
            authorization: authorization, ownerID: ownerID, registry: registry, sessions: sessions,
            session: work, traversalLimits: limits, dependencies: dependencies)
        for _ in 0..<32 {
            let subscription = try await registry.subscribe(sessionID: handle.sessionID)
            for await event in subscription.stream where event.terminal != nil { break }
            let result = try #require(await handle.latestResult())
            if !result.continuationAvailable { return result }
            handle = try await ScanEngine.continueScan(from: handle, registry: registry)
        }
        Issue.record("Continuation failed to converge within the bounded fixture")
        return try #require(await handle.latestResult())
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
