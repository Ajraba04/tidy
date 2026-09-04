# T07.2b Shared Profile Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use test-driven-development, requesting-code-review and verification-before-completion. No production edit is allowed until this card is independently approved.

**Goal:** Route T07.2a’s exact document delta and issued import preview through the existing bounded `ExecutionPolicyBridge` and shared `AppConfigStore`, with synchronous invalidation, ordered replay, selected-profile resolution, relaunch restoration and two-window synchronization.

**Architecture:** One pure projection applies a preferences-document delta and classifies its aggregate storage/policy effect. The accepted bridge retains that exact delta or store-issued preview in its existing single ordered queue and uses the existing coordinator ticket before any invalidating write. `AppConfigStore` optimistically replays only accepted payloads, observes every ordered saved outcome for cross-window synchronization, and resolves the selected profile as app-visible policy data; it creates no authority and no second writer.

**Tech Stack:** Swift, Swift Testing/XCTest, Observation, TidyCore, the existing app-model test host; no new dependencies.

## Global constraints

- T07.2a’s wire, delta bases, token lifecycle, one-attempt import commit and single `SettingsStore` writer remain unchanged.
- Queue limits remain 32 retained snapshots and 32 MiB with checked accounting. Rejection occurs before retention or policy invalidation.
- Authority/consent/local/project/volume identity rejects as `.unsupportedAuthority` before retention. Profile/global structure and monotone rules remain those accepted in T07.1/T07.2a.
- Aggregate effect is `.invalidate` when active selection changes or any changed field’s registry effect is `.invalidate`; a mixed delta invalidates. Pure name, inert/quarantine and `.none` presentation changes use storage revision only. `.consent` is never accepted.
- Activation/deactivation requires exact current base and a final existing profile; activation always invalidates synchronously. Deleting active profile requires the same delta to set active nil and invalidates.
- Import preview admission requires an empty bridge queue and a live bridge-side issuance binding. Later ordinary deltas may queue behind an admitted import using its exact predicted candidate.
- Every outcome is delivered in bridge order. A failed head is not silently rebased: dependent optimistic tails are removed by their own exact conflict/failure outcomes. A foreign failed/conflict outcome never mutates another window's acknowledged state and never occupies its local outcome buffer; any later saved outcome is still acknowledged and replayed in delivery order.
- App-visible effective policy uses global plus the exact selected profile only. Profile identity, storage revision and `EffectivePolicy` are observations, never execution capability or local authority.
- No SwiftUI, picker, file exporter, local reassociation, data clearing or adapter effect is added here.

## Exact allowlist

- Modify `TidyCore/Sources/TidyCore/Policy/SettingsEnvelope.swift`: make document delta types Codable and add the pure shared projection/effect result.
- Modify `TidyCore/Sources/TidyCore/Policy/SettingsStore.swift`: replace its private document application with the shared projection; no publication/token algorithm change.
- Modify `TidyCore/Sources/TidyCore/Execution/ExecutionPolicyBridge.swift`: retain/replay document and import-preview payloads in the existing queue.
- Modify `Tidy/Settings/AppConfigStore.swift`: shared document/import APIs, ordered all-window acknowledgement, active/inert/effective-policy projection.
- Modify `TidyAppModelTests/SharedSettingsWiringTests.swift`: append the complete RED extension below.
- Create `docs/verification/T07-2b-shared-profile-handoff.md` after GREEN/review.

No `AppExecutionServices`, coordinator, settings publication/journal, SwiftUI, Xcode project or other test file may change. The bridge initializer may gain an internal defaulted `pendingByteLimit` solely so the app-model accounting test can exercise the real rejection boundary without changing production construction or its 32 MiB default.

## Exact shared projection

```swift
public enum PreferencesDocumentProjectionError: Error, Equatable, Sendable {
    case stale, invalid, unsupportedAuthority
}

public enum PreferencesDocumentEffect {
    public static func classify(before: SettingsEnvelope,
                                after: SettingsEnvelope) throws -> AuthorityEffect
}

public struct AppliedPreferencesDocument: Equatable, Sendable {
    public let envelope: SettingsEnvelope // same revision as input; pure prediction
    public let effect: AuthorityEffect
}

public enum PreferencesDocumentProjection {
    public static func apply(_ delta: PreferencesDocumentDelta,
                             to envelope: SettingsEnvelope) throws
        -> AppliedPreferencesDocument
}
```

`PreferenceFieldEdit`, `ProfileDocumentEdit`, `InertImportEdit` and `PreferencesDocumentDelta` become `Codable` solely for exact bounded retained-byte accounting. This is not a public import/persistence wire. Import preview accounting instead uses a private closed Codable mirror in `ExecutionPolicyBridge.swift`; `SettingsTransfer.swift` and its public wire remain unchanged.

Projection preserves T07.2a validation order and errors. It returns `.stale` for future base or any touched-base mismatch and `.invalid` for duplicate/structurally invalid/finally orphaned state. It applies the complete candidate at the input revision, reverse-projects changed compatibility globals, and computes effect from the exact changed fields:

- active touch always `.invalidate` even when edited identity equals base;
- global edits use the one registry definition and return `.unsupportedAuthority` for `.consent`, authority, nonportable or local rows;
- profile insert/delete examines every contained field; update examines union of base/edited IDs plus name; name-only is `.none`;
- inert edits are `.none`;
- `.invalidate` dominates `.none`; every disallowed field in any global/profile insert/update/delete path returns `.unsupportedAuthority`.

`PreferencesDocumentEffect.classify` compares exact before/after global fields, profile identities/names/values, active selection and inert entries. Only actually changed field IDs contribute registry effects; activation changes always invalidate, profile names and inert entries are `.none`, `.invalidate` dominates, and any authority/consent/nonportable/local field throws `.unsupportedAuthority`. Document projection and import admission both call this classifier. The store maps `.stale` to `SettingsStoreError.staleRevision` and both `.invalid` and `.unsupportedAuthority` to `.invalidChange`, then publishes the projected envelope fields through the unchanged `save` path. The bridge maps `.unsupportedAuthority` to its exact public rejection.

## Exact bridge/app interfaces

```swift
extension ExecutionPolicyBridge {
    public func submit(document delta: PreferencesDocumentDelta) -> SettingsSubmissionAdmission
    public func submit(importPreview: SettingsImportPreview) -> SettingsSubmissionAdmission

    public func analyzeImport(bytes: Data) async throws -> SettingsImportAnalysis
    public func issueImportPreview(analysisID: SettingsImportAnalysisID,
        choices: [UUID: ProfileCollisionChoice]) async throws -> SettingsImportPreview
    public func cancelImport(analysisID: SettingsImportAnalysisID) async
    public func cancelImport(previewID: SettingsImportPreviewID) async
}

extension AppConfigStore {
    @discardableResult
    func submit(document delta: PreferencesDocumentDelta) -> SettingsSubmissionAdmission
    func analyzeImport(bytes: Data) async throws -> SettingsImportAnalysis
    func issueImportPreview(analysisID: SettingsImportAnalysisID,
        choices: [UUID: ProfileCollisionChoice]) async throws -> SettingsImportPreview
    @discardableResult
    func commitImport(_ preview: SettingsImportPreview) -> SettingsSubmissionAdmission
    func cancelImport(analysisID: SettingsImportAnalysisID) async
    func cancelImport(previewID: SettingsImportPreviewID) async

    var activeProfileID: UUID? { get }
    var inertImports: [InertPortableSetting] { get }
    var effectivePolicy: EffectivePolicy? { get }
}
```

Bridge `Payload` gains `.document(PreferencesDocumentDelta)` and `.importPreview(expectedRevision: UInt64, preview: SettingsImportPreview)`. Admission applies the shared projection to `predictedSubmittedEnvelope`, rejects invalid/authority before accounting, encodes the exact document payload for retained bytes, and begins the existing coordinator update ticket synchronously only for `.invalidate`.

The bridge owns a private issuance binding keyed by preview ID: the exact store-issued preview plus the exact acknowledged revision at issuance. `analyzeImport` invalidates all prior bridge bindings before forwarding; `issueImportPreview` invalidates prior bindings, requires an empty queue, obtains the store preview, and records its exact revision and value; either cancellation removes the corresponding binding; every successful saved outcome clears all bindings. `submit(importPreview:)` requires an empty queue and an exact equality match to a live binding whose revision equals both acknowledged and predicted revision. It rejects stale, cancelled, reused, mutated or foreign previews before accounting, optimistic display or coordinator invalidation, and consumes the binding exactly once only when admission succeeds. This mirror is a fail-fast UI/bridge guard; the `SettingsStore` remains authoritative and independently validates/consumes its own token.

Import retained bytes use a private closed Codable accounting mirror in `ExecutionPolicyBridge.swift` covering the intent ID, expected revision, preview/analysis IDs, every row field and enum payload, every collision/name, every collision choice including clone UUID, the complete candidate preferences and inert entries, and both digests. Encoding/size addition uses checked arithmetic. Import prediction combines the preview candidate with the current envelope while preserving active selection/projects and compatibility projection, then calls `PreferencesDocumentEffect.classify(before:after:)`; storage-only imports create no ticket/generation change and invalidating imports begin the ticket before retention becomes visible.

`perform` maps document to `.preferencesDocument(delta)` and import to `settings.commitImport`. The existing saved/conflict/invalid/failed outcomes, policy-ticket commit, generation ownership, recovery ticket, queue accounting and replay order remain unchanged. Prediction rebuild uses the shared projection/import candidate in admission order; no delta is rebased.

`AppConfigStore.PendingTransform` gains document/import cases and uses the same pure projection. It tracks locally admitted IDs for optimistic display, but `receive` must process every `.saved(_, exactEnvelope)` outcome—even IDs initiated by another window—by replacing `acknowledged` in bridge delivery order and replaying its own remaining transforms. Unknown failed/conflict outcomes do not alter acknowledged state or accumulate. This is the two-window synchronization mechanism; there is still one shared bridge/store.

`effectivePolicy` builds neutral app-visible `PolicyInputs` with `.global` plus `.profile` only when `activeProfileID` names exactly one displayed profile, no selected/approved volume, no capacity, `ProcessInfo.processInfo.activeProcessorCount`, and false pressure flags/empty mandatory exclusions. It returns nil on any validation failure. No coordinator call consumes this value in T07.2b.

## Complete RED extension

Append this extension verbatim to `TidyAppModelTests/SharedSettingsWiringTests.swift` before production edits. The focused app-model command must fail on the missing bridge/app APIs.

```swift
extension SharedSettingsWiringTests {
    private func t07ID(_ raw: String) -> SettingID { .init(rawValue: raw) }
    private func t07Values(_ pairs: [(String, SettingValue)]) -> PolicyValues {
        .init(fields: Dictionary(uniqueKeysWithValues: pairs.map { (t07ID($0.0), $0.1) }))
    }
    private func t07Profile(_ id: UUID, _ name: String,
                            _ pairs: [(String, SettingValue)] = []) -> SavedProfile {
        .init(id: id, name: name, values: t07Values(pairs))
    }

    func testDocumentActivationInvalidatesSynchronouslyResolvesAndRelaunches() async throws {
        try await run(stops: ["config.2"]) { s, services, io in
            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            let profile = self.t07Profile(profileID, "Work", [("ui.units", .choice("decimal"))])
            let app = services.configStore
            let inserted = app.submit(document: .init(baseRevision: 0,
                                                       profiles: [.insert(profile)]))
            guard case .accepted = inserted else { return XCTFail("Profile insert rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            XCTAssertNil(app.activeProfileID)

            let activation = app.submit(document: .init(baseRevision: 1,
                activeProfileBase: nil, activeProfileEdit: profileID,
                touchesActiveProfile: true))
            guard case .accepted = activation else { return XCTFail("Activation rejected") }
            XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 2))
            XCTAssertFalse(services.isExecutionEnabled)
            XCTAssertEqual(app.activeProfileID, profileID)
            XCTAssertEqual(app.effectivePolicy?.fields[self.t07ID("ui.units")]?.value,
                           .stored(.choice("decimal")))
            try await io.probe.waitFor("config.2")
            io.probe.release("config.2")
            await services.policyBridge.drain()
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 2))
            XCTAssertTrue(services.isExecutionEnabled)
            let loadResult = await services.settings.load()
            let loaded = try XCTUnwrap(loadResult.envelope)
            XCTAssertEqual(loaded.activeProfileID, profileID)
            let reopened = await AppExecutionServices.bootstrap(paths: s.paths)
            XCTAssertEqual(reopened.configStore.activeProfileID, profileID)
            XCTAssertEqual(reopened.configStore.effectivePolicy?
                .fields[self.t07ID("ui.units")]?.value, .stored(.choice("decimal")))
        }
    }

    func testNameAndInertAreStorageOnlyButMixedFieldInvalidates() async throws {
        try await run(stops: ["config.3"]) { _, services, io in
            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            let original = self.t07Profile(profileID, "Original")
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                profiles: [.insert(original)])) else { return XCTFail("Insert rejected") }
            await services.policyBridge.drain()
            let beforeGeneration = services.policyBridge.updateGeneration
            let inert = InertPortableSetting(scope: .profile, profileID: profileID,
                id: "future.flag", value: .bool(true), valueKind: nil,
                valueDigest: nil, redacted: false)
            let renamed = self.t07Profile(profileID, "Renamed")
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 1,
                profiles: [.update(id: profileID, base: original, edited: renamed)],
                inert: [.init(item: inert, presentInBase: false, presentAfterEdit: true)]))
            else { return XCTFail("Storage-only edit rejected") }
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            XCTAssertEqual(services.policyBridge.updateGeneration, beforeGeneration)
            await services.policyBridge.drain()
            XCTAssertEqual(services.configStore.inertImports, [inert])

            let invalidating = self.t07Profile(profileID, "Renamed",
                                                [("scan.preset", .choice("eco"))])
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 2,
                profiles: [.update(id: profileID, base: renamed, edited: invalidating)]))
            else { return XCTFail("Mixed invalidating edit rejected") }
            XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 2))
            try await io.probe.waitFor("config.3")
            io.probe.release("config.3")
        }
    }

    func testDeletingActiveProfileFallsBackToGlobalAndInvalidates() async throws {
        try await run { _, services, _ in
            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            let profile = self.t07Profile(profileID, "Work", [("ui.units", .choice("decimal"))])
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                global: [.init(id: self.t07ID("ui.units"), baseValue: nil,
                               editedValue: .choice("binary"))], profiles: [.insert(profile)],
                activeProfileBase: nil, activeProfileEdit: profileID,
                touchesActiveProfile: true)) else { return XCTFail("Setup rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(services.configStore.effectivePolicy?
                .fields[self.t07ID("ui.units")]?.value, .stored(.choice("decimal")))
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 1,
                profiles: [.delete(id: profileID, base: profile)],
                activeProfileBase: profileID, activeProfileEdit: nil,
                touchesActiveProfile: true)) else { return XCTFail("Delete rejected") }
            XCTAssertNil(services.configStore.activeProfileID)
            XCTAssertEqual(services.configStore.effectivePolicy?
                .fields[self.t07ID("ui.units")]?.value, .stored(.choice("binary")))
            XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 3))
            await services.policyBridge.drain()
            let loadResult = await services.settings.load()
            XCTAssertEqual(loadResult.envelope?.activeProfileID, nil)
        }
    }

    func testTwoWindowStoresSynchronizeOrderedSavedDocuments() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let loaded = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: loaded, bridge: services.policyBridge)
            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            let profile = self.t07Profile(profileID, "First")
            guard case .accepted = first.submit(document: .init(baseRevision: 0,
                profiles: [.insert(profile)])) else { return XCTFail("First-window edit rejected") }
            XCTAssertEqual(first.preferences.profiles, [profile])
            XCTAssertTrue(second.preferences.profiles.isEmpty)
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            await services.policyBridge.drain()
            XCTAssertEqual(second.preferences.profiles, [profile])
            let renamed = self.t07Profile(profileID, "Second")
            guard case .accepted = second.submit(document: .init(baseRevision: 1,
                profiles: [.update(id: profileID, base: profile, edited: renamed)]))
            else { return XCTFail("Second-window edit rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(first.preferences.profiles, [renamed])
            XCTAssertEqual(second.preferences.profiles, [renamed])
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
        }
    }

    func testFailedDocumentHeadConflictsDependentTailWithoutVanishingState() async throws {
        try await run(stops: ["config.1"], fault: .configReplaceNumber(1)) { _, services, io in
            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            let first = self.t07Profile(profileID, "First",
                                        [("scan.preset", .choice("eco"))])
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                profiles: [.insert(first)])) else { return XCTFail("Head rejected") }
            let second = self.t07Profile(profileID, "Second",
                                         [("scan.preset", .choice("eco"))])
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                profiles: [.update(id: profileID, base: first, edited: second)]))
            else { return XCTFail("Tail rejected") }
            XCTAssertEqual(services.configStore.preferences.profiles, [second])
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            await services.policyBridge.drain()
            XCTAssertTrue(services.configStore.preferences.profiles.isEmpty)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertFalse(services.isExecutionEnabled)
            XCTAssertEqual(io.configAttempts, 1)
        }
    }

    func testDocumentAuthorityRejectsBeforeRetentionAndQueueBoundIsShared() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let authority = PreferenceFieldEdit(id: self.t07ID("maintenance.mode"),
                baseValue: nil, editedValue: .choice("authorizedCaches"))
            guard case .rejected(_, .unsupportedAuthority) = services.configStore.submit(
                document: .init(baseRevision: 0, global: [authority]))
            else { return XCTFail("Authority delta was not rejected exactly") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(io.configAttempts, 0)

            let forbiddenID = UUID()
            let forbidden = self.t07Profile(forbiddenID, "Forbidden",
                [("scope.projectRoots", .strings(["/private/project"]))])
            for delta in [PreferencesDocumentDelta(baseRevision: 0,
                                                    profiles: [.insert(forbidden)])] {
                let generation = services.policyBridge.updateGeneration
                guard case .rejected(_, .unsupportedAuthority) =
                    services.configStore.submit(document: delta)
                else { return XCTFail("Profile authority/local delta was not rejected exactly") }
                XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
                XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
                XCTAssertEqual(services.policyBridge.updateGeneration, generation)
                XCTAssertEqual(io.configAttempts, 0)
            }

            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            var base = self.t07Profile(profileID, "P0")
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                profiles: [.insert(base)])) else { return XCTFail("Queue head rejected") }
            try await io.probe.waitFor("config.1")
            for index in 1..<32 {
                let edited = self.t07Profile(profileID, "P\(index)")
                guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                    profiles: [.update(id: profileID, base: base, edited: edited)]))
                else { return XCTFail("Queue item \(index) rejected") }
                base = edited
            }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 32)
            let overflow = self.t07Profile(profileID, "overflow")
            guard case .rejected(_, .queueFull) = services.configStore.submit(document: .init(
                baseRevision: 0, profiles: [.update(id: profileID, base: base, edited: overflow)]))
            else { return XCTFail("33rd document was retained") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 32)
            XCTAssertLessThanOrEqual(services.policyBridge.pendingSnapshotBytes, 32 * 1_048_576)
            io.probe.release("config.1")
        }
    }

    func testProfileUpdateAuthorityRejectsBeforeRetention() async throws {
        let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let clean = self.t07Profile(profileID, "Clean")
        let seedEnvelope = SettingsEnvelope(schemaVersion: 2, revision: 0, config: .init(),
            preferences: .init(profiles: [clean]))
        let seed = try SettingsDecoding.encode(seedEnvelope)
        try await run(seed: seed) { _, services, io in
            let forbidden = self.t07Profile(profileID, "Clean",
                [("scope.projectRoots", .strings(["/private/project"]))])
            let generation = services.policyBridge.updateGeneration
            let delta = PreferencesDocumentDelta(baseRevision: 0, profiles: [
                .update(id: profileID, base: clean, edited: forbidden)
            ])
            guard case .rejected(_, .unsupportedAuthority) =
                services.configStore.submit(document: delta)
            else { return XCTFail("Profile update authority/local delta was not rejected") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(io.configAttempts, 0)
        }
    }

    func testIssuedImportFlowsThroughBridgeAndNeverActivatesImportedProfile() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let importedID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
            let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"scan.preset":{"choice":"eco"}}},"profiles":[{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","name":"Imported","values":{"fields":{"ui.units":{"choice":"decimal"}}}}],"inertImports":[]}"#.utf8)
            let analysis = try await services.configStore.analyzeImport(bytes: bytes)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            guard case .accepted = services.configStore.commitImport(preview)
            else { return XCTFail("Issued import was not admitted") }
            XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 2))
            XCTAssertNil(services.configStore.activeProfileID)
            XCTAssertEqual(services.configStore.preferences.profiles.first?.id, importedID)
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            await services.policyBridge.drain()
            let loadResult = await services.settings.load()
            let durable = try XCTUnwrap(loadResult.envelope)
            XCTAssertEqual(durable.preferences?.profiles.first?.id, importedID)
            XCTAssertNil(durable.activeProfileID)
            XCTAssertEqual(io.configAttempts, 1)
        }
    }

    func testStorageOnlyImportDoesNotInvalidatePolicy() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let generation = services.policyBridge.updateGeneration
            let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
            let analysis = try await services.configStore.analyzeImport(bytes: bytes)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            guard case .accepted = services.configStore.commitImport(preview)
            else { return XCTFail("Storage-only import rejected") }
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            await services.policyBridge.drain()
            XCTAssertEqual(io.configAttempts, 1)
        }
    }

    func testImportPreviewRejectsStaleCancelledReusedForeignAndQueuedBeforeEffects() async throws {
        let portable = Data(#"{"schemaVersion":1,"global":{"fields":{"scan.preset":{"choice":"eco"}}},"profiles":[],"inertImports":[]}"#.utf8)

        try await run { _, services, io in
            let analysis = try await services.configStore.analyzeImport(bytes: portable)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            let profile = self.t07Profile(UUID(), "Storage only")
            guard case .accepted = services.configStore.submit(document: .init(
                baseRevision: 0, profiles: [.insert(profile)])) else {
                return XCTFail("Intervening save rejected")
            }
            await services.policyBridge.drain()
            let generation = services.policyBridge.updateGeneration
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Stale preview was admitted") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(io.configAttempts, 1)
        }

        try await run { _, services, io in
            let analysis = try await services.configStore.analyzeImport(bytes: portable)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            await services.configStore.cancelImport(previewID: preview.id)
            let generation = services.policyBridge.updateGeneration
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Cancelled preview was admitted") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(io.configAttempts, 0)
        }

        try await run { _, services, io in
            let analysis = try await services.configStore.analyzeImport(bytes: portable)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            let foreign = SettingsImportPreview(id: preview.id, analysisID: preview.analysisID,
                rows: preview.rows, collisions: preview.collisions, choices: preview.choices,
                candidate: preview.candidate, sourceDigest: preview.sourceDigest + "x",
                candidateDigest: preview.candidateDigest)
            let generation = services.policyBridge.updateGeneration
            guard case .rejected(_, .invalid) = services.configStore.commitImport(foreign)
            else { return XCTFail("Mutated/foreign preview was admitted") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(io.configAttempts, 0)
        }

        try await run(stops: ["config.1"]) { _, services, io in
            let analysis = try await services.configStore.analyzeImport(bytes: portable)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            guard case .accepted = services.configStore.submit(document: .init(
                baseRevision: 0, profiles: [.insert(self.t07Profile(UUID(), "Queued"))]))
            else { return XCTFail("Queue head rejected") }
            try await io.probe.waitFor("config.1")
            let generation = services.policyBridge.updateGeneration
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Preview entered a nonempty queue") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 1)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(io.configAttempts, 1)
            io.probe.release("config.1")
        }

        try await run(stops: ["config.1"]) { _, services, io in
            let analysis = try await services.configStore.analyzeImport(bytes: portable)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            guard case .accepted = services.configStore.commitImport(preview)
            else { return XCTFail("First commit rejected") }
            let generation = services.policyBridge.updateGeneration
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Preview was admitted twice") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 1)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            await services.policyBridge.drain()
            XCTAssertEqual(io.configAttempts, 1)
        }
    }

    func testForeignSavedAcknowledgementReplaysLocalPendingTransform() async throws {
        try await run(stops: ["config.1", "config.2"]) { _, services, io in
            let loaded = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: loaded, bridge: services.policyBridge)
            let aID = UUID(), bID = UUID()
            let a = self.t07Profile(aID, "A")
            let b = self.t07Profile(bID, "B")
            guard case .accepted = first.submit(document: .init(baseRevision: 0,
                profiles: [.insert(a)])) else { return XCTFail("A rejected") }
            guard case .accepted = second.submit(document: .init(baseRevision: 0,
                profiles: [.insert(b)])) else { return XCTFail("B rejected") }
            XCTAssertEqual(Set(second.preferences.profiles.map(\.id)), Set([bID]))
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            try await io.probe.waitFor("config.2")
            XCTAssertEqual(Set(second.preferences.profiles.map(\.id)), Set([aID, bID]))
            io.probe.release("config.2")
            await services.policyBridge.drain()
            XCTAssertEqual(Set(first.preferences.profiles.map(\.id)), Set([aID, bID]))
            XCTAssertEqual(Set(second.preferences.profiles.map(\.id)), Set([aID, bID]))
        }
    }

    func testForeignFailureAndDependentConflictDoNotBlockLaterSavedAcknowledgement() async throws {
        try await run(stops: ["config.1"], fault: .configReplaceNumber(1)) { _, services, io in
            let loaded = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: loaded, bridge: services.policyBridge)
            let id = UUID()
            let head = self.t07Profile(id, "Head", [("scan.preset", .choice("eco"))])
            let tail = self.t07Profile(id, "Tail", [("scan.preset", .choice("eco"))])
            guard case .accepted = first.submit(document: .init(baseRevision: 0,
                profiles: [.insert(head)])) else { return XCTFail("Head rejected") }
            guard case .accepted = second.submit(document: .init(baseRevision: 0,
                profiles: [.update(id: id, base: head, edited: tail)]))
            else { return XCTFail("Dependent tail rejected before exact execution") }
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            await services.policyBridge.drain()
            XCTAssertTrue(first.preferences.profiles.isEmpty)
            XCTAssertTrue(second.preferences.profiles.isEmpty)

            let units = PreferenceFieldEdit(id: self.t07ID("ui.units"), baseValue: nil,
                                            editedValue: .choice("decimal"))
            guard case .accepted = first.submit(document: .init(baseRevision: 0,
                global: [units])) else { return XCTFail("Fresh unrelated save rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(second.preferences.global.fields[self.t07ID("ui.units")],
                           .choice("decimal"))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertEqual(io.configAttempts, 2)
        }
    }

    func testImportAccountingIsExactDeterministicBoundedAndOverflowSafe() async throws {
        let ids = [
            UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        ]
        let localProfiles = ids.enumerated().map {
            self.t07Profile($0.element, "Local-\($0.offset)")
        }
        let seedEnvelope = SettingsEnvelope(schemaVersion: 2, revision: 0, config: .init(),
            preferences: .init(profiles: localProfiles))
        let seed = try SettingsDecoding.encode(seedEnvelope)
        let importedProfiles = ids.enumerated().map {
            self.t07Profile($0.element, "Imported-\($0.offset)", [
                ("ui.units", .choice($0.offset == 0 ? "decimal" : "binary"))
            ])
        }
        let imported = PortableSettingsState(preferences: .init(global: self.t07Values([
            ("scan.preset", .choice("eco")), ("history.enabled", .bool(true)),
            ("history.retentionDays", .integer(30))
        ]), profiles: importedProfiles), inertImports: [
            .init(scope: .global, profileID: nil, id: "future.bool", value: .bool(true),
                  valueKind: nil, valueDigest: nil, redacted: false),
            .init(scope: .global, profileID: nil, id: "future.integer", value: .integer(7),
                  valueKind: nil, valueDigest: nil, redacted: false),
            .init(scope: .profile, profileID: ids[0], id: "future.null", value: .null,
                  valueKind: nil, valueDigest: nil, redacted: false),
            .init(scope: .global, profileID: nil, id: "future.redacted", value: nil,
                  valueKind: .choice, valueDigest: String(repeating: "a", count: 64),
                  redacted: true)
        ])
        let importBytes = try SettingsTransfer.export(imported)
        let choices: [UUID: ProfileCollisionChoice] = [
            ids[0]: .keepLocal, ids[1]: .replace,
            ids[2]: .clone(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!)
        ]

        try await run(seed: seed) { s, services, io in
            func bridge(limit: Int) -> ExecutionPolicyBridge {
                ExecutionPolicyBridge(coordinator: services.coordinator,
                    settings: services.settings, loaded: services.settingsLoad,
                    homeDirectory: s.home.path, detectedTools: [],
                    pendingByteLimit: limit)
            }
            func issue(_ bridge: ExecutionPolicyBridge) async throws -> SettingsImportPreview {
                let app = AppConfigStore(loaded: try XCTUnwrap(services.settingsLoad.envelope),
                                         bridge: bridge)
                let analysis = try await app.analyzeImport(bytes: importBytes)
                return try await app.issueImportPreview(
                    analysisID: try XCTUnwrap(analysis.analysisID), choices: choices)
            }
            func copy(_ value: SettingsImportPreview, id: UUID? = nil,
                      analysisID: UUID? = nil, rows: [SettingsImportRow]? = nil,
                      collisions: [ProfileImportCollision]? = nil,
                      choices: [UUID: ProfileCollisionChoice]? = nil,
                      candidate: PortableSettingsState? = nil,
                      sourceDigest: String? = nil,
                      candidateDigest: String? = nil) -> SettingsImportPreview {
                SettingsImportPreview(id: id ?? value.id,
                    analysisID: analysisID ?? value.analysisID,
                    rows: rows ?? value.rows, collisions: collisions ?? value.collisions,
                    choices: choices ?? value.choices, candidate: candidate ?? value.candidate,
                    sourceDigest: sourceDigest ?? value.sourceDigest,
                    candidateDigest: candidateDigest ?? value.candidateDigest)
            }

            let reference = bridge(limit: 32 * 1_048_576)
            let referencePreview = try await issue(reference)
            let intent = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
            let accounting = try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0, preview: referencePreview)
            XCTAssertEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0, preview: referencePreview))
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: UUID(), expectedRevision: 0, preview: referencePreview))
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 1, preview: referencePreview))
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, id: UUID(), analysisID: UUID())))
            var rows = referencePreview.rows
            let firstRow = try XCTUnwrap(rows.first)
            rows[0] = .init(scope: firstRow.scope, profileID: firstRow.profileID,
                id: (firstRow.id ?? "nil") + "x", idDigest: firstRow.idDigest,
                outcome: firstRow.outcome, value: firstRow.value,
                valueKind: firstRow.valueKind, valueDigest: firstRow.valueDigest)
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, rows: rows)))
            let rowVariants: [SettingsImportRow] = [
                .init(scope: firstRow.scope == .global ? .profile : .global,
                      profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: firstRow.idDigest, outcome: firstRow.outcome,
                      value: firstRow.value, valueKind: firstRow.valueKind,
                      valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: UUID(), id: firstRow.id,
                      idDigest: firstRow.idDigest, outcome: firstRow.outcome,
                      value: firstRow.value, valueKind: firstRow.valueKind,
                      valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: (firstRow.idDigest ?? "none") + "x",
                      outcome: firstRow.outcome, value: firstRow.value,
                      valueKind: firstRow.valueKind, valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: firstRow.idDigest,
                      outcome: firstRow.outcome == .committable ? .inert : .committable,
                      value: firstRow.value, valueKind: firstRow.valueKind,
                      valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: firstRow.idDigest, outcome: firstRow.outcome,
                      value: .choice("changed"), valueKind: firstRow.valueKind,
                      valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: firstRow.idDigest, outcome: firstRow.outcome,
                      value: firstRow.value,
                      valueKind: firstRow.valueKind == .strings ? .choice : .strings,
                      valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: firstRow.idDigest, outcome: firstRow.outcome,
                      value: firstRow.value, valueKind: firstRow.valueKind,
                      valueDigest: (firstRow.valueDigest ?? "none") + "x")
            ]
            for variant in rowVariants {
                var changedRows = referencePreview.rows
                changedRows[0] = variant
                XCTAssertNotEqual(accounting,
                    try ExecutionPolicyBridge.retainedImportAccountingData(
                        intentID: intent, expectedRevision: 0,
                        preview: copy(referencePreview, rows: changedRows)))
            }
            var collisions = referencePreview.collisions
            let firstCollision = try XCTUnwrap(collisions.first)
            collisions[0] = .init(profileID: firstCollision.profileID,
                                  localName: firstCollision.localName + "x",
                                  importedName: firstCollision.importedName)
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, collisions: collisions)))
            for changedCollision in [
                ProfileImportCollision(profileID: UUID(), localName: firstCollision.localName,
                    importedName: firstCollision.importedName),
                ProfileImportCollision(profileID: firstCollision.profileID,
                    localName: firstCollision.localName,
                    importedName: firstCollision.importedName + "x")
            ] {
                var changed = referencePreview.collisions
                changed[0] = changedCollision
                XCTAssertNotEqual(accounting,
                    try ExecutionPolicyBridge.retainedImportAccountingData(
                        intentID: intent, expectedRevision: 0,
                        preview: copy(referencePreview, collisions: changed)))
            }
            var changedChoices = referencePreview.choices
            changedChoices[ids[0]] = .replace
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, choices: changedChoices)))
            var rekeyedChoices = referencePreview.choices
            let movedChoice = rekeyedChoices.removeValue(forKey: ids[0])
            rekeyedChoices[UUID()] = try XCTUnwrap(movedChoice)
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, choices: rekeyedChoices)))
            var changedGlobal = referencePreview.candidate
            changedGlobal.preferences.global.fields[self.t07ID("ui.units")] = .choice("decimal")
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, candidate: changedGlobal)))
            let baseProfile = try XCTUnwrap(referencePreview.candidate.preferences.profiles.first)
            var changedProfileIdentity = referencePreview.candidate
            changedProfileIdentity.preferences.profiles[0] = .init(id: UUID(),
                name: baseProfile.name, values: baseProfile.values)
            var changedProfileName = referencePreview.candidate
            changedProfileName.preferences.profiles[0] = .init(id: baseProfile.id,
                name: baseProfile.name + "x", values: baseProfile.values)
            var profileValues = baseProfile.values
            profileValues.fields[self.t07ID("history.enabled")] = .bool(false)
            var changedProfileValues = referencePreview.candidate
            changedProfileValues.preferences.profiles[0] = .init(id: baseProfile.id,
                name: baseProfile.name, values: profileValues)
            for candidate in [changedProfileIdentity, changedProfileName, changedProfileValues] {
                XCTAssertNotEqual(accounting,
                    try ExecutionPolicyBridge.retainedImportAccountingData(
                        intentID: intent, expectedRevision: 0,
                        preview: copy(referencePreview, candidate: candidate)))
            }
            var changedCandidate = referencePreview.candidate
            changedCandidate.inertImports.append(.init(scope: .global, profileID: nil,
                id: "future.extra", value: .bool(false), valueKind: nil,
                valueDigest: nil, redacted: false))
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, candidate: changedCandidate)))
            let baseInert = try XCTUnwrap(referencePreview.candidate.inertImports.first)
            let inertVariants: [InertPortableSetting] = [
                .init(scope: baseInert.scope == .global ? .profile : .global,
                      profileID: baseInert.profileID, id: baseInert.id, value: baseInert.value,
                      valueKind: baseInert.valueKind, valueDigest: baseInert.valueDigest,
                      redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: UUID(), id: baseInert.id,
                      value: baseInert.value, valueKind: baseInert.valueKind,
                      valueDigest: baseInert.valueDigest, redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: baseInert.profileID,
                      id: baseInert.id + "x", value: baseInert.value,
                      valueKind: baseInert.valueKind, valueDigest: baseInert.valueDigest,
                      redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: baseInert.profileID, id: baseInert.id,
                      value: .integer(99), valueKind: baseInert.valueKind,
                      valueDigest: baseInert.valueDigest, redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: baseInert.profileID, id: baseInert.id,
                      value: baseInert.value, valueKind: .choice,
                      valueDigest: baseInert.valueDigest, redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: baseInert.profileID, id: baseInert.id,
                      value: baseInert.value, valueKind: baseInert.valueKind,
                      valueDigest: "digest-x", redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: baseInert.profileID, id: baseInert.id,
                      value: baseInert.value, valueKind: baseInert.valueKind,
                      valueDigest: baseInert.valueDigest, redacted: !baseInert.redacted)
            ]
            for variant in inertVariants {
                var candidate = referencePreview.candidate
                candidate.inertImports[0] = variant
                XCTAssertNotEqual(accounting,
                    try ExecutionPolicyBridge.retainedImportAccountingData(
                        intentID: intent, expectedRevision: 0,
                        preview: copy(referencePreview, candidate: candidate)))
            }
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, sourceDigest: referencePreview.sourceDigest + "x",
                              candidateDigest: referencePreview.candidateDigest + "x")))
            await reference.cancelImport(previewID: referencePreview.id)

            let limited = bridge(limit: accounting.count - 1)
            let limitedPreview = try await issue(limited)
            let limitedApp = AppConfigStore(loaded: try XCTUnwrap(services.settingsLoad.envelope),
                                            bridge: limited)
            let generation = limited.updateGeneration
            guard case .rejected(_, .queueFull) = limitedApp.commitImport(limitedPreview)
            else { return XCTFail("Below-exact import byte limit admitted") }
            XCTAssertEqual(limited.pendingSnapshotCount, 0)
            XCTAssertEqual(limited.pendingSnapshotBytes, 0)
            XCTAssertEqual(limited.updateGeneration, generation)
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            XCTAssertEqual(io.configAttempts, 0)
            await limitedApp.cancelImport(previewID: limitedPreview.id)

            let exact = bridge(limit: accounting.count)
            let exactPreview = try await issue(exact)
            let exactApp = AppConfigStore(loaded: try XCTUnwrap(services.settingsLoad.envelope),
                                          bridge: exact)
            guard case .accepted(_, let completion) = exactApp.commitImport(exactPreview)
            else { return XCTFail("Exact import byte limit rejected") }
            guard case .saved = await completion.value
            else { return XCTFail("Exact-limit import did not save") }
            await exact.drain()
            XCTAssertEqual(exact.pendingSnapshotCount, 0)
            XCTAssertEqual(exact.pendingSnapshotBytes, 0)
            XCTAssertEqual(io.configAttempts, 1)
            XCTAssertThrowsError(try ExecutionPolicyBridge.checkedRetainedTotalForTesting(
                Int.max, adding: 1))
        }
    }
}
```

## Exact accounting RED test

The final app-model RED test constructs an import whose analysis contains multiple value-bearing row shapes, three real profile collisions, all three collision choices (including a clone UUID), candidate global/profile values, inert global/profile entries, IDs and both digests. The bridge owns two internal pure helpers, used by production admission and visible to `@testable` tests:

```swift
internal static func retainedImportAccountingData(
    intentID: SettingsIntentID,
    expectedRevision: UInt64,
    preview: SettingsImportPreview
) throws -> Data
internal static func checkedRetainedTotalForTesting(_ current: Int,
                                                     adding: Int) throws -> Int
```

The accounting helper is the exact production representation and uses `JSONEncoder.outputFormatting = [.sortedKeys]`. The embedded test obtains a real store-issued preview, proves byte determinism, and mutates intent/revision, preview IDs, rows, collisions, choices, candidate data and digests to prove each category affects the encoded accounting data. It then creates otherwise identical bridges one byte below and exactly at the measured size, verifies rejection has no effects and leaves the token cancellable, drains the exact-limit admitted task/ticket, and invokes the real checked-add overflow helper. This proves coverage rather than merely checking a positive total.

## Commands and acceptance

- [ ] Append only the RED extension and run the focused `TidyAppModelTests` scheme with `-only-testing:TidyAppModelTests/SharedSettingsWiringTests`; capture missing-symbol failures.
- [ ] Add the pure shared projection and refactor store document application; run T07.2a core tests plus policy persistence/transfer.
- [ ] Add bridge payload admission/accounting/prediction/perform logic; run the focused app-model tests including exact import accounting.
- [ ] Add AppConfigStore replay, all-window acknowledgement, import forwarding and selected-profile resolution; run focused GREEN.
- [ ] Run ordinary core, isolated bounded/settings-process partitions, all app-model tests and unsigned arm64 app build with two jobs.
- [ ] Run `git diff --check`, exact allowlist audit and fresh adversarial source review. Every finding requires a regression before correction.
- [ ] Commit source/tests, then acceptance evidence/progress ledger separately.

## Acceptance boundary

Passing T07.2b completes only T07.2 durable/shared handoff. T07.3a registry UI, T07.3b workflows, T07.3d bounded clearing, T07.4 hostile coordinator regression, T22.3 local reassociation, T22.4 accepted-adapter hostile regression, device/accessibility/performance gates and release work remain open.
