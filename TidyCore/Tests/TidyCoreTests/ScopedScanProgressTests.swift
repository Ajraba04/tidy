import Foundation
import Testing
@testable import TidyCore

private actor ScopedProgressEndGate {
    private var reached = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?

    func visit(_ path: String) async {
        guard path.hasSuffix("/zz-end") else { return }
        reached = true
        waiting?.resume(); waiting = nil
        await withCheckedContinuation { blocked = $0 }
    }

    func wait() async {
        if reached { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func release() { blocked?.resume(); blocked = nil }
}

@Suite("Scoped scan live aggregate progress", .serialized)
struct ScopedScanProgressTests {
    enum Ending: CaseIterable { case complete, cancel, policyChange }

    @Test("actual scoped totals are visible before the last batch and invalidation cannot complete",
          arguments: Ending.allCases)
    @MainActor
    func usefulProgressPrecedesEndGate(ending: Ending) async throws {
        let rig = try await TraversalBridgeRig.make()
        let payload = rig.root.appendingPathComponent("aa-payload")
        try Data(repeating: 7, count: 16_384).write(to: payload)
        try Data(repeating: 3, count: 4_096).write(to: rig.root.appendingPathComponent("zz-end"))
        let scopeOwner = ScanScopeAuthority(bridge: rig.bridge, homeDirectory: rig.root.path)
        let ownerID = UUID()
        let consent = try scopeOwner.issueFullHomeConsent(ownerID: ownerID)
        let scope = try scopeOwner.authorizeFullHome(consent: consent, ownerID: ownerID)
        let envelope = try #require(rig.bridge.acknowledgedScanEnvelope)
        let environment = envelope.config.makePolicyEnvironment(
            homeDirectory: rig.root.path, detectedTools: [])
        let registry = ScanSessionRegistry()
        let gate = ScopedProgressEndGate()
        let handle = try await ScanEngine.start(environment: environment,
            authorization: scope, ownerID: ownerID, registry: registry,
            sessions: rig.sessions, session: rig.session,
            traversalLimits: try standardLimits(batchEntries: 1),
            dependencies: CoreScanDependencies(processProbe: { _, _ in .availableEmpty },
                testHook: nil, metadataVisit: { await gate.visit($0) }))
        let subscription = try await registry.subscribe(sessionID: handle.sessionID)
        await gate.wait()

        let inFlight = try await registry.state(sessionID: handle.sessionID)
        let partial = await handle.latestResult()
        #expect(inFlight.terminal == nil)
        #expect(inFlight.snapshot.processedEntries > 0)
        #expect(inFlight.snapshot.totalBytes > 0)
        #expect(partial != nil)
        #expect(partial?.coverage.isComplete == false)
        #expect(partial?.continuationAvailable == false)
        #expect(partial?.report.topLevelHomeRanking.contains {
            PathGuard.canonicalize($0.path) == PathGuard.canonicalize(rig.root.path)
                && $0.bytes > 0
        } == true)

        switch ending {
        case .complete: break
        case .cancel: try await registry.cancel(sessionID: handle.sessionID)
        case .policyChange:
            let id = SettingID(rawValue: "feature.headroom")
            let admission = rig.bridge.submit(global: .init(baseRevision: envelope.revision,
                id: id, baseValue: envelope.preferences?.global.fields[id], editedValue: .bool(false)))
            if case .accepted(_, let completion) = admission { _ = await completion.value }
            else { Issue.record("Policy invalidation was not admitted") }
        }
        await gate.release()
        var terminalEvents = 0
        for await event in subscription.stream where event.terminal != nil {
            terminalEvents += 1
        }
        #expect(terminalEvents == 1)
        let final = try #require(await handle.latestResult())
        let terminal = try await registry.state(sessionID: handle.sessionID)
        switch ending {
        case .complete:
            #expect(terminal.terminal == .complete)
            #expect(final.coverage.isComplete)
            #expect(final.report.topLevelHomeRanking.filter {
                PathGuard.canonicalize($0.path) == PathGuard.canonicalize(rig.root.path)
            }.count == 1)
        case .cancel, .policyChange:
            #expect(terminal.terminal != .complete)
            #expect(!final.coverage.isComplete)
        }
        await subscription.cancel()
        await rig.cleanup()
    }
}
