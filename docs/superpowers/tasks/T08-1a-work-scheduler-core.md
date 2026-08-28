# T08.1a — Work-scheduler core and exact-envelope resolution

> **Status:** PREIMPLEMENTATION. Depends on committed T08 entry `24f8091`, as amended to split T08.1a/T08.1b. This card authorizes no source/test work. It requires separate approval, observed RED/GREEN, verification, and adversarial review.

## Outcome and boundary

Create an initially unavailable, bounded filesystem scheduler, a synchronous admission barrier, and an internal nonforgeable policy controller. The controller accepts an exact `SettingsEnvelope` plus the one existing-owner machine fact in `SchedulerResolutionInputs`: logical CPU count. It independently constructs neutral-scope `PolicyInputs`, calls production `PolicyResolver.resolve`, and uses production `PreferencesDocumentEffect.classify(previous,candidate)` as one classification input. It never accepts caller-supplied `EffectivePolicy`, `AuthorityEffect`, worker cap, admission, or resolved snapshot.

T08.1a has no persistence integration or durability claim. The invalidating `prepare` path is bound to a synchronously closed admission ticket. A separately bound async `preparePresentation` path never closes admission and may succeed only after independently validating and resolving an exact candidate whose production classifier is `.none` and whose scheduler execution identity exactly equals the acknowledged identity. `commit` accepts an exact acknowledged envelope supplied by the future owner; invalidating `fail` stays closed, while a rejected presentation candidate cannot install anything. T08.1b is the only approved real owner connecting these calls to `ExecutionPolicyBridge` and actual `SettingsStore` outcomes.

This checkpoint performs no filesystem I/O, process launch, traversal, system observation, detached task, timer, app wiring, UI, background work, or mutation. It creates no singleton.

## Exact allowlist

Implementation may change only:

- create `TidyCore/Sources/TidyCore/Scanning/WorkScheduler.swift`
- create `TidyCore/Tests/TidyCoreTests/WorkSchedulerTests.swift`
- create `docs/verification/T08-1a-work-scheduler-core.md` only after GREEN

SwiftPM discovers both Swift files automatically. Do not edit policy, settings, bridge, engine, app, package, PBX, other tests, the entry card, or other documentation during implementation.

## Closed features, explicit local inputs, and production resolution

```text
public enum SchedulerFeature: String, CaseIterable, Hashable, Sendable {
    case headroom, buildPrep, projects, rescue, ecosystems, budgets, history, maintenance
}

public struct SchedulerRequirements: Hashable, Sendable {
    public let features: Set<SchedulerFeature>
    public init(features: Set<SchedulerFeature>) throws // nonempty
}

internal struct SchedulerResolutionInputs: Equatable, Sendable {
    let logicalCPUCount: Int
    init(logicalCPUCount: Int) throws
}

internal enum SchedulerObservation: Equatable, Sendable {
    case unknown, nominal, constrained, critical
}
```

The closed feature cases exactly match the current finite `EffectivePolicy.allowedFeatures` universe. Unknown allowed-feature strings reject; they are never ignored. Session requirements contain no arbitrary string and must be nonempty.

`SchedulerResolutionInputs` is the only supplied resolution context. It validates logical CPU `1...1_024`. It contains no project/volume/capacity/exclusion, layers, preferences, active profile, worker/process value, admission, effect, settings revision, observation, or policy. Project selection, volume/capacity, and traversal exclusions belong to T08.2/T08.4 session/scope owners.

For every prepare/observation resolution the controller constructs layers exactly:

1. global = `candidate.preferences?.global ?? PolicyValues()`;
2. profile = the single profile whose ID equals `candidate.activeProfileID`; missing or duplicate active profile fails closed; no active ID means no profile layer;
3. project layer is absent; `selectedVolumeID=nil`, `approvedVolumeIDs=[]`, `capacityBytes=nil`, and `mandatoryExclusions=[]` are passed exactly;
4. logical CPU comes from `SchedulerResolutionInputs`;
5. it calls `PolicyResolver.resolve` exactly once and retains that returned `EffectivePolicy` as the operative resolution.

Before resolution it requires current schema, nonzero revision, unique profile IDs, valid active selection, and `SettingsTransfer.validatePersistedState` for preferences/inert imports. Invalid portable/authority values, layers, identities, duplicates, or resolver errors fail closed. It does not duplicate resolver preset, feature, restriction, CPU, or pressure arithmetic. Projects and volume/capacity are deliberately not scheduler inputs; their edits are proven scheduler-irrelevant in RED and remain owned by later scope checkpoints.

Observation maps to production `PolicyInputs`:

- nominal: `lowPower=false`, `seriousThermal=false`, `critical=false`;
- constrained: both conservative constraints true and critical false, so production restrictions decide pause versus explicit-only;
- critical: critical true, so production resolution must return paused and zero walk/process budgets;
- unknown: resolve nominal through production, then apply only the documented fallback clamp of at most one walk worker and explicit-only; a production-resolved pause remains paused.

The scheduler snapshot carries settings revision, observation epoch, resolved policy identity, enabled closed features, walk/process budgets, admission, exact integer `scan.sliceSeconds` (`30...1_800`), and exact `scan.uiBatchesPerSecond` (`1...4`). Missing/wrong effective fields or mismatch with convenience budgets fail closed.

## Internal authority and exact API

`WorkScheduler`, `SchedulerPolicyController`, `SchedulerPolicyControllerCapability`, and `PreparedSchedulerPolicy` are created together by one internal factory. The capability/token/session/cancellation probe have private nonces and no public/memberwise initializer. A token/handle from another factory is inert.

The factory also binds an internal `SchedulerAdmissionBarrier`, analogous to `PolicyInvalidationBarrier`: a lock-backed `@unchecked Sendable` synchronous gate with a nonforgeable controller capability and checked monotonic transition ticket. `SchedulerPolicyController.beginAdmissionTransition(using:)` is `nonisolated` and synchronous. It closes admission before returning its ticket. `WorkScheduler.beginSession` checks the barrier before and inside actor admission; `withPermit` checks before enqueue, before grant, and immediately before the closure. No actor queue can admit while the barrier is updating/unavailable even if controller preparation has not run yet.

```text
internal actor SchedulerPolicyController {
    static func make(inputs: SchedulerResolutionInputs,
                     limits: WorkSchedulerLimits) throws
      -> (controller: SchedulerPolicyController,
          scheduler: WorkScheduler,
          capability: SchedulerPolicyControllerCapability)

    nonisolated func beginAdmissionTransition(
                 using: SchedulerPolicyControllerCapability) throws
      -> SchedulerAdmissionTicket

    func prepare(_ admission: SchedulerAdmissionTicket,
                 candidate: SettingsEnvelope,
                 observation: SchedulerObservation,
                 using: SchedulerPolicyControllerCapability) async
      -> SchedulerPrepareResult

    func preparePresentation(candidate: SettingsEnvelope,
                 observation: SchedulerObservation,
                 using: SchedulerPolicyControllerCapability) async
      -> SchedulerPresentationPrepareResult

    func commitPresentation(_ prepared: PreparedSchedulerPresentation,
                acknowledgedEnvelope: SettingsEnvelope,
                using: SchedulerPolicyControllerCapability) async
      -> SchedulerCommitResult

    func discardPresentation(_ prepared: PreparedSchedulerPresentation,
                using: SchedulerPolicyControllerCapability) async
      -> SchedulerPresentationDiscardResult

    func commit(_ prepared: PreparedSchedulerPolicy,
                acknowledgedEnvelope: SettingsEnvelope,
                using: SchedulerPolicyControllerCapability) async
      -> SchedulerCommitResult

    func fail(_ prepared: PreparedSchedulerPolicy,
              using: SchedulerPolicyControllerCapability) async
      -> SchedulerFailResult

    func updateObservation(epoch: UInt64,
                 observation: SchedulerObservation,
                 acknowledgedEnvelope: SettingsEnvelope,
                 using: SchedulerPolicyControllerCapability) async
      -> SchedulerObservationResult

    func issueExplicitCapability(requirements: SchedulerRequirements,
                 using: SchedulerPolicyControllerCapability) async throws
      -> ExplicitWorkCapability

    func beginDiscretionarySession(requirements: SchedulerRequirements,
                 using: SchedulerPolicyControllerCapability) async throws
      -> WorkSession
}

public actor WorkScheduler {
    public func beginSession(requirements: SchedulerRequirements,
                             capability: ExplicitWorkCapability) async throws -> WorkSession
    public func withPermit<T: Sendable>(session: WorkSession,
        operation: @Sendable (SchedulerCancellationProbe) async throws -> T
    ) async throws -> T
    public func cancel(session: WorkSession) async
    public func finish(session: WorkSession) async
    public func state(of: WorkSession) -> WorkSessionState?
    public func snapshot() -> WorkSchedulerSnapshot
}
```

There is no public/internal `prepare(policy:)`, supplied-effect argument, public `update`, public explicit/discretionary boolean, public controller/barrier capability, public lease/grant/release, or alternate initializer of an operative scheduler. Admission tickets are controller-bound, single-use, superseding, and accepted by invalidating `prepare` only while they are the barrier's current closed transition. `PreparedSchedulerPresentation` is a distinct controller-bound, single-use type that never carries an admission ticket and cannot be passed to invalidating `commit`/`fail`; only `commitPresentation` with the exact acknowledged candidate may install it, while `discardPresentation` consumes it after save failure/cancellation without changing operative scheduler state.

Explicit capability issuance requires an operative acknowledged envelope, exact enabled requirements, and non-paused explicit admission. It is single-use and bound to controller/scheduler nonce, settings revision, observation epoch, scheduler generation, and exact requirements. Stale, consumed, foreign, disabled, or wrong-requirements capability rejects before session accounting or closure invocation. Discretionary creation stays internal and requires resolved `.discretionaryAllowed`.

## Prepare, commit, fail, and observation epochs

Initial state is unavailable, settings revision nil, observation epoch zero, generation zero, zero work admission.

`prepare` independently validates/resolves candidate behind the current closed admission ticket. First install is always invalidating. Later it computes `PreferencesDocumentEffect.classify(before:acknowledged, after:candidate)` and also compares exact scheduler execution identity between independently resolved previous/candidate envelopes. Identity is enabled closed features, resolved walk/process budgets, admission, slice seconds, and every scope/exclusion value actually consumed by T08.1a (currently none). Any identity change is invalidating even if the classifier returns `.none`; the classifier is never the sole safety decision. Classifier `.none` plus identity equality makes a candidate eligible for the separately typed core presentation path, but does not authorize an integration caller to choose that path; T08.1b narrows it to the exact typed rate delta.

Before either prepare path resolves or compares identity, the four legacy compatibility pairs must obey production canonical projection semantics, using `PolicyPreferences.project(legacy:saved:)` and `LegacyCompatibilityProjection.reverseProject` rather than duplicated mapping arithmetic: `config.keepCookieDomains` ↔ `browsers.keepCookieDomains`, `config.transcriptAgeThresholdDays` ↔ `cleanup.transcriptDays`, `config.staleNodeModulesThresholdDays` ↔ `item.normal.extras.stale-node-modules.inactiveDays`, and `config.allowRestartToReclaimSwap` ↔ `rescue.showAdvancedMemoryActions`. The exact config defaults are `[]`, `45`, `60`, and `false`; only those defaults permit the corresponding global field to be absent. A present global field requires the exact canonical `SettingValue` tag and value, and reverse-projecting that global must reproduce the exact config field. Config-only non-default, global-only non-default, wrong tag, wrong value, or reverse-projection mismatch fails closed. Exact non-default lockstep is valid and conservatively invalidating on the closing path.

Candidate revision must be strictly greater than the last acknowledged revision. Invalidating prepare returns a single-use token bound to exact candidate equality/digest, resolution inputs, observation, controller nonce, barrier admission ticket, and preparation generation. Presentation prepare returns its distinct token bound to the same exact candidate/resolution/observation/controller/current-acknowledgement identity but no barrier ticket; a newer transition or observation epoch supersedes it.

Invalidating prepare synchronously freezes affected admission before returning. Feature loss cancels sessions requiring a lost feature; slice change cancels all scan sessions; discretionary→user-requested cancels discretionary sessions only. Cap-only changes do not cancel. Paused/zero freezes explicit queued work and lets active explicit work drain.

`preparePresentation` independently repeats full persisted-state, compatibility, active-profile, production-resolution, classifier, revision, and exact-candidate validation without touching the barrier or scheduler state. It returns a presentation token only when `PreferencesDocumentEffect.classify` is exactly `.none` and the full scheduler execution identity equals the acknowledged identity. Malformed, first-install, authority, legacy, invalidating, or identity-changing candidates reject before save and cannot install. A successfully prepared candidate does not freeze, cancel, reorder, change scheduler generation, or invalidate an otherwise current explicit capability while awaiting acknowledgement; commit changes only revision and presentation fields. The core does not inspect an edit-route claim. T08.1b alone may invoke this path, and only for the exact typed global `scan.uiBatchesPerSecond` delta; document/import/legacy/project/active-profile/other-global routes remain conservatively closing even if their eventual classifier/identity happens to be equal.

Invalidating `commit` accepts only the exact prepared candidate as `acknowledgedEnvelope` and atomically opens the barrier for the installed scheduler generation. Mismatch, foreign token, superseded token, reused token, stale revision, or late commit after fail rejects and cannot reopen. Invalidating `fail` consumes the token and leaves the barrier closed; late acknowledgement after failure cannot commit. `commitPresentation` accepts only its exact still-current acknowledged candidate, advances acknowledged revision/presentation fields without touching the barrier or scheduler generation, and consumes the token. `discardPresentation` consumes without install; late/reused/foreign/superseded presentation commit rejects and cannot mutate admission. A newer valid admission transition/prepare/commit can recover. T08.1a does not claim who may truthfully call either commit; T08.1b binds those calls to actual save success.

Only one prepared token is current. A newer valid prepare supersedes the old token. Malformed prepare, impossible effect classification, checked generation/epoch/waiter overflow, or internal inconsistency fail closed without trap/wrap.

Observation update is not a settings update. It requires: exact equality with the current acknowledged envelope, same explicit `SchedulerResolutionInputs`, epoch strictly greater than current, controller capability, and no settings prepare in flight. It re-runs production resolution over the same envelope. Stale/same epoch rejects. It never increments or fabricates settings revision. Unknown/constrained/critical/nominal transitions update admission/budgets monotonically by epoch; critical pauses, constrained respects real restrictions, unknown is conservative, and nominal recovery reopens eligible oldest FIFO work. Observation generation uses checked arithmetic.

## Caps, FIFO, cancellation, and reclamation

Limits are sessions `1...64`, total queued `1...256`, per-session queued `1...32`, tombstones `0...64`; per-session cannot exceed total. Global eligible order is strict FIFO. New/reacquired work joins the tail. Queue/session overflow rejects before retaining a continuation or running a closure.

Exact cap transitions:

- `4→1`: no cancellation; active drains, grants resume below one;
- `2→0`: no active cancellation; active drains and queued remains frozen;
- `0→1`: oldest eligible queued waiter grants;
- `1→4`: fill slots in preserved FIFO order; new arrivals cannot leapfrog;
- paused→explicit-only: oldest explicit waiter resumes; discretionary remains rejected.

Permits are internal/nonforgeable/exact-release. Each suspension revalidates nonce, settings revision, observation epoch, generation, requirements, cancellation, admission, and FIFO head. Caller cancellation at acquiring/enqueued/granting/before-operation/active releases exactly once; closure never runs in the first four cases. Active scheduler cancel marks the probe; it does not cancel caller Task. Cancel/finish are idempotent and automatically reclaim live session accounting after queue/active drain. Terminal tombstones are FIFO-capped and do not consume the 64 live-session limit; evicted state returns nil. Checked overflow fails closed.

## Deterministic RED seam

An internal test-only hook, accepted only by `makeForTesting`, emits checked waiter IDs and may suspend at `.acquiring`, `.enqueued`, `.granting`, `.operationStarting`, `.released`, and `.presentationPrepared(revision:)` immediately before returning a valid non-closing token. Tests arm/wait/release actor continuations; no Task start-order assumption, sleep, timeout synchronization, unbounded `Task.yield`, or polling loop is allowed.

## Complete RED test file

Create this file verbatim first. Focused compilation must fail only on the missing approved T08.1a declarations. Any fixture-only compile correction requires a dated card amendment.

```swift
import Foundation
import Testing
@testable import TidyCore

private func id(_ raw: String) -> SettingID { SettingID(rawValue: raw) }
private func values(_ pairs: [(String, SettingValue)]) -> PolicyValues {
    PolicyValues(fields: Dictionary(uniqueKeysWithValues: pairs.map { (id($0.0), $0.1) }))
}

private let profileID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

private func envelope(_ revision: UInt64, workers: Int64 = 2, processes: Int64 = 2,
    slice: Int64 = 300, rate: Int64 = 4, active: UUID? = profileID,
    projectDays: Int64 = 41) -> SettingsEnvelope {
    let project = [("cleanup.inactiveDays", SettingValue.integer(projectDays))]
    let global = values([
        ("scan.preset", .choice("custom")),
        ("scan.requestedWorkers", .integer(workers)),
        ("scan.readOnlyProcesses", .integer(processes)),
        ("scan.sliceSeconds", .integer(slice)),
        ("scan.uiBatchesPerSecond", .integer(rate)),
        ("feature.projects", .bool(true))
    ])
    let profile = SavedProfile(id: profileID, name: "Low spec", values: values([
        ("scan.preset", .choice("custom")),
        ("scan.requestedWorkers", .integer(workers)),
        ("scan.readOnlyProcesses", .integer(processes)),
        ("cleanup.inactiveDays", .integer(55))
    ]))
    return SettingsEnvelope(schemaVersion: 2, revision: revision,
        config: TidyConfig(schemaVersion: 2),
        preferences: PolicyPreferences(global: global, profiles: [profile],
            projects: ["project-a": values(project)]), activeProfileID: active)
}

private func inputs() throws -> SchedulerResolutionInputs {
    try SchedulerResolutionInputs(logicalCPUCount: 8)
}

private actor Hook: SchedulerTestHook {
    private var seen: [SchedulerTestEvent] = []
    private var waiters: [SchedulerTestEvent: CheckedContinuation<Void, Never>] = [:]
    private var blocked: Set<SchedulerTestEvent> = []
    private var releases: [SchedulerTestEvent: CheckedContinuation<Void, Never>] = [:]
    func block(_ event: SchedulerTestEvent) { blocked.insert(event) }
    func receive(_ event: SchedulerTestEvent) async {
        seen.append(event); waiters.removeValue(forKey: event)?.resume()
        if blocked.remove(event) != nil { await withCheckedContinuation { releases[event] = $0 } }
    }
    func wait(_ event: SchedulerTestEvent) async {
        if seen.contains(event) { return }
        await withCheckedContinuation { waiters[event] = $0 }
    }
    func release(_ event: SchedulerTestEvent) { releases.removeValue(forKey: event)?.resume() }
    func events() -> [SchedulerTestEvent] { seen }
}

private actor Gate {
    private var entered: [Int] = []
    private var active = 0
    private var highWater = 0
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var holds: [Int: CheckedContinuation<Void, Never>] = [:]
    private var probes: [Int: SchedulerCancellationProbe] = [:]
    func hold(_ value: Int, _ probe: SchedulerCancellationProbe) async throws {
        entered.append(value); active += 1; highWater = max(highWater, active)
        probes[value] = probe; waiters.removeValue(forKey: value)?.resume()
        await withCheckedContinuation { holds[value] = $0 }
        active -= 1
        try await probe.checkCancellation()
    }
    func wait(_ value: Int) async {
        if entered.contains(value) { return }
        await withCheckedContinuation { waiters[value] = $0 }
    }
    func release(_ value: Int) { holds.removeValue(forKey: value)?.resume() }
    func cancelled(_ value: Int) async -> Bool { await probes[value]?.isCancelled() ?? false }
    func order() -> [Int] { entered }
    func peak() -> Int { highWater }
}

private struct Rig {
    let controller: SchedulerPolicyController
    let scheduler: WorkScheduler
    let owner: SchedulerPolicyControllerCapability
    let hook: Hook
    static func make(generation: UInt64 = 0, epoch: UInt64 = 0, waiterID: UInt64 = 0,
                     limits: WorkSchedulerLimits = try! .init()) throws -> Rig {
        let hook = Hook()
        let made = try SchedulerPolicyController.makeForTesting(inputs: inputs(), limits: limits,
            initialGeneration: generation, initialObservationEpoch: epoch,
            initialWaiterID: waiterID, hook: hook)
        return Rig(controller: made.controller, scheduler: made.scheduler,
                   owner: made.capability, hook: hook)
    }
    func install(_ candidate: SettingsEnvelope,
                 observation: SchedulerObservation = .nominal) async throws {
        let prepared = try await prepare(candidate, observation: observation)
        let token = try #require(prepared.token)
        #expect(await controller.commit(token, acknowledgedEnvelope: candidate, using: owner) ==
                .committed(settingsRevision: candidate.revision))
    }
    func prepare(_ candidate: SettingsEnvelope,
                 observation: SchedulerObservation = .nominal) async throws
      -> SchedulerPrepareResult {
        let admission = try controller.beginAdmissionTransition(using: owner)
        return await controller.prepare(admission, candidate: candidate,
            observation: observation, using: owner)
    }
    func preparePresentation(_ candidate: SettingsEnvelope,
                 observation: SchedulerObservation = .nominal) async
      -> SchedulerPresentationPrepareResult {
        await controller.preparePresentation(candidate: candidate,
            observation: observation, using: owner)
    }
    func session(_ features: Set<SchedulerFeature> = [.projects]) async throws -> WorkSession {
        let requirements = try SchedulerRequirements(features: features)
        let capability = try await controller.issueExplicitCapability(
            requirements: requirements, using: owner)
        return try await scheduler.beginSession(requirements: requirements, capability: capability)
    }
}

@Suite(.serialized)
struct WorkSchedulerTests {
    @Test func tenSessionsShareOneExactAggregateCap() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 4))
        let gate = Gate(); var sessions: [WorkSession] = []
        for _ in 0..<10 { sessions.append(try await rig.session()) }
        var tasks: [Task<Void, Error>] = []
        for index in sessions.indices {
            let task = Task { try await rig.scheduler.withPermit(session: sessions[index]) {
                try await gate.hold(index, $0)
            } }
            tasks.append(task)
            if index < 4 { await gate.wait(index) }
            else { await rig.hook.wait(.enqueued(UInt64(index + 1))) }
        }
        #expect(await gate.peak() == 4)
        for index in sessions.indices {
            await gate.release(index)
            if index + 4 < sessions.count { await gate.wait(index + 4) }
            #expect(await gate.peak() == 4)
        }
        for task in tasks { _ = try? await task.value }
        #expect(await rig.scheduler.snapshot().active == 0)
    }

    @Test func realEnvelopeSelectsGlobalAndActiveProfileWithNeutralScopeInputs() async throws {
        let rig = try Rig.make(); let candidate = envelope(1, workers: 1, projectDays: 41)
        try await rig.install(candidate)
        let resolved = try #require(await rig.controller.resolvedPolicyForTesting(using: rig.owner))
        #expect(resolved.walkWorkers == 1)
        #expect(resolved.fields[id("cleanup.inactiveDays")]?.value == .stored(.integer(55)))
        #expect(await rig.scheduler.snapshot().settingsRevision == 1)

        let missingActive = envelope(2, active: UUID())
        #expect(try await rig.prepare(missingActive) == .failedClosed(.invalidActiveProfile))
    }

    @Test func projectDocumentsAreExplicitlySchedulerIrrelevantButActiveProfileIsNot() async throws {
        let rig = try Rig.make(); let first = envelope(1, workers: 2)
        try await rig.install(first)
        var changedProjects = first.preferences!
        changedProjects.projects["project-a"] = values([("cleanup.inactiveDays", .integer(99))])
        changedProjects.projects["project-b"] = values([("cleanup.inactiveDays", .integer(12))])
        let projectOnly = SettingsEnvelope(schemaVersion: 2, revision: 2, config: first.config,
            preferences: changedProjects, activeProfileID: first.activeProfileID)
        let generation = await rig.scheduler.snapshot().generation
        let projectPrepared = await rig.preparePresentation(projectOnly)
        #expect(projectPrepared.effect == .none)
        let projectToken = try #require(projectPrepared.token)
        #expect(await rig.controller.commitPresentation(projectToken, acknowledgedEnvelope: projectOnly,
            using: rig.owner) == .committed(settingsRevision: 2))
        #expect(await rig.scheduler.snapshot().generation == generation)

        let otherID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        var activePreferences = changedProjects
        activePreferences.profiles.append(SavedProfile(id: otherID, name: "Other", values: values([
            ("scan.preset", .choice("custom")), ("scan.requestedWorkers", .integer(1)),
            ("scan.readOnlyProcesses", .integer(1))
        ])))
        let activeChanged = SettingsEnvelope(schemaVersion: 2, revision: 3, config: first.config,
            preferences: activePreferences, activeProfileID: otherID)
        let activePrepared = try await rig.prepare(activeChanged)
        #expect(activePrepared.effect == .invalidate)
    }

    @Test func legacyCompatibilityRequiresExactFourPairLockstep() async throws {
        typealias Mutation = (inout TidyConfig) -> Void
        let cases: [(raw: String, value: SettingValue, wrongTag: SettingValue,
                     wrongValue: SettingValue, mutate: Mutation)] = [
            ("browsers.keepCookieDomains", .strings(["example.com"]), .bool(true),
             .strings(["other.example"]), { $0.keepCookieDomains = ["example.com"] }),
            ("cleanup.transcriptDays", .integer(46), .bool(true), .integer(47),
             { $0.transcriptAgeThresholdDays = 46 }),
            ("item.normal.extras.stale-node-modules.inactiveDays", .integer(61),
             .strings(["61"]), .integer(62), { $0.staleNodeModulesThresholdDays = 61 }),
            ("rescue.showAdvancedMemoryActions", .bool(true), .integer(1), .bool(false),
             { $0.allowRestartToReclaimSwap = true })
        ]
        let defaults = TidyConfig(schemaVersion: 2)
        #expect(defaults.keepCookieDomains == [])
        #expect(defaults.transcriptAgeThresholdDays == 45)
        #expect(defaults.staleNodeModulesThresholdDays == 60)
        #expect(defaults.allowRestartToReclaimSwap == false)
        let defaultProjection = PolicyPreferences.project(legacy: defaults, saved: nil)

        for row in cases {
            #expect(defaultProjection.global.fields[id(row.raw)] == nil)
            let defaultRig = try Rig.make()
            try await defaultRig.install(envelope(1)) // default config + absent global is canonical

            var nondefault = defaults; row.mutate(&nondefault)
            let basePreferences = envelope(1).preferences!
            func candidate(_ config: TidyConfig, _ globalValue: SettingValue?) -> SettingsEnvelope {
                var preferences = basePreferences
                preferences.global.fields[id(row.raw)] = globalValue
                return SettingsEnvelope(schemaVersion: 2, revision: 2, config: config,
                    preferences: preferences, activeProfileID: profileID)
            }

            let configOnly = try Rig.make(); try await configOnly.install(envelope(1))
            #expect(try await configOnly.prepare(candidate(nondefault, nil)) ==
                    .failedClosed(.legacyCompatibilityMismatch))

            let globalOnly = try Rig.make(); try await globalOnly.install(envelope(1))
            #expect(try await globalOnly.prepare(candidate(defaults, row.value)) ==
                    .failedClosed(.legacyCompatibilityMismatch))

            let wrongTag = try Rig.make(); try await wrongTag.install(envelope(1))
            #expect(try await wrongTag.prepare(candidate(nondefault, row.wrongTag)) ==
                    .failedClosed(.legacyCompatibilityMismatch))

            let wrongValue = try Rig.make(); try await wrongValue.install(envelope(1))
            #expect(try await wrongValue.prepare(candidate(nondefault, row.wrongValue)) ==
                    .failedClosed(.legacyCompatibilityMismatch))

            let validRig = try Rig.make(); try await validRig.install(envelope(1))
            let projected = PolicyPreferences.project(legacy: nondefault, saved: basePreferences)
            #expect(projected.global.fields[id(row.raw)] == row.value)
            #expect(LegacyCompatibilityProjection.reverseProject(defaults, replacing: nil,
                with: projected.global) == nondefault)
            let valid = SettingsEnvelope(schemaVersion: 2, revision: 2, config: nondefault,
                preferences: projected, activeProfileID: profileID)
            let prepared = try await validRig.prepare(valid)
            #expect(prepared.effect == .invalidate)
            let token = try #require(prepared.token)
            #expect(await validRig.controller.commit(token, acknowledgedEnvelope: valid,
                using: validRig.owner) == .committed(settingsRevision: 2))
        }
    }

    @Test func malformedInputsDuplicateProfilesStaleAuthorityAndLayerMatricesFailClosed() async throws {
        #expect(throws: WorkSchedulerError.invalidResolutionInputs) {
            try SchedulerResolutionInputs(logicalCPUCount: 0)
        }
        #expect(throws: WorkSchedulerError.invalidResolutionInputs) {
            try SchedulerResolutionInputs(logicalCPUCount: 1_025)
        }
        let duplicateRig = try Rig.make(); var duplicates = envelope(1).preferences!
        duplicates.profiles.append(duplicates.profiles[0])
        let duplicate = SettingsEnvelope(schemaVersion: 2, revision: 1,
            config: envelope(1).config, preferences: duplicates, activeProfileID: profileID)
        #expect(try await duplicateRig.prepare(duplicate) == .failedClosed(.duplicateProfileID))

        let staleRig = try Rig.make(); try await staleRig.install(envelope(2))
        #expect(try await staleRig.prepare(envelope(2)) == .rejected(.staleRevision(current: 2)))

        for (layer, bad) in [
            ("authority", values([("scope.projectRoots", .strings(["/tmp/project"]))])),
            ("project-layer", values([("scan.requestedWorkers", .integer(2))]))
        ] {
            let rig = try Rig.make(); var preferences = envelope(1).preferences!
            if layer == "authority" { preferences.global = bad }
            else { preferences.projects["project-a"] = bad }
            let candidate = SettingsEnvelope(schemaVersion: 2, revision: 1,
                config: envelope(1).config, preferences: preferences, activeProfileID: profileID)
            #expect(try await rig.prepare(candidate) == .failedClosed(.invalidPolicyDocument))
        }
    }

    @Test func firstInstallInvalidatesAndCandidateMustMatchExactAcknowledgement() async throws {
        let rig = try Rig.make(); let first = envelope(1)
        let prepared = try await rig.prepare(first)
        let token = try #require(prepared.token)
        #expect(prepared.effect == .invalidate)
        #expect(await rig.controller.commit(token, acknowledgedEnvelope: envelope(1, rate: 1),
            using: rig.owner) == .failedClosed(.candidateMismatch))
        #expect(await rig.scheduler.snapshot().availability == .unavailable)
        #expect(await rig.controller.commit(token, acknowledgedEnvelope: first,
            using: rig.owner) == .rejected(.consumed))
    }

    @Test func synchronousBarrierBlocksEverySessionAndGrantBeforeAsyncPrepare() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1))
        let requirements = try SchedulerRequirements(features: [.projects])
        let existing = try await rig.session()
        let capability = try await rig.controller.issueExplicitCapability(
            requirements: requirements, using: rig.owner)
        let admission = try rig.controller.beginAdmissionTransition(using: rig.owner)
        await #expect(throws: WorkSchedulerError.admissionUpdating) {
            _ = try await rig.scheduler.beginSession(requirements: requirements,
                                                      capability: capability)
        }
        await #expect(throws: WorkSchedulerError.admissionUpdating) {
            try await rig.scheduler.withPermit(session: existing) { _ in
                Issue.record("grant crossed synchronous admission barrier")
            }
        }
        let candidate = envelope(2, workers: 1)
        let prepared = await rig.controller.prepare(admission, candidate: candidate,
            observation: .nominal, using: rig.owner)
        let token = try #require(prepared.token)
        #expect(await rig.controller.commit(token, acknowledgedEnvelope: candidate,
            using: rig.owner) == .committed(settingsRevision: 2))
        try await rig.scheduler.withPermit(session: existing) { _ in }
    }

    @Test func presentationPrepareAndAcknowledgementNeverCloseSessionsOrQueuedGrant() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1, rate: 4))
        let before = await rig.scheduler.snapshot()
        let active = try await rig.session(); let queued = try await rig.session()
        let gate = Gate()
        let running = Task { try await rig.scheduler.withPermit(session: active) {
            try await gate.hold(0, $0)
        } }
        await gate.wait(0)
        let waiting = Task { try await rig.scheduler.withPermit(session: queued) {
            try await gate.hold(1, $0)
        } }
        await rig.hook.wait(.enqueued(2))

        await rig.hook.block(.presentationPrepared(revision: 2))
        let candidate = envelope(2, workers: 1, rate: 1)
        let preparation = Task {
            await rig.preparePresentation(candidate)
        }
        await rig.hook.wait(.presentationPrepared(revision: 2))

        _ = try await rig.session() // creation remains admitted before prepare/save acknowledgement
        await gate.release(0); _ = try? await running.value
        await gate.wait(1) // the already queued grant advances while presentation prepare is blocked
        let pending = await rig.scheduler.snapshot()
        #expect(pending.settingsRevision == 1)
        #expect(pending.generation == before.generation)

        await rig.hook.release(.presentationPrepared(revision: 2))
        let prepared = await preparation.value
        #expect(prepared.effect == .none)
        let token = try #require(prepared.token)
        #expect(await rig.controller.commitPresentation(token, acknowledgedEnvelope: candidate,
            using: rig.owner) == .committed(settingsRevision: 2))
        #expect(await rig.scheduler.snapshot().generation == before.generation)
        await gate.release(1); _ = try? await waiting.value
    }

    @Test func presentationPathRejectsAnythingExceptValidatedNoneAndEqualIdentity() async throws {
        let unavailable = try Rig.make()
        #expect(await unavailable.preparePresentation(envelope(1)) ==
                .rejected(.firstInstallRequiresInvalidation))
        #expect(await unavailable.scheduler.snapshot().availability == .unavailable)

        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 2, rate: 4))
        #expect(await rig.preparePresentation(envelope(2, workers: 1, rate: 4)) ==
                .rejected(.notPresentationOnly))

        var malformed = envelope(2, workers: 2, rate: 1).preferences!
        malformed.global.fields[id("scan.uiBatchesPerSecond")] = .bool(true)
        let malformedCandidate = SettingsEnvelope(schemaVersion: 2, revision: 2,
            config: envelope(1).config, preferences: malformed, activeProfileID: profileID)
        #expect(await rig.preparePresentation(malformedCandidate) ==
                .rejected(.invalidPolicyDocument))

        var noncanonicalConfig = TidyConfig(schemaVersion: 2)
        noncanonicalConfig.transcriptAgeThresholdDays = 46
        let noncanonical = SettingsEnvelope(schemaVersion: 2, revision: 2,
            config: noncanonicalConfig, preferences: envelope(1, rate: 1).preferences,
            activeProfileID: profileID)
        #expect(await rig.preparePresentation(noncanonical) ==
                .rejected(.legacyCompatibilityMismatch))
        let valid = envelope(2, workers: 2, rate: 1)
        let prepared = await rig.preparePresentation(valid)
        let token = try #require(prepared.token)
        #expect(await rig.controller.discardPresentation(token, using: rig.owner) == .discarded)
        #expect(await rig.controller.commitPresentation(token, acknowledgedEnvelope: valid,
            using: rig.owner) == .rejected(.consumed))
        #expect(await rig.scheduler.snapshot().settingsRevision == 1)
        _ = try await rig.session()
    }

    @Test func foreignSupersededFailedAndLateTokensCannotReopen() async throws {
        let a = try Rig.make(); let b = try Rig.make()
        #expect(throws: WorkSchedulerError.foreignController) {
            _ = try a.controller.beginAdmissionTransition(using: b.owner)
        }
        let bPrepared = try await b.prepare(envelope(1))
        let bToken = try #require(bPrepared.token)
        #expect(await a.controller.commit(bToken, acknowledgedEnvelope: envelope(1),
            using: a.owner) == .rejected(.foreignToken))
        let one = try await a.prepare(envelope(1))
        let oneToken = try #require(one.token)
        let two = try await a.prepare(envelope(2))
        let twoToken = try #require(two.token)
        #expect(await a.controller.commit(oneToken, acknowledgedEnvelope: envelope(1),
            using: a.owner) == .rejected(.superseded))
        #expect(await a.controller.fail(twoToken, using: a.owner) == .failedClosed)
        #expect(await a.controller.commit(twoToken, acknowledgedEnvelope: envelope(2),
            using: a.owner) == .rejected(.consumed))
        await #expect(throws: WorkSchedulerError.admissionUnavailable) { _ = try await a.session() }
        let recovery = try await a.prepare(envelope(3))
        let recoveryToken = try #require(recovery.token)
        #expect(await a.controller.commit(recoveryToken, acknowledgedEnvelope: envelope(3),
            using: a.owner) == .committed(settingsRevision: 3))
        _ = try await a.session()
    }

    @Test func observationEpochUsesSameEnvelopeAndNeverInventsSettingsRevision() async throws {
        let rig = try Rig.make(); let acknowledged = envelope(7, workers: 4)
        try await rig.install(acknowledged)
        #expect(await rig.controller.updateObservation(epoch: 1, observation: .unknown,
            acknowledgedEnvelope: acknowledged, using: rig.owner) == .applied)
        #expect(await rig.scheduler.snapshot().effectiveWorkers == 1)
        #expect(await rig.scheduler.snapshot().settingsRevision == 7)
        #expect(await rig.controller.updateObservation(epoch: 1, observation: .nominal,
            acknowledgedEnvelope: acknowledged, using: rig.owner) == .rejectedStale(current: 1))
        #expect(await rig.controller.updateObservation(epoch: 2, observation: .constrained,
            acknowledgedEnvelope: acknowledged, using: rig.owner) == .applied)
        #expect(await rig.controller.updateObservation(epoch: 3, observation: .critical,
            acknowledgedEnvelope: acknowledged, using: rig.owner) == .applied)
        #expect(await rig.scheduler.snapshot().effectiveWorkers == 0)
        #expect(await rig.controller.updateObservation(epoch: 4, observation: .nominal,
            acknowledgedEnvelope: envelope(8), using: rig.owner) == .failedClosed(.envelopeMismatch))
    }

    @Test func staleAndWrongRequirementsCapabilitiesRejectBeforeAccounting() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1))
        let project = try SchedulerRequirements(features: [.projects])
        let capability = try await rig.controller.issueExplicitCapability(
            requirements: project, using: rig.owner)
        let wrong = try SchedulerRequirements(features: [.buildPrep])
        await #expect(throws: WorkSchedulerError.wrongRequirements) {
            _ = try await rig.scheduler.beginSession(requirements: wrong, capability: capability)
        }
        #expect(await rig.scheduler.snapshot().liveSessions == 0)
        let stale = try await rig.controller.issueExplicitCapability(
            requirements: project, using: rig.owner)
        try await rig.install(envelope(2, slice: 301))
        await #expect(throws: WorkSchedulerError.staleCapability) {
            _ = try await rig.scheduler.beginSession(requirements: project, capability: stale)
        }
    }

    @Test func actualTwoToZeroFreezesThenPausedToExplicitResumesOldest() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 2))
        let gate = Gate()
        let session0 = try await rig.session()
        let session1 = try await rig.session()
        let session2 = try await rig.session()
        let sessions = [session0, session1, session2]
        let first = Task { try await rig.scheduler.withPermit(session: sessions[0]) { try await gate.hold(0, $0) } }
        await gate.wait(0)
        let second = Task { try await rig.scheduler.withPermit(session: sessions[1]) { try await gate.hold(1, $0) } }
        await gate.wait(1)
        let third = Task { try await rig.scheduler.withPermit(session: sessions[2]) { try await gate.hold(2, $0) } }
        await rig.hook.wait(.enqueued(3))
        let paused = envelope(2, workers: 1)
        let prepared = try await rig.prepare(paused, observation: .critical)
        let token = try #require(prepared.token)
        #expect(await rig.controller.commit(token, acknowledgedEnvelope: paused, using: rig.owner) ==
                .committed(settingsRevision: 2))
        #expect(await rig.scheduler.snapshot().effectiveWorkers == 0)
        #expect(await rig.scheduler.snapshot().effectiveReadOnlyProcesses == 0)
        #expect(await rig.scheduler.snapshot().admission == .paused)
        #expect(!(await gate.cancelled(0))); #expect(!(await gate.cancelled(1)))
        await gate.release(0); await gate.release(1); _ = try? await first.value; _ = try? await second.value
        #expect(await rig.scheduler.snapshot().queued == 1)
        #expect(await rig.controller.updateObservation(epoch: 1, observation: .unknown,
            acknowledgedEnvelope: paused, using: rig.owner) == .applied)
        #expect(await rig.scheduler.snapshot().admission == .userRequestedOnly)
        await gate.wait(2); #expect(await gate.order() == [0, 1, 2])
        await gate.release(2); _ = try? await third.value
    }

    @Test func sliceChangeCancelsButRateOnlyPreservesActive() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 2))
        let gate = Gate(); let a = try await rig.session(); let b = try await rig.session()
        let ta = Task { try await rig.scheduler.withPermit(session: a) { try await gate.hold(1, $0) } }
        let tb = Task { try await rig.scheduler.withPermit(session: b) { try await gate.hold(2, $0) } }
        await gate.wait(1); await gate.wait(2)
        try await rig.install(envelope(2, workers: 2, rate: 1))
        #expect(!(await gate.cancelled(1))); #expect(!(await gate.cancelled(2)))
        let changed = envelope(3, workers: 2, slice: 301, rate: 1)
        let prepared = try await rig.prepare(changed)
        let token = try #require(prepared.token)
        #expect(await gate.cancelled(1)); #expect(await gate.cancelled(2))
        #expect(await rig.controller.commit(token, acknowledgedEnvelope: changed,
            using: rig.owner) == .committed(settingsRevision: 3))
        await gate.release(1); await gate.release(2); _ = try? await ta.value; _ = try? await tb.value
    }

    @Test func deterministicStarvationSequenceKeepsOldestAheadOfReacquire() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1))
        let gate = Gate(); let a = try await rig.session(); let b = try await rig.session()
        let first = Task { try await rig.scheduler.withPermit(session: a) { try await gate.hold(0, $0) } }
        await gate.wait(0)
        let old = Task { try await rig.scheduler.withPermit(session: b) { try await gate.hold(1, $0) } }
        await rig.hook.wait(.enqueued(2))
        var newer: [Task<Void, Error>] = []
        for value in 2...6 {
            let task = Task { try await rig.scheduler.withPermit(session: a) {
                try await gate.hold(value, $0)
            } }
            await rig.hook.wait(.enqueued(UInt64(value + 1)))
            newer.append(task)
        }
        await gate.release(0); _ = try? await first.value; await gate.wait(1)
        #expect(await gate.order() == [0, 1])
        await gate.release(1); _ = try? await old.value
        for value in 2...6 {
            await gate.wait(value); await gate.release(value)
        }
        for task in newer { _ = try? await task.value }
        #expect(await gate.order() == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test func activeCancelSetsProbeAndAutomaticallyReclaimsSession() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1))
        let gate = Gate(); let session = try await rig.session()
        let task = Task { try await rig.scheduler.withPermit(session: session) { try await gate.hold(9, $0) } }
        await gate.wait(9); await rig.scheduler.cancel(session: session)
        #expect(await gate.cancelled(9)); #expect(await rig.scheduler.snapshot().liveSessions == 1)
        await gate.release(9); _ = try? await task.value
        #expect(await rig.scheduler.snapshot().active == 0)
        #expect(await rig.scheduler.snapshot().liveSessions == 0)
    }

    @Test func cancelAIsolationAndCancelFinishReleaseRaceAreExact() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1))
        let gate = Gate(); let a = try await rig.session(); let b = try await rig.session()
        let ta = Task { try await rig.scheduler.withPermit(session: a) { try await gate.hold(1, $0) } }
        await gate.wait(1)
        let tb = Task { try await rig.scheduler.withPermit(session: b) { try await gate.hold(2, $0) } }
        await rig.hook.wait(.enqueued(2))
        async let cancelled: Void = rig.scheduler.cancel(session: a)
        async let finished: Void = rig.scheduler.finish(session: a)
        await gate.release(1); _ = await (cancelled, finished); _ = try? await ta.value
        await gate.wait(2)
        #expect(await rig.scheduler.state(of: b) == .open)
        #expect(!(await gate.cancelled(2)))
        await gate.release(2); _ = try? await tb.value
        #expect(await rig.scheduler.snapshot().active == 0)
    }

    @Test func releaseRacingInvalidatingPrepareCannotGrantAcrossBarrier() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1))
        let gate = Gate(); let a = try await rig.session(); let b = try await rig.session()
        let ta = Task { try await rig.scheduler.withPermit(session: a) { try await gate.hold(1, $0) } }
        await gate.wait(1)
        let tb = Task { try await rig.scheduler.withPermit(session: b) { try await gate.hold(2, $0) } }
        await rig.hook.wait(.enqueued(2)); await rig.hook.block(.released(1))
        await gate.release(1); await rig.hook.wait(.released(1))
        let candidate = envelope(2, slice: 301)
        let admission = try rig.controller.beginAdmissionTransition(using: rig.owner)
        let prepared = await rig.controller.prepare(admission, candidate: candidate,
            observation: .nominal, using: rig.owner)
        await rig.hook.release(.released(1)); _ = try? await ta.value
        #expect(await rig.scheduler.snapshot().active == 0)
        let token = try #require(prepared.token)
        #expect(await rig.controller.commit(token, acknowledgedEnvelope: candidate,
            using: rig.owner) == .committed(settingsRevision: 2))
        _ = try? await tb.value
        #expect(!(await gate.order().contains(2)))
    }

    @Test func twentyActiveCancelFinishCyclesReclaimEverything() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1))
        let gate = Gate()
        for value in 0..<20 {
            let session = try await rig.session()
            let task = Task { try await rig.scheduler.withPermit(session: session) {
                try await gate.hold(value, $0)
            } }
            await gate.wait(value)
            if value.isMultiple(of: 2) { await rig.scheduler.cancel(session: session) }
            else { await rig.scheduler.finish(session: session) }
            await gate.release(value); _ = try? await task.value
        }
        let snapshot = await rig.scheduler.snapshot()
        #expect(snapshot.active == 0); #expect(snapshot.queued == 0)
        #expect(snapshot.liveSessions == 0)
    }

    @Test func limitsQueuesTombstonesAndSixtyFifthFreshSessionAreBounded() async throws {
        for tuple in [(0, 1, 1, 0), (65, 1, 1, 0), (1, 0, 1, 0),
                      (1, 257, 1, 0), (1, 2, 0, 0), (1, 2, 3, 0),
                      (1, 2, 1, -1), (1, 2, 1, 65)] {
            #expect(throws: WorkSchedulerError.invalidLimits) {
                try WorkSchedulerLimits(sessions: tuple.0, queued: tuple.1,
                    queuedPerSession: tuple.2, tombstones: tuple.3)
            }
        }
        let limits = try WorkSchedulerLimits(sessions: 64, queued: 2,
            queuedPerSession: 1, tombstones: 2)
        let rig = try Rig.make(limits: limits); try await rig.install(envelope(1, workers: 1))
        var sessions: [WorkSession] = []
        for _ in 0..<64 { sessions.append(try await rig.session()) }
        for index in sessions.indices {
            if index.isMultiple(of: 2) { await rig.scheduler.cancel(session: sessions[index]) }
            else { await rig.scheduler.finish(session: sessions[index]) }
        }
        #expect(await rig.scheduler.snapshot().liveSessions == 0)
        _ = try await rig.session()
        #expect(await rig.scheduler.snapshot().tombstones == 2)
        #expect(await rig.scheduler.state(of: sessions[0]) == nil)
    }

    @Test func totalAndPerSessionQueueOverflowNeverRunClosureAndCancellationReclaims() async throws {
        let total = try Rig.make(limits: try .init(sessions: 3, queued: 1,
            queuedPerSession: 1, tombstones: 0))
        try await total.install(envelope(1, workers: 1))
        let a = try await total.session(); let b = try await total.session(); let gate = Gate()
        let active = Task { try await total.scheduler.withPermit(session: a) { try await gate.hold(0, $0) } }
        await gate.wait(0)
        let queued = Task { try await total.scheduler.withPermit(session: b) { _ in } }
        await total.hook.wait(.enqueued(2))
        await #expect(throws: WorkSchedulerError.queueLimit) {
            try await total.scheduler.withPermit(session: a) { _ in Issue.record("global overflow ran") }
        }
        queued.cancel(); await total.hook.wait(.released(2))
        await gate.release(0); _ = try? await active.value; _ = try? await queued.value
        #expect(await total.scheduler.snapshot().queued == 0)

        let perSession = try Rig.make(limits: try .init(sessions: 2, queued: 2,
            queuedPerSession: 1, tombstones: 0))
        try await perSession.install(envelope(1, workers: 1))
        let session = try await perSession.session(); let perGate = Gate()
        let perActive = Task { try await perSession.scheduler.withPermit(session: session) {
            try await perGate.hold(1, $0)
        } }
        await perGate.wait(1)
        let perQueued = Task { try await perSession.scheduler.withPermit(session: session) { _ in } }
        await perSession.hook.wait(.enqueued(2))
        await #expect(throws: WorkSchedulerError.sessionQueueLimit) {
            try await perSession.scheduler.withPermit(session: session) {
                _ in Issue.record("per-session overflow ran")
            }
        }
        perQueued.cancel(); await perSession.hook.wait(.released(2))
        await perGate.release(1); _ = try? await perActive.value; _ = try? await perQueued.value
        #expect(await perSession.scheduler.snapshot().queued == 0)
    }

    @Test func fourToOneDrainsAndOneToFourFillsPreservedFIFO() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 4))
        let gate = Gate(); var sessions: [WorkSession] = []
        for _ in 0..<5 { sessions.append(try await rig.session()) }
        var tasks: [Task<Void, Error>] = []
        for index in 0..<4 {
            let task = Task { try await rig.scheduler.withPermit(session: sessions[index]) {
                try await gate.hold(index, $0)
            } }
            tasks.append(task); await gate.wait(index)
        }
        let oldest = Task { try await rig.scheduler.withPermit(session: sessions[4]) {
            try await gate.hold(4, $0)
        } }
        await rig.hook.wait(.enqueued(5))
        let one = envelope(2, workers: 1)
        let p1 = try await rig.prepare(one)
        let t1 = try #require(p1.token)
        #expect(await rig.controller.commit(t1, acknowledgedEnvelope: one, using: rig.owner) ==
                .committed(settingsRevision: 2))
        for index in 0..<4 { #expect(!(await gate.cancelled(index))); await gate.release(index) }
        for task in tasks { _ = try? await task.value }
        await gate.wait(4)
        let newer = try await rig.session()
        let newerTask = Task { try await rig.scheduler.withPermit(session: newer) {
            try await gate.hold(5, $0)
        } }
        await rig.hook.wait(.enqueued(6))
        let four = envelope(3, workers: 4)
        let p4 = try await rig.prepare(four)
        let t4 = try #require(p4.token)
        #expect(await rig.controller.commit(t4, acknowledgedEnvelope: four, using: rig.owner) ==
                .committed(settingsRevision: 3))
        await gate.wait(5); #expect(await gate.order().suffix(2) == [4, 5])
        await gate.release(4); await gate.release(5); _ = try? await oldest.value; _ = try? await newerTask.value
    }

    @Test func featureLossOverlappingRequirementsAndAdmissionNarrowingAreExact() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 3))
        let overlap = try await rig.session([.projects, .buildPrep])
        let build = try await rig.session([.buildPrep])
        let discretionary = try await rig.controller.beginDiscretionarySession(
            requirements: SchedulerRequirements(features: [.buildPrep]), using: rig.owner)
        let gate = Gate()
        let tasks = [
            Task { try await rig.scheduler.withPermit(session: overlap) { try await gate.hold(1, $0) } },
            Task { try await rig.scheduler.withPermit(session: build) { try await gate.hold(2, $0) } },
            Task { try await rig.scheduler.withPermit(session: discretionary) { try await gate.hold(3, $0) } }
        ]
        await gate.wait(1); await gate.wait(2); await gate.wait(3)
        var restricted = envelope(2, workers: 1)
        restricted = SettingsEnvelope(schemaVersion: restricted.schemaVersion,
            revision: restricted.revision, config: restricted.config,
            preferences: PolicyPreferences(global: values([
                ("scan.preset", .choice("custom")), ("scan.requestedWorkers", .integer(1)),
                ("scan.readOnlyProcesses", .integer(1)), ("scan.sliceSeconds", .integer(300)),
                ("scan.uiBatchesPerSecond", .integer(4)), ("feature.projects", .bool(false))
            ]), profiles: restricted.preferences?.profiles ?? [], projects: restricted.preferences?.projects ?? [:]),
            activeProfileID: restricted.activeProfileID)
        let prepared = try await rig.prepare(restricted, observation: .constrained)
        let token = try #require(prepared.token)
        #expect(await rig.controller.commit(token, acknowledgedEnvelope: restricted, using: rig.owner) ==
                .committed(settingsRevision: 2))
        #expect(await gate.cancelled(1)); #expect(!(await gate.cancelled(2)))
        #expect(await gate.cancelled(3))
        for index in 1...3 { await gate.release(index) }; for task in tasks { _ = try? await task.value }
    }

    @Test func foreignSessionCapabilityControllerAndCheckedOverflowsFailClosed() async throws {
        let a = try Rig.make(); let b = try Rig.make(); try await a.install(envelope(1)); try await b.install(envelope(1))
        let requirements = try SchedulerRequirements(features: [.projects])
        let foreignCapability = try await b.controller.issueExplicitCapability(
            requirements: requirements, using: b.owner)
        await #expect(throws: WorkSchedulerError.foreignCapability) {
            _ = try await a.scheduler.beginSession(requirements: requirements,
                                                    capability: foreignCapability)
        }
        let foreignSession = try await b.session()
        await #expect(throws: WorkSchedulerError.foreignSession) {
            try await a.scheduler.withPermit(session: foreignSession) { _ in Issue.record("foreign ran") }
        }
        #expect(throws: WorkSchedulerError.foreignController) {
            _ = try a.controller.beginAdmissionTransition(using: b.owner)
        }

        let generation = try Rig.make(generation: UInt64.max)
        let failed = try await generation.prepare(envelope(1))
        #expect(failed == .failedClosed(.generationOverflow))
        let epoch = try Rig.make(epoch: UInt64.max); try await epoch.install(envelope(1))
        #expect(await epoch.controller.updateObservation(epoch: UInt64.max,
            observation: .nominal, acknowledgedEnvelope: envelope(1), using: epoch.owner) ==
                .rejectedStale(current: UInt64.max))
        let waiter = try Rig.make(waiterID: UInt64.max); try await waiter.install(envelope(1))
        let session = try await waiter.session()
        await #expect(throws: WorkSchedulerError.counterOverflow) {
            try await waiter.scheduler.withPermit(session: session) { _ in }
        }
        #expect(await waiter.scheduler.snapshot().availability == .unavailable)
    }

    @Test func allCancellationHooksPreventClosureBeforeStart() async throws {
        for event in [SchedulerTestEvent.acquiring(1), .enqueued(1),
                      .granting(1), .operationStarting(1)] {
            let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1))
            await rig.hook.block(event); let session = try await rig.session()
            let task = Task { try await rig.scheduler.withPermit(session: session) { _ in
                Issue.record("closure ran across cancellation boundary")
            } }
            await rig.hook.wait(event); task.cancel(); await rig.hook.release(event)
            _ = try? await task.value
            #expect(await rig.scheduler.snapshot().active == 0)
            #expect(await rig.scheduler.snapshot().queued == 0)
        }
    }

    @Test func sourceHasNoSuppliedPolicyEffectOrPublicAuthorityEscape() throws {
        let file = URL(fileURLWithPath: #filePath)
        let source = try String(contentsOf: file.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TidyCore/Scanning/WorkScheduler.swift"), encoding: .utf8)
        for forbidden in ["prepare(policy:", "changeEffect:", "public func update",
            "public func preparePresentation",
            "public init(policy:", "public var userInitiated", "public func release",
            "public struct WorkLease", "public struct SchedulerAdmissionTicket",
            "public struct SchedulerPolicyControllerCapability", "Task.detached", "Timer(", "Process(",
            "FileManager.default", "&+=", "wrappingIncrement"] {
            #expect(!source.contains(forbidden), "forbidden T08.1a surface: \(forbidden)")
        }
        #expect(source.contains("PolicyResolver.resolve"))
        #expect(source.contains("PreferencesDocumentEffect.classify"))
        #expect(source.contains("PolicyInvalidationBarrier") == false)
        #expect(source.contains("NSLock"))
        #expect(source.contains("beginAdmissionTransition"))
        #expect(source.contains("func preparePresentation"))
    }
}
```

The embedded file is the complete T08.1a RED boundary: bounded-limit/tombstone/counter cases, real resolution, handoff races, transition matrix, authority negatives, FIFO/starvation, and every cancellation hook are not deferrable to T08.1b.

## TDD and verification

```bash
cd /private/tmp/tidy-headroom.r1yE0o/TidyCore
swift test --jobs 2 --filter WorkSchedulerTests
# record intended missing-declaration RED
swift test --jobs 2 --filter WorkSchedulerTests
swift test --jobs 2 --filter 'PolicyResolutionTests|PolicyDefaultsTests|SettingsProfilePersistenceTests|WorkSchedulerTests'
swift test --jobs 2

cd /private/tmp/tidy-headroom.r1yE0o
git diff --check
git status --short
```

GREEN requires exact allowlist, no warnings/data races, source-negative proof, and fresh adversarial review of real envelope resolution, effect derivation, authority tokens, every actor suspension, FIFO/cancellation, observation epochs, checked arithmetic, and bounds. The verification record explicitly leaves real save ordering/durability to T08.1b and traversal/process/app/physical performance to later checkpoints.

## Nonclaims

T08.1a does not prove persistence ordering, app integration, traversal/FD behavior, process sharing, UI responsiveness, real observation sources, background authority, monitoring, maintenance, mutation, or physical low-spec performance. Only T08.1b may connect commit/fail to real `ExecutionPolicyBridge` persistence outcomes.
