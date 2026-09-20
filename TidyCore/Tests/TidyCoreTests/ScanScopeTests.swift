import Foundation
import Testing
@testable import TidyCore

@Suite("Production scan scope authorization", .serialized)
struct ScanScopeTests {
    @Test("consumed project scopes expire and invalidate during a pending policy transition")
    @MainActor
    func liveProjectScopeChecksPolicyAndExpiry() async throws {
        let clock = ScanScopeTestClock()
        let rig = try await ScanScopeRig.make(defaultScope: "selectedProjects", gitRoots: [], clock: clock)
        defer { rig.remove() }
        let scope = try rig.scopeAuthority.authorizeProjects(ownerID: rig.ownerID)
        try scope.checkValidity()
        let envelope = try #require(rig.bridge.acknowledgedScanEnvelope)
        let id = SettingID(rawValue: "feature.projects")
        let submission = rig.bridge.submit(global: .init(baseRevision: envelope.revision,
            id: id, baseValue: envelope.preferences?.global.fields[id], editedValue: .bool(false)))
        guard case .accepted(_, let completion) = submission else {
            Issue.record("Fixture policy invalidation was not admitted")
            return
        }
        #expect(throws: ScanScopeAuthorizationError.expiredConsent) { try scope.checkValidity() }
        _ = await completion.value
        #expect(throws: ScanScopeAuthorizationError.expiredConsent) { try scope.checkValidity() }

        let secondRig = try await ScanScopeRig.make(defaultScope: "selectedProjects", gitRoots: [], clock: clock)
        defer { secondRig.remove() }
        let timed = try secondRig.scopeAuthority.authorizeProjects(ownerID: secondRig.ownerID)
        try timed.checkValidity()
        clock.advance(nanoseconds: 11)
        #expect(throws: ScanScopeAuthorizationError.expiredConsent) { try timed.checkValidity() }
    }

    @Test("exact absent-file defaults authorize only the bounded Quick roots")
    @MainActor
    func freshDefaultsAuthorizeQuickScopeWithoutPersistingSettings() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("TidyR05FreshScope-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let cache = home.appendingPathComponent("Library/Caches/typescript", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let settingsURL = root.appendingPathComponent("settings/config.json")
        let settings = SettingsStore(url: settingsURL)
        let bootstrap = await settings.loadForSchedulerBootstrap()
        let loaded = bootstrap.result
        #expect(loaded.disposition == .newDefaults)
        let config = try #require(loaded.envelope?.config)
        let environment = config.makePolicyEnvironment(homeDirectory: home.path, detectedTools: [])
        let coordinator = ExecutionCoordinator(environment: environment,
            journalDirectory: root.appendingPathComponent("journal"))
        let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: settings,
            bootstrap: bootstrap, homeDirectory: home.path, detectedTools: [])
        await bridge.drain()

        let authority = ScanScopeAuthority(bridge: bridge, homeDirectory: home.path)
        let authorization = try authority.authorizePolicyDefault(ownerID: UUID())
        #expect(authorization.mode == .quick)
        #expect(authorization.roots == [PathGuard.canonicalize(cache.path)])
        #expect(!FileManager.default.fileExists(atPath: settingsURL.path))
    }

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

    @Test("Quick cache aliases never authorize home, unrelated or outside roots",
          arguments: ["home", "unrelated", "outside", "ancestor"])
    @MainActor
    func quickCacheAliasesDoNotExpandScope(_ kind: String) async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [])
        defer { rig.remove() }
        let cache = rig.home.appendingPathComponent("Library/Caches/typescript")
        let unrelated = rig.home.appendingPathComponent("Documents")
        let outside = rig.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        if kind == "ancestor" {
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent().deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside.appendingPathComponent("typescript"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: cache.deletingLastPathComponent(), withDestinationURL: outside)
        } else {
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            let target = kind == "home" ? rig.home : (kind == "unrelated" ? unrelated : outside)
            try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: target)
        }
        let authorization = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        #expect(authorization.roots.isEmpty)
        // Even the red fixture is entirely inside the owned scratch root.
        let visits = ScanMetadataVisitRecorder()
        _ = try await rig.run(authorization: authorization, visits: visits)
        #expect(await visits.paths().isEmpty)
    }

    @Test("moving an authorized cache ancestor and replacing it with an alias denies start")
    @MainActor
    func ancestorAliasCannotReuseTheSameLeafIdentity() async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [])
        defer { rig.remove() }
        let caches = rig.home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: caches.appendingPathComponent("typescript"), withIntermediateDirectories: true)
        let authorization = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        let moved = rig.root.appendingPathComponent("moved-caches")
        try FileManager.default.moveItem(at: caches, to: moved)
        try FileManager.default.createSymbolicLink(at: caches, withDestinationURL: moved)
        let visits = ScanMetadataVisitRecorder()
        await #expect(throws: ScanScopeAuthorizationError.invalidRoot) {
            _ = try await rig.run(authorization: authorization, visits: visits)
        }
        #expect(await visits.paths().isEmpty)
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

        let consent = try rig.scopeAuthority.issueFullHomeConsent(ownerID: rig.ownerID)
        let expiringFullHome = try rig.scopeAuthority.authorizeFullHome(
            consent: consent, ownerID: rig.ownerID)
        clock.advance(nanoseconds: 11)
        await #expect(throws: ScanScopeAuthorizationError.expiredConsent) {
            _ = try await rig.run(authorization: expiringFullHome,
                visits: ScanMetadataVisitRecorder())
        }
    }

    @Test("successful scope grants release captured identities and replay still denies")
    @MainActor
    func repeatedGrantConsumptionRetainsNoLedgerState() async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [])
        defer { rig.remove() }
        let cache = rig.home.appendingPathComponent("Library/Caches/typescript", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let environment = try #require(rig.bridge.acknowledgedEnvelope).config
            .makePolicyEnvironment(homeDirectory: rig.home.path, detectedTools: [])

        for _ in 0..<32 {
            let authorization = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
            #expect(rig.scopeAuthority.retainedGrantCountForTesting == 1)
            try authorization.consumeForStart(ownerID: rig.ownerID, environment: environment)
            #expect(rig.scopeAuthority.retainedGrantCountForTesting == 0)
            #expect(throws: ScanScopeAuthorizationError.consumedConsent) {
                try authorization.consumeForStart(ownerID: rig.ownerID, environment: environment)
            }
        }
    }

    @Test("register reaps expired abandoned scope grants")
    @MainActor
    func abandonedExpiredGrantsAreReapedOnNextRegistration() async throws {
        let clock = ScanScopeTestClock()
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [], clock: clock)
        defer { rig.remove() }
        let cache = rig.home.appendingPathComponent("Library/Caches/typescript", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        _ = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        _ = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        #expect(rig.scopeAuthority.retainedGrantCountForTesting == 2)

        clock.advance(nanoseconds: 11)
        let current = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        #expect(rig.scopeAuthority.retainedGrantCountForTesting == 1)
        let environment = try #require(rig.bridge.acknowledgedEnvelope).config
            .makePolicyEnvironment(homeDirectory: rig.home.path, detectedTools: [])
        try current.consumeForStart(ownerID: rig.ownerID, environment: environment)
        #expect(rig.scopeAuthority.retainedGrantCountForTesting == 0)
    }

    @Test("successful full-home consent and grant release metadata while both replays deny")
    @MainActor
    func repeatedFullHomeStartRetainsNeitherLedger() async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [])
        defer { rig.remove() }
        let environment = try #require(rig.bridge.acknowledgedEnvelope).config
            .makePolicyEnvironment(homeDirectory: rig.home.path, detectedTools: [])

        for _ in 0..<32 {
            let consent = try rig.scopeAuthority.issueFullHomeConsent(ownerID: rig.ownerID)
            #expect(rig.scopeAuthority.retainedConsentCountForTesting == 1)
            let authorization = try rig.scopeAuthority.authorizeFullHome(
                consent: consent, ownerID: rig.ownerID)
            #expect(rig.scopeAuthority.retainedConsentCountForTesting == 0)
            #expect(rig.scopeAuthority.retainedGrantCountForTesting == 1)
            try authorization.consumeForStart(ownerID: rig.ownerID, environment: environment)
            #expect(rig.scopeAuthority.retainedGrantCountForTesting == 0)
            #expect(throws: ScanScopeAuthorizationError.consumedConsent) {
                try rig.scopeAuthority.authorizeFullHome(consent: consent, ownerID: rig.ownerID)
            }
            #expect(throws: ScanScopeAuthorizationError.consumedConsent) {
                try authorization.consumeForStart(ownerID: rig.ownerID, environment: environment)
            }
        }
    }

    @Test("full-home consent is consumed before failed root capture")
    @MainActor
    func fullHomeRootCaptureFailureStillConsumesConsent() async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [])
        defer { rig.remove() }
        let consent = try rig.scopeAuthority.issueFullHomeConsent(ownerID: rig.ownerID)
        let moved = rig.root.appendingPathComponent("moved-home", isDirectory: true)
        try FileManager.default.moveItem(at: rig.home, to: moved)

        #expect(throws: ScanScopeAuthorizationError.invalidRoot) {
            try rig.scopeAuthority.authorizeFullHome(consent: consent, ownerID: rig.ownerID)
        }
        #expect(rig.scopeAuthority.retainedConsentCountForTesting == 0)
        #expect(throws: ScanScopeAuthorizationError.consumedConsent) {
            try rig.scopeAuthority.authorizeFullHome(consent: consent, ownerID: rig.ownerID)
        }
    }

    @Test("root replacement after authorization is rejected before traversal")
    @MainActor
    func rootReplacementInvalidatesGrant() async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [])
        defer { rig.remove() }
        let cache = rig.home.appendingPathComponent("Library/Caches/typescript", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let authorization = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        await #expect(throws: ScanScopeAuthorizationError.invalidRoot) {
            _ = try await rig.run(authorization: authorization,
                visits: ScanMetadataVisitRecorder())
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

    @Test("event after guard consumption invalidates the published cursor at suspension")
    @MainActor
    func continuationGuardIsConsumedInsideScanEngineHandoff() async throws {
        let rig = try await ScanScopeRig.make(defaultScope: "quick", gitRoots: [])
        defer { rig.remove() }
        let cache = rig.home.appendingPathComponent("Library/Caches/typescript", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for name in ["a-visited.bin", "m-pending.bin", "z-pending.bin"] {
            try Data(repeating: 1, count: 4_096).write(to: cache.appendingPathComponent(name))
        }
        let authorization = try rig.scopeAuthority.authorizePolicyDefault(ownerID: rig.ownerID)
        let environment = rig.bridge.acknowledgedEnvelope!.config.makePolicyEnvironment(
            homeDirectory: rig.home.path, detectedTools: [])
        let sessions = rig.bridge.explicitSessions
        let work = try await sessions.beginSession(
            requirements: try SchedulerRequirements(features: [.headroom]))
        defer { Task { await sessions.finish(session: work) } }
        let registry = ScanSessionRegistry()
        let source = FakeScanEventSource()
        let dbURL = rig.root.appendingPathComponent("continuation-index.sqlite")
        let store = try ScanIndexStore(databaseURL: dbURL)
        let index = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: source))
        let volumeUUID = try #require(ScanRootIdentity.resolve(path: authorization.roots[0]))
            .volumeUUID
        try await store.persistCursor(volumeUUID: volumeUUID, cursor: 0,
            deviceUUID: "fixture-device")
        await index.startWatching(approvedRoots: authorization.roots, volumeUUID: volumeUUID)
        let limits = try TraversalLimits(batchEntries: 1).withTestingBatchLimitPerSlice(2)
        let changedPath = cache.appendingPathComponent("a-visited.bin").path
        let dependencies = CoreScanDependencies(processProbe: { _, _ in .availableEmpty },
            testHook: { point in
                if point == .afterContinuationGuardConsumed {
                    await source.emit(events: [ScanEvent(path: changedPath)],
                        historyReliable: true)
                }
            }, metadataVisit: nil)
        let first = try await ScanEngine.start(environment: environment,
            authorization: authorization, ownerID: rig.ownerID, registry: registry,
            sessions: sessions, session: work, traversalLimits: limits,
            dependencies: dependencies, indexCoordinator: index)
        let firstSubscription = try await registry.subscribe(sessionID: first.sessionID)
        for await event in firstSubscription.stream where event.terminal != nil { break }
        #expect((await first.latestResult())?.continuationAvailable == true)

        #expect(await index.suspendWatchingForManualContinuation())
        let watchGuard = try #require(await index.resumeWatchingForManualContinuation())
        let continued = try await ScanEngine.continueScan(from: first, registry: registry,
            watchGuard: watchGuard)
        let continuedSubscription = try await registry.subscribe(sessionID: continued.sessionID)
        for await event in continuedSubscription.stream where event.terminal != nil { break }
        let result = try #require(await continued.latestResult())
        #expect(!result.coverage.isComplete)
        #expect(result.continuationAvailable)
        #expect(!(await index.suspendWatchingForManualContinuation()),
            "publication-to-suspension event must reject the newly retained cursor")
        await continued.discardContinuation()
        await #expect(throws: CoreOrchestrationError.invalidScopeAuthorization) {
            _ = try await ScanEngine.continueScan(from: continued, registry: registry)
        }
        await index.stopWatching()
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
