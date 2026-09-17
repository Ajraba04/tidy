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
        let resolved = try #require(await rig.controller.resolvedPolicy(using: rig.owner))
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
            var preferences = envelope(1).preferences!
            preferences.global.fields[id(row.raw)] = PolicyValidator.definition(
                for: id(row.raw))!.defaultValue
            let explicitDefault = SettingsEnvelope(schemaVersion: 2, revision: 1,
                config: defaults, preferences: preferences, activeProfileID: profileID)
            let rig = try Rig.make(); try await rig.install(explicitDefault)
        }

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

    @Test func bridgeAdmissionHoldsBlockQueuedPermitUntilAllAcceptedHandoffsFinish() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1))
        let active = try await rig.session(); let queued = try await rig.session(); let gate = Gate()
        let activeTask = Task { try await rig.scheduler.withPermit(session: active) {
            try await gate.hold(0, $0)
        } }
        await gate.wait(0)
        let queuedTask = Task { try await rig.scheduler.withPermit(session: queued) {
            try await gate.hold(1, $0)
        } }
        await rig.hook.wait(.enqueued(2))

        let firstHold = try rig.controller.acquireAdmissionHold(using: rig.owner)
        let secondHold = try rig.controller.acquireAdmissionHold(using: rig.owner)
        let firstAdmission = try rig.controller.beginAdmissionTransition(using: rig.owner)
        let firstCandidate = envelope(2, workers: 1, projectDays: 42)
        let firstPrepared = await rig.controller.prepare(firstAdmission, candidate: firstCandidate,
            observation: .nominal, using: rig.owner)
        let firstToken = try #require(firstPrepared.token)
        #expect(await rig.controller.commit(firstToken, acknowledgedEnvelope: firstCandidate,
            using: rig.owner) == .committed(settingsRevision: 2))

        await gate.release(0); _ = try await activeTask.value
        #expect(await rig.scheduler.snapshot().queued == 1)
        #expect(!(await gate.order().contains(1)))
        await rig.controller.releaseAdmissionHold(firstHold, using: rig.owner)
        #expect(await rig.scheduler.snapshot().queued == 1)
        #expect(!(await gate.order().contains(1)))

        let secondAdmission = try rig.controller.beginAdmissionTransition(using: rig.owner)
        let secondCandidate = envelope(3, workers: 1, projectDays: 43)
        let secondPrepared = await rig.controller.prepare(secondAdmission, candidate: secondCandidate,
            observation: .nominal, using: rig.owner)
        let secondToken = try #require(secondPrepared.token)
        #expect(await rig.controller.commit(secondToken, acknowledgedEnvelope: secondCandidate,
            using: rig.owner) == .committed(settingsRevision: 3))
        #expect(!(await gate.order().contains(1)))

        await rig.controller.releaseAdmissionHold(secondHold, using: rig.owner)
        await gate.wait(1)
        await gate.release(1); _ = try await queuedTask.value
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
        let oneAdmission = try a.controller.beginAdmissionTransition(using: a.owner)
        let twoAdmission = try a.controller.beginAdmissionTransition(using: a.owner)
        #expect(await a.controller.prepare(oneAdmission, candidate: envelope(1),
            observation: .nominal, using: a.owner) == .rejected(.superseded))
        let two = await a.controller.prepare(twoAdmission, candidate: envelope(2),
            observation: .nominal, using: a.owner)
        let twoToken = try #require(two.token)
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

    @Test func snapshotProjectsOnlyAcknowledgedSliceAndPresentationRate() async throws {
        let rig = try Rig.make()
        var snapshot = await rig.scheduler.snapshot()
        #expect(snapshot.settingsRevision == nil)
        #expect(snapshot.effectiveSliceSeconds == nil)
        #expect(snapshot.effectiveUIBatchesPerSecond == nil)

        let initial = envelope(7, workers: 4, slice: 30, rate: 4)
        try await rig.install(initial)
        snapshot = await rig.scheduler.snapshot()
        #expect(snapshot.effectiveSliceSeconds == 30)
        #expect(snapshot.effectiveUIBatchesPerSecond == 4)

        let presentation = envelope(8, workers: 4, slice: 30, rate: 1)
        let preparedPresentation = await rig.preparePresentation(presentation)
        let presentationToken = try #require(preparedPresentation.token)
        #expect(await rig.controller.commitPresentation(presentationToken,
            acknowledgedEnvelope: presentation, using: rig.owner) ==
                .committed(settingsRevision: 8))
        snapshot = await rig.scheduler.snapshot()
        #expect(snapshot.effectiveSliceSeconds == 30)
        #expect(snapshot.effectiveUIBatchesPerSecond == 1)

        let invalidating = envelope(9, workers: 4, slice: 1_800, rate: 3)
        try await rig.install(invalidating)
        #expect(await rig.controller.updateObservation(epoch: 1, observation: .constrained,
            acknowledgedEnvelope: invalidating, using: rig.owner) == .applied)
        snapshot = await rig.scheduler.snapshot()
        #expect(snapshot.effectiveSliceSeconds == 1_800)
        #expect(snapshot.effectiveUIBatchesPerSecond == 3)
        #expect(snapshot.effectiveWorkers == 1)

        #expect(await rig.controller.updateObservation(epoch: 2, observation: .critical,
            acknowledgedEnvelope: invalidating, using: rig.owner) == .applied)
        snapshot = await rig.scheduler.snapshot()
        #expect(snapshot.admission == .paused)
        #expect(snapshot.effectiveWorkers == 0)
        #expect(snapshot.effectiveSliceSeconds == 1_800)
        #expect(snapshot.effectiveUIBatchesPerSecond == 3)

        #expect(await rig.controller.updateObservation(epoch: 3, observation: .nominal,
            acknowledgedEnvelope: invalidating, using: rig.owner) == .applied)
        snapshot = await rig.scheduler.snapshot()
        #expect(snapshot.admission != .paused)
        #expect(snapshot.effectiveWorkers == 4)
        #expect(snapshot.effectiveSliceSeconds == 1_800)
        #expect(snapshot.effectiveUIBatchesPerSecond == 3)
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
        for (event, needsBlocker) in [(SchedulerTestEvent.acquiring(1), false),
                                     (.enqueued(2), true), (.granting(1), false),
                                     (.operationStarting(1), false)] {
            let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1))
            let gate = Gate()
            let blockerSession = needsBlocker ? try await rig.session() : nil
            let blocker = blockerSession.map { blockerSession in
                Task { try await rig.scheduler.withPermit(session: blockerSession) {
                    try await gate.hold(99, $0)
                } }
            }
            if needsBlocker { await gate.wait(99) }
            await rig.hook.block(event); let session = try await rig.session()
            let task = Task { try await rig.scheduler.withPermit(session: session) { _ in
                Issue.record("closure ran across cancellation boundary")
            } }
            await rig.hook.wait(event); task.cancel(); await rig.hook.release(event)
            _ = try? await task.value
            if needsBlocker {
                await gate.release(99)
                if let blocker { _ = try? await blocker.value }
            }
            #expect(await rig.scheduler.snapshot().active == 0)
            #expect(await rig.scheduler.snapshot().queued == 0)
        }
    }

    @Test func newerBarrierTransitionRejectsOldPrepareAndPresentationWhilePreparedInvalidationOwnsBarrier() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1))
        let oldAdmission = try rig.controller.beginAdmissionTransition(using: rig.owner)
        let newAdmission = try rig.controller.beginAdmissionTransition(using: rig.owner)
        #expect(await rig.controller.prepare(oldAdmission, candidate: envelope(2, workers: 1),
            observation: .nominal, using: rig.owner) == .rejected(.superseded))
        let prepared = await rig.controller.prepare(newAdmission, candidate: envelope(2, workers: 1),
            observation: .nominal, using: rig.owner)
        let token = try #require(prepared.token)
        #expect(await rig.controller.updateObservation(epoch: 1, observation: .unknown,
            acknowledgedEnvelope: envelope(1), using: rig.owner) == .failedClosed(.envelopeMismatch))
        #expect(throws: WorkSchedulerError.admissionUpdating) {
            _ = try rig.controller.beginAdmissionTransition(using: rig.owner)
        }
        #expect(await rig.controller.commit(token, acknowledgedEnvelope: envelope(2, workers: 1),
            using: rig.owner) == .committed(settingsRevision: 2))

        let recovery = try await rig.prepare(envelope(3))
        let recoveryToken = try #require(recovery.token)
        #expect(await rig.controller.commit(recoveryToken, acknowledgedEnvelope: envelope(3),
            using: rig.owner) == .committed(settingsRevision: 3))
        let presentation = await rig.preparePresentation(envelope(4, rate: 1))
        let presentationToken = try #require(presentation.token)
        _ = try rig.controller.beginAdmissionTransition(using: rig.owner)
        #expect(await rig.controller.commitPresentation(presentationToken,
            acknowledgedEnvelope: envelope(4, rate: 1), using: rig.owner) == .rejected(.superseded))
        #expect(await rig.scheduler.snapshot().settingsRevision == 3)
    }

    @Test func rateCommitPreservesCapabilityAndPostGrantCancellationReleasesExactlyOnce() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1, rate: 4))
        let requirements = try SchedulerRequirements(features: [.projects])
        let capability = try await rig.controller.issueExplicitCapability(
            requirements: requirements, using: rig.owner)
        let presentation = await rig.preparePresentation(envelope(2, workers: 1, rate: 1))
        let token = try #require(presentation.token)
        #expect(await rig.controller.commitPresentation(token,
            acknowledgedEnvelope: envelope(2, workers: 1, rate: 1), using: rig.owner) ==
                .committed(settingsRevision: 2))
        let session = try await rig.scheduler.beginSession(requirements: requirements,
            capability: capability)
        await rig.hook.block(.grantedBeforeReturn(1))
        let task = Task { try await rig.scheduler.withPermit(session: session) { _ in
            Issue.record("closure ran after post-grant cancellation")
        } }
        await rig.hook.wait(.grantedBeforeReturn(1)); task.cancel()
        await rig.hook.release(.grantedBeforeReturn(1)); _ = try? await task.value
        #expect(await rig.scheduler.snapshot().active == 0)
        #expect((await rig.hook.events()).filter { $0 == .released(1) }.count == 1)
    }

    @Test func replayOwnershipIsCapped() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1))
        for _ in 0..<100 {
            let prepared = await rig.preparePresentation(envelope(2, rate: 1))
            let token = try #require(prepared.token)
            #expect(await rig.controller.discardPresentation(token, using: rig.owner) == .discarded)
        }
        #expect(await rig.controller.replayCountForTesting() <= 64)
    }

    @Test func postGrantCancellationReapsAndDrainsOldestSuccessor() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1))
        let first = try await rig.session(); let second = try await rig.session(); let gate = Gate()
        await rig.hook.block(.grantedBeforeReturn(1))
        let cancelled = Task { try await rig.scheduler.withPermit(session: first) { _ in
            Issue.record("cancelled post-grant closure ran")
        } }
        await rig.hook.wait(.grantedBeforeReturn(1))
        let successor = Task { try await rig.scheduler.withPermit(session: second) {
            try await gate.hold(2, $0)
        } }
        await rig.hook.wait(.enqueued(2)); cancelled.cancel()
        async let cancel: Void = rig.scheduler.cancel(session: first)
        async let finish: Void = rig.scheduler.finish(session: first)
        _ = await (cancel, finish)
        await rig.hook.release(.grantedBeforeReturn(1)); _ = try? await cancelled.value
        #expect(await rig.scheduler.snapshot().liveSessions == 1)
        await gate.wait(2); await gate.release(2); _ = try? await successor.value
        await rig.scheduler.finish(session: second)
        #expect(await rig.scheduler.snapshot().active == 0)
        #expect(await rig.scheduler.snapshot().queued == 0)
        #expect(await rig.scheduler.snapshot().liveSessions == 0)
    }

    @Test func presentationMismatchConsumesTokenBeforeAnyLaterCorrectCommit() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1))
        let candidate = envelope(2, rate: 1)
        let prepared = await rig.preparePresentation(candidate)
        let token = try #require(prepared.token)
        #expect(await rig.controller.commitPresentation(token,
            acknowledgedEnvelope: envelope(2, rate: 2), using: rig.owner) ==
                .failedClosed(.candidateMismatch))
        #expect(await rig.controller.commitPresentation(token,
            acknowledgedEnvelope: candidate, using: rig.owner) == .rejected(.consumed))
        #expect(await rig.scheduler.snapshot().settingsRevision == 1)
    }

    @Test func supersededInvalidatingPrepareCannotCancelActiveOrQueuedVictims() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1, workers: 1))
        let active = try await rig.session(); let queued = try await rig.session(); let gate = Gate()
        let activeTask = Task { try await rig.scheduler.withPermit(session: active) {
            try await gate.hold(1, $0)
        } }
        await gate.wait(1)
        let queuedTask = Task { try await rig.scheduler.withPermit(session: queued) {
            try await gate.hold(2, $0)
        } }
        await rig.hook.wait(.enqueued(2))
        await rig.hook.block(.invalidationClaiming(revision: 2))
        let admission = try rig.controller.beginAdmissionTransition(using: rig.owner)
        let preparing = Task { await rig.controller.prepare(admission,
            candidate: envelope(2, workers: 1, slice: 301), observation: .nominal,
            using: rig.owner) }
        await rig.hook.wait(.invalidationClaiming(revision: 2))
        _ = try rig.controller.beginAdmissionTransition(using: rig.owner)
        await rig.hook.release(.invalidationClaiming(revision: 2))
        #expect(await preparing.value == .rejected(.superseded))
        #expect(await gate.cancelled(1) == false)
        #expect(await rig.scheduler.snapshot().active == 1)
        #expect(await rig.scheduler.snapshot().queued == 1)
        await rig.scheduler.cancel(session: queued)
        await gate.release(1); _ = try? await activeTask.value
        _ = try? await queuedTask.value
        await rig.scheduler.finish(session: active)
    }

    @Test func invalidatingPreparationClaimBlocksTicketReplacementDuringDestruction() async throws {
        let rig = try Rig.make(); try await rig.install(envelope(1))
        await rig.hook.block(.invalidationPrepared(revision: 2))
        let admission = try rig.controller.beginAdmissionTransition(using: rig.owner)
        let preparing = Task { await rig.controller.prepare(admission,
            candidate: envelope(2, workers: 1), observation: .nominal, using: rig.owner) }
        await rig.hook.wait(.invalidationPrepared(revision: 2))
        #expect(throws: WorkSchedulerError.admissionUpdating) {
            _ = try rig.controller.beginAdmissionTransition(using: rig.owner)
        }
        await rig.hook.release(.invalidationPrepared(revision: 2))
        #expect((await preparing.value).token != nil)
        #expect(await rig.scheduler.snapshot().settingsRevision == 1)
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
            "public struct SchedulerPolicyControllerCapability", "public struct SchedulerAdmissionHold",
            "Task.detached", "Timer(", "Process(",
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
