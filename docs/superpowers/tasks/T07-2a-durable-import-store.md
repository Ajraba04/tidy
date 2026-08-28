# T07.2a Durable Profile State and Issued Import Preview Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use test-driven-development, then requesting-code-review and verification-before-completion. Steps use checkbox syntax. No production edit is allowed until this card is independently approved.

**Goal:** Extend the single durable schema-2 settings owner with active-profile and inert-import state, exact base-bound document deltas, and actor-issued single-use import previews that can publish only the reviewed candidate.

**Architecture:** `SettingsEnvelope` remains the only persisted settings document and `SettingsStore` remains its only writer. Pure `SettingsTransfer` analysis stays non-committable; the store retains bounded UUID bindings for one analysis and one resolved preview, binds them to exact loaded disk identity and cryptographic digests, and consumes a preview before its sole publication attempt. T07.2b will route the accepted delta through the existing bridge/app owner; this card does not modify app or coordinator code.

**Tech Stack:** Swift 5, Foundation, CryptoKit, Swift Testing, the accepted T05 settings publication protocol and T07.1 transfer/profile policy.

## Global constraints

- Native Swift/SwiftUI, macOS 14+, no new dependency and no network access.
- No authority, consent, path, executable, endpoint, project/volume identity or capability may be created by settings import.
- Missing `activeProfileID` and `inertImports` on old schema-2 bytes decode as `nil` and `[]`; malformed selection or inert state enters read-only recovery without rewriting bytes.
- Active selection names exactly one saved profile. Imported profiles never activate. Deleting the active profile atomically sets selection to nil.
- Every touched delta base is compared exactly. Unrelated settings survive; any conflicting touched base rejects atomically.
- A store load, external disk change, any successful save, recovery latch, new analysis, new preview or cancellation invalidates older import tokens.
- Commit accepts only `(expectedRevision, previewID)`: no choices, source bytes or replacement candidate. It consumes the token before one publication attempt.
- This card changes no app source, creates no second writer/revision stream and grants no execution authority.

## Exact allowlist

- Modify `docs/superpowers/tasks/T07-settings-customization-entry.md` only for the controlled T07.2a/T07.2b checkpoint split and the analysis-cancellation lifecycle refinement recorded with this card.
- Create this preimplementation card; it is committed before any production/test entry.
- Modify `TidyCore/Sources/TidyCore/Policy/SettingsEnvelope.swift`: additive envelope fields, strict wire parsing/encoding validation, delta declarations.
- Modify `TidyCore/Sources/TidyCore/Policy/SettingsTransfer.swift`: Codable inert wire plus internal complete-state validation and store-only analysis rebinding helpers; no I/O.
- Modify `TidyCore/Sources/TidyCore/Policy/SettingsStore.swift`: exact delta application and issued analysis/preview lifecycle.
- Create `TidyCore/Tests/TidyCoreTests/SettingsProfilePersistenceTests.swift`: complete RED suite below.
- Modify `TidyCore/Tests/TidyCoreTests/SettingsProcessAcceptanceTests.swift`: add both `Policy/SessionProfile.swift` and `Policy/SettingsTransfer.swift` to the explicit standalone compiler manifest because the envelope now owns inert state and transfer depends on profile policy. Both files must be present in the generated source SHA-256 manifest.
- Create `docs/verification/T07-2a-durable-import-store.md` only after GREEN and review.

No `ExecutionPolicyBridge`, `AppConfigStore`, SwiftUI, coordinator, publication algorithm, journal protocol or existing test file beyond the compiler manifest may change in this unit.

## Exact interfaces

Additive envelope shape:

```swift
public struct SettingsEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let revision: UInt64
    public let config: TidyConfig
    public let preferences: PolicyPreferences?
    public let activeProfileID: UUID?
    public let inertImports: [InertPortableSetting]

    public init(schemaVersion: Int, revision: UInt64, config: TidyConfig,
                preferences: PolicyPreferences? = nil,
                activeProfileID: UUID? = nil,
                inertImports: [InertPortableSetting] = [])
}
```

Base-bound delta declarations:

```swift
public struct PreferenceFieldEdit: Equatable, Sendable {
    public let id: SettingID
    public let baseValue: SettingValue?
    public let editedValue: SettingValue?
    public init(id: SettingID, baseValue: SettingValue?, editedValue: SettingValue?)
}

public enum ProfileDocumentEdit: Equatable, Sendable {
    case insert(SavedProfile)
    case update(id: UUID, base: SavedProfile, edited: SavedProfile)
    case delete(id: UUID, base: SavedProfile)
}

public struct InertImportEdit: Equatable, Sendable {
    public let item: InertPortableSetting
    public let presentInBase: Bool
    public let presentAfterEdit: Bool
    public init(item: InertPortableSetting, presentInBase: Bool, presentAfterEdit: Bool)
}

public struct PreferencesDocumentDelta: Equatable, Sendable {
    public let baseRevision: UInt64
    public let global: [PreferenceFieldEdit]
    public let profiles: [ProfileDocumentEdit]
    public let activeProfileBase: UUID?
    public let activeProfileEdit: UUID?
    public let touchesActiveProfile: Bool
    public let inert: [InertImportEdit]
    public init(baseRevision: UInt64, global: [PreferenceFieldEdit] = [],
                profiles: [ProfileDocumentEdit] = [],
                activeProfileBase: UUID? = nil, activeProfileEdit: UUID? = nil,
                touchesActiveProfile: Bool = false,
                inert: [InertImportEdit] = [])
}
```

`touchesActiveProfile` distinguishes “selection untouched” from “explicitly set nil”; absent/default values are not conflated. Duplicate touched global IDs, profile IDs or inert keys reject. Insert requires absence; update/delete require exact base equality. `ProfileDocumentEdit.update` requires `edited.id == id`; duplicate final UUIDs reject. Inert keys are `(scope, profileID, id)` and every removal/addition compares exact whole values.

`baseRevision` may be older than the current revision only when every touched base still matches exactly; a future revision rejects. Deleting the active profile is rejected unless the same delta has `touchesActiveProfile == true`, `activeProfileBase` equals that UUID and `activeProfileEdit == nil`. Activation requires the selected UUID to exist in the final profile set. Profile inserts/updates pass T07.1b profile validation, so authority, local identity, project identity and volume identity reject. Inert additions may reference a profile inserted by the same delta, but an occupied key, wrong whole-value removal base or final orphan rejects.

Add `case preferencesDocument(PreferencesDocumentDelta)` to `SettingsChange`. Store application preserves projects and untouched fields, reverse-projects only touched compatibility globals, validates the complete candidate, and increments revision once only after successful publication.

Issued import surface:

```swift
public typealias SettingsImportAnalysisID = UUID
public typealias SettingsImportPreviewID = UUID

public struct SettingsImportPreview: Equatable, Sendable {
    public let id: SettingsImportPreviewID
    public let analysisID: SettingsImportAnalysisID
    public let rows: [SettingsImportRow]
    public let collisions: [ProfileImportCollision]
    public let choices: [UUID: ProfileCollisionChoice]
    public let candidate: PortableSettingsState
    public let sourceDigest: String
    public let candidateDigest: String
}

extension SettingsStore {
    public func analyzeImport(bytes: Data) throws -> SettingsImportAnalysis
    public func issueImportPreview(analysisID: SettingsImportAnalysisID,
                                   choices: [UUID: ProfileCollisionChoice]) throws
        -> SettingsImportPreview
    public func commitImport(expectedRevision: UInt64,
                             previewID: SettingsImportPreviewID) throws -> SettingsEnvelope
    public func cancelImport(analysisID: SettingsImportAnalysisID)
    public func cancelImport(previewID: SettingsImportPreviewID)
}
```

Add `public let analysisID: UUID?` to `SettingsImportAnalysis`. `SettingsTransfer.analyze` always returns nil; only `SettingsStore.analyzeImport` returns non-nil. The store retains the parsed analysis plus SHA-256 source digest, never the raw source bytes. Its binding includes exact loaded revision and `SettingsDiskImage`. `issueImportPreview` removes the analysis binding before every attempt, then requires its revision/image still exactly match actor and disk state; invalid/missing collision choices therefore also consume it. It resolves a copied choices dictionary, validates the exact complete candidate, preserves current `activeProfileID`, and stores an immutable binding containing: preview UUID, analysis UUID, exact base revision, exact `SettingsDiskImage`, source digest, candidate digest, rows, collision choices and candidate. Public preview construction is unavailable. Explicit analysis cancellation clears parsed analysis immediately.

`SettingsTransfer` exposes only these internal helpers to the store; neither is public and neither performs I/O:

```swift
static func validatePersistedState(_ state: PortableSettingsState) throws
static func issuedAnalysis(_ analysis: SettingsImportAnalysis,
                           identity: SettingsImportAnalysisID) -> SettingsImportAnalysis
```

The first validates the exact unsanitized durable preferences/inert graph. The second copies an already parsed analysis while adding only its opaque store identity; callers cannot construct one.

The candidate digest is SHA-256 of the exact `SettingsDecoding.encode` bytes intended for the next revision: preserved projects and active selection, resolved preferences/inert state, checked `baseRevision + 1`, and the compatibility-projected config. Import preserves every legacy-only and untouched config field while applying `LegacyCompatibilityProjection.reverseProject` from the current global preferences to the resolved imported global preferences. Every changed portable compatibility global is projected: transcript age, stale-node age and advanced-memory visibility may change. Nonportable cookie domains remain exactly preserved in both preferences and config. `commitImport` first removes the binding from actor state, then requires exact expected revision and current disk identity, recomputes those exact bytes/digest, and calls the existing `save` once. Publication failure never re-enables the consumed token. Import never edits projects, unrelated legacy-only fields or active selection. Every successful `save` and every recovery latch clears both import bindings.

## Strict persistence wire

The finite schema-2 root grammar is exactly these four key sets; no other combination is valid:

- `schemaVersion,revision,config` (legacy schema-2);
- the preceding keys plus `preferences`;
- `schemaVersion,revision,config,preferences,inertImports`;
- the preceding keys plus `activeProfileID`.

`activeProfileID` is forbidden without `preferences`; `inertImports` is forbidden without `preferences`; active selection requires a non-nil preferences document and matching profile. New writes with preferences include `inertImports` always and include `activeProfileID` only when non-nil:

```json
{"activeProfileID":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","config":{"allowRestartToReclaimSwap":false,"appsApprovedForQuit":[],"gitRoots":[],"hasCompletedOnboarding":false,"keepCookieDomains":[],"presets":[],"schemaVersion":2,"simulatorsApprovedForDeletion":[],"staleNodeModulesThresholdDays":60,"transcriptAgeThresholdDays":45},"inertImports":[{"id":"future.flag","profileID":null,"redacted":false,"scope":"global","value":{"bool":true},"valueDigest":null,"valueKind":null}],"preferences":{"global":{"fields":{}},"profiles":[{"id":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","name":"Work","values":{"fields":{}}}],"projects":{}},"revision":7,"schemaVersion":2}
```

Persisted profile UUIDs and active UUID use Foundation's canonical uppercase `uuidString`, matching the existing settings-envelope profile wire. Inert records use exactly seven keys shown above. Safe values use exactly one of `bool`, `integer`, or `null:true`; redacted records require `value:null`, lowercase 64-hex digest, non-nil `choice|strings|volume`, and `redacted:true`. Scope/profile ownership, safe IDs, duplicate keys, profile existence, 1,000 inert bound, 4,096 UTF-8 string bound, 4,096 aggregate field bound and 1 MiB final bytes are enforced without truncation. Synthesized enum Codable is forbidden: `SettingsDecoding` must manually construct and parse this closed inert form (or the inert types must implement an equivalent explicit custom Codable form which is then re-parsed by `SettingsDecoding`).

## Complete RED test file

Create the following file verbatim before production edits. The focused command must fail on missing envelope fields, delta and issued-preview APIs.

```swift
import CryptoKit
import Foundation
import Testing
@testable import TidyCore

@Suite struct SettingsProfilePersistenceTests {
    let profileA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let profileB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    func id(_ raw: String) -> SettingID { .init(rawValue: raw) }
    func values(_ pairs: [(String, SettingValue)]) -> PolicyValues {
        .init(fields: Dictionary(uniqueKeysWithValues: pairs.map { (id($0.0), $0.1) }))
    }
    func profile(_ id: UUID, _ name: String, _ pairs: [(String, SettingValue)] = []) -> SavedProfile {
        .init(id: id, name: name, values: values(pairs))
    }
    func inert(_ raw: String, profileID: UUID? = nil) -> InertPortableSetting {
        .init(scope: profileID == nil ? .global : .profile, profileID: profileID,
              id: raw, value: .bool(true), valueKind: nil, valueDigest: nil, redacted: false)
    }

    @Test func olderSchema2DefaultsNewStateWithoutRewrite() async throws {
        let config = #"{"allowRestartToReclaimSwap":false,"appsApprovedForQuit":[],"gitRoots":[],"hasCompletedOnboarding":false,"keepCookieDomains":[],"presets":[],"schemaVersion":2,"simulatorsApprovedForDeletion":[],"staleNodeModulesThresholdDays":60,"transcriptAgeThresholdDays":45}"#
        let variants = [
            Data(#"{"config":\#(config),"revision":7,"schemaVersion":2}"#.utf8),
            Data(#"{"config":\#(config),"preferences":{"global":{"fields":{}},"profiles":[],"projects":{}},"revision":7,"schemaVersion":2}"#.utf8)
        ]
        for bytes in variants {
            let scratch = try T072Scratch(); defer { scratch.remove() }
            try scratch.seed(bytes)
            let result = await SettingsStore(url: scratch.file).load()
            let envelope = try #require(result.envelope)
            #expect(envelope.activeProfileID == nil)
            #expect(envelope.inertImports.isEmpty)
            #expect(try Data(contentsOf: scratch.file) == bytes)
        }
    }

    @Test func finiteRootGrammarAcceptsOnlyFourExactKeySets() async throws {
        let config = #"{"allowRestartToReclaimSwap":false,"appsApprovedForQuit":[],"gitRoots":[],"hasCompletedOnboarding":false,"keepCookieDomains":[],"presets":[],"schemaVersion":2,"simulatorsApprovedForDeletion":[],"staleNodeModulesThresholdDays":60,"transcriptAgeThresholdDays":45}"#
        let base = Data(#"{"config":\#(config),"revision":7,"schemaVersion":2}"#.utf8)
        let preferences = Data(#"{"config":\#(config),"preferences":{"global":{"fields":{}},"profiles":[],"projects":{}},"revision":7,"schemaVersion":2}"#.utf8)
        let inert = Data(#"{"config":\#(config),"inertImports":[],"preferences":{"global":{"fields":{}},"profiles":[],"projects":{}},"revision":7,"schemaVersion":2}"#.utf8)
        let activeEnvelope = SettingsEnvelope(schemaVersion: 2, revision: 7,
            config: TidyConfig(schemaVersion: 2),
            preferences: .init(profiles: [profile(profileA, "A")]),
            activeProfileID: profileA, inertImports: [])
        let active = try SettingsDecoding.encode(activeEnvelope)
        for bytes in [base, preferences, inert, active] {
            let scratch = try T072Scratch(); defer { scratch.remove() }
            try scratch.seed(bytes)
            #expect(await SettingsStore(url: scratch.file).load().envelope != nil)
            #expect(try Data(contentsOf: scratch.file) == bytes)
        }

        let activeRoot = try StrictJSON.parse(active).object()
        var invalidRoots: [[String: StrictJSON.Value]] = []
        var basePlusInert = try StrictJSON.parse(base).object()
        basePlusInert["inertImports"] = .array([]); invalidRoots.append(basePlusInert)
        var basePlusActive = try StrictJSON.parse(base).object()
        basePlusActive["activeProfileID"] = .string(profileA.uuidString); invalidRoots.append(basePlusActive)
        var preferencesPlusActive = activeRoot
        preferencesPlusActive["inertImports"] = nil; invalidRoots.append(preferencesPlusActive)
        for root in invalidRoots {
            let bytes = try StrictJSON.canonicalData(.object(root))
            let scratch = try T072Scratch(); defer { scratch.remove() }
            try scratch.seed(bytes)
            #expect(await SettingsStore(url: scratch.file).load().disposition == .recoveryReadOnly)
            #expect(try Data(contentsOf: scratch.file) == bytes)
        }
    }

    @Test func activeAndInertRoundTripWhileInvalidSelectionRecoversReadOnly() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let savedProfile = profile(profileA, "Work")
        let delta = PreferencesDocumentDelta(baseRevision: initial.revision,
            profiles: [.insert(savedProfile)], activeProfileBase: nil,
            activeProfileEdit: profileA, touchesActiveProfile: true,
            inert: [.init(item: inert("future.flag"), presentInBase: false, presentAfterEdit: true)])
        let saved = try await store.update(expectedRevision: initial.revision,
                                           change: .preferencesDocument(delta))
        #expect(saved.activeProfileID == profileA)
        #expect(saved.inertImports == [inert("future.flag")])
        #expect(try #require(await SettingsStore(url: scratch.file).load().envelope) == saved)

        let root = try StrictJSON.parse(try Data(contentsOf: scratch.file)).object()
        var invalid = root
        invalid["activeProfileID"] = .string(profileB.uuidString)
        let invalidBytes = try StrictJSON.canonicalData(.object(invalid))
        try scratch.replace(invalidBytes)
        let recovery = await SettingsStore(url: scratch.file).load()
        #expect(recovery.disposition == .recoveryReadOnly)
        #expect(try Data(contentsOf: scratch.file) == invalidBytes)
    }

    @Test func exactDocumentDeltaPreservesUnrelatedAndRejectsTouchedConflict() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let local = profile(profileA, "Local", [("ui.units", .choice("decimal"))])
        let base = PreferencesDocumentDelta(baseRevision: initial.revision,
            profiles: [.insert(local)])
        let one = try await store.update(expectedRevision: initial.revision,
                                         change: .preferencesDocument(base))
        let rename = PreferencesDocumentDelta(baseRevision: one.revision,
            profiles: [.update(id: profileA, base: local,
                edited: profile(profileA, "Renamed", [("ui.units", .choice("decimal"))]))])
        let units = GlobalPreferenceDelta(baseRevision: one.revision, id: id("ui.density"),
                                          baseValue: nil, editedValue: .choice("compact"))
        let two = try await store.update(expectedRevision: one.revision,
                                         change: .globalPreferenceDelta(units))
        let three = try await store.update(expectedRevision: two.revision,
                                           change: .preferencesDocument(rename))
        #expect(three.preferences?.global.fields[id("ui.density")] == .choice("compact"))
        #expect(three.preferences?.profiles.first?.name == "Renamed")
        do {
            _ = try await store.update(expectedRevision: three.revision,
                                       change: .preferencesDocument(rename))
            Issue.record("Conflicting profile base was accepted")
        } catch let error as SettingsStoreError { #expect(error == .staleRevision) }
    }

    @Test func touchedCompatibilityGlobalReverseProjectsWithoutChangingUntouchedLegacy() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let edit = PreferenceFieldEdit(id: id("cleanup.transcriptDays"), baseValue: nil,
                                       editedValue: .integer(90))
        let saved = try await store.update(expectedRevision: initial.revision,
            change: .preferencesDocument(.init(baseRevision: initial.revision, global: [edit])))
        #expect(saved.config.transcriptAgeThresholdDays == 90)
        #expect(saved.config.staleNodeModulesThresholdDays == initial.config.staleNodeModulesThresholdDays)
        #expect(saved.config.keepCookieDomains == initial.config.keepCookieDomains)
        #expect(saved.config.allowRestartToReclaimSwap == initial.config.allowRestartToReclaimSwap)
    }

    @Test func deletingActiveProfileClearsSelectionAtomically() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let local = profile(profileA, "Local")
        let created = try await store.update(expectedRevision: initial.revision,
            change: .preferencesDocument(.init(baseRevision: initial.revision,
                profiles: [.insert(local)], activeProfileBase: nil,
                activeProfileEdit: profileA, touchesActiveProfile: true)))
        let deleted = try await store.update(expectedRevision: created.revision,
            change: .preferencesDocument(.init(baseRevision: created.revision,
                profiles: [.delete(id: profileA, base: local)], activeProfileBase: profileA,
                activeProfileEdit: nil, touchesActiveProfile: true)))
        #expect(deleted.preferences?.profiles.isEmpty == true)
        #expect(deleted.activeProfileID == nil)
        #expect(deleted.revision == created.revision + 1)
    }

    @Test func authorityAndMalformedMixedDeltaRejectBeforePublication() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let authority = PreferenceFieldEdit(id: id("maintenance.mode"), baseValue: nil,
                                             editedValue: .choice("authorizedCaches"))
        let safe = PreferenceFieldEdit(id: id("ui.units"), baseValue: nil,
                                        editedValue: .choice("decimal"))
        do {
            _ = try await store.update(expectedRevision: initial.revision,
                change: .preferencesDocument(.init(baseRevision: initial.revision,
                                                    global: [safe, authority])))
            Issue.record("Authority-bearing mixed delta was accepted")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.root.path).isEmpty)
    }

    @Test func hostileBytesThroughStoreCommitOnlySafePortableAndInertRows() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let local = profile(profileA, "Local")
        let project = values([("cleanup.inactiveDays", .integer(60))])
        let seeded = try await store.update(expectedRevision: initial.revision,
            change: .preferences(PolicyPreferences(profiles: [local], projects: ["local": project])))
        let selected = try await store.update(expectedRevision: seeded.revision,
            change: .preferencesDocument(.init(baseRevision: seeded.revision,
                activeProfileBase: nil, activeProfileEdit: profileA, touchesActiveProfile: true)))
        let bytes = Data("""
        {"schemaVersion":1,"global":{"fields":{
          "ui.units":{"choice":"decimal"},
          "future.safe":{"bool":true},
          "maintenance.mode":{"choice":"authorizedCaches"},
          "notifications.enabled":{"bool":true},
          "app.launchAtLogin":{"bool":true},
          "monitor.backgroundEnabled":{"bool":true},
          "scope.projectRoots":{"strings":["/Users/alice/project"]},
          "scope.currentProject":{"choice":"secret-project"},
          "tools.approvedExecutables":{"strings":["/usr/local/bin/tool"]},
          "docker.approvedEndpoints":{"strings":["unix:///private/docker.sock"]},
          "simulators.approvedDeletionUDIDs":{"strings":["DEVICE-1"]},
          "rescue.approvedApplications":{"strings":["com.example.secret"]},
          "headroom.volumeOverrides.\(profileB.uuidString)":{"volume":{"target":{"fixedGiB":12},"warning":{"automatic":true},"clear":{"inherit":true}}}
        }},"profiles":[],"inertImports":[]}
        """.utf8)
        let analysis = try await store.analyzeImport(bytes: bytes)
        let outcomes = Dictionary(uniqueKeysWithValues: analysis.rows.compactMap { row in
            row.id.map { ($0, row.outcome) }
        })
        for rejected in ["maintenance.mode", "notifications.enabled", "app.launchAtLogin",
                         "monitor.backgroundEnabled"] {
            #expect(outcomes[rejected] == .rejectedAuthority)
        }
        for local in ["scope.projectRoots", "scope.currentProject", "tools.approvedExecutables",
                      "docker.approvedEndpoints", "simulators.approvedDeletionUDIDs",
                      "rescue.approvedApplications",
                      "headroom.volumeOverrides.\(profileB.uuidString)"] {
            #expect(outcomes[local] == .requiresLocalReassociation)
        }
        #expect(outcomes["ui.units"] == .committable)
        #expect(outcomes["future.safe"] == .inert)
        let preview = try await store.issueImportPreview(
            analysisID: try #require(analysis.analysisID), choices: [:])
        let committed = try await store.commitImport(expectedRevision: selected.revision,
                                                     previewID: preview.id)
        #expect(committed.preferences?.global.fields == values([("ui.units", .choice("decimal"))]).fields)
        #expect(committed.preferences?.projects == ["local": project])
        #expect(committed.preferences?.profiles == [local])
        #expect(committed.activeProfileID == profileA)
        #expect(committed.config == selected.config)
        #expect(committed.inertImports.map(\.id) == ["future.safe"])
        let durable = try #require(await SettingsStore(url: scratch.file).load().envelope)
        #expect(durable == committed)
        let encoded = String(decoding: try Data(contentsOf: scratch.file), as: UTF8.self)
        for forbidden in ["authorizedCaches", "/Users/alice", "/usr/local/bin/tool",
                          "docker.sock", "DEVICE-1", "com.example.secret", "secret-project",
                          profileB.uuidString] {
            #expect(!encoded.contains(forbidden))
        }
    }

    @Test func importReverseProjectsOnlyChangedCompatibilityGlobals() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"cleanup.transcriptDays":{"integer":90},"rescue.showAdvancedMemoryActions":{"bool":true},"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
        let analysis = try await store.analyzeImport(bytes: bytes)
        let preview = try await store.issueImportPreview(
            analysisID: try #require(analysis.analysisID), choices: [:])
        var projected = initial.config
        projected.transcriptAgeThresholdDays = 90
        projected.allowRestartToReclaimSwap = true
        let expected = SettingsEnvelope(schemaVersion: 2, revision: initial.revision + 1,
            config: projected, preferences: preview.candidate.preferences,
            activeProfileID: initial.activeProfileID,
            inertImports: preview.candidate.inertImports)
        let expectedDigest = SHA256.hash(data: try SettingsDecoding.encode(expected))
            .map { String(format: "%02x", $0) }.joined()
        #expect(preview.candidateDigest == expectedDigest)
        let saved = try await store.commitImport(expectedRevision: initial.revision,
                                                 previewID: preview.id)
        #expect(saved.preferences?.global.fields[id("cleanup.transcriptDays")] == .integer(90))
        #expect(saved.preferences?.global.fields[id("rescue.showAdvancedMemoryActions")] == .bool(true))
        #expect(saved.config.transcriptAgeThresholdDays == 90)
        #expect(saved.config.allowRestartToReclaimSwap)
        #expect(saved.config.staleNodeModulesThresholdDays == initial.config.staleNodeModulesThresholdDays)
        #expect(saved.config.keepCookieDomains == initial.config.keepCookieDomains)
        #expect(saved.config.hasCompletedOnboarding == initial.config.hasCompletedOnboarding)
        #expect(saved.config.gitRoots == initial.config.gitRoots)
        #expect(saved.config.presets == initial.config.presets)
    }

    @Test func issuedPreviewBindsChoicesAndCommitsReviewedCandidateOnce() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let local = profile(profileA, "Local")
        let seeded = try await store.update(expectedRevision: initial.revision,
            change: .preferencesDocument(.init(baseRevision: initial.revision,
                                                profiles: [.insert(local)])))
        let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"Imported","values":{"fields":{"ui.units":{"choice":"decimal"}}}}],"inertImports":[]}"#.utf8)
        let analysis = try await store.analyzeImport(bytes: bytes)
        let analysisID = try #require(analysis.analysisID)
        var choices: [UUID: ProfileCollisionChoice] = [profileA: .replace]
        let preview = try await store.issueImportPreview(analysisID: analysisID, choices: choices)
        choices[profileA] = .keepLocal
        let committed = try await store.commitImport(expectedRevision: seeded.revision,
                                                     previewID: preview.id)
        #expect(committed.preferences?.profiles.first?.name == "Imported")
        #expect(committed.activeProfileID == nil)
        #expect(committed.revision == seeded.revision + 1)
        do {
            _ = try await store.commitImport(expectedRevision: committed.revision,
                                             previewID: preview.id)
            Issue.record("Single-use preview committed twice")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }
    }

    @Test func staleCancelledReloadedAndSupersededTokensWriteNothing() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
        let a1 = try await store.analyzeImport(bytes: bytes)
        let a2 = try await store.analyzeImport(bytes: bytes)
        do {
            _ = try await store.issueImportPreview(analysisID: try #require(a1.analysisID), choices: [:])
            Issue.record("Superseded analysis remained live")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }
        let p1 = try await store.issueImportPreview(analysisID: try #require(a2.analysisID), choices: [:])
        await store.cancelImport(previewID: p1.id)
        do {
            _ = try await store.commitImport(expectedRevision: initial.revision, previewID: p1.id)
            Issue.record("Cancelled preview committed")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }

        let a3 = try await store.analyzeImport(bytes: bytes)
        let p2 = try await store.issueImportPreview(analysisID: try #require(a3.analysisID), choices: [:])
        _ = await store.load()
        do {
            _ = try await store.commitImport(expectedRevision: initial.revision, previewID: p2.id)
            Issue.record("Load did not invalidate preview")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.root.path).isEmpty)
    }

    @Test func analysisIsSingleUseCancelableAndBoundBeforeIssuance() async throws {
        let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let seeded = try await store.update(expectedRevision: initial.revision,
            change: .preferencesDocument(.init(baseRevision: initial.revision,
                                                profiles: [.insert(profile(profileA, "Local"))])))
        let cancelled = try await store.analyzeImport(bytes: bytes)
        await store.cancelImport(analysisID: try #require(cancelled.analysisID))
        do {
            _ = try await store.issueImportPreview(
                analysisID: try #require(cancelled.analysisID), choices: [:])
            Issue.record("Cancelled analysis issued")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }

        let collisionBytes = Data(#"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"Imported","values":{"fields":{}}}],"inertImports":[]}"#.utf8)
        let failing = try await store.analyzeImport(bytes: collisionBytes)
        let failingID = try #require(failing.analysisID)
        do {
            _ = try await store.issueImportPreview(analysisID: failingID, choices: [:])
            Issue.record("Missing collision choice issued")
        } catch {}
        do {
            _ = try await store.issueImportPreview(analysisID: failingID,
                                                   choices: [profileA: .keepLocal])
            Issue.record("Failed issuance analysis was reusable")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }

        let staleActor = try await store.analyzeImport(bytes: bytes)
        _ = try await store.update(expectedRevision: seeded.revision,
            change: .globalPreferenceDelta(.init(baseRevision: seeded.revision,
                id: id("ui.density"), baseValue: nil, editedValue: .choice("compact"))))
        do {
            _ = try await store.issueImportPreview(
                analysisID: try #require(staleActor.analysisID), choices: [:])
            Issue.record("Actor update left analysis live")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }

        let current = try #require(await store.load().envelope)
        let staleDisk = try await store.analyzeImport(bytes: bytes)
        try scratch.replace(try Data(contentsOf: scratch.file))
        do {
            _ = try await store.issueImportPreview(
                analysisID: try #require(staleDisk.analysisID), choices: [:])
            Issue.record("External replacement left analysis live")
        } catch let error as SettingsStoreError { #expect(error == .changedExternally) }
        #expect(current.revision == 2)
    }

    @Test func externalChangeAndStaleRevisionConsumePreviewWithoutImportWrite() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
        let analysis = try await store.analyzeImport(bytes: bytes)
        let preview = try await store.issueImportPreview(
            analysisID: try #require(analysis.analysisID), choices: [:])
        do {
            _ = try await store.commitImport(expectedRevision: initial.revision + 1,
                                             previewID: preview.id)
            Issue.record("Stale revision committed")
        } catch let error as SettingsStoreError { #expect(error == .staleRevision) }
        do {
            _ = try await store.commitImport(expectedRevision: initial.revision,
                                             previewID: preview.id)
            Issue.record("Failed preview was reusable")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }
    }

    @Test func duplicateTouchedKeysAndWrongProfileBasesRejectExactly() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let local = profile(profileA, "Local")
        let seeded = try await store.update(expectedRevision: initial.revision,
            change: .preferencesDocument(.init(baseRevision: initial.revision,
                profiles: [.insert(local)], activeProfileBase: nil,
                activeProfileEdit: profileA, touchesActiveProfile: true,
                inert: [.init(item: inert("future.flag", profileID: profileA), presentInBase: false,
                              presentAfterEdit: true)])))
        let field = PreferenceFieldEdit(id: id("ui.units"), baseValue: nil,
                                         editedValue: .choice("decimal"))
        let invalidCases: [(PreferencesDocumentDelta, SettingsStoreError)] = [
            (.init(baseRevision: seeded.revision, global: [field, field]), .invalidChange),
            (.init(baseRevision: seeded.revision,
                   profiles: [.insert(profile(profileA, "A"))]), .staleRevision),
            (.init(baseRevision: seeded.revision,
                   profiles: [.update(id: profileB, base: profile(profileB, "Missing"),
                                      edited: profile(profileB, "Edit"))]), .staleRevision),
            (.init(baseRevision: seeded.revision,
                   profiles: [.delete(id: profileB, base: profile(profileB, "Missing"))]),
             .staleRevision),
            (.init(baseRevision: seeded.revision,
                   profiles: [.delete(id: profileA, base: profile(profileA, "Wrong"))]),
             .staleRevision),
            (.init(baseRevision: seeded.revision,
                   profiles: [.update(id: profileA, base: profile(profileA, "Wrong"),
                                      edited: profile(profileA, "Edit"))]), .staleRevision),
            (.init(baseRevision: seeded.revision,
                   profiles: [.update(id: profileA, base: local,
                                      edited: profile(profileB, "Changed ID"))]), .invalidChange),
            (.init(baseRevision: seeded.revision,
                   profiles: [.update(id: profileA, base: local, edited: profile(profileA, "A")),
                              .delete(id: profileA, base: local)]), .invalidChange),
            (.init(baseRevision: seeded.revision,
                   profiles: [.insert(profile(profileB, "B1")),
                              .insert(profile(profileB, "B2"))]), .invalidChange),
            (.init(baseRevision: seeded.revision, activeProfileBase: nil,
                   activeProfileEdit: nil, touchesActiveProfile: true), .staleRevision),
            (.init(baseRevision: seeded.revision, activeProfileBase: profileA,
                   activeProfileEdit: profileB, touchesActiveProfile: true), .invalidChange),
            (.init(baseRevision: seeded.revision,
                   profiles: [.delete(id: profileA, base: local)],
                   inert: [.init(item: inert("future.flag", profileID: profileA),
                                 presentInBase: true, presentAfterEdit: false)]), .invalidChange),
            (.init(baseRevision: seeded.revision,
                   profiles: [.insert(profile(profileB, "Local ID",
                     [("scope.currentProject", .choice("project"))]))]), .invalidChange),
            (.init(baseRevision: seeded.revision,
                   profiles: [.insert(profile(UUID(), "Authority",
                     [("maintenance.mode", .choice("authorizedCaches"))]))]), .invalidChange),
            (.init(baseRevision: seeded.revision,
                   profiles: [.update(id: profileA, base: local,
                     edited: profile(profileA, "Local Edit",
                       [("scope.currentProject", .choice("project"))]))]), .invalidChange),
            (.init(baseRevision: seeded.revision,
                   inert: [.init(item: inert("future.flag", profileID: profileA),
                                 presentInBase: false, presentAfterEdit: true)]), .staleRevision),
            (.init(baseRevision: seeded.revision,
                   profiles: [.delete(id: profileA, base: local)],
                   activeProfileBase: profileA, activeProfileEdit: nil,
                   touchesActiveProfile: true), .invalidChange)
        ]
        for invalid in invalidCases {
            do {
                _ = try await store.update(expectedRevision: seeded.revision,
                                           change: .preferencesDocument(invalid.0))
                Issue.record("Invalid document delta was accepted")
            } catch let error as SettingsStoreError {
                #expect(error == invalid.1)
            }
        }
        do {
            _ = try await store.update(expectedRevision: seeded.revision,
                change: .preferencesDocument(.init(baseRevision: seeded.revision + 1)))
            Issue.record("Future base revision was accepted")
        } catch let error as SettingsStoreError { #expect(error == .staleRevision) }

        let insertedInert = inert("future.profile", profileID: profileB)
        let accepted = try await store.update(expectedRevision: seeded.revision,
            change: .preferencesDocument(.init(baseRevision: seeded.revision,
                profiles: [.insert(profile(profileB, "B"))],
                inert: [.init(item: insertedInert, presentInBase: false,
                              presentAfterEdit: true)])))
        #expect(accepted.inertImports.contains(insertedInert))
    }

    @Test func inertEditsCompareExactWholeValuesAndDuplicateKeysReject() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let old = inert("future.flag")
        let one = try await store.update(expectedRevision: initial.revision,
            change: .preferencesDocument(.init(baseRevision: initial.revision,
                inert: [.init(item: old, presentInBase: false, presentAfterEdit: true)])))
        let different = InertPortableSetting(scope: .global, profileID: nil, id: "future.flag",
            value: .bool(false), valueKind: nil, valueDigest: nil, redacted: false)
        for edits in [
            [InertImportEdit(item: different, presentInBase: true, presentAfterEdit: false)],
            [InertImportEdit(item: old, presentInBase: true, presentAfterEdit: false),
             InertImportEdit(item: old, presentInBase: true, presentAfterEdit: false)]
        ] {
            do {
                _ = try await store.update(expectedRevision: one.revision,
                    change: .preferencesDocument(.init(baseRevision: one.revision, inert: edits)))
                Issue.record("Invalid inert base/key set was accepted")
            } catch let error as SettingsStoreError {
                #expect(error == (edits.count == 1 ? .staleRevision : .invalidChange))
            }
        }
    }

    @Test func completeCandidateBoundsRejectWithoutTruncation() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let profiles = (0..<51).map { index in
            ProfileDocumentEdit.insert(profile(UUID(), "P\(index)"))
        }
        do {
            _ = try await store.update(expectedRevision: initial.revision,
                change: .preferencesDocument(.init(baseRevision: initial.revision,
                                                    profiles: profiles)))
            Issue.record("51 profiles were accepted")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }
        let inertEdits = (0..<1_001).map { index in
            InertImportEdit(item: inert("future.\(index)"), presentInBase: false,
                            presentAfterEdit: true)
        }
        do {
            _ = try await store.update(expectedRevision: initial.revision,
                change: .preferencesDocument(.init(baseRevision: initial.revision,
                                                    inert: inertEdits)))
            Issue.record("1,001 inert records were accepted")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.root.path).isEmpty)
    }

    @Test func malformedPersistedInertAndNoncanonicalActiveUUIDRecover() async throws {
        for mutation in ["orphan-inert", "lowercase-active"] {
            let scratch = try T072Scratch(); defer { scratch.remove() }
            let profile = profile(profileA, "A")
            let envelope = SettingsEnvelope(schemaVersion: 2, revision: 7,
                config: TidyConfig(schemaVersion: 2),
                preferences: .init(profiles: [profile]), activeProfileID: profileA,
                inertImports: [inert("future.flag")])
            var root = try StrictJSON.parse(try SettingsDecoding.encode(envelope)).object()
            if mutation == "lowercase-active" {
                root["activeProfileID"] = .string(profileA.uuidString.lowercased())
            } else {
                root["inertImports"] = .array([.object([
                    "scope": .string("profile"), "profileID": .string(profileB.uuidString),
                    "id": .string("future.flag"), "value": .object(["bool": .bool(true)]),
                    "valueKind": .null, "valueDigest": .null, "redacted": .bool(false)
                ])])
            }
            let bytes = try StrictJSON.canonicalData(.object(root))
            try scratch.seed(bytes)
            let result = await SettingsStore(url: scratch.file).load()
            #expect(result.disposition == .recoveryReadOnly)
            #expect(try Data(contentsOf: scratch.file) == bytes)
        }
    }

    @Test func closedInertWireRoundTripsEveryShapeAndRejectsMalformedWithoutRewrite() async throws {
        let digest = String(repeating: "a", count: 64)
        let records: [InertPortableSetting] = [
            .init(scope: .global, profileID: nil, id: "future.bool", value: .bool(true),
                  valueKind: nil, valueDigest: nil, redacted: false),
            .init(scope: .global, profileID: nil, id: "future.integer", value: .integer(7),
                  valueKind: nil, valueDigest: nil, redacted: false),
            .init(scope: .global, profileID: nil, id: "future.null", value: .null,
                  valueKind: nil, valueDigest: nil, redacted: false),
            .init(scope: .global, profileID: nil, id: "future.choice", value: nil,
                  valueKind: .choice, valueDigest: digest, redacted: true),
            .init(scope: .global, profileID: nil, id: "future.strings", value: nil,
                  valueKind: .strings, valueDigest: digest, redacted: true),
            .init(scope: .profile, profileID: profileA, id: "future.volume", value: nil,
                  valueKind: .volume, valueDigest: digest, redacted: true)
        ]
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 7,
            config: TidyConfig(schemaVersion: 2),
            preferences: .init(profiles: [profile(profileA, "A")]),
            activeProfileID: profileA, inertImports: records)
        let valid = try SettingsDecoding.encode(envelope)
        let validRoot = try StrictJSON.parse(valid).object()
        #expect(Set(validRoot.keys) == ["schemaVersion", "revision", "config", "preferences",
                                         "activeProfileID", "inertImports"])
        guard case .array(let rows)? = validRoot["inertImports"] else {
            Issue.record("Missing inert array"); return
        }
        for row in rows {
            #expect(Set(try row.object().keys) == ["scope", "profileID", "id", "value",
                                                   "valueKind", "valueDigest", "redacted"])
        }
        let scratch = try T072Scratch(); defer { scratch.remove() }
        try scratch.seed(valid)
        #expect(await SettingsStore(url: scratch.file).load().envelope == envelope)

        func malformed(_ mutate: (inout [String: StrictJSON.Value]) -> Void) async throws {
            var root = validRoot
            mutate(&root)
            let bytes = try StrictJSON.canonicalData(.object(root))
            let fixture = try T072Scratch(); defer { fixture.remove() }
            try fixture.seed(bytes)
            #expect(await SettingsStore(url: fixture.file).load().disposition == .recoveryReadOnly)
            #expect(try Data(contentsOf: fixture.file) == bytes)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[0] else { return }
            row["extra"] = .bool(true); values[0] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[0] else { return }
            row["redacted"] = nil; values[0] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[3] else { return }
            row["value"] = .object(["bool": .bool(true)])
            values[3] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[3] else { return }
            row["valueDigest"] = .string(String(repeating: "A", count: 64))
            values[3] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[3] else { return }
            row["valueDigest"] = .string(String(repeating: "a", count: 63))
            values[3] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[0] else { return }
            row["id"] = .string("/Users/alice")
            values[0] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[0] else { return }
            row["scope"] = .string("profile"); row["profileID"] = .null
            values[0] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(let values)? = root["inertImports"] else { return }
            root["inertImports"] = .array(values + [values[0]])
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[2] else { return }
            row["value"] = .object(["null": .bool(false)])
            values[2] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[0] else { return }
            row["value"] = .object(["bool": .bool(true), "integer": .number("1")])
            values[0] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[0] else { return }
            row["value"] = .object(["future": .bool(true)])
            values[0] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[0] else { return }
            row["valueKind"] = .string("choice")
            row["valueDigest"] = .string(String(repeating: "a", count: 64))
            values[0] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[3] else { return }
            row["redacted"] = .bool(false)
            values[3] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[3] else { return }
            row["valueKind"] = .string("future")
            values[3] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[5] else { return }
            row["profileID"] = .string(profileA.uuidString.lowercased())
            values[5] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[5] else { return }
            row["profileID"] = .string(profileB.uuidString)
            values[5] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in
            guard case .array(var values)? = root["inertImports"],
                  case .object(var row) = values[0] else { return }
            row["profileID"] = .string(profileA.uuidString)
            values[0] = .object(row); root["inertImports"] = .array(values)
        }
        try await malformed { root in root["preferences"] = nil }
        try await malformed { root in root["activeProfileID"] = .null }
        try await malformed { root in
            guard case .object(var preferences)? = root["preferences"],
                  case .array(var profiles)? = preferences["profiles"],
                  case .object(var profile) = profiles[0] else { return }
            profile["id"] = .string(profileA.uuidString.lowercased())
            profiles[0] = .object(profile); preferences["profiles"] = .array(profiles)
            root["preferences"] = .object(preferences)
        }
    }

    @Test func malformedPersistedBoundsNeverTruncateOrRewrite() async throws {
        let valid = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 7,
            config: TidyConfig(schemaVersion: 2), preferences: .init(),
            inertImports: [inert("future.template")]))
        let validRoot = try StrictJSON.parse(valid).object()
        guard case .array(let templateRows)? = validRoot["inertImports"],
              case .object(let template) = templateRows[0] else {
            Issue.record("Missing valid inert template"); return
        }
        var overInertRoot = validRoot
        overInertRoot["inertImports"] = .array((0..<1_001).map { index in
            var row = template; row["id"] = .string("future.\(index)"); return .object(row)
        })
        let exactName = String(repeating: "😀", count: 1_024)
        let exactNameBytes = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2,
            revision: 7, config: TidyConfig(schemaVersion: 2),
            preferences: .init(profiles: [profile(profileA, exactName)]), inertImports: []))
        #expect(exactName.utf8.count == 4_096)
        #expect(exactNameBytes.count < SettingsDecoding.byteLimit)
        let exactScratch = try T072Scratch(); defer { exactScratch.remove() }
        try exactScratch.seed(exactNameBytes)
        #expect(await SettingsStore(url: exactScratch.file).load().envelope != nil)
        var overStringRoot = try StrictJSON.parse(exactNameBytes).object()
        guard case .object(var namePreferences)? = overStringRoot["preferences"],
              case .array(var nameProfiles)? = namePreferences["profiles"],
              case .object(var nameProfile) = nameProfiles[0] else {
            Issue.record("Missing valid profile-name template"); return
        }
        nameProfile["name"] = .string(exactName + "x")
        nameProfiles[0] = .object(nameProfile)
        namePreferences["profiles"] = .array(nameProfiles)
        overStringRoot["preferences"] = .object(namePreferences)

        let document = values([("cleanup.transcriptDays", .integer(45)),
                               ("cleanup.inactiveDays", .integer(60)),
                               ("cleanup.recentProtectionDays", .integer(7)),
                               ("cleanup.warmProjectCount", .integer(5)),
                               ("cleanup.minimumItemMiB", .integer(1))])
        let oneProject = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2,
            revision: 7, config: TidyConfig(schemaVersion: 2),
            preferences: .init(projects: ["p": document]), inertImports: []))
        var aggregateRoot = try StrictJSON.parse(oneProject).object()
        guard case .object(var preferences)? = aggregateRoot["preferences"],
              case .object(let projects)? = preferences["projects"],
              let projectTemplate = projects["p"] else {
            Issue.record("Missing valid project template"); return
        }
        preferences["projects"] = .object(Dictionary(uniqueKeysWithValues:
            (0..<1_000).map { ("p\($0)", projectTemplate) }))
        aggregateRoot["preferences"] = .object(preferences)
        let roots = [overInertRoot, overStringRoot, aggregateRoot]
        let fixtures = try roots.map { root -> Data in
            #expect(Set(root.keys) == ["schemaVersion", "revision", "config", "preferences",
                                       "inertImports"])
            guard case .array(let rows)? = root["inertImports"] else {
                throw SettingsTransferError.invalidDocument
            }
            for row in rows.prefix(1) {
                #expect(Set(try row.object().keys) == ["scope", "profileID", "id", "value",
                                                       "valueKind", "valueDigest", "redacted"])
            }
            let bytes = try StrictJSON.canonicalData(.object(root))
            #expect(bytes.count < SettingsDecoding.byteLimit)
            return bytes
        }
        for bytes in fixtures {
            let scratch = try T072Scratch(); defer { scratch.remove() }
            try scratch.seed(bytes)
            #expect(await SettingsStore(url: scratch.file).load().disposition == .recoveryReadOnly)
            #expect(try Data(contentsOf: scratch.file) == bytes)
        }
    }

    @Test func previewDigestsAreStableAndCandidateIsExact() async throws {
        let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
        var previews: [SettingsImportPreview] = []
        for _ in 0..<2 {
            let scratch = try T072Scratch(); defer { scratch.remove() }
            let store = SettingsStore(url: scratch.file)
            let initial = try #require(await store.load().envelope)
            let analysis = try await store.analyzeImport(bytes: bytes)
            let preview = try await store.issueImportPreview(
                analysisID: try #require(analysis.analysisID), choices: [:])
            let expected = SettingsEnvelope(schemaVersion: 2, revision: initial.revision + 1,
                config: initial.config, preferences: preview.candidate.preferences,
                activeProfileID: initial.activeProfileID,
                inertImports: preview.candidate.inertImports)
            let expectedDigest = SHA256.hash(data: try SettingsDecoding.encode(expected))
                .map { String(format: "%02x", $0) }.joined()
            #expect(preview.candidateDigest == expectedDigest)
            previews.append(preview)
        }
        #expect(previews[0].sourceDigest == previews[1].sourceDigest)
        #expect(previews[0].candidateDigest == previews[1].candidateDigest)
        #expect(previews[0].candidate == previews[1].candidate)
        #expect(previews[0].sourceDigest == SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }.joined())
    }

    @Test func newPreviewAndExternalDiskIdentityInvalidatePriorBinding() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let persisted = try await store.update(expectedRevision: initial.revision,
            change: .globalPreferenceDelta(.init(baseRevision: initial.revision,
                id: id("ui.density"), baseValue: nil, editedValue: .choice("compact"))))
        let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
        let first = try await store.analyzeImport(bytes: bytes)
        let oldPreview = try await store.issueImportPreview(
            analysisID: try #require(first.analysisID), choices: [:])
        let second = try await store.analyzeImport(bytes: bytes)
        _ = try await store.issueImportPreview(analysisID: try #require(second.analysisID), choices: [:])
        do {
            _ = try await store.commitImport(expectedRevision: persisted.revision,
                                             previewID: oldPreview.id)
            Issue.record("New preview left old preview live")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }

        let third = try await store.analyzeImport(bytes: bytes)
        let diskPreview = try await store.issueImportPreview(
            analysisID: try #require(third.analysisID), choices: [:])
        try scratch.replace(try Data(contentsOf: scratch.file))
        do {
            _ = try await store.commitImport(expectedRevision: persisted.revision,
                                             previewID: diskPreview.id)
            Issue.record("Changed disk identity committed")
        } catch let error as SettingsStoreError { #expect(error == .changedExternally) }
    }

    @Test func successfulImportUsesOneConfigPublicationSequence() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let io = CountingT072IO()
        let store = SettingsStore(url: scratch.file, io: io)
        let initial = try #require(await store.load().envelope)
        let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
        let analysis = try await store.analyzeImport(bytes: bytes)
        let preview = try await store.issueImportPreview(
            analysisID: try #require(analysis.analysisID), choices: [:])
        _ = try await store.commitImport(expectedRevision: initial.revision,
                                         previewID: preview.id)
        #expect(io.configReplacements == 1)
    }

    @Test func failedPublicationConsumesPreviewBeforeFirstAttempt() async throws {
        let scratch = try T072Scratch(); defer { scratch.remove() }
        let io = FailingT072IO()
        let store = SettingsStore(url: scratch.file, io: io)
        let initial = try #require(await store.load().envelope)
        let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
        let analysis = try await store.analyzeImport(bytes: bytes)
        let preview = try await store.issueImportPreview(
            analysisID: try #require(analysis.analysisID), choices: [:])
        do {
            _ = try await store.commitImport(expectedRevision: initial.revision,
                                             previewID: preview.id)
            Issue.record("Injected publication failure succeeded")
        } catch {}
        #expect(io.configAttempts == 1)
        do {
            _ = try await store.commitImport(expectedRevision: initial.revision,
                                             previewID: preview.id)
            Issue.record("Failed preview retried")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }
        #expect(io.configAttempts == 1)
    }
}

private struct T072Scratch {
    let root: URL
    var file: URL { root.appendingPathComponent("config.json") }
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("T07-2A-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
    }
    func seed(_ bytes: Data) throws {
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func replace(_ bytes: Data) throws {
        try? FileManager.default.removeItem(at: file)
        try seed(bytes)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class CountingT072IO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let lock = NSLock()
    private var replacements = 0
    var configReplacements: Int { lock.withLock { replacements } }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        try base.write(fd: fd, bytes: bytes, offset: offset)
    }
    func syncFile(fd: Int32) throws { try base.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        if destination == "config.json" { lock.withLock { replacements += 1 } }
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
    }
    func syncDirectory(fd: Int32) throws { try base.syncDirectory(fd: fd) }
}

private final class FailingT072IO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let lock = NSLock()
    private var attempts = 0
    var configAttempts: Int { lock.withLock { attempts } }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        try base.write(fd: fd, bytes: bytes, offset: offset)
    }
    func syncFile(fd: Int32) throws { try base.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        if destination == "config.json" {
            lock.withLock { attempts += 1 }
            throw POSIXError(.EIO)
        }
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
    }
    func syncDirectory(fd: Int32) throws { try base.syncDirectory(fd: fd) }
}
```

## Post-review binding amendment

The authoritative executable artifact is `TidyCore/Tests/TidyCoreTests/SettingsProfilePersistenceTests.swift`. The initial block above was created verbatim for RED. The reviewed RED-to-GREEN cycle then made these binding test amendments:

- intentionally over-bound 1,001-inert and 4,097-byte hostile persisted fixtures are emitted through the explicit closed Codable wire because `StrictJSON.canonicalData` correctly refuses to construct values beyond its own bounds; production limits were not weakened;
- `durableGlobalEligibilityOptInPersistsWhileProfileAndImportCannotWeaken` separates locally owned durable global opt-ins from stricter profile/import monotonicity;
- the closed inert matrix rejects a recognized safe tag accompanied by an unknown tag;
- `rollbackRestoresProfilesActiveSelectionAndInertStateTogether` binds rollback to the complete backed-up profile graph, active selection and inert state instead of mixing backup preferences with current active/inert values.

These regressions and the corresponding rollback fields on `SettingsRollbackPreview`/the internal store binding are part of this card's acceptance contract.

## Execution steps

- [ ] Create only `SettingsProfilePersistenceTests.swift`; run `cd TidyCore && swift test --jobs 2 --filter SettingsProfilePersistenceTests`; preserve the missing-symbol RED.
- [ ] Add the envelope fields and strict old/new wire parsing. Run the older-wire, round-trip and malformed-state tests until GREEN.
- [ ] Add the base-bound delta declarations and pure exact application inside `SettingsStore`; run the delta/active/delete/authority tests until GREEN.
- [ ] Add store-only analysis/preview bindings and SHA-256 binding. Run lifecycle, digest, disk-identity, single-use and one-publication tests until GREEN.
- [ ] Run existing malformed/migration/publication suites to prove no recovery or atomic-publication regression.
- [ ] Add `Policy/SessionProfile.swift` and `Policy/SettingsTransfer.swift` to the process compiler manifest, assert both hashes in its generated SHA manifest, and run ordinary, bounded-process and settings-process partitions with `--jobs 2`.
- [ ] Run `git diff --check`, exact allowlist audit and a fresh adversarial source review. Correct findings with new RED regressions before acceptance.
- [ ] Commit source/tests, then create and commit `docs/verification/T07-2a-durable-import-store.md` plus the progress-ledger update.

## Acceptance boundary

Passing T07.2a proves durable active/inert state, exact store deltas and actor-issued imports only. It does not prove bridge queue semantics, synchronous policy invalidation, app-visible selected-profile resolution, two-window synchronization, SwiftUI workflows, local reassociation, data clearing, hostile coordinator/effect rejection, device performance, README, GitHub publication or DMG release. Those remain T07.2b, T07.3, T07.4/dependency gates and T08–T24.
