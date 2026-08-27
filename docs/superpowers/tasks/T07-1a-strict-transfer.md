# T07.1a preimplementation card — shared strict JSON and pure transfer

Status: proposed source-entry card. No production edit is allowed before independent approval. It consumes the accepted T07.1b restriction comparator at `c1b7969` and adds no actor, persistence, active selection, authority, coordinator, app or UI behavior.

## Exact allowlist

- Create `TidyCore/Sources/TidyCore/Policy/StrictJSON.swift`
- Create `TidyCore/Sources/TidyCore/Policy/SettingsTransfer.swift`
- Modify `TidyCore/Sources/TidyCore/Policy/SettingsEnvelope.swift` only to replace private `SettingsJSON` with `StrictJSON` and map parser errors to the existing `SettingsDecoding.Failure`
- Create `TidyCore/Tests/TidyCoreTests/SettingsTransferTests.swift`

No settings schema/model/store, profile source, bridge, coordinator, app, project or generated-project file may change.

## Shared parser contract

`StrictJSON` is package-internal. It owns one bounded `Value` AST, parser and canonical encoder. Limits are 1 MiB input/output, depth 16, 1,000 object/array members and 4,096 UTF-8 bytes per decoded string. It rejects invalid UTF-8, duplicate keys, invalid escapes/surrogates, leading-zero/overflow/nonfinite numbers, trailing bytes and bound overflow. Canonical encoding emits UTF-8 without whitespace, sorts object keys by UTF-8 bytes, preserves array order, and emits integers only; transfer rejects fractional/exponent numbers.

Canonical strings leave non-ASCII UTF-8 and `/` unescaped; escape `"`, `\\`, backspace, form-feed, newline, carriage return and tab with their two-byte JSON escapes; encode other U+0000...U+001F scalars as lowercase `\u00xx`. Canonical numbers normalize `-0` to `0`; fractional/exponent spellings have no canonical transfer encoding and reject.

```swift
enum StrictJSONError: Error, Equatable { case malformed, oversized }
struct StrictJSON {
    indirect enum Value: Equatable { case object([String: Value]), array([Value]), string(String), number(String), bool(Bool), null }
    static let byteLimit = 1_048_576
    static func parse(_ data: Data) throws -> Value
    static func canonicalData(_ value: Value) throws -> Data
}
```

`SettingsDecoding.load` and `storeIdentity` map `.malformed` to their existing `.malformed`; size checks retain existing `.oversized`. Existing settings fixtures and byte-preservation behavior must remain unchanged.

## Exact transfer types and API

```swift
public enum InertScope: String, Equatable, Sendable { case global, profile }
public enum InertSafeValue: Equatable, Sendable { case bool(Bool), integer(Int64), null }
public enum RedactedValueKind: String, Equatable, Sendable { case choice, strings, volume }
public struct InertPortableSetting: Equatable, Sendable {
    public let scope: InertScope
    public let profileID: UUID?
    public let id: String
    public let value: InertSafeValue?
    public let valueKind: RedactedValueKind?
    public let valueDigest: String?
    public let redacted: Bool
}
public struct PortableSettingsState: Equatable, Sendable {
    public var preferences: PolicyPreferences
    public var inertImports: [InertPortableSetting]
}
public enum PortableClassification: Equatable, Sendable {
    case portable, requiresLocalReassociation, rejectedAuthority, rejectedNonPortable
}
public enum SettingsImportOutcome: String, Equatable, Sendable {
    case committable, inert, redacted, requiresLocalReassociation, rejectedAuthority
    case rejectedProtectionWeakening, rejectedInvalid, rejectedNonPortable
    case rejectedUnsupportedLayer, collision
}
public struct SettingsImportRow: Equatable, Sendable {
    public let scope: InertScope
    public let profileID: UUID?
    public let id: String?
    public let idDigest: String?
    public let outcome: SettingsImportOutcome
    public let value: SettingValue?
    public let valueKind: RedactedValueKind?
    public let valueDigest: String?
}
public struct ProfileImportCollision: Equatable, Sendable {
    public let profileID: UUID
    public let localName: String
    public let importedName: String
}
public struct SettingsImportAnalysis: Equatable, Sendable {
    public let rows: [SettingsImportRow]
    public let collisions: [ProfileImportCollision]
    internal let committableImported: PolicyPreferences
    internal let importedInert: [InertPortableSetting]
    internal let current: PortableSettingsState
}
public enum ProfileCollisionChoice: Equatable, Sendable {
    case keepLocal, replace, clone(UUID)
}
public struct ResolvedSettingsImport: Equatable, Sendable {
    public let candidate: PortableSettingsState
    public let rows: [SettingsImportRow]
}
public enum SettingsTransferError: Error, Equatable, Sendable {
    case malformed, oversized, unsupportedSchema(Int), invalidDocument
    case candidateInvalid(SettingID)
    case missingCollisionChoice(UUID), unexpectedCollisionChoice(UUID)
    case cloneIDCollision(UUID), tooManyProfiles
}
public enum PortableSettingPolicy {
    public static func classify(id: SettingID, value: SettingValue,
                                layer: PolicyLayer) throws -> PortableClassification
    internal static var classificationPartitions: (
        portable: Set<SettingID>, reassociation: Set<SettingID>,
        authority: Set<SettingID>, nonportable: Set<SettingID>,
        dynamicCatalogPortable: Set<SettingID>) { get }
}
public enum SettingsTransfer {
    public static func analyze(bytes: Data, current: PortableSettingsState) throws -> SettingsImportAnalysis
    public static func resolve(_ analysis: SettingsImportAnalysis,
                               choices: [UUID: ProfileCollisionChoice]) throws -> ResolvedSettingsImport
    public static func export(_ state: PortableSettingsState) throws -> Data
}
```

Public initializers are supplied for all public value structs. Analysis contains no secret token and is never commit-capable.

## Classification and safety rules

Known rows resolve through the production registry. Structural/type/range/relation failures become visible `rejectedInvalid`; valid unsupported layers become `rejectedUnsupportedLayer`. All A rows are `rejectedAuthority`, except local identity-list rows (`scope.projectRoots`, `scope.externalVolumes`, simulator/device, executable, app and Docker endpoint identities), which are `requiresLocalReassociation`. Volume overrides and `scope.currentProject` are also `requiresLocalReassociation`. `browsers.keepCookieDomains` and any other known domains/local-machine field are `rejectedNonPortable`.

Portability is an exhaustive, fail-closed registry partition, not an inference from P/R or value kind. Production owns disjoint exact static-ID sets for portable, reassociation, authority and nonportable rows. Dynamic catalog rows are admitted only when their ID is the exact `item.<current-catalog-id>.<suffix>` expansion for the four deliberately portable suffixes `enabled`, `inactiveDays`, `minimumItemMiB` and `retainRecentArtifacts`; dynamic volume rows are deliberately reassociation-only. The union must equal the expanded production registry. Any new static row or dynamic suffix fails tests and classification until deliberately added; there is no generic “all remaining P/R rows are portable” branch. Portable R values are accepted only when equal/stricter than the current global/default baseline or, inside an imported profile, the post-merge global value/default. A weaker R is `rejectedProtectionWeakening`. Rejected rows are excluded before candidate validation.

Unknown IDs matching `[a-z0-9][A-Za-z0-9._-]{0,255}` are permanently inert: bool/integer/null are stored exactly; valid tagged choice/strings/volume become redacted records. The redacted digest is lowercase SHA-256 of the canonical original tagged subtree. Unsafe unknown IDs appear only as a preview row with `id == nil`, `idDigest` set, no value, and are never durable/exported. Unknown outer tags or arbitrary shapes are structural errors, not inert values.

Rows sort by `(scope, profileID-or-empty, id-or-empty, idDigest-or-empty, outcome.rawValue)` using UTF-8 bytes. No rejected row retains a sensitive raw value. Committable safe values may retain `value`; reassociation/nonportable/authority/redacted rows retain only kind/digest as applicable.

`SettingsImportAnalysis.committableImported` contains only known committable active fields. `importedInert` contains only exact safe scalars or redacted kind/digest records. Before `analyze` returns, it discards the raw AST and every rejected/redacted raw ID/value string. Only validated portable profile display names may remain for collisions. This boundary is tested through `@testable` reflection and direct field inspection.

## Wire, merge and collision rules

The exact closed schema-1 grammar and canonical ordering are those in the approved T07 entry card. Root/profile/inert objects reject extra or missing keys. Transfer UUID spelling is canonical lowercase-hyphenated. Duplicate profile UUIDs and orphan/ambiguous profile-scoped inert rows reject atomically.

Explicit imported global keys merge; absent keys preserve current values. Projects remain byte/value-identical and are never imported/exported. Imported profiles merge by UUID; duplicate names are valid. Every collision requires exactly one choice:

- `keepLocal`: keep the local profile and discard imported profile-scoped inert rows as visible collision rows;
- `replace`: use the imported profile and its inert rows at the same UUID;
- `clone(newID)`: require a fresh noncolliding ID and remap the imported profile plus all its inert rows.

Unexpected/missing choices reject. Clone remapping happens before canonical sort. Resolved candidates have unique IDs, at most 50 profiles, valid names/values, and pass T07.1b profile/monotone validation against the merged global policy. Resolve/export perform no I/O.

The inert key is exactly `(scope, profileID-or-nil, id)`. Duplicate inert keys inside one import reject. Current inert records are preserved by default; exact imported duplicates deduplicate. A conflicting global inert record keeps the current record and adds a sanitized `.collision` row for the discarded import. For a profile collision, `keepLocal` preserves current inert and visibly discards imported inert; `replace` discards current inert for that UUID visibly and retains imported inert; `clone` preserves current inert and remaps imported inert to the clone. A post-remap key collision keeps the current record and visibly discards the import. An explicitly inert ID that is now known remains inert and is never promoted. The candidate has at most one record per inert key. Canonical export sorts inert rows by the approved exact tuple `(scope, profileID-or-empty, id, valueKind-or-empty, valueDigest-or-empty)` using UTF-8 bytes.

One checked candidate validator is used by both resolve and export. It enforces at most 1,000 fields per policy document, 4,096 aggregate typed fields including preserved projects, 1,000 inert records, 50 profiles, 4,096 UTF-8 bytes per string, checked addition, and at most 1 MiB canonical portable output. Current state outside any bound rejects; merging never truncates. Resolve validates the sanitized active candidate through T07.1b. Export first classifies and omits hostile A/local/nonportable fields, then validates the sanitized portable projection; excluded hostile fields never appear in bytes and do not make export preserve them by failing back to a raw encoder.

Transfer validation is context-free and deterministic. Each imported field is considered in UTF-8 ID order against the evolving preserved candidate; a field that introduces an invalid quiet-hours pair, fixed generic `warningGiB >= clearGiB`, or known `budget.<id>.lowGiB >= highGiB` is `rejectedInvalid` and is not applied. Capacity/selected-volume bounds are deferred to later local reassociation and never guessed. After the batch, every imported and preserved profile is checked against the post-merge global restrictions. An imported profile field that weakens that global policy becomes `rejectedProtectionWeakening`; if a stricter imported global makes an existing local profile invalid, resolve throws `candidateInvalid(id)` rather than rewriting it. Blank, untrimmed, oversized or otherwise invalid imported profile metadata rejects the document atomically.

Export uses one `PortableSettingPolicy`: it includes portable global/profile fields and safe/redacted inert records, sorts profiles/inert rows canonically, and excludes projects, authority, local identity, volume/project IDs and nonportable domains. Registry growth never promotes inert records.

## Complete RED test file

Create this file verbatim before production edits; the focused command must fail to compile on the prescribed missing symbols.

```swift
import Foundation
import Testing
@testable import TidyCore

@Suite struct SettingsTransferTests {
    let profileA = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    let profileB = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    func id(_ raw: String) -> SettingID { .init(rawValue: raw) }
    func values(_ pairs: [(String, SettingValue)]) -> PolicyValues {
        .init(fields: Dictionary(uniqueKeysWithValues: pairs.map { (id($0.0), $0.1) }))
    }
    func state(_ preferences: PolicyPreferences = .init(),
               inert: [InertPortableSetting] = []) -> PortableSettingsState {
        .init(preferences: preferences, inertImports: inert)
    }
    func data(_ text: String) -> Data { Data(text.utf8) }
    func inert(_ rawID: String, scope: InertScope = .global, profile: UUID? = nil,
               value: InertSafeValue = .bool(true)) -> InertPortableSetting {
        .init(scope: scope, profileID: profile, id: rawID, value: value,
              valueKind: nil, valueDigest: nil, redacted: false)
    }
    func typedState(totalFields: Int) -> PortableSettingsState {
        let projectFields = values([
            ("cleanup.inactiveDays", .integer(60)), ("cleanup.transcriptDays", .integer(45)),
            ("cleanup.recentProtectionDays", .integer(7)), ("cleanup.warmProjectCount", .integer(5))])
        let projectCount = min(1_000, totalFields / 4)
        let projects = Dictionary(uniqueKeysWithValues: (0..<projectCount).map {
            ("p\($0)", projectFields)
        })
        let remaining = totalFields - projectCount * 4
        let definitions = (PolicyDefaults.rows + CleanCatalog.allItems.flatMap {
            PolicyDefaults.itemRows(catalogID: $0.id)
        }).filter { $0.resolution != .authority && $0.layers.contains(.global) }
          .sorted { $0.id.rawValue < $1.id.rawValue }
        let global = PolicyValues(fields: Dictionary(uniqueKeysWithValues:
            definitions.prefix(remaining).map { ($0.id, $0.defaultValue) }))
        return state(PolicyPreferences(global: global, projects: projects))
    }

    @Test func sharedParserRejectsDuplicatesDepthInvalidUTF8AndCanonicalizes() throws {
        #expect(throws: StrictJSONError.malformed) {
            try StrictJSON.parse(data(#"{"a":1,"a":2}"#))
        }
        let deep = String(repeating: "[", count: 17) + "0" + String(repeating: "]", count: 17)
        #expect(throws: StrictJSONError.malformed) { try StrictJSON.parse(data(deep)) }
        #expect(throws: StrictJSONError.malformed) { try StrictJSON.parse(Data([0xff])) }
        let parsed = try StrictJSON.parse(data(#"{"z":0,"a":[true,null,"é"]}"#))
        #expect(String(decoding: try StrictJSON.canonicalData(parsed), as: UTF8.self)
            == #"{"a":[true,null,"é"],"z":0}"#)
    }

    @Test func settingsMalformedFixturesStillMapToExistingFailures() throws {
        for fixture in PolicyMalformedPreferenceFixture.allCases {
            do {
                _ = try SettingsDecoding.load(fixture.bytes)
                Issue.record("Malformed settings fixture loaded: \(fixture.rawValue)")
            } catch SettingsDecoding.Failure.oversized {
                #expect(fixture == .oversized)
            } catch SettingsDecoding.Failure.unsupportedSchema(let version) {
                Issue.record("Unexpected root schema failure \(version) for \(fixture.rawValue)")
            } catch SettingsDecoding.Failure.malformed {
                #expect(fixture != .oversized)
            }
        }
        do {
            _ = try SettingsDecoding.load(data(#"{"schemaVersion":3}"#))
            Issue.record("Unsupported root schema loaded")
        } catch SettingsDecoding.Failure.unsupportedSchema(let version) {
            #expect(version == 3)
        } catch { Issue.record("Wrong unsupported-schema failure: \(error)") }
        do {
            _ = try SettingsDecoding.load(Data(repeating: 0x20, count: SettingsDecoding.byteLimit + 1))
            Issue.record("Oversized settings bytes loaded")
        } catch SettingsDecoding.Failure.oversized {}
        let identity = data(#"{"schema":1,"storeID":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"}"#)
        #expect(try SettingsDecoding.storeIdentity(identity) == profileA)
        do {
            _ = try SettingsDecoding.storeIdentity(Data(repeating: 0x20, count: 1_025))
            Issue.record("Over-limit identity loaded")
        } catch SettingsDecoding.Failure.malformed {}
        catch { Issue.record("Wrong identity failure: \(error)") }
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 7, config: .init(),
            preferences: PolicyPreferences(global: values([("ui.units", .choice("decimal"))])))
        let encoded = try SettingsDecoding.encode(envelope)
        #expect(try SettingsDecoding.load(encoded).envelope == envelope)
    }

    @Test func canonicalExportIsByteStableAndOmitsProjectsAndIdentities() throws {
        let profile = SavedProfile(id: profileA, name: "Work",
            values: values([("scan.preset", .choice("eco")),
                            ("scope.currentProject", .choice("local-project"))]))
        let preferences = PolicyPreferences(global: values([
            ("ui.units", .choice("decimal")), ("scan.preset", .choice("balanced")),
            ("browsers.keepCookieDomains", .strings(["private.example"]))]),
            profiles: [profile], projects: ["secret-project": values([("ui.units", .choice("binary"))])])
        let expected = #"{"global":{"fields":{"scan.preset":{"choice":"balanced"},"ui.units":{"choice":"decimal"}}},"inertImports":[],"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"Work","values":{"fields":{"scan.preset":{"choice":"eco"}}}}],"schemaVersion":1}"#
        let first = try SettingsTransfer.export(state(preferences))
        let reordered = PolicyPreferences(global: values([
            ("scan.preset", .choice("balanced")), ("ui.units", .choice("decimal"))]),
            profiles: [profile], projects: preferences.projects)
        #expect(first == data(expected))
        #expect(try SettingsTransfer.export(state(reordered)) == first)
    }

    @Test func portableClassifierCoversEveryStaticDynamicAndCatalogDefinition() throws {
        let definitions = PolicyDefaults.rows + CleanCatalog.allItems.flatMap {
            PolicyDefaults.itemRows(catalogID: $0.id)
        }
        let partitions = PortableSettingPolicy.classificationPartitions
        let registryIDs = Set(definitions.map(\.id))
        let featureNames = ["headroom", "buildPrep", "projects", "rescue",
                            "ecosystems", "budgets", "history", "maintenance"]
        let ecosystemNames = ["apple", "android", "node", "languages", "homebrew",
                              "docker", "ides", "models", "git", "data"]
        let budgetNames = ["apple-derived-data", "apple-simulators", "android", "docker",
                           "package-caches", "models", "ides", "git", "data", "other"]
        let portableFixed = Set(([
            "cleanup.inactiveDays", "cleanup.transcriptDays", "cleanup.recentProtectionDays",
            "cleanup.warmProjectCount", "cleanup.minimumCandidateMiB", "cleanup.minimumItemMiB",
            "cleanup.retainRecentArtifacts", "cleanup.costCeiling", "cleanup.requestedBatchGiB",
            "cleanup.requestedBatchItems", "cleanup.hardBatchGiB", "cleanup.hardBatchItems",
            "cleanup.manualInactiveAcknowledgementMinutes", "headroom.targetGiB",
            "headroom.warningGiB", "headroom.clearGiB",
            "scan.preset", "scan.requestedWorkers", "scan.readOnlyProcesses", "scan.defaultScope",
            "scan.sliceSeconds", "scan.uiBatchesPerSecond", "scan.onLowPower",
            "scan.onSeriousThermal", "scan.resumeAfterCriticalSeconds", "scan.cacheEnabled",
            "scan.cacheMiB", "scan.cacheExpiryHours", "monitor.visibleIntervalSeconds",
            "monitor.hiddenIntervalSeconds", "monitor.rawHistoryEnabled", "monitor.rawHistoryHours",
            "monitor.suppressHiddenSampling", "rescue.showAdvancedMemoryActions",
            "rescue.quitTimeoutSeconds", "notifications.pressureSustainSeconds",
            "notifications.recoverySeconds", "notifications.cooldownMinutes",
            "notifications.quietHoursEnabled", "notifications.quietStart", "notifications.quietEnd",
            "history.enabled", "history.retentionDays", "history.maxMiB", "ui.density", "ui.units",
            "ui.cards", "ui.ecosystemOrder", "ui.showBadges", "ui.advancedSettings",
            "export.redactDiagnostics"
        ] + featureNames.map { "feature.\($0)" }
          + ecosystemNames.flatMap { ["ecosystem.\($0).inventory", "ecosystem.\($0).manualActions"] }
          + budgetNames.flatMap { ["budget.\($0).enabled", "budget.\($0).highGiB", "budget.\($0).lowGiB"] })
          .map { id($0) })
        let expectedReassociation = Set([
            "scope.projectRoots", "scope.externalVolumes", "scope.currentProject",
            "simulators.approvedDeletionUDIDs", "tools.approvedExecutables",
            "docker.approvedEndpoints", "rescue.approvedApplications"
        ].map { id($0) })
        let expectedAuthority = Set([
            "monitor.backgroundEnabled", "notifications.enabled", "maintenance.mode",
            "maintenance.maxGiB", "maintenance.maxItems", "maintenance.deadlineSeconds",
            "maintenance.minimumAgeDays", "maintenance.minimumIntervalHours", "app.launchAtLogin"
        ].map { id($0) })
        let expectedNonportable = Set([
            "scope.excludedRoots", "scope.pinnedProjects", "browsers.keepCookieDomains"
        ].map { id($0) })
        let dynamicExpected = Set(CleanCatalog.allItems.flatMap { item in
            ["enabled", "inactiveDays", "minimumItemMiB", "retainRecentArtifacts"].map {
                SettingID(rawValue: "item.\(item.id).\($0)")
            }
        })
        let expectedPortable = portableFixed.union(dynamicExpected)
        #expect(partitions.portable == expectedPortable)
        #expect(partitions.reassociation == expectedReassociation)
        #expect(partitions.authority == expectedAuthority)
        #expect(partitions.nonportable == expectedNonportable)
        #expect(partitions.dynamicCatalogPortable == dynamicExpected)
        #expect(partitions.dynamicCatalogPortable.isSubset(of: partitions.portable))
        #expect(partitions.portable.isDisjoint(with: partitions.reassociation))
        #expect(partitions.portable.isDisjoint(with: partitions.authority))
        #expect(partitions.portable.isDisjoint(with: partitions.nonportable))
        #expect(partitions.reassociation.isDisjoint(with: partitions.authority))
        #expect(partitions.reassociation.isDisjoint(with: partitions.nonportable))
        #expect(partitions.authority.isDisjoint(with: partitions.nonportable))
        #expect(partitions.portable.union(partitions.reassociation)
            .union(partitions.authority).union(partitions.nonportable) == registryIDs)
        for definition in definitions {
            let layer: PolicyLayer = definition.layers.contains(.global) ? .global : .profile
            let actual = try PortableSettingPolicy.classify(id: definition.id,
                value: definition.defaultValue, layer: layer)
            let expected: PortableClassification
            if partitions.portable.contains(definition.id) { expected = .portable }
            else if partitions.reassociation.contains(definition.id) { expected = .requiresLocalReassociation }
            else if partitions.authority.contains(definition.id) { expected = .rejectedAuthority }
            else if partitions.nonportable.contains(definition.id) { expected = .rejectedNonPortable }
            else { Issue.record("Unclassified registry row \(definition.id.rawValue)"); continue }
            #expect(actual == expected, "classification \(definition.id.rawValue)")
        }
        let volume = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let volumeID = id("headroom.volumeOverrides.\(volume.uuidString)")
        #expect(try PortableSettingPolicy.classify(id: volumeID,
            value: .volume(.init(target: .inherit, warning: .automatic, clear: .fixedGiB(20))),
            layer: .global) == .requiresLocalReassociation)
    }

    @Test func hostileInMemoryAuthorityFamiliesCannotEscapeThroughExport() throws {
        let authority = PolicyDefaults.rows.filter { $0.resolution == .authority }
        var fields = Dictionary(uniqueKeysWithValues: authority.map { ($0.id, $0.defaultValue) })
        fields[id("scope.currentProject")] = .choice("private-project")
        let volume = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        fields[id("headroom.volumeOverrides.\(volume.uuidString)")] = .volume(.init(
            target: .fixedGiB(10), warning: .automatic, clear: .inherit))
        let exported = String(decoding: try SettingsTransfer.export(state(
            PolicyPreferences(global: .init(fields: fields)))), as: UTF8.self)
        for definition in authority { #expect(!exported.contains(definition.id.rawValue)) }
        #expect(!exported.contains("scope.currentProject"))
        #expect(!exported.contains("headroom.volumeOverrides"))
        #expect(!exported.contains("private-project"))
    }

    @Test func hostileKnownRowsAreVisibleButNeverCandidateValues() throws {
        let bytes = data(#"{"schemaVersion":1,"global":{"fields":{"feature.maintenance":{"bool":true},"maintenance.mode":{"choice":"authorizedCaches"},"scope.projectRoots":{"strings":["/Users/alice"]},"tools.approvedExecutables":{"strings":["/usr/local/bin/tool"]},"docker.approvedEndpoints":{"strings":["unix:///private/docker.sock"]},"browsers.keepCookieDomains":{"strings":["private.example"]},"future.path":{"choice":"/Users/alice"},"scan.preset":{"bool":true}}},"profiles":[],"inertImports":[]}"#)
        let current = PolicyPreferences(global: values([("feature.maintenance", .bool(false))]))
        let analysis = try SettingsTransfer.analyze(bytes: bytes, current: state(current))
        let outcomes = Dictionary(uniqueKeysWithValues: analysis.rows.compactMap { row in
            row.id.map { ($0, row.outcome) }
        })
        #expect(outcomes["feature.maintenance"] == .rejectedProtectionWeakening)
        #expect(outcomes["maintenance.mode"] == .rejectedAuthority)
        #expect(outcomes["scope.projectRoots"] == .requiresLocalReassociation)
        #expect(outcomes["browsers.keepCookieDomains"] == .rejectedNonPortable)
        #expect(outcomes["scan.preset"] == .rejectedInvalid)
        let resolved = try SettingsTransfer.resolve(analysis, choices: [:])
        #expect(resolved.candidate.preferences.global == current.global)
        #expect(resolved.candidate.inertImports.count == 1)
        #expect(analysis.rows.filter { $0.outcome != .committable }.allSatisfy { $0.value == nil })
        for secret in ["/Users/alice", "private.example", "/usr/local/bin/tool",
                       "unix:///private/docker.sock"] {
            #expect(!String(reflecting: analysis.committableImported).contains(secret))
            #expect(!String(reflecting: analysis.importedInert).contains(secret))
            #expect(!String(reflecting: analysis.rows).contains(secret))
            #expect(!String(reflecting: resolved.candidate).contains(secret))
            #expect(!String(decoding: try SettingsTransfer.export(resolved.candidate), as: UTF8.self)
                .contains(secret))
        }
    }

    @Test func unknownSafeScalarsPersistAndSensitiveValuesRedactExactly() throws {
        let bytes = data(#"{"schemaVersion":1,"global":{"fields":{"future.bool":{"bool":true},"future.count":{"integer":7},"future.none":{"null":true},"future.path":{"choice":"/Users/alice"}}},"profiles":[],"inertImports":[]}"#)
        let resolved = try SettingsTransfer.resolve(
            SettingsTransfer.analyze(bytes: bytes, current: state()), choices: [:])
        #expect(resolved.candidate.preferences.global.fields.isEmpty)
        #expect(resolved.candidate.inertImports.count == 4)
        let path = try #require(resolved.candidate.inertImports.first { $0.id == "future.path" })
        #expect(path.value == nil && path.valueKind == .choice && path.redacted)
        #expect(path.valueDigest == "f2f81912810b3a6b4e5a236377df2e4fd8cd5de950140f9929a53f0a4cd270cd")
        #expect(resolved.candidate.inertImports.first { $0.id == "future.bool" }?.value == .bool(true))
    }

    @Test func unsafeUnknownIDIsPreviewOnlyAndUnknownShapesRejectAtomically() throws {
        let unsafe = data(#"{"schemaVersion":1,"global":{"fields":{"/Users/alice":{"choice":"secret"}}},"profiles":[],"inertImports":[]}"#)
        let analysis = try SettingsTransfer.analyze(bytes: unsafe, current: state())
        let row = try #require(analysis.rows.first)
        #expect(row.id == nil && row.idDigest != nil && row.outcome == .redacted)
        #expect(row.idDigest == "983b47eddf324fb25fd56000dba5027ed362c7e9a6cd62a3b3508a2dc5300322")
        #expect(!String(reflecting: analysis.committableImported).contains("/Users/alice"))
        #expect(!String(reflecting: analysis.importedInert).contains("/Users/alice"))
        #expect(try SettingsTransfer.resolve(analysis, choices: [:]).candidate.inertImports.isEmpty)
        for malformed in [
            #"{"schemaVersion":1,"global":{"fields":{"future.x":{"object":{}}}},"profiles":[],"inertImports":[]}"#,
            #"{"schemaVersion":1,"global":{"fields":{"future.x":[1,2]}},"profiles":[],"inertImports":[]}"#
        ] {
            #expect(throws: SettingsTransferError.malformed) {
                try SettingsTransfer.analyze(bytes: data(malformed), current: state())
            }
        }
    }

    @Test func closedWireRejectsExtraKeysDuplicateProfilesAndOrphanInert() throws {
        let duplicate = #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"A","values":{"fields":{}}},{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"B","values":{"fields":{}}}],"inertImports":[]}"#
        let orphan = #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[],"inertImports":[{"scope":"profile","profileID":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","id":"future.x","value":{"bool":true},"valueKind":null,"valueDigest":null,"label":null}]}"#
        let extra = #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[],"inertImports":[],"extra":true}"#
        for malformed in [duplicate, orphan, extra] {
            #expect(throws: SettingsTransferError.invalidDocument) {
                try SettingsTransfer.analyze(bytes: data(malformed), current: state())
            }
        }
        let invalidDocuments = [
            #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","name":"A","values":{"fields":{}}}],"inertImports":[]}"#,
            #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"","values":{"fields":{}}}],"inertImports":[]}"#,
            #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":" A ","values":{"fields":{}}}],"inertImports":[]}"#,
            #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"A","values":{"fields":{}},"extra":true}],"inertImports":[]}"#,
            #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[],"inertImports":[{"scope":"global","profileID":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","id":"future.x","value":{"bool":true},"valueKind":null,"valueDigest":null,"label":null}]}"#,
            #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"A","values":{"fields":{}}}],"inertImports":[{"scope":"profile","profileID":null,"id":"future.x","value":{"bool":true},"valueKind":null,"valueDigest":null,"label":null}]}"#,
            #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[],"inertImports":[{"scope":"global","profileID":null,"id":"future.x","value":{"bool":true},"valueKind":"choice","valueDigest":"f2f81912810b3a6b4e5a236377df2e4fd8cd5de950140f9929a53f0a4cd270cd","label":"redacted"}]}"#,
            #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[],"inertImports":[{"scope":"global","profileID":null,"id":"future.x","value":null,"valueKind":"object","valueDigest":"f2f81912810b3a6b4e5a236377df2e4fd8cd5de950140f9929a53f0a4cd270cd","label":"redacted"}]}"#,
            #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[],"inertImports":[{"scope":"global","profileID":null,"id":"future.x","value":null,"valueKind":"choice","valueDigest":"F2F81912810B3A6B4E5A236377DF2E4FD8CD5DE950140F9929A53F0A4CD270CD","label":"redacted"}]}"#,
            #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[],"inertImports":[{"scope":"global","profileID":null,"id":"/unsafe","value":{"bool":true},"valueKind":null,"valueDigest":null,"label":null}]}"#,
            #"{"schemaVersion":1,"global":{"fields":{}},"profiles":[],"inertImports":[{"scope":"global","profileID":null,"id":"future.x","value":{"bool":true},"valueKind":null,"valueDigest":null,"label":null},{"scope":"global","profileID":null,"id":"future.x","value":{"bool":true},"valueKind":null,"valueDigest":null,"label":null}]}"#
        ]
        for invalid in invalidDocuments {
            #expect(throws: SettingsTransferError.invalidDocument) {
                try SettingsTransfer.analyze(bytes: data(invalid), current: state())
            }
        }
        for malformedTag in [
            #"{"schemaVersion":1,"global":{"fields":{"future.x":{"null":false}}},"profiles":[],"inertImports":[]}"#,
            #"{"schemaVersion":1,"global":{"fields":{"future.x":{"volume":{"clear":{"inherit":false},"target":{"inherit":true},"warning":{"automatic":true}}}}},"profiles":[],"inertImports":[]}"#,
            #"{"schemaVersion":1,"global":{"fields":{"future.x":{"integer":1.5}}},"profiles":[],"inertImports":[]}"#,
            #"{"schemaVersion":1e0,"global":{"fields":{}},"profiles":[],"inertImports":[]}"#
        ] {
            #expect(throws: SettingsTransferError.malformed) {
                try SettingsTransfer.analyze(bytes: data(malformedTag), current: state())
            }
        }
        #expect(throws: SettingsTransferError.unsupportedSchema(2)) {
            try SettingsTransfer.analyze(bytes: data(
                #"{"schemaVersion":2,"global":{"fields":{}},"profiles":[],"inertImports":[]}"#),
                current: state())
        }
        let exactString = String(repeating: "é", count: 2_048)
        _ = try SettingsTransfer.analyze(bytes: data(
            #"{"schemaVersion":1,"global":{"fields":{"future.x":{"choice":"\#(exactString)"}}},"profiles":[],"inertImports":[]}"#),
            current: state())
        let overString = exactString + "é"
        #expect(throws: SettingsTransferError.malformed) {
            try SettingsTransfer.analyze(bytes: data(
                #"{"schemaVersion":1,"global":{"fields":{"future.x":{"choice":"\#(overString)"}}},"profiles":[],"inertImports":[]}"#),
                current: state())
        }
        let thousandFields = (0..<1_000).map { #""future.\#($0)":{"bool":true}"# }.joined(separator: ",")
        _ = try SettingsTransfer.analyze(bytes: data(
            #"{"schemaVersion":1,"global":{"fields":{\#(thousandFields)}},"profiles":[],"inertImports":[]}"#), current: state())
        let thousandOne = thousandFields + #", "future.extra":{"bool":true}"#
        #expect(throws: SettingsTransferError.malformed) {
            try SettingsTransfer.analyze(bytes: data(
                #"{"schemaVersion":1,"global":{"fields":{\#(thousandOne)}},"profiles":[],"inertImports":[]}"#), current: state())
        }
    }

    @Test func collisionsRequireExactChoiceAndCloneRemapsProfileInert() throws {
        let local = SavedProfile(id: profileA, name: "Local", values: values([("ui.units", .choice("binary"))]))
        let current = state(PolicyPreferences(profiles: [local]))
        let bytes = data(#"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"Imported","values":{"fields":{"ui.units":{"choice":"decimal"}}}}],"inertImports":[{"scope":"profile","profileID":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","id":"future.flag","value":{"bool":true},"valueKind":null,"valueDigest":null,"label":null}]}"#)
        let analysis = try SettingsTransfer.analyze(bytes: bytes, current: current)
        #expect(analysis.collisions == [.init(profileID: profileA, localName: "Local", importedName: "Imported")])
        #expect(throws: SettingsTransferError.missingCollisionChoice(profileA)) {
            try SettingsTransfer.resolve(analysis, choices: [:])
        }
        let kept = try SettingsTransfer.resolve(analysis, choices: [profileA: .keepLocal])
        #expect(kept.candidate.preferences.profiles == [local])
        #expect(kept.candidate.inertImports.isEmpty)
        let replaced = try SettingsTransfer.resolve(analysis, choices: [profileA: .replace])
        #expect(replaced.candidate.preferences.profiles[0].name == "Imported")
        #expect(replaced.candidate.inertImports[0].profileID == profileA)
        let cloned = try SettingsTransfer.resolve(analysis, choices: [profileA: .clone(profileB)])
        #expect(cloned.candidate.preferences.profiles.map(\.id) == [profileA, profileB])
        #expect(cloned.candidate.inertImports[0].profileID == profileB)
    }

    @Test func inertMergeDeduplicatesAndKeepsCurrentOnGlobalConflict() throws {
        let current = state(.init(), inert: [inert("future.same"),
            inert("future.conflict", value: .integer(1)), inert("ui.units")])
        let bytes = data(#"{"schemaVersion":1,"global":{"fields":{}},"profiles":[],"inertImports":[{"scope":"global","profileID":null,"id":"future.same","value":{"bool":true},"valueKind":null,"valueDigest":null,"label":null},{"scope":"global","profileID":null,"id":"future.conflict","value":{"integer":2},"valueKind":null,"valueDigest":null,"label":null},{"scope":"global","profileID":null,"id":"ui.units","value":{"bool":true},"valueKind":null,"valueDigest":null,"label":null}]}"#)
        let resolved = try SettingsTransfer.resolve(
            SettingsTransfer.analyze(bytes: bytes, current: current), choices: [:])
        #expect(resolved.candidate.inertImports.count == 3)
        #expect(resolved.candidate.inertImports.first { $0.id == "future.conflict" }?.value == .integer(1))
        #expect(resolved.candidate.inertImports.first { $0.id == "ui.units" }?.value == .bool(true))
        #expect(resolved.rows.contains { $0.id == "future.conflict" && $0.outcome == .collision })
    }

    @Test func eachProfileCollisionChoiceOwnsCurrentAndImportedInertExactly() throws {
        let local = SavedProfile(id: profileA, name: "Local", values: .init())
        let currentInert = inert("future.local", scope: .profile, profile: profileA)
        let current = state(PolicyPreferences(profiles: [local]), inert: [currentInert])
        let bytes = data(#"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"Imported","values":{"fields":{}}}],"inertImports":[{"scope":"profile","profileID":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","id":"future.imported","value":{"bool":true},"valueKind":null,"valueDigest":null,"label":null}]}"#)
        let analysis = try SettingsTransfer.analyze(bytes: bytes, current: current)
        let kept = try SettingsTransfer.resolve(analysis, choices: [profileA: .keepLocal])
        #expect(kept.candidate.inertImports == [currentInert])
        #expect(kept.rows.contains { $0.id == "future.imported" && $0.outcome == .collision })
        let replaced = try SettingsTransfer.resolve(analysis, choices: [profileA: .replace])
        #expect(replaced.candidate.inertImports.map(\.id) == ["future.imported"])
        #expect(replaced.rows.contains { $0.id == "future.local" && $0.outcome == .collision })
        let cloned = try SettingsTransfer.resolve(analysis, choices: [profileA: .clone(profileB)])
        #expect(Set(cloned.candidate.inertImports.map(\.id)) == ["future.local", "future.imported"])
        #expect(cloned.candidate.inertImports.first { $0.id == "future.imported" }?.profileID == profileB)
    }

    @Test func collisionChoiceSetAndProfileLimitFailClosed() throws {
        let local = SavedProfile(id: profileA, name: "Local", values: .init())
        let bytes = data(#"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"Imported","values":{"fields":{}}}],"inertImports":[]}"#)
        let analysis = try SettingsTransfer.analyze(bytes: bytes,
            current: state(PolicyPreferences(profiles: [local])))
        #expect(throws: SettingsTransferError.unexpectedCollisionChoice(profileB)) {
            try SettingsTransfer.resolve(analysis, choices: [profileA: .keepLocal, profileB: .keepLocal])
        }
        #expect(throws: SettingsTransferError.cloneIDCollision(profileA)) {
            try SettingsTransfer.resolve(analysis, choices: [profileA: .clone(profileA)])
        }
        let fifty = (0..<50).map { index in
            SavedProfile(id: UUID(uuidString: String(format:
                "10000000-0000-0000-0000-%012d", index))!, name: "P\(index)", values: .init())
        }
        let noncollision = data(#"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","name":"51","values":{"fields":{}}}],"inertImports":[]}"#)
        #expect(throws: SettingsTransferError.tooManyProfiles) {
            let over = try SettingsTransfer.analyze(bytes: noncollision,
                current: state(PolicyPreferences(profiles: fifty)))
            _ = try SettingsTransfer.resolve(over, choices: [:])
        }
        let twoLocal = [local, SavedProfile(id: profileB, name: "Local B", values: .init())]
        let twoImports = data(#"{"schemaVersion":1,"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"A","values":{"fields":{}}},{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","name":"B","values":{"fields":{}}}],"inertImports":[]}"#)
        let two = try SettingsTransfer.analyze(bytes: twoImports,
            current: state(PolicyPreferences(profiles: twoLocal)))
        let sameClone = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        #expect(throws: SettingsTransferError.cloneIDCollision(sameClone)) {
            try SettingsTransfer.resolve(two,
                choices: [profileA: .clone(sameClone), profileB: .clone(sameClone)])
        }
    }

    @Test func importMergesExplicitGlobalAndPreservesProjectsAndAbsentValues() throws {
        let projects = ["local": values([("ui.units", .choice("binary"))])]
        let current = PolicyPreferences(global: values([
            ("ui.units", .choice("binary")), ("ui.density", .choice("compact"))]),
            projects: projects)
        let bytes = data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#)
        let resolved = try SettingsTransfer.resolve(
            SettingsTransfer.analyze(bytes: bytes, current: state(current)), choices: [:])
        #expect(resolved.candidate.preferences.global.fields[id("ui.units")] == .choice("decimal"))
        #expect(resolved.candidate.preferences.global.fields[id("ui.density")] == .choice("compact"))
        #expect(resolved.candidate.preferences.projects == projects)
    }

    @Test func importedProfilesCannotWeakenPostMergeGlobalRestrictions() throws {
        let bytes = data(#"{"schemaVersion":1,"global":{"fields":{"cleanup.hardBatchGiB":{"integer":8},"feature.headroom":{"bool":false},"monitor.suppressHiddenSampling":{"bool":true}}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"Weak","values":{"fields":{"cleanup.hardBatchGiB":{"integer":12},"feature.headroom":{"bool":true},"monitor.suppressHiddenSampling":{"bool":false}}}},{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","name":"Strict","values":{"fields":{"cleanup.hardBatchGiB":{"integer":4},"feature.headroom":{"bool":false},"monitor.suppressHiddenSampling":{"bool":true}}}}],"inertImports":[]}"#)
        let analysis = try SettingsTransfer.analyze(bytes: bytes, current: state())
        let weak = analysis.rows.filter { $0.profileID == profileA }
        #expect(weak.filter { $0.outcome == .rejectedProtectionWeakening }.count == 3)
        let resolved = try SettingsTransfer.resolve(analysis, choices: [:])
        #expect(resolved.candidate.preferences.profiles.first { $0.id == profileA }?.values.fields.isEmpty == true)
        #expect(resolved.candidate.preferences.profiles.first { $0.id == profileB }?.values.fields.count == 3)
    }

    @Test func stricterImportedGlobalCannotSilentlyInvalidateLocalProfile() throws {
        let local = SavedProfile(id: profileA, name: "Local",
            values: values([("feature.headroom", .bool(true))]))
        let bytes = data(#"{"schemaVersion":1,"global":{"fields":{"feature.headroom":{"bool":false}}},"profiles":[],"inertImports":[]}"#)
        let analysis = try SettingsTransfer.analyze(bytes: bytes,
            current: state(PolicyPreferences(global: values([("feature.headroom", .bool(true))]),
                                             profiles: [local])))
        #expect(throws: SettingsTransferError.candidateInvalid(id("feature.headroom"))) {
            try SettingsTransfer.resolve(analysis, choices: [:])
        }
    }

    @Test func contextFreeRelationsRejectImportedRowAndPreserveCurrent() throws {
        let current = PolicyPreferences(global: values([
            ("notifications.quietStart", .choice("22:00")),
            ("headroom.warningGiB", .integer(10)),
            ("budget.models.highGiB", .integer(20))]))
        let bytes = data(#"{"schemaVersion":1,"global":{"fields":{"budget.models.lowGiB":{"integer":20},"headroom.clearGiB":{"integer":10},"notifications.quietEnd":{"choice":"22:00"}}},"profiles":[],"inertImports":[]}"#)
        let analysis = try SettingsTransfer.analyze(bytes: bytes, current: state(current))
        #expect(analysis.rows.filter { $0.outcome == .rejectedInvalid }.count == 3)
        let result = try SettingsTransfer.resolve(analysis, choices: [:]).candidate.preferences.global
        #expect(result == current.global)
    }

    @Test func inputBoundIsExact() throws {
        let oversized = Data(repeating: 0x20, count: StrictJSON.byteLimit + 1)
        #expect(throws: SettingsTransferError.oversized) {
            try SettingsTransfer.analyze(bytes: oversized, current: state())
        }
    }

    @Test func mergedCandidateAggregateFieldAndInertBoundsAreExact() throws {
        let empty = data(#"{"schemaVersion":1,"global":{"fields":{}},"profiles":[],"inertImports":[]}"#)
        let atFieldLimit = typedState(totalFields: 4_096)
        _ = try SettingsTransfer.resolve(
            SettingsTransfer.analyze(bytes: empty, current: atFieldLimit), choices: [:])
        #expect(throws: SettingsTransferError.invalidDocument) {
            let over = try SettingsTransfer.analyze(bytes: empty,
                current: typedState(totalFields: 4_097))
            _ = try SettingsTransfer.resolve(over, choices: [:])
        }
        let thousand = (0..<1_000).map { inert(String(format: "future.i%04d", $0)) }
        _ = try SettingsTransfer.export(state(.init(), inert: thousand))
        let oneMore = data(#"{"schemaVersion":1,"global":{"fields":{"future.extra":{"bool":true}}},"profiles":[],"inertImports":[]}"#)
        #expect(throws: SettingsTransferError.invalidDocument) {
            let over = try SettingsTransfer.analyze(bytes: oneMore,
                current: state(.init(), inert: thousand))
            _ = try SettingsTransfer.resolve(over, choices: [:])
        }
        #expect(throws: SettingsTransferError.invalidDocument) {
            _ = try SettingsTransfer.export(state(.init(), inert: thousand + [inert("future.extra")]))
        }
    }

    @Test func canonicalEncoderExactOneMiBBoundaryAndCheckedGrowth() throws {
        let full = String(repeating: "a", count: 4_096)
        let exact = StrictJSON.Value.array((0..<255).map { _ in .string(full) }
            + [.string(String(repeating: "b", count: 3_327))])
        #expect(try StrictJSON.canonicalData(exact).count == StrictJSON.byteLimit)
        let over = StrictJSON.Value.array((0..<255).map { _ in .string(full) }
            + [.string(String(repeating: "b", count: 3_328))])
        #expect(throws: StrictJSONError.oversized) { try StrictJSON.canonicalData(over) }
    }

    @Test func malformedPreservedStateRejectsWithoutTruncationOrRepair() throws {
        let empty = data(#"{"schemaVersion":1,"global":{"fields":{}},"profiles":[],"inertImports":[]}"#)
        let invalidGlobal = state(PolicyPreferences(global:
            values([("scan.requestedWorkers", .integer(99))])))
        let invalidProject = state(PolicyPreferences(projects: ["p":
            values([("scan.requestedWorkers", .integer(99))])]))
        let orphan = state(.init(), inert: [inert("future.x", scope: .profile, profile: profileA)])
        let duplicate = state(.init(), inert: [inert("future.x"), inert("future.x")])
        let overlong = state(PolicyPreferences(projects:
            [String(repeating: "é", count: 2_049): .init()]))
        for current in [invalidGlobal, invalidProject, orphan, duplicate, overlong] {
            #expect(throws: SettingsTransferError.invalidDocument) {
                let analysis = try SettingsTransfer.analyze(bytes: empty, current: current)
                _ = try SettingsTransfer.resolve(analysis, choices: [:])
            }
            #expect(throws: SettingsTransferError.invalidDocument) {
                _ = try SettingsTransfer.export(current)
            }
        }
    }

    @Test func canonicalEscapingNumbersProfileAndInertOrderAreDeterministic() throws {
        let special = "\"\\\u{8}\u{c}\n\r\t\u{1f}é/"
        let encoded = String(decoding: try StrictJSON.canonicalData(.string(special)), as: UTF8.self)
        #expect(encoded == "\"\\\"\\\\\\b\\f\\n\\r\\t\\u001fé/\"")
        #expect(String(decoding: try StrictJSON.canonicalData(
            try StrictJSON.parse(data("-0"))), as: UTF8.self) == "0")
        let profileC = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let profiles = [profileC, profileA, profileB].map {
            SavedProfile(id: $0, name: "P\($0.uuidString.prefix(1))",
                values: values([("ui.units", .choice("decimal"))]))
        }
        let inertRows = [inert("future.z", scope: .profile, profile: profileC),
                         inert("future.b"), inert("future.a"),
                         inert("future.a", scope: .profile, profile: profileA)]
        let first = try SettingsTransfer.export(state(
            PolicyPreferences(profiles: profiles), inert: inertRows))
        let second = try SettingsTransfer.export(state(
            PolicyPreferences(profiles: Array(profiles.reversed())), inert: Array(inertRows.reversed())))
        #expect(first == second)
        guard case .object(let root) = try StrictJSON.parse(first),
              case .array(let encodedProfiles)? = root["profiles"],
              case .array(let encodedInert)? = root["inertImports"] else {
            Issue.record("Missing canonical export arrays"); return
        }
        func profileID(_ value: StrictJSON.Value) throws -> String {
            guard case .object(let row) = value,
                  case .string(let value)? = row["id"] else {
                throw SettingsTransferError.invalidDocument
            }
            return value
        }
        #expect(try encodedProfiles.map(profileID) == [
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            "cccccccc-cccc-cccc-cccc-cccccccccccc"
        ])
        func inertTuple(_ value: StrictJSON.Value) throws -> String {
            guard case .object(let row) = value,
                  case .string(let scope)? = row["scope"],
                  case .string(let id)? = row["id"] else {
                throw SettingsTransferError.invalidDocument
            }
            let profile: String
            if case .string(let value)? = row["profileID"] { profile = value }
            else { profile = "" }
            let kind: String
            if case .string(let value)? = row["valueKind"] { kind = value }
            else { kind = "" }
            let digest: String
            if case .string(let value)? = row["valueDigest"] { digest = value }
            else { digest = "" }
            return "\(scope)|\(profile)|\(id)|\(kind)|\(digest)"
        }
        #expect(try encodedInert.map(inertTuple) == [
            "global||future.a||", "global||future.b||",
            "profile|aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa|future.a||",
            "profile|cccccccc-cccc-cccc-cccc-cccccccccccc|future.z||"
        ])
    }
}
```

## Commands and acceptance

1. Create only the test file and run `cd TidyCore && swift test --jobs 2 --filter SettingsTransferTests`; capture missing-symbol compile RED.
2. Extract `StrictJSON` and map existing settings errors; run existing malformed settings tests before implementing transfer.
3. Implement `SettingsTransfer.swift`; run focused GREEN.
4. Run ordinary package coverage plus isolated bounded-process and settings-process partitions with `--jobs 2`.
5. `git diff --check`, exact allowlist audit and fresh adversarial code review are mandatory before acceptance.

The source review must inspect both new files for `FileManager`, `Data(contentsOf:)`, write APIs, `Process`, networking, global persistence and hidden singleton use. Purity is established by value-only signatures plus source audit; no ambient-filesystem test may be used as false I/O proof.

No app file changes, so no Xcode app build is required. Passing T07.1a claims neither durable import, actor-issued previews, profile activation, UI nor full T07 acceptance.
