# T05 — Settings preservation and UI safety implementation-entry plan

> **For agentic workers:** Use executing-plans after independent review and assignment of the entered unit. This is a documentation-only entry card: every new interface and test below is proposed, not implemented or verified. Source work is serialized with other assigned implementers; T03.A currently owns overlapping RunReport changes. No source commit, launch, test or build is authorized by preparation of this card.

**Goal:** Preserve historical settings and reports, make recovery non-destructive, and test shared application settings/confirmation ownership without granting fixture execution authority.

**Architecture:** One SettingsStore actor owns settings bytes and durable storage revisions. The existing T02 ExecutionPolicyBridge retains ordered submissions and the coordinator's synchronous policy invalidation/opaque commit tickets; storage revisions are not execution permission. All windows consume one AppExecutionServices. Keep the audited metadata-only manual host unchanged; a separately reviewed scratch-only safety host tests actual shared settings wiring.

**Tech stack:** Native Swift/SwiftUI, Swift Testing/XCTest, Foundation/Darwin, local TidyCore; no third-party runtime dependencies.

## Binding constraints and source checkpoint

- Native Swift/SwiftUI, macOS 14+, local TidyCore package, zero third-party runtime dependencies.
- Intel x86_64 and Apple Silicon arm64 supported; both require build and device evidence.
- No internet requests, telemetry, remote updates, repository fetches, model downloads, or remote package dependencies at runtime.
- Local IPC to an explicitly identified local tool service is allowed. No remote Docker contexts, TCP endpoints, SSH endpoints, or daemon auto-start during discovery.
- No repository deletion, database deletion, Docker volume deletion, local-model deletion, generic duplicate-file deletion, arbitrary scripts, or automatic force-quitting.
- No kernel tuning, swap-file manipulation, launch-agent disabling, privileged persistent helper, or changes to other tools' settings.
- No full-home scans on popover open or timers. No repository-supplied executable/config evaluation merely to discover a project.
- No change to signing, publishing, deployment, or remote Git state is authorized by this document.

PRODUCT.md, design S01–S16 and the entire registry/default/adapter contract remain binding. Import limits: 1 MiB bytes, depth16, profiles50, list entries1,000, string characters4,096; invalid UTF-8, duplicate keys and integer overflow reject. Every unknown ID is inert, not a capability. Roots, executable/volume identities, quit rights, notifications, login items and automation consent are local authority, never portable preferences. No settings reset clears the mandatory unfinished-effect journal.

Initial inspected checkpoint was `10f6901` on branch `CAJ/developer-headroom`. T02 foundation is now independently approved through `10616b3`: ConfigStore.save throws, load still falls back on corruption, and AppConfigStore submits through the existing policy bridge. TidyConfig remains schema1; old ItemResult missing-memory compatibility and off-main settings/startup I/O remain T05 work. T03.A is concurrently assigned report-schema changes, so reconcile its final reviewed RunReport before T05 source entry. Do not rely on the initial pre-T02 source snapshot or create a second writer.

The entire `T02-sealed-execution.md` is the consuming contract. Its bridge already chains writes, invalidates synchronously before any Task/await/projection, and commits only the latest opaque ticket after successful throwing ConfigStore.save. Do not restore a swallowing overload or add a second writer/policy resolver. T02's measurement availability field concerns coordinator no-op/denial; it does not establish old historical memory measurement.

## Units and entry gates

| Unit | Entry | Independently reviewable result |
|---|---|---|
| T05A.1 | T02 source idle/landed; card review | Bounded v1 decoding, schema2 envelope, recoverable read, old report memory unavailable; complete core RED below |
| T05A.2 | A.1 review | Owner-only atomic persistence, backup/explicit rollback, single-writer conflict rejection; actual I/O failure preservation |
| T05A.3 | A.2 + explicit T02 integration review | Off-main startup/settings I/O with the existing bridge's synchronous invalidation and ordering preserved; shared service tests |
| T05B.1 | A.3 + re-audit actual app service constructor | Separate fixed-scratch host + real shared threshold editor, two-window setter/close tests; denied-row visibility stays in manual host |
| T05B.2 | Accepted existing-scope `.M` adapter, T03/T04 + reviewed fixture and complete new RED code | Positive selected/deselected execution, actual frozen confirmation UI, in-flight close/drain/busy and unknown-import effect denial |

T05B.2 is **entry-blocked**, not a task to populate with fake trusted IDs or an allow-all registry. Its complete tests cannot truthfully be specified against a nonexistent accepted adapter. Before entry, extend this card with that adapter's exact disposable fixture, parser/planner/effect boundary and full executable UI tests; independent review is mandatory. A.1–B.1 may establish foundations only, never full T05 or useful cleanup acceptance.

## T05A.1 — Exact shape, fixtures and complete core RED

Files for A.1: create `TidyCore/Sources/TidyCore/Policy/SettingsEnvelope.swift`, `SettingsStore.swift`; modify `Model/RunReport.swift` and `TidyCore/Package.swift`; create `TidyCore/Tests/TidyCoreTests/SettingsMigrationTests.swift` and `Fixtures/Config/{v1-original,v1-memory,corrupt,v999,old-report}.json`. `Model/TidyConfig.swift`, `Engine/ConfigStore.swift`, existing ConfigStoreTests and all app persistence call sites remain unchanged through A.1/A.2; their migration belongs to A.3's atomic app cutover.

T03.A reconciliation: A.1 also owns the single `GuardedDeletionTests.missingLegacyMemoryDoesNotSilentlyBecomeMeasuredZero` test migration once its explicit availability fields land. Its interim T03 expectation is a decode error rather than invented zero. Replace only that expectation with successful legacy decode plus `measuredReclaimedMemoryBytes == nil` and nil aggregate/round-trip observations; do not remove the regression or retain a contradictory required-key expectation after A.1. Other T03 mechanism tests remain unchanged. Include this focused test in A.1 GREEN verification alongside its original migration suite.

Complete replacement for that one test at A.1 entry (not a T03 source edit):

```swift
@Test func missingLegacyMemoryDoesNotSilentlyBecomeMeasuredZero() throws {
    let bytes = Data(#"{"id":"x","title":"X","freedBytes":100,"succeeded":true}"#.utf8)
    let item = try JSONDecoder().decode(ItemResult.self, from: bytes)
    #expect(item.measuredReclaimedMemoryBytes == nil)
    let report = RunReport(tier: .safe, results: [item],
        startedAt: Date(timeIntervalSince1970: 100), finishedAt: Date(timeIntervalSince1970: 101),
        freeSpaceBeforeBytes: 1000, freeSpaceAfterBytes: 1000)
    #expect(report.measuredTotalReclaimedMemoryBytes == nil)
    let roundTrip = try JSONDecoder().decode(RunReport.self, from: JSONEncoder().encode(report))
    #expect(roundTrip.results[0].measuredReclaimedMemoryBytes == nil)
    #expect(roundTrip.measuredTotalReclaimedMemoryBytes == nil)
}
```

**Staging contract:** A.1's SettingsStore uses its own bounded legacy decoder and constructs the in-memory projection with explicit `TidyConfig(schemaVersion: 2, ...)`. Keep `TidyConfig.currentSchemaVersion`, its default initializer and T02's existing flat ConfigStore writer at schema1 through A.1/A.2. Do not change the default to2 while ConfigStore still writes flat objects: a flat schema2 file is not a valid schema2 envelope. A.2's new writer is exercised only at explicit disposable scratch URLs until A.3; it must not share the live app URL with the legacy writer. Existing fallback load behavior/tests remain untouched until A.3 replaces all app consumers together. Intermediate A.1/A.2 builds are not deployable migration releases and must never be reported as production recovery-safe.

Proposed signatures (declarations specify implementation obligations, not compiled source):

```swift
public enum SettingsLoadDisposition: Equatable, Sendable {
    case newDefaults, migrated, loaded, recoveryReadOnly
}
public enum SettingsRecoveryReason: Equatable, Sendable {
    case malformed, unsupportedSchema(Int), unavailable, unsafeLocation, oversized
}
public struct SettingsEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int // exactly 2
    public let revision: UInt64   // storage revision; starts at 0, checked increment
    public let config: TidyConfig // schemaVersion == 2; legacy names remain inert
}
public struct SettingsLoadResult: Equatable, Sendable {
    public let disposition: SettingsLoadDisposition
    public let envelope: SettingsEnvelope? // nil for recovery, NOT usable defaults
    public let recoveryReason: SettingsRecoveryReason?
}
public enum SettingsChange: Equatable, Sendable {
    case transcriptAgeDays(Int)
    case legacyPreferences(TidyConfig)
}
public enum SettingsStoreError: Error, Equatable, Sendable {
    case readOnlyRecovery, staleRevision, changedExternally, invalidChange
    case unavailable, unsafeLocation, oversized, revisionOverflow, writeFailed, durabilityUncertain
}
public struct SettingsRollbackPreview: Sendable {
    public let config: TidyConfig
    // Store-issued opaque identity; constructor and original-byte digest internal.
}
public actor SettingsStore {
    public init(url: URL) // no default path, no I/O in initializer
    public func load() -> SettingsLoadResult
    public func update(expectedRevision: UInt64, change: SettingsChange) throws -> SettingsEnvelope
    public func previewRollback() throws -> SettingsRollbackPreview
    public func rollback(expectedRevision: UInt64, preview: SettingsRollbackPreview) throws -> SettingsEnvelope
    // All methods are async to callers by actor isolation. No policy commit here.
}
```

`legacyPreferences` exists only for T02's existing whole-value AppConfigStore setter transition. Validate every field/range/size, require schema2, preserve unknown preset IDs, and never mint local authority from legacy name/path/Bool fields. A legacy name approval is inert pending identity reassociation; old restart true means advanced visibility only, no restart permission. Existing local roots survive byte/value migration, but are not evidence of new local root authorization. T06 owns the registry-backed settings/EffectivePolicy integration and its reviewed resolver boundary; T05 must not implement a competing resolver. T02 conservatively invalidates every edit meanwhile.

Read the bounded JSON object's schemaVersion before decoding any payload. Known version1 is a flat object: required original fields must decode; only the later `appsApprovedForQuit` and `allowRestartToReclaimSwap` fields default to []/false when absent. Do not make every malformed required field silently default. Version2 is the envelope above; nested config.schemaVersion must also be2. Unsupported version means recovery even when its payload is not recognizable. Missing file alone means newDefaults; unreadable, directory, symlink, foreign-owned, oversized, zero-byte, malformed or future content is recovery. Load is read-only: a migrated result is memory migration, not permission to rewrite bytes. Revision0 for new/v1; first explicit successful change writes revision1. Valid v2 retains its revision across relaunch. UInt64.max blocks edits, never wraps.

Fixture contents, including all fields (write the named files exactly; no real user paths):

`v1-original.json`:
```json
{"schemaVersion":1,"hasCompletedOnboarding":true,"keepCookieDomains":["example.invalid","keep.invalid"],"simulatorsApprovedForDeletion":["Old simulator name"],"gitRoots":["/fixture/Developer","/fixture/Other"],"staleNodeModulesThresholdDays":90,"transcriptAgeThresholdDays":120,"presets":[{"name":"Weekly","itemIDs":["safe.tool.npm-cache-clean","unknown.preset.id","deep.simulator.erase-all"]}]}
```

`v1-memory.json`:
```json
{"schemaVersion":1,"hasCompletedOnboarding":true,"keepCookieDomains":["example.invalid","keep.invalid"],"simulatorsApprovedForDeletion":["Old simulator name"],"gitRoots":["/fixture/Developer","/fixture/Other"],"staleNodeModulesThresholdDays":90,"transcriptAgeThresholdDays":120,"transcriptAgeThresholdDaysUnused":999,"appsApprovedForQuit":["Old application name"],"allowRestartToReclaimSwap":true,"presets":[{"name":"Weekly","itemIDs":["safe.tool.npm-cache-clean","unknown.preset.id","deep.simulator.erase-all"]}]}
```

`corrupt.json` (intentionally incomplete):
```text
{"schemaVersion":1,"presets":[
```

`v999.json`:
```json
{"schemaVersion":999,"payload":{"unrecognized":true},"neverOverwrite":"future bytes"}
```

`old-report.json` (Foundation default Date strategy: seconds since reference date):
```json
{"tier":"safe","results":[{"id":"historical","title":"Old cache record","freedBytes":13,"succeeded":true,"message":null}],"startedAt":0,"finishedAt":1,"freeSpaceBeforeBytes":100,"freeSpaceAfterBytes":113}
```

Unknown raw JSON keys in historical migration are not reinterpreted as authority. Preserve the original exact bytes in the backup on the first explicit save. Unknown preset IDs survive the schema2 round trip as data. If lossless arbitrary extension-key round-tripping is requested beyond these original shapes, stop for review rather than widening the portable settings schema implicitly.

**T06 extension boundary:** `config` is the migrated legacy compatibility projection, not the permanent complete settings registry. T06 consumes the same envelope/storage revision and adds registry-backed Feature/Scan/Cleanup/Experience preferences plus EffectivePolicy through a reviewed additive schema2 payload field. No registry defaults, feature flags or second effective-policy resolver are invented here. Before T06 publishes such files, its decoder/encoder must preserve that typed field on every legacy-control edit, distinguish absent/inherit from explicit values, and reject unsupported keys/layers without resetting to defaults. A T05-only binary encountering a schema2 extension it cannot preserve must enter recoveryReadOnly rather than erase it on a subsequent save; version2 is not permission to silently discard unknown envelope fields. The machine-local A authorization ledger stays separate, never embedded as portable authority in this extension. The exact typed registry representation is T06's entry-review obligation; coordinate that envelope extension before implementation rather than permanently locking schema2 to the legacy config shape.

Add `.copy("Fixtures/Config")` to the **testTarget** resources only; `Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Config")` is the fixture lookup. No package production resources or remote dependencies.

Add `ItemResult.measuredReclaimedMemoryBytes: Int64?` and `RunReport.measuredTotalReclaimedMemoryBytes: Int64?`. Keep old numeric fields only as compatibility data while migrating callers; absence of historical memory observations returns nil, never inferred zero. Mixed known/unknown item observations give unavailable aggregate. A new explicitly supplied memory measurement may be zero. Default initializer argument must become optional so omission cannot masquerade as measured zero. Preserve T02's disposition/coordinatorMeasurementsAvailable defaults and denial display. At A.3's reviewed app integration, results UI must read availability, never fall back to compatibility zero for these historical reports. Production report consumers remain unchanged in the non-deployable A.1 checkpoint. Full T03 outcome schema remains separate.

Complete `SettingsMigrationTests.swift`:

```swift
import Foundation
import Darwin
import Testing
@testable import TidyCore

private func canonicalSettingsScratchBase() throws -> URL {
    var path = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath("/private/tmp", &path) != nil else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return URL(fileURLWithPath: String(cString: path), isDirectory: true)
}

private struct SettingsScratch {
    let root: URL
    var file: URL { root.appendingPathComponent("config.json") }
    var backup: URL { root.appendingPathComponent("config.backup.json") }
    init() throws {
        root = try canonicalSettingsScratchBase()
            .appendingPathComponent("T05-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
    }
    func seed(_ bytes: Data) throws {
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json",
                                             subdirectory: "Config"))
    return try Data(contentsOf: url)
}
private func expectStoreError(_ expected: SettingsStoreError,
                             _ body: () async throws -> Void) async {
    do { try await body(); Issue.record("Expected \(expected)") }
    catch let error as SettingsStoreError { #expect(error == expected) }
    catch { Issue.record("Unexpected error: \(error)") }
}
private func mode(_ url: URL) throws -> Int {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attrs[.posixPermissions] as? NSNumber).intValue & 0o777
}

@Suite("Settings migration")
struct SettingsMigrationTests {
    @Test func missingOnlyCreatesInMemoryDefaults() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .newDefaults)
        let value = try #require(result.envelope)
        #expect(value.schemaVersion == 2 && value.revision == 0)
        #expect(value.config.gitRoots.isEmpty && value.config.presets.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: s.file.path))
    }

    @Test(arguments: ["v1-original", "v1-memory"])
    func bothHistoricalShapes(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture(name); try s.seed(original)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .migrated && result.recoveryReason == nil)
        let envelope = try #require(result.envelope)
        #expect(envelope.schemaVersion == 2 && envelope.revision == 0)
        let c = envelope.config
        #expect(c.schemaVersion == 2 && c.hasCompletedOnboarding)
        #expect(c.gitRoots == ["/fixture/Developer", "/fixture/Other"])
        #expect(c.keepCookieDomains == ["example.invalid", "keep.invalid"])
        #expect(c.simulatorsApprovedForDeletion == ["Old simulator name"])
        #expect(c.staleNodeModulesThresholdDays == 90 && c.transcriptAgeThresholdDays == 120)
        #expect(c.presets == [CustomPreset(name: "Weekly", itemIDs: [
            "safe.tool.npm-cache-clean", "unknown.preset.id", "deep.simulator.erase-all"])])
        #expect(c.appsApprovedForQuit == (name == "v1-memory" ? ["Old application name"] : []))
        #expect(c.allowRestartToReclaimSwap == (name == "v1-memory"))
        #expect(try Data(contentsOf: s.file) == original)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
    }

    @Test(arguments: ["v1-original", "v1-memory"])
    func bothHistoricalShapesPersistRoundTrip(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture(name); try s.seed(original)
        let store = SettingsStore(url: s.file)
        let result = await store.load()
        #expect(result.disposition == .migrated)
        let envelope = try #require(result.envelope)
        let c = envelope.config
        #expect(c.schemaVersion == 2 && c.hasCompletedOnboarding)
        #expect(c.gitRoots == ["/fixture/Developer", "/fixture/Other"])
        #expect(c.keepCookieDomains == ["example.invalid", "keep.invalid"])
        #expect(c.simulatorsApprovedForDeletion == ["Old simulator name"])
        #expect(c.staleNodeModulesThresholdDays == 90 && c.transcriptAgeThresholdDays == 120)
        #expect(c.presets == [CustomPreset(name: "Weekly", itemIDs: [
            "safe.tool.npm-cache-clean", "unknown.preset.id", "deep.simulator.erase-all"])])
        #expect(c.appsApprovedForQuit == (name == "v1-memory" ? ["Old application name"] : []))
        #expect(c.allowRestartToReclaimSwap == (name == "v1-memory"))
        #expect(try Data(contentsOf: s.file) == original) // load never writes
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        let saved = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(121))
        #expect(saved.revision == 1 && saved.config.transcriptAgeThresholdDays == 121)
        #expect(saved.config.gitRoots == c.gitRoots && saved.config.presets == c.presets)
        #expect(try Data(contentsOf: s.backup) == original)
        let reopened = await SettingsStore(url: s.file).load()
        #expect(reopened.disposition == .loaded && reopened.envelope == saved)
        #expect(try mode(s.root) == 0o700)
        #expect(try mode(s.file) == 0o600 && mode(s.backup) == 0o600)
    }

    @Test(arguments: ["corrupt", "v999"])
    func recoveryPreservesBytes(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture(name); try s.seed(bytes)
        let store = SettingsStore(url: s.file); let result = await store.load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(result.recoveryReason == (name == "v999" ? .unsupportedSchema(999) : .malformed))
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        await expectStoreError(.readOnlyRecovery) { _ = try await store.previewRollback() }
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
    }

    @Test(arguments: [Data(), Data("{\"schemaVersion\":1,\"hasCompletedOnboarding\":false}".utf8),
                       Data("{\"schemaVersion\":1,\"schemaVersion\":2}".utf8),
                       Data(repeating: 0x20, count: 1_048_577), Data([0xff, 0xfe])])
    func existingInvalidIsNeverNewDefaults(bytes: Data) async throws {
        let s = try SettingsScratch(); defer { s.remove() }; try s.seed(bytes)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(try Data(contentsOf: s.file) == bytes)
    }

    @Test func symlinkDoesNotAuthorizeReadingOrReplacingDestination() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let target = s.root.appendingPathComponent("other.json")
        let bytes = try fixture("v1-original"); try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: s.file, withDestinationURL: target)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly)
        #expect(try Data(contentsOf: target) == bytes)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: s.file.path) == target.path)
    }

    @Test func realWriteFailureLeavesExistingConfigAndRevision() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        let store = SettingsStore(url: s.file); _ = await store.load()
        guard geteuid() != 0 else { Issue.record("Requires ordinary unprivileged test user"); return }
        // Real pre-publication EACCES in this exact disposable directory. Because
        // load is read-only and has not created config.lock, the first failure may
        // be stable-lock creation, not candidate-temp creation. Do not claim a
        // later write stage without observing that the real lock was established.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: s.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: s.root.path) }
        await expectStoreError(.writeFailed) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(await store.load().envelope?.revision == 0)
    }

    @Test func staleRevisionAndExternalReplacementCannotOverwrite() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let store = SettingsStore(url: s.file); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let first = try Data(contentsOf: s.file)
        await expectStoreError(.staleRevision) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        }
        #expect(try Data(contentsOf: s.file) == first)
        let future = try fixture("v999"); try s.seed(future)
        await expectStoreError(.changedExternally) {
            _ = try await store.update(expectedRevision: 1, change: .transcriptAgeDays(90))
        }
        #expect(try Data(contentsOf: s.file) == future)
    }

    @Test func invalidEditAndExplicitRollback() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-memory"); try s.seed(bytes)
        let store = SettingsStore(url: s.file); _ = await store.load()
        await expectStoreError(.invalidChange) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(366))
        }
        #expect(try Data(contentsOf: s.file) == bytes)
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let preview = try await store.previewRollback()
        let restored = try await store.rollback(expectedRevision: 1, preview: preview)
        #expect(restored.revision == 2 && restored.config.transcriptAgeThresholdDays == 120)
        #expect(restored.config.presets.first?.itemIDs.contains("unknown.preset.id") == true)
    }

    @Test func oldReportsHaveUnavailableMemoryNotMeasuredZero() throws {
        let report = try JSONDecoder().decode(RunReport.self, from: fixture("old-report"))
        #expect(report.totalFreedBytes == 13)
        #expect(report.results[0].measuredReclaimedMemoryBytes == nil)
        #expect(report.measuredTotalReclaimedMemoryBytes == nil)
        let roundTrip = try JSONDecoder().decode(RunReport.self, from: JSONEncoder().encode(report))
        #expect(roundTrip.measuredTotalReclaimedMemoryBytes == nil)
        #expect(roundTrip.results[0].measuredReclaimedMemoryBytes == nil)
    }
}
```

Mandatory additional RED methods in the same SettingsMigrationTests suite (before A.1/A.2 implementation, not postponed coverage):

```swift
extension SettingsMigrationTests {
    private func schema2(nestedVersion: Int = 2, revision: UInt64 = 0,
                         extra: [String: Any] = [:]) throws -> Data {
        var config = try #require(JSONSerialization.jsonObject(with: fixture("v1-original")) as? [String: Any])
        config["schemaVersion"] = nestedVersion
        config["appsApprovedForQuit"] = [String]()
        config["allowRestartToReclaimSwap"] = false
        var envelope: [String: Any] = ["schemaVersion": 2, "revision": NSNumber(value: revision), "config": config]
        for (key, value) in extra { envelope[key] = value }
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    @Test func knownSchema2LoadsNonzeroRevisionWithoutWriting() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try schema2(revision: 41); try s.seed(bytes)
        let expected = TidyConfig(schemaVersion: 2, hasCompletedOnboarding: true,
            keepCookieDomains: ["example.invalid", "keep.invalid"],
            simulatorsApprovedForDeletion: ["Old simulator name"],
            gitRoots: ["/fixture/Developer", "/fixture/Other"],
            staleNodeModulesThresholdDays: 90, transcriptAgeThresholdDays: 120,
            appsApprovedForQuit: [], allowRestartToReclaimSwap: false,
            presets: [CustomPreset(name: "Weekly", itemIDs: [
                "safe.tool.npm-cache-clean", "unknown.preset.id", "deep.simulator.erase-all"])])
        let store = SettingsStore(url: s.file)
        let result = await store.load()
        #expect(result.disposition == .loaded && result.recoveryReason == nil)
        let envelope = try #require(result.envelope)
        #expect(envelope.schemaVersion == 2 && envelope.revision == 41)
        #expect(envelope.config == expected)
        #expect(await store.load() == result)
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
    }

    @Test func unknownSchema2ExtensionAndNestedMismatchAreReadOnly() async throws {
        for bytes in [try schema2(extra: ["registryPreferences": ["feature.rescue": true]]),
                      try schema2(nestedVersion: 1)] {
            let s = try SettingsScratch(); defer { s.remove() }; try s.seed(bytes)
            let store = SettingsStore(url: s.file); let result = await store.load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            await expectStoreError(.readOnlyRecovery) {
                _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
            }
            await expectStoreError(.readOnlyRecovery) { _ = try await store.previewRollback() }
            #expect(try Data(contentsOf: s.file) == bytes)
            #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        }
    }

    @Test func revisionOverflowNeverWrapsOrWrites() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try schema2(revision: UInt64.max); try s.seed(bytes)
        let store = SettingsStore(url: s.file); _ = await store.load()
        await expectStoreError(.revisionOverflow) {
            _ = try await store.update(expectedRevision: UInt64.max, change: .transcriptAgeDays(90))
        }
        #expect(try Data(contentsOf: s.file) == bytes)
    }

    @Test func depthListAndStringBoundsRejectWithoutRewrite() async throws {
        var base = try #require(JSONSerialization.jsonObject(with: fixture("v1-original")) as? [String: Any])
        var largeList = base; largeList["gitRoots"] = Array(repeating: "/fixture/root", count: 1001)
        var longString = base; longString["gitRoots"] = [String(repeating: "x", count: 4097)]
        var nested: Any = "leaf"
        for _ in 0..<17 { nested = ["next": nested] }
        base["unknownNested"] = nested
        for object in [largeList, longString, base] {
            let s = try SettingsScratch(); defer { s.remove() }
            let bytes = try JSONSerialization.data(withJSONObject: object); try s.seed(bytes)
            let result = await SettingsStore(url: s.file).load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            #expect(try Data(contentsOf: s.file) == bytes)
        }
    }

    @Test func ownedLegacy755DirectoryAnd644FileMigrateWithoutSilentChmod() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: s.file.path)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .migrated && result.recoveryReason == nil)
        let envelope = try #require(result.envelope)
        #expect(envelope.schemaVersion == 2 && envelope.revision == 0)
        #expect(envelope.config.gitRoots == ["/fixture/Developer", "/fixture/Other"])
        #expect(try mode(s.root) == 0o755 && mode(s.file) == 0o644)
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
    }

    @Test func ownedLegacy755DirectoryAnd644FileSaveOwnerOnlyCopies() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: s.file.path)
        let store = SettingsStore(url: s.file); let result = await store.load()
        #expect(result.disposition == .migrated && result.envelope != nil)
        #expect(try mode(s.root) == 0o755 && mode(s.file) == 0o644)
        #expect(try Data(contentsOf: s.file) == bytes)
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        #expect(try mode(s.root) == 0o755)
        #expect(try mode(s.file) == 0o600 && mode(s.backup) == 0o600)
        #expect(try Data(contentsOf: s.backup) == bytes)
    }

    @Test(arguments: [true, false])
    func groupWritableLegacyLocationIsReadOnly(directory: Bool) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        let changed = directory ? s.root : s.file
        let permissions = directory ? 0o770 : 0o660
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: changed.path)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(try mode(changed) == permissions)
        #expect(try Data(contentsOf: s.file) == bytes)
    }

    @Test(arguments: ["config.lock", "config.backup.json"])
    func unsafeExistingAuxiliaryFilesAreNotRepaired(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        let auxiliary = s.root.appendingPathComponent(name)
        let sentinel = Data("preserve unsafe auxiliary".utf8)
        try sentinel.write(to: auxiliary)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: auxiliary.path)
        let store = SettingsStore(url: s.file)
        #expect(await store.load().disposition == .recoveryReadOnly)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        }
        #expect(try Data(contentsOf: auxiliary) == sentinel && mode(auxiliary) == 0o666)
        #expect(try Data(contentsOf: s.file) == bytes)
    }

    @Test func replacingBackupAfterPreviewCannotRollbackDifferentValue() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let store = SettingsStore(url: s.file); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        let preview = try await store.previewRollback()
        let current = try Data(contentsOf: s.file)
        let replacement = try fixture("v1-memory")
        try replacement.write(to: s.backup, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: s.backup.path)
        await expectStoreError(.changedExternally) {
            _ = try await store.rollback(expectedRevision: 1, preview: preview)
        }
        #expect(try Data(contentsOf: s.file) == current)
        #expect(try Data(contentsOf: s.backup) == replacement)
    }

    @Test func recoveryCannotUsePreviouslyIssuedRollbackPreview() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let store = SettingsStore(url: s.file); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        let preview = try await store.previewRollback()
        let future = try schema2(extra: ["registryPreferences": ["unknown.key": true]])
        try s.seed(future)
        #expect(await store.load().disposition == .recoveryReadOnly)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.rollback(expectedRevision: 1, preview: preview)
        }
        #expect(try Data(contentsOf: s.file) == future)
    }
}
```

A.1 GREEN is exactly this named subset (parameterized tests include every supplied argument):

- `missingOnlyCreatesInMemoryDefaults`
- `bothHistoricalShapes`
- `knownSchema2LoadsNonzeroRevisionWithoutWriting`
- `ownedLegacy755DirectoryAnd644FileMigrateWithoutSilentChmod`
- `recoveryPreservesBytes`
- `existingInvalidIsNeverNewDefaults`
- `symlinkDoesNotAuthorizeReadingOrReplacingDestination`
- `unknownSchema2ExtensionAndNestedMismatchAreReadOnly`
- `depthListAndStringBoundsRejectWithoutRewrite`
- `groupWritableLegacyLocationIsReadOnly`
- `unsafeExistingAuxiliaryFilesAreNotRepaired`
- `oldReportsHaveUnavailableMemoryNotMeasuredZero`

These tests perform no successful SettingsStore write; read-only recovery tests may call update/preview solely to assert `.readOnlyRecovery`. Keep those recovery denials implemented in A.1 and have otherwise-valid persistence requests fail closed with `.unavailable` until A.2. A.2 owns `bothHistoricalShapesPersistRoundTrip`, `ownedLegacy755DirectoryAnd644FileSaveOwnerOnlyCopies`, and all successful save/rollback, overflow, conflict and actual-write-failure tests. Never claim the whole SettingsMigrationTests suite GREEN at A.1. Add the complete tests before their owning unit, not after implementation. Foreign-owner rejection requires a safely pre-provisioned fixture under another UID; if unavailable record that gap, never run privileged chown to fabricate it.

- [ ] Add exact fixtures/tests first, run focused command below; record absent production API as compile RED, then behavioral failures as APIs land. Do not present a compile-only failure as proof of persistence semantics.
- [ ] Implement SettingsStore's bounded decoder and recovery result only. Leave legacy ConfigStore and its existing fallback/roundtrip tests unchanged through A.1/A.2; new recovery assertions exercise SettingsStore. Removal of the fallback loader and migration of its tests/callers happen together at A.3, never piecemeal during this unit.
- [ ] Implement and test core historical memory-availability decoding; retain T02 disposition/availability compatibility. Production results consumers remain unchanged in this non-deployable A.1 checkpoint. A.3 must explicitly include `Tidy/Clean/CleanResultsView.swift` and any other actual report consumers, with reviewed presentation RED for historical unavailable memory, explicitly measured zero, mixed unavailable/known observations and existing T02 no-op/denial rendering before app integration may enter.
- [ ] Run focused RED/GREEN, review preservation diff and fixture membership. No auto-save occurs merely because decoding succeeded.

### A.1/A.2 reader addendum — FIFO entry fixture approved

The original A.1 JSON/mode entry batch and this additional phase-specific FIFO fixture are independently approved for implementation entry. Review corrections bind the lock probe to preserved device/inode identities and distinguish new-API compile RED from genuine behavioral regression evidence. T02 contains `FIFOAdmissionWatchdog` and its real FIFO regression in `TidyCore/Tests/TidyCoreTests/ConfirmedExecutionTests.swift` (helper at line70 at this inspection). This card adapts that tested mechanism; it does not claim the settings tests below have run. Keep the helper private in `SettingsMigrationTests.swift` under the distinct name below. T05 owns only that new settings test code; do not move/edit T02's helper or create a public production testing API. Sharing a test-support source later would need separately assigned file ownership and both callers' verification.

Phase allocation:

- A.1: `config.json` FIFO in an otherwise uninitialized legacy fixture; real SettingsStore.load must return recoveryReadOnly/no envelope promptly, preserve the FIFO and original bytes, and create no lock/bootstrap/backup/staging files. Follow-up update is denied readOnlyRecovery without bootstrap.
- A.2F: initialized `config.json`, `config.backup.json`, `config.lock`, `config.store.json`; plus `config.pending.json` and recognized candidate/backup staging remnants. These must be rejected without blocking, publication, repair or implicit rollback. Existing valid metadata/config/backup bytes and filenames remain exact. Pending/staging presence can be rejected without reading their contents; do not require an unnecessary FIFO open merely to exercise the watchdog. A.2 owns these tests because their setup performs a genuine successful SettingsStore transaction.
- All actual regular-file readers open using `O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC`, then fstat the opened FD and reject nonregular/wrong-owner/unsafe-mode files **before any read**. The stable lock uses equivalent no-follow/nonblocking safety with O_RDWR and regular-FD validation before flock. A pathname lstat-only check is not sufficient against replacement. Source review must establish this descriptor-validation order before running FIFO RED: the watchdog bounds the known blocking-open defect, not an invented implementation that reads an unvalidated FIFO indefinitely.

Append the complete following code to `SettingsMigrationTests.swift` (including `import Dispatch` once), staged by phase: A.1 adds the private helpers and `extension SettingsMigrationTests`; A.2F adds the final `extension SettingsPublicationTests` when that suite's declaration is added. Do not compile the A.2 extension against an undeclared suite during A.1. It uses the existing private SettingsScratch/fixture helpers. Every production call made while a FIFO is present is wrapped; both success and thrown-error outcomes are captured before synchronous drain. No throwing assertion or cleanup occurs between starting the watchdog and drain. A rescue writer is opened only after5seconds; any rescue makes RED fail. The rescue thread keeps its writer and guard-reader FDs alive until the production call has actually returned, then closes them and exits before cleanup. Rescue failure terminates only the owned test process while retaining scratch; no cancellation race or active-fixture deletion substitutes for drainage.

```swift
import Dispatch

private final class SettingsFIFOReadWatchdog {
    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        func markFired() { lock.lock(); fired = true; lock.unlock() }
        func didFire() -> Bool { lock.lock(); defer { lock.unlock() }; return fired }
    }
    private let completed = DispatchSemaphore(value: 0)
    private let drained = DispatchSemaphore(value: 0)
    private let outcome = Outcome()
    private let worker: Thread

    init(fifo: URL) throws {
        let reader = open(fifo.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard reader >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        // Prove rescue is possible, then leave NO writer alive during the call.
        let probe = open(fifo.path, O_WRONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard probe >= 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(reader); throw error
        }
        close(probe)
        let completed = self.completed, drained = self.drained, outcome = self.outcome
        let path = fifo.path
        worker = Thread {
            var writer: Int32 = -1
            if completed.wait(timeout: .now() + .seconds(5)) == .timedOut {
                outcome.markFired()
                writer = open(path, O_WRONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                guard writer >= 0 else {
                    fatalError("Settings FIFO rescue failed (errno \(errno)); retaining scratch at \(path) because settings I/O may still be active")
                }
                completed.wait()
            }
            if writer >= 0 { close(writer) }
            close(reader) // ownership transferred after successful initialization
            drained.signal()
        }
        worker.start()
    }
    func finishAndDrain() -> Bool {
        completed.signal()
        drained.wait()
        while !worker.isFinished { Thread.sleep(forTimeInterval: 0.001) }
        return outcome.didFire()
    }
}

private func withSettingsFIFORescue<Value>(
    _ fifo: URL, operation: () async throws -> Value
) async throws -> Result<Value, Error> {
    let watchdog = try SettingsFIFOReadWatchdog(fifo: fifo)
    let result: Result<Value, Error>
    do { result = .success(try await operation()) }
    catch { result = .failure(error) }
    let fired = watchdog.finishAndDrain() // before any assertion can throw/return
    #expect(!fired, "Settings I/O needed the FIFO rescue writer after five seconds")
    return result
}

private func expectFIFOStoreError<Value>(_ expected: SettingsStoreError,
                                         result: Result<Value, Error>) {
    switch result {
    case .success: Issue.record("Expected settings error \(expected)")
    case .failure(let error):
        guard let error = error as? SettingsStoreError else {
            Issue.record("Wrong settings error: \(error)"); return
        }
        #expect(error == expected)
    }
}

private struct SettingsFIFOImage {
    let fifo: URL
    let before: stat
    let names: [String]
    let regularBytes: [String: Data]
    let regularModes: [String: mode_t]
    let regularDevices: [String: dev_t]
    let regularInodes: [String: ino_t]
    let directoryMode: mode_t

    init(scratch: SettingsScratch, name: String) throws {
        fifo = scratch.root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: fifo.path) {
            // Only an exact existing disposable regular fixture is moved aside.
            let retained = scratch.root.appendingPathComponent("retained-original-" + name)
            try FileManager.default.moveItem(at: fifo, to: retained)
        }
        try #require(mkfifo(fifo.path, 0o600) == 0)
        var info = stat(), directory = stat()
        try #require(lstat(fifo.path, &info) == 0)
        try #require(info.st_mode & S_IFMT == S_IFIFO)
        try #require(info.st_mode & 0o777 == 0o600)
        try #require(lstat(scratch.root.path, &directory) == 0)
        before = info; directoryMode = directory.st_mode
        names = try FileManager.default.contentsOfDirectory(atPath: scratch.root.path).sorted()
        var bytes: [String: Data] = [:], modes: [String: mode_t] = [:]
        var devices: [String: dev_t] = [:], inodes: [String: ino_t] = [:]
        for other in names where other != name {
            let url = scratch.root.appendingPathComponent(other)
            var regular = stat()
            try #require(lstat(url.path, &regular) == 0 && regular.st_mode & S_IFMT == S_IFREG)
            bytes[other] = try Data(contentsOf: url)
            modes[other] = regular.st_mode
            devices[other] = regular.st_dev
            inodes[other] = regular.st_ino
        }
        regularBytes = bytes; regularModes = modes
        regularDevices = devices; regularInodes = inodes
    }
    func expectPreserved(in scratch: SettingsScratch) throws {
        var after = stat(), directory = stat()
        try #require(lstat(fifo.path, &after) == 0)
        #expect(after.st_mode & S_IFMT == S_IFIFO)
        #expect(after.st_dev == before.st_dev && after.st_ino == before.st_ino)
        #expect(after.st_mode == before.st_mode)
        try #require(lstat(scratch.root.path, &directory) == 0)
        #expect(directory.st_mode == directoryMode)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.root.path).sorted() == names)
        for (name, bytes) in regularBytes {
            let url = scratch.root.appendingPathComponent(name)
            var info = stat()
            try #require(lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG)
            #expect(try Data(contentsOf: url) == bytes)
            #expect(info.st_mode == regularModes[name])
            #expect(info.st_dev == regularDevices[name] && info.st_ino == regularInodes[name])
        }
    }
}

extension SettingsMigrationTests {
    @Test func fifoConfigReadRejectsPromptlyWithoutBootstrap() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture("v1-original"); try s.seed(original)
        let image = try SettingsFIFOImage(scratch: s, name: "config.json")
        let store = SettingsStore(url: s.file)
        let load = try await withSettingsFIFORescue(image.fifo) { await store.load() }
        let result = try load.get() // watchdog already drained
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        let edit = try await withSettingsFIFORescue(image.fifo) {
            try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        expectFIFOStoreError(.readOnlyRecovery, result: edit)
        try image.expectPreserved(in: s)
        #expect(try Data(contentsOf: s.root.appendingPathComponent("retained-original-config.json")) == original)
        #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.lock").path))
        #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.store.json").path))
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        withExtendedLifetime(store) {}
    }
}

extension SettingsPublicationTests {
    @Test(arguments: ["config.json", "config.backup.json", "config.lock", "config.store.json",
                      "config.pending.json", ".config-candidate-11111111-1111-1111-1111-111111111111",
                      ".config-backup-11111111-1111-1111-1111-111111111111"])
    func fifoInitializedSettingsAndArtifactsArePreserved(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let writer = SettingsStore(url: s.file); _ = await writer.load()
        _ = try await writer.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let image = try SettingsFIFOImage(scratch: s, name: name)
        let store = SettingsStore(url: s.file)
        let loaded = try await withSettingsFIFORescue(image.fifo) { await store.load() }
        let result = try loaded.get()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        let edit = try await withSettingsFIFORescue(image.fifo) {
            try await store.update(expectedRevision: 1, change: .transcriptAgeDays(90))
        }
        expectFIFOStoreError(.readOnlyRecovery, result: edit)
        let preview = try await withSettingsFIFORescue(image.fifo) { try await store.previewRollback() }
        expectFIFOStoreError(.readOnlyRecovery, result: preview)
        try image.expectPreserved(in: s)
        if name != "config.lock" {
            let fd = open(s.root.appendingPathComponent("config.lock").path,
                          O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            try #require(fd >= 0)
            defer { close(fd) }
            let locked = flock(fd, LOCK_EX | LOCK_NB)
            #expect(locked == 0, "Read failure must release any transient settings lock")
            if locked == 0 { _ = flock(fd, LOCK_UN) }
        }
        // Keep objects alive: deinit must not provide the lock-release evidence.
        withExtendedLifetime((store, writer)) {}
    }
}
```

For A.1, add `fifoConfigReadRejectsPromptlyWithoutBootstrap` to its focused GREEN subset **after this addendum is approved**. A.2F's existing combined suite filter also selects the initialized-files test once its source is added. SettingsStore does not yet exist: record natural missing-API RED separately from any behavioral failures as implementation arrives. A correct nonblocking reader may pass the FIFO test on its first behavioral run; do not deliberately introduce a blocking open to manufacture RED. T02's genuine pre-existing FIFO defect is not settings regression evidence. GREEN requires no rescue, unavailable/recovery presentation, byte/mode/inode preservation and no initialization/publication. The regular-file identity assertions run before the lock probe, so replacing config.lock with identical bytes cannot supply false lock-release evidence. These are specified acceptance results, not results obtained in this documentation turn.

Controller-scheduled focused commands after the corresponding phase's review/source entry (not executed while preparing this card):

```sh
cd /private/tmp/tidy-headroom.wUbV9h/TidyCore
swift test --filter fifoConfigReadRejectsPromptlyWithoutBootstrap --jobs 2
```

```sh
cd /private/tmp/tidy-headroom.wUbV9h/TidyCore
swift test --filter fifoInitializedSettingsAndArtifactsArePreserved --jobs 2
```

The first must select the one A.1 FIFO test; the second must execute all seven A.2 arguments. Zero selected tests is not acceptance.

## T05A.2 — Persistence transaction and rollback boundary

The actor serializes a complete transaction without suspension between expected-revision check and publication. Disk work never runs on MainActor. New settings directories are0700; new config/backup/temp/stable `config.lock` files are0600. Verified owned, local, no-follow legacy directory0755/file0644 with no group/other write are accepted unchanged for read-only in-memory migration. An explicit valid save publishes config/backup0600 and leaves the existing directory0755 unchanged. Group/other writable, foreign-owned, symlink or unsafe existing lock/backup fails closed; never chmod or overwrite it into acceptability. Use anchored descriptors and an advisory settings lock across disk identity/bytes recheck and write. The stable lock is not the mutation ledger lock, never replaced/unlinked. Independently constructed actors/processes cannot overwrite one another: under the lock recheck the exact loaded original bytes plus file identity; mismatch returns changedExternally and requires a new read/review. The app itself creates only one settings actor.

For known loaded bytes: validate/encode bounded candidate first; create exclusive same-directory temp files owner-only; write/synchronize candidate; publish a synchronized exact-old-byte backup atomically; only then rename candidate over config and synchronize directory. Check every error and clean only this operation's exact temporary names. Last-known-good config remains intact for all failures before config rename; the EACCES test proves a real pre-publication filesystem failure, potentially at initial stable-lock creation because load creates no lock. It does not establish candidate-temp/backup/rename failure coverage without stage-specific evidence. **After** a successful rename but failed directory fsync, return `.durabilityUncertain`, latch this store recoveryReadOnly with no usable envelope, and block policy commit. Do not assert old bytes necessarily survived or retry automatically. Repeated load/update/preview/rollback on that store remain latched; a fresh process needs a separately reviewed recovery procedure, not automatic enabled startup based merely on readable new bytes.

**Entry state:** A.2F's protocol, fault coverage, fixture-lifetime design and additional FIFO fixture have been independently approved, conditional on T04's sole shared-I/O primitive implementation and A.1 prerequisites. No settings source/tests have been implemented or run by preparing this card. A.2P process/crash acceptance and A.3/B.1/B.2 remain separately gated. Approval of the foundation design grants no alternate settings/policy authority, production launch flag or cleanup permission.

Rollback is an explicit user action available only from a valid writable loaded state after `previewRollback()` returns the store-owned opaque preview. That preview binds store identity, current revision, backup file identity and exact-byte digest plus decoded value. On confirmation, rollback rechecks all of these under the same stable settings lock; a replaced backup cannot silently change what was previewed. It validates backup schema/ownership, writes its value as a **new** revision through the same transaction/bridge, and never restores consent or old revision numbers. RecoveryReadOnly cannot issue a preview and rejects any previously issued preview; there is no reset/overwrite authority. Offer read-only export/reveal and explanation; repairing/replacing corrupt/future state requires separately specified user authority. No default reset button, timestamp-based overwrite or treating backup existence as permission.

T02's throwing ConfigStore.save, ConfigStore.load, schema1 default writer and existing compatibility tests remain untouched throughout A.1 **and A.2**; switch app use atomically in A.3. Only at that cutover remove the unsafe fallback API and migrate its old tests plus every app/T02 caller to the reviewed recoverable contract; make any retained raw I/O primitives internal to SettingsStore. Never have both legacy save and actor write paths active for the same production URL. Test-only scratch callers must not become a public bypass. T02 integration review decides exact compatibility removal with its implementer; do not silently weaken its successful-save/failed-save expectations or deploy the intermediate migration build.

### A.2 proposed durable publication protocol

**Delivery split:** A.2F is the publication **foundation**: same-process independent stores/descriptors, exact transaction/bootstrap syscall-fault tests and fresh-store reopen checks below. A.2P is a separately gated fulfillment unit for actual two-process bootstrap/lock contention and abrupt-process crash-prefix/relaunch tests. Before A.2P source/test entry, provide its complete helper executable and RED tests for independent process lifetimes; none are supplied or claimed here. Completing A.2F does not complete A.2, T05, cross-process serialization or crash acceptance. This split schedules the remaining requirements; it does not remove them. Both units still require the shared T04 I/O primitive ownership review.

This is a settings transaction, **not** an unfinished-effect ledger. It never opens, repairs, clears or grants authority through T02's mutation.lock/bootstrap/unfinished-effects files. `config.lock` serializes settings I/O only; the ExecutionCoordinator and its policy tickets remain the only execution authority. No successful write/rollback can clear effect uncertainty. A.3 still commits a policy ticket only after the settings update actually returns success.

Reuse the exact internal `JournalPOSIXIO`/`DarwinJournalIO` declarations proposed by `T04-journal-and-recovery.md` (write, syncFile, descriptor-relative replace, syncDirectory). T04 owns the single shared primitive's source implementation; T05 consumes it after that implementation/review is available. Do not create a second POSIX persistence algorithm, duplicate definitions, or inject an alternative complete store. If T04's primitive is not landed, that dependency remains an A.2F source-entry gate, not permission for T05 to create a competing copy. Settings format/state remain in `Policy/SettingsStore.swift` and new `Policy/SettingsPublication.swift`, not RunJournal. Add one internal initializer `SettingsStore.init(url: URL, io: any JournalPOSIXIO)`; public init(url:) selects DarwinJournalIO. File opens, permissions, identity checks, locks, fixed filenames and final unlink stay production code, outside the injected seam.

**Additional reader regression gate from T02 review:** opening a pathname with blocking O_RDONLY before fstat can hang on a substituted FIFO. Settings config, metadata and staging readers must use `O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC`, then validate the opened FD is an owned regular file before bounded reads; a pathname precheck does not close the replacement race. Reject FIFO/device/socket and other nonregular FDs, do not fall back to blocking open. The complete phase-specific FIFO addendum above is entry-approved but still awaits actual settings implementation/testing. Neither approved JSON fixtures nor T02's passing journal test constitute settings-reader evidence.

A.2 adds `SettingsStoreError.finalizationBlocked` to the existing enum. It means the candidate and backup were successfully synchronized, but removal of a transaction artifact failed; it is **not** an unproven config publication. `.durabilityUncertain` is reserved for an error at/after an attempted config rename and before successful config-directory synchronization. Earlier errors are `.writeFailed`; all failures after creating a transaction marker latch recoveryReadOnly. All three errors return no new envelope/revision and never commit policy. `load()` must not clear a latch on the same actor just because bytes parse. Relaunch rules below rely on a preexisting prepared marker rather than on successfully writing a new error flag.

For precise failure evidence, add the internal observation-only `SettingsPublicationFailure: Equatable, Sendable { let stage: String; let errno: Int32 }` and actor method `lastPublicationFailure() -> SettingsPublicationFailure?`. Capture the actual caught POSIX errno at the production boundary before translating to SettingsStoreError; never synthesize errno from the selected test fault. Stable stage strings are the exact `failureStage` values in the test enum below. This is not a recovery setter, policy override or injected callback. In particular `finalize.marker.unlink/EACCES` must originate from the actual failing production unlinkat; the test wrapper cannot create that observation. Successful new transactions clear previous diagnostic state only after validation/admission, never clear recovery latches.

Fixed files, relative to the already-validated anchored settings directory:

- `config.lock`: stable owner-only inode, advisory exclusive flock; never replaced/unlinked. After exclusive creation its bounded JSON is `{"schema":1,"storeID":"<UUID>"}`.
- `config.store.json`: owner-only bootstrap identity with the same bounded JSON; at most1KiB. Immutable after first bootstrap. Not an execution/consent ledger.
- `config.pending.json`: exclusively created owner-only transaction marker, at most4KiB. Schema1 fields: `storeID`, `transactionID`, `oldRevision`, `newRevision`, `oldConfigSHA256` (null only for genuine first save), `candidateSHA256`, and exact generated `candidateName`/`backupName`. Both temporary basenames are fixed prefixes plus the same UUID, never arbitrary paths from JSON.
- `.config-candidate-<transactionID>` and `.config-backup-<transactionID>`: exclusive0600 staging files, each at most1MiB; the backup staging file contains the **exact old config bytes**, not re-encoded JSON. For first save without an old file, no backup staging/publication occurs and oldConfigSHA256 is null. No zero-byte fake backup.
- `config.json` and `config.backup.json`: candidate and exact immediately preceding config, published by anchored renameat. An older backup is allowed to be replaced only by the transaction's already-synchronized exact-old bytes. An issued rollback preview cannot survive this identity/digest change; pending recovery blocks rollback outright.

SHA-256 uses the system CryptoKit implementation; it detects accidental byte changes, not malicious owner rewriting. The marker is not caller authority: every field is validated against the store's captured identity and fixed filename grammar. Read/write budgets include all metadata/staging files and at most one transaction; no unbounded transaction history or new generic framework.

Before **any** bootstrap write, directory creation, lock creation or auxiliary-file creation: validate the entire SettingsChange against the loaded value, check the caller's expected revision against the loaded revision, perform checked revision arithmetic, encode the complete bounded candidate, and validate all configured bounds/types. A rejected edit against valid legacy bytes must leave exactly those bytes/modes and no new metadata; a fresh store must still return migrated and accept a subsequent valid edit. These prechecks are not disk authority: under the actual stable lock, recheck current config/backup/parent identity, exact bytes, revision and rollback preview before publishing. Validation cannot be deferred until after writing bootstrap identity.

Bootstrap, on the first **explicit, already validated update only**, never on load:

1. With no lock/store metadata/pending/staging remnants, a known valid legacy or schema2 config (or genuinely absent config and absent backup) may bootstrap. Exclusively create config.lock, acquire its flock, write/check/synchronize its identity, then exclusively create/write/synchronize config.store.json and synchronize the directory. Never use an existing lock as proof this process may initialize missing metadata.
2. A competitor observing the held lock returns `.unavailable` without touching files; this transient contention does not latch recovery on that actor. If two validated writers race to bootstrap, only the O_EXCL winner may initialize. The loser opens the existing no-follow lock and attempts nonblocking flock: contention returns unavailable; after acquisition it requires complete matching metadata and rechecks disk/config revision. It may not finish another writer's bootstrap. A surviving lock without valid matching config.store.json, missing lock with metadata present, malformed/unknown schema, storeID mismatch, unsafe owner/mode or symlink is recoveryReadOnly. No repair, chmod, reset or fallback directory. Once bootstrap file creation has begun, any subsequent bootstrap I/O/recheck failure conservatively latches that actor; surviving partial metadata on reopen blocks. A failed final bootstrap-directory sync over an already-schema2 file can leave readable complete metadata with unchanged config; that fresh read is not proof the failed bootstrap succeeded or permission to overwrite without a new explicit edit and locked revalidation. No config/backup publication occurs in bootstrap.
3. With both valid identities present, reopen and flock the **same** no-follow stable lock; verify identity again, then recheck exact loaded config bytes/file identity, expected storage revision and any rollback preview under that lock. A load does not create missing files. A.1 standalone known-schema2-without-metadata read remains valid; A.2 adds metadata only on its first explicit write.

Under the lock, after all validation/encoding succeeds, transaction order is fixed:

| Boundary | Required completed work before proceeding | Failure/current process | Reopen without fault injection |
|---|---|---|---|
| P0 | Recheck loaded config/backup identity, expected revision, limits; no mutation yet | validation error; no publication | unchanged readable config |
| P1 | O_EXCL pending marker; complete checked writes; file sync; directory sync | writeFailed; retain marker, even partial; no config/backup change | any marker/remnant blocks read-write mode |
| P2 | Create/write/sync candidate and exact-old backup staging files | writeFailed; retain artifacts; config and prior backup unchanged | prepared marker blocks |
| P3 | rename backup staging onto config.backup.json; directory sync | writeFailed; backup may be old or newly published exact-old; config unchanged | prepared marker blocks; no auto-rollback |
| P4 | rename candidate onto config.json; directory sync | durabilityUncertain; config may be old or new; exact-old backup remains | prepared marker blocks even if new envelope is valid |
| P5 | After P4 sync success, remove only any known leftover staging names; finally unlink exact pending marker inode | finalizationBlocked if an unlink fails; config+backup already proven synchronized; retain marker when removal fails | marker present => recovery; absent => normal loaded state after P4 |
| Return | Final marker unlink returned success; no further required I/O | return new envelope/revision exactly once | valid matching metadata, no marker/remnants => loaded |

Do **not** require a final directory sync after deleting the marker. Settings and backup were synchronized before deletion; durable absence of the marker is unnecessary for safety. A crash may resurrect it, producing conservative read-only recovery. Adding a required sync after marker removal would create a new ambiguous last-error boundary with no remaining durable blocker. There is no “persist failure flag after failure” fallback. P5 uses the actual checked local unlinkat return; the shared fault seam cannot fake a successful unlink. If underlying local-filesystem semantics cannot establish that removal failed/preserved the named marker, report that limitation rather than claiming an impossible external failure-proof record.

At P5 a staging basename already consumed by a successful rename is expected absent; do not attempt an unconditional unlink and misclassify ENOENT as a failed transaction. Remove only this transaction's still-present, identity-verified staging artifacts, never globbed names or foreign replacements. The fixed pending marker is unlinked last after verifying its held identity still matches the name. If a staging artifact/marker was replaced externally, fail closed without deleting the replacement.

Load/relaunch rules are explicit:

- Any pending marker, including zero bytes, unknown format or mismatching hashes, means recoveryReadOnly/no envelope; do not auto-finalize even if candidate, backup and manifest agree. Any recognized staging remnant without its marker also blocks; do not delete it to manufacture a clean launch.
- With matching initialized metadata and no marker/remnants, require a valid schema2 config. A missing config after settings bootstrap is recovery, not defaults. Before bootstrap, a missing config means newDefaults **only when** no backup/lock/store/pending/staging evidence exists. Missing plus retained backup is recovery.
- Failed P4 leaves the pre-P4 durable marker in place before the error occurs. A newly constructed store without fault injection therefore stays read-only; reopening never retries, copies backup or clears the marker.
- Failed P5 differs: config durability is already established, but marker removal failure still blocks if the marker remains. A known successful final unlink allows ordinary load; its non-durable absence may reverse after a power loss only into the safer blocked state.
- Rollback uses exactly P0–Return, with the store-issued preview rechecked under the lock and a newly encoded revision. Its backup is the exact config that existed immediately before rollback. A failed rollback never restores the old revision or silently retries. Pending recovery disables both preview issuance and previously issued previews.
- No app import/reset/history operation may remove these metadata/marker files. Recovery UI remains read-only export/reveal with explanation; repair/abandon/replacement requires a separately reviewed explicit user action. This card adds no such authority.

These are internal implementation choices within the approved preservation contract: one lock/identity, bounded prepared marker, checked publication, conservative reopen and fault seam. They require adversarial technical review, not a new user feature decision. New user decisions would include permission to discard/reinitialize damaged settings, automatic rollback/finalization, an external tamperproof anchor, or widened import authority; none is inferred. Same-owner modification, wholesale directory removal/rollback and malicious valid-snapshot restoration cannot be reliably detected by co-located metadata/hashes. No physical power-loss or hostile-filesystem proof is claimed.

### A.2 complete publication-fault RED

Append the following complete code to `SettingsMigrationTests.swift` after its existing helpers; it uses the same private SettingsScratch/fixture/schema primitives. No fixture executor, policy resolver or fake save-success closure is injected. Run the new `SettingsPublicationTests` suite plus all A.2 migration tests only after entry review.

Faults below occur over actual production-created scratch files and real write/rename calls. For a deterministic failed sync, the wrapper invokes the actual Darwin synchronization implementation with FD -1 at the selected production boundary, yielding EBADF. This is **invalid-descriptor syscall fault injection**, not a claim that the scratch filesystem suffered real media EIO or power loss. Rename-before failure invokes actual renameat with a guaranteed absent generated temporary name; rename-after performs real rename before a real failing sync syscall. The post-config-rename directory-sync test asserts both that config bytes changed and that the selected syscall failed. P5 uses a real directory permission change to make the production unlinkat fail with EACCES; ordinary non-root user required.

```swift
private enum SettingsIOFault: String, CaseIterable, Sendable {
    case bootstrapLockWrite, bootstrapLockSync, bootstrapStoreWrite, bootstrapStoreSync, bootstrapDirectorySync
    case markerSync, preparedDirectorySync, candidateShortWrite, candidateSync, backupSync
    case backupRenameBefore, backupRenameAfter, backupDirectorySync
    case configRenameBefore, configRenameAfter, configDirectorySync, markerRemoval
    static let bootstrap: [Self] = [.bootstrapLockWrite, .bootstrapLockSync,
        .bootstrapStoreWrite, .bootstrapStoreSync, .bootstrapDirectorySync]
    static let publication: [Self] = [.markerSync, .preparedDirectorySync, .candidateShortWrite,
        .candidateSync, .backupSync, .backupRenameBefore, .backupRenameAfter, .backupDirectorySync,
        .configRenameBefore, .configRenameAfter, .configDirectorySync, .markerRemoval]
    var failureStage: String {
        switch self {
        case .bootstrapLockWrite: "bootstrap.lock.write"
        case .bootstrapLockSync: "bootstrap.lock.syncFile"
        case .bootstrapStoreWrite: "bootstrap.store.write"
        case .bootstrapStoreSync: "bootstrap.store.syncFile"
        case .bootstrapDirectorySync: "bootstrap.syncDirectory"
        case .markerSync: "marker.syncFile"
        case .preparedDirectorySync: "prepared.syncDirectory"
        case .candidateShortWrite: "candidate.write"
        case .candidateSync: "candidate.syncFile"
        case .backupSync: "backup.syncFile"
        case .backupRenameBefore, .backupRenameAfter: "backup.replace"
        case .backupDirectorySync: "backup.syncDirectory"
        case .configRenameBefore, .configRenameAfter: "config.replace"
        case .configDirectorySync: "config.syncDirectory"
        case .markerRemoval: "finalize.marker.unlink"
        }
    }
    var expectedErrno: Int32 {
        switch self {
        case .backupRenameBefore, .configRenameBefore: ENOENT
        case .markerRemoval: EACCES
        default: EBADF
        }
    }
}
private enum FaultHarnessError: Error { case unexpectedSyscallSuccess }

private final class SettingsFaultIO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let lock = NSLock()
    private var fault: SettingsIOFault?
    private var publication = "prepared"
    private var failNextCandidateWrite = false
    private var events: [String] = []

    func arm(_ value: SettingsIOFault) {
        lock.lock(); defer { lock.unlock() }
        fault = value; publication = "prepared"; events = []; failNextCandidateWrite = false
    }
    func trace() -> [String] { lock.lock(); defer { lock.unlock() }; return events }
    private func record(_ value: String) { lock.lock(); events.append(value); lock.unlock() }
    private func consume(_ value: SettingsIOFault) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard fault == value else { return false }
        fault = nil; events.append("fault.consumed.\(value.rawValue)"); return true
    }
    private func name(_ fd: Int32) throws -> String {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &path) == 0 else { throw POSIXError(.EBADF) }
        return URL(fileURLWithPath: String(cString: path)).lastPathComponent
    }
    private func failingSyscall<T>(_ fault: SettingsIOFault, _ body: () throws -> T) throws -> T {
        do { _ = try body(); throw FaultHarnessError.unexpectedSyscallSuccess }
        catch let error as POSIXError {
            record("fault.errno.\(fault.rawValue).\(error.code.rawValue)")
            throw error
        }
    }
    private func fileStage(_ file: String) -> String {
        if file == "config.lock" { return "bootstrap.lock" }
        if file == "config.store.json" { return "bootstrap.store" }
        if file == "config.pending.json" { return "marker" }
        if file.hasPrefix(".config-candidate-") { return "candidate" }
        if file.hasPrefix(".config-backup-") { return "backup" }
        return "other"
    }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        let stage = fileStage(try name(fd)), candidate = stage == "candidate"
        record(stage + ".write.begin")
        if stage == "bootstrap.lock" && consume(.bootstrapLockWrite) {
            return try failingSyscall(.bootstrapLockWrite) { try base.write(fd: -1, bytes: bytes, offset: offset) }
        }
        if stage == "bootstrap.store" && consume(.bootstrapStoreWrite) {
            return try failingSyscall(.bootstrapStoreWrite) { try base.write(fd: -1, bytes: bytes, offset: offset) }
        }
        lock.lock()
        let fail = candidate && failNextCandidateWrite
        if fail { failNextCandidateWrite = false }
        lock.unlock()
        if fail {
            return try failingSyscall(.candidateShortWrite) { try base.write(fd: -1, bytes: bytes, offset: offset) }
        }
        if candidate && consume(.candidateShortWrite) {
            lock.lock(); failNextCandidateWrite = true; lock.unlock()
            let written = try base.write(fd: fd, bytes: Data(bytes.dropFirst(offset).prefix(1)), offset: 0)
            record("candidate.write.oneByte.\(written)")
            return written
        }
        let written = try base.write(fd: fd, bytes: bytes, offset: offset)
        record(stage + ".write.succeeded")
        return written
    }
    func syncFile(fd: Int32) throws {
        let stage = fileStage(try name(fd))
        record(stage + ".syncFile.begin")
        let wanted: SettingsIOFault?
        switch stage {
        case "bootstrap.lock": wanted = .bootstrapLockSync
        case "bootstrap.store": wanted = .bootstrapStoreSync
        case "marker": wanted = .markerSync
        case "candidate": wanted = .candidateSync
        case "backup": wanted = .backupSync
        default: wanted = nil
        }
        if let wanted, consume(wanted) {
            return try failingSyscall(wanted) { try base.syncFile(fd: -1) }
        }
        try base.syncFile(fd: fd)
        record(stage + ".syncFile.succeeded")
    }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        let stage: String?
        if destination == "config.backup.json" { stage = "backup" }
        else if destination == "config.json" { stage = "config" }
        else { stage = nil }
        if let stage {
            record(stage + ".replace.begin")
            lock.lock(); publication = stage; lock.unlock()
            let before: SettingsIOFault = stage == "backup" ? .backupRenameBefore : .configRenameBefore
            if consume(before) {
                return try failingSyscall(before) {
                    try base.replace(directoryFD: directoryFD,
                        temporary: ".config-guaranteed-absent-\(UUID().uuidString)", destination: destination)
                }
            }
        }
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
        if let stage {
            record(stage + ".renamed")
            let after: SettingsIOFault = stage == "backup" ? .backupRenameAfter : .configRenameAfter
            if consume(after) { return try failingSyscall(after) { try base.syncDirectory(fd: -1) } }
        }
    }
    func syncDirectory(fd: Int32) throws {
        lock.lock(); let published = publication; lock.unlock()
        var marker = stat()
        let pendingExists = fstatat(fd, "config.pending.json", &marker, AT_SYMLINK_NOFOLLOW) == 0
        let stage = pendingExists ? published : "bootstrap"
        let wanted: SettingsIOFault = stage == "config" ? .configDirectorySync :
            (stage == "backup" ? .backupDirectorySync :
                (stage == "bootstrap" ? .bootstrapDirectorySync : .preparedDirectorySync))
        record(stage + ".syncDirectory.begin")
        if consume(wanted) { return try failingSyscall(wanted) { try base.syncDirectory(fd: -1) } }
        try base.syncDirectory(fd: fd)
        record(stage + ".syncDirectory.succeeded")
        if stage == "config" {
            if consume(.markerRemoval) {
                guard fchmod(fd, 0o500) == 0 else { throw POSIXError(.EACCES) }
                record("markerRemoval.directoryMode500")
            }
        }
    }
}

private func expectExactFault(_ fault: SettingsIOFault, io: SettingsFaultIO,
                              store: SettingsStore) async throws {
    let calls = io.trace()
    #expect(calls.filter { $0.hasPrefix("fault.consumed.") } == ["fault.consumed.\(fault.rawValue)"])
    let failure = try #require(await store.lastPublicationFailure())
    #expect(failure.stage == fault.failureStage)
    #expect(failure.errno == fault.expectedErrno)
    let required: [String]
    let forbidden: [String]
    switch fault {
    case .bootstrapLockWrite:
        required = ["bootstrap.lock.write.begin"]
        forbidden = ["bootstrap.lock.syncFile", "bootstrap.store", "marker.", "candidate.", "backup.", "config."]
    case .bootstrapLockSync:
        required = ["bootstrap.lock.write.succeeded", "bootstrap.lock.syncFile.begin"]
        forbidden = ["bootstrap.store", "bootstrap.syncDirectory", "marker.", "candidate.", "backup.", "config."]
    case .bootstrapStoreWrite:
        required = ["bootstrap.lock.syncFile.succeeded", "bootstrap.store.write.begin"]
        forbidden = ["bootstrap.store.syncFile", "bootstrap.syncDirectory", "marker.", "candidate.", "backup.", "config."]
    case .bootstrapStoreSync:
        required = ["bootstrap.lock.syncFile.succeeded", "bootstrap.store.write.succeeded", "bootstrap.store.syncFile.begin"]
        forbidden = ["bootstrap.syncDirectory", "marker.", "candidate.", "backup.", "config."]
    case .bootstrapDirectorySync:
        required = ["bootstrap.lock.syncFile.succeeded", "bootstrap.store.syncFile.succeeded", "bootstrap.syncDirectory.begin"]
        forbidden = ["bootstrap.syncDirectory.succeeded", "marker.", "candidate.", "backup.", "config."]
    case .markerSync:
        required = ["marker.write.succeeded", "marker.syncFile.begin"]
        forbidden = ["prepared.syncDirectory", "candidate.", "backup.", "config."]
    case .preparedDirectorySync:
        required = ["marker.syncFile.succeeded", "prepared.syncDirectory.begin"]
        forbidden = ["prepared.syncDirectory.succeeded", "candidate.", "backup.", "config."]
    case .candidateShortWrite:
        required = ["prepared.syncDirectory.succeeded", "candidate.write.begin",
                    "fault.consumed.candidateShortWrite", "candidate.write.oneByte.1", "candidate.write.begin"]
        forbidden = ["candidate.syncFile", "backup.", "config."]
        #expect(calls.filter { $0 == "candidate.write.begin" }.count == 2)
    case .candidateSync:
        required = ["prepared.syncDirectory.succeeded", "candidate.write.succeeded", "candidate.syncFile.begin"]
        forbidden = ["candidate.syncFile.succeeded", "backup.", "config."]
    case .backupSync:
        required = ["candidate.syncFile.succeeded", "backup.write.succeeded", "backup.syncFile.begin"]
        forbidden = ["backup.syncFile.succeeded", "backup.replace", "backup.renamed", "config."]
    case .backupRenameBefore:
        required = ["backup.syncFile.succeeded", "backup.replace.begin"]
        forbidden = ["backup.renamed", "backup.syncDirectory", "config."]
    case .backupRenameAfter:
        required = ["backup.syncFile.succeeded", "backup.replace.begin", "backup.renamed"]
        forbidden = ["backup.syncDirectory", "config."]
    case .backupDirectorySync:
        required = ["backup.renamed", "backup.syncDirectory.begin"]
        forbidden = ["backup.syncDirectory.succeeded", "config."]
    case .configRenameBefore:
        required = ["backup.renamed", "backup.syncDirectory.succeeded", "config.replace.begin"]
        forbidden = ["config.renamed", "config.syncDirectory"]
    case .configRenameAfter:
        required = ["backup.syncDirectory.succeeded", "config.replace.begin", "config.renamed"]
        forbidden = ["config.syncDirectory"]
    case .configDirectorySync:
        required = ["backup.syncDirectory.succeeded", "config.renamed", "config.syncDirectory.begin"]
        forbidden = ["config.syncDirectory.succeeded", "markerRemoval."]
    case .markerRemoval:
        required = ["config.renamed", "config.syncDirectory.succeeded",
                    "fault.consumed.markerRemoval", "markerRemoval.directoryMode500"]
        forbidden = []
        #expect(calls.filter { $0 == "config.syncDirectory.begin" }.count == 1)
        #expect(calls.last == "markerRemoval.directoryMode500")
        #expect(calls.filter { $0.hasPrefix("fault.errno.") }.isEmpty)
    }
    var cursor = 0
    for event in required {
        guard let index = calls[cursor...].firstIndex(of: event) else {
            Issue.record("Missing ordered stage \(event) for \(fault.rawValue): \(calls)"); return
        }
        cursor = index + 1
    }
    for prefix in forbidden { #expect(!calls.contains { $0.hasPrefix(prefix) }) }
    if fault != .markerRemoval {
        let errorEvent = "fault.errno.\(fault.rawValue).\(fault.expectedErrno)"
        #expect(calls.filter { $0.hasPrefix("fault.errno.") } == [errorEvent])
        #expect(calls.last == errorEvent) // no later write/sync/rename after observed failure
    }
}

// Scheduling-only pause after a real lock-identity write while the production
// bootstrap still holds flock. It supplies neither data nor a success result.
private final class PausingBootstrapIO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let condition = NSCondition()
    private var entered = false, released = false, paused = false
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
    private func hasEntered() -> Bool { condition.lock(); defer { condition.unlock() }; return entered }
    func waitForEntry() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if hasEntered() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        let written = try base.write(fd: fd, bytes: bytes, offset: offset)
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &path) == 0 else { throw POSIXError(.EBADF) }
        guard URL(fileURLWithPath: String(cString: path)).lastPathComponent == "config.lock" else { return written }
        condition.lock(); defer { condition.unlock() }
        if paused { return written }; paused = true; entered = true; condition.broadcast()
        let deadline = Date().addingTimeInterval(5)
        while !released {
            guard condition.wait(until: deadline) else { throw POSIXError(.ETIMEDOUT) }
        }
        return written
    }
    func syncFile(fd: Int32) throws { try base.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
    }
    func syncDirectory(fd: Int32) throws { try base.syncDirectory(fd: fd) }
}

private struct HeldSettingsLockResult: Sendable {
    let acquired: Bool
    let watchdogFired: Bool
    let failureErrno: Int32?
}

// Only this dedicated Thread owns the FD: open/flock/unlock/close all occur
// there. Test continuations receive observations, never an FD to close/reuse.
private final class HeldSettingsLockThread: @unchecked Sendable {
    private let path: String
    private let state = NSLock()
    private var started = false, acquired = false, releaseRequested = false
    private var watchdogFired = false
    private var result: HeldSettingsLockResult?
    private var readyWaiters: [CheckedContinuation<Bool, Never>] = []
    private var joinWaiters: [CheckedContinuation<HeldSettingsLockResult, Never>] = []

    init(lockURL: URL) { path = lockURL.path }
    func start() {
        state.lock(); precondition(!started); started = true; state.unlock()
        Thread { [self] in run() }.start()
    }
    func release() { state.lock(); releaseRequested = true; state.unlock() }
    private func shouldRelease() -> Bool {
        state.lock(); defer { state.unlock() }; return releaseRequested
    }
    func waitUntilReady() async -> Bool {
        await withCheckedContinuation { continuation in
            state.lock()
            if acquired { state.unlock(); continuation.resume(returning: true) }
            else if result != nil { state.unlock(); continuation.resume(returning: false) }
            else { readyWaiters.append(continuation); state.unlock() }
        }
    }
    // Completion is published only after the owning Thread has unlocked and
    // closed its FD. There is no remaining filesystem work after this join.
    func join() async -> HeldSettingsLockResult {
        await withCheckedContinuation { continuation in
            state.lock()
            if let result { state.unlock(); continuation.resume(returning: result) }
            else { joinWaiters.append(continuation); state.unlock() }
        }
    }
    private func publishReady() {
        state.lock(); acquired = true
        let waiters = readyWaiters; readyWaiters = []; state.unlock()
        for waiter in waiters { waiter.resume(returning: true) }
    }
    private func finish(_ failure: Int32?) {
        state.lock()
        let completed = HeldSettingsLockResult(acquired: acquired,
            watchdogFired: watchdogFired, failureErrno: failure)
        result = completed
        let ready = readyWaiters, joined = joinWaiters
        readyWaiters = []; joinWaiters = []; state.unlock()
        for waiter in ready { waiter.resume(returning: false) }
        for waiter in joined { waiter.resume(returning: completed) }
    }
    private func run() {
        let fd = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { finish(errno); return }
        var failure: Int32?
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            failure = errno
        } else {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            publishReady()
            while !shouldRelease() {
                if ContinuousClock.now >= deadline {
                    state.lock(); watchdogFired = true; state.unlock()
                    break
                }
                // Relative short sleep; the deadline comparison is monotonic.
                // OS descheduling may delay it; no hard real-time claim.
                usleep(10_000)
            }
            if flock(fd, LOCK_UN) != 0 { failure = errno }
        }
        if close(fd) != 0, failure == nil { failure = errno }
        finish(failure) // last action, after all FD work on this same Thread
    }
}

@Suite("Settings publication")
struct SettingsPublicationTests {
    @Test func invalidLegacyEditCannotBootstrapAndValidEditStillSucceeds() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture("v1-original"); try s.seed(original)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: s.file.path)
        let io = SettingsFaultIO(), store = SettingsStore(url: s.file, io: io)
        #expect(await store.load().disposition == .migrated)
        await expectStoreError(.invalidChange) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(366))
        }
        await expectStoreError(.staleRevision) {
            _ = try await store.update(expectedRevision: 9, change: .transcriptAgeDays(60))
        }
        #expect(io.trace().isEmpty)
        #expect(try Data(contentsOf: s.file) == original)
        #expect(try mode(s.root) == 0o755 && mode(s.file) == 0o644)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
        let fresh = SettingsStore(url: s.file)
        let loaded = await fresh.load()
        #expect(loaded.disposition == .migrated && loaded.envelope?.revision == 0)
        let saved = try await fresh.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        #expect(saved.revision == 1 && saved.config.transcriptAgeThresholdDays == 60)
        #expect(try Data(contentsOf: s.backup) == original)
        #expect(try mode(s.root) == 0o755 && mode(s.file) == 0o600 && mode(s.backup) == 0o600)
    }

    @Test(arguments: SettingsIOFault.bootstrap)
    func bootstrapFaultNeverPublishesConfigAndPreservesReopenEvidence(fault: SettingsIOFault) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture("v1-original"); try s.seed(original)
        let io = SettingsFaultIO(), store = SettingsStore(url: s.file, io: io)
        #expect(await store.load().disposition == .migrated)
        io.arm(fault)
        await expectStoreError(.writeFailed) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        try await expectExactFault(fault, io: io, store: store)
        #expect(try Data(contentsOf: s.file) == original)
        #expect(try mode(s.root) == 0o700 && mode(s.file) == 0o600)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.pending.json").path))
        let names = try FileManager.default.contentsOfDirectory(atPath: s.root.path).sorted()
        var evidence: [String: Data] = [:]
        for name in names { evidence[name] = try Data(contentsOf: s.root.appendingPathComponent(name)) }
        #expect(names.contains("config.lock"))
        #expect(await store.load().disposition == .recoveryReadOnly)
        let fresh = SettingsStore(url: s.file)
        let reopened = await fresh.load()
        #expect(reopened.disposition == .recoveryReadOnly && reopened.envelope == nil)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await fresh.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path).sorted() == names)
        for (name, bytes) in evidence { #expect(try Data(contentsOf: s.root.appendingPathComponent(name)) == bytes) }
    }

    @Test func independentStoreCannotOverwriteNewerDiskRevision() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let a = SettingsStore(url: s.file), bIO = SettingsFaultIO()
        let b = SettingsStore(url: s.file, io: bIO)
        _ = await a.load(); _ = await b.load()
        _ = try await a.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let newest = try Data(contentsOf: s.file), backup = try Data(contentsOf: s.backup)
        await expectStoreError(.changedExternally) {
            _ = try await b.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        }
        #expect(bIO.trace().isEmpty)
        #expect(try Data(contentsOf: s.file) == newest && Data(contentsOf: s.backup) == backup)
        #expect(await b.load().envelope?.revision == 1)
        let second = try await b.update(expectedRevision: 1, change: .transcriptAgeDays(90))
        #expect(second.revision == 2 && second.config.transcriptAgeThresholdDays == 90)
    }

    @Test func independentHeldLockBlocksWithoutWritingThenExplicitRetrySucceeds() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let first = SettingsStore(url: s.file); _ = await first.load()
        _ = try await first.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let io = SettingsFaultIO(), second = SettingsStore(url: s.file, io: io)
        _ = await second.load()
        let lockURL = s.root.appendingPathComponent("config.lock")
        let holder = HeldSettingsLockThread(lockURL: lockURL)
        holder.start()
        do {
            let ready = await holder.waitUntilReady()
            if !ready {
                holder.release(); let joined = await holder.join()
                Issue.record("Dedicated lock holder failed to acquire: \(String(describing: joined.failureErrno))")
                return
            }
            let bytes = try Data(contentsOf: s.file)
            await expectStoreError(.unavailable) {
                _ = try await second.update(expectedRevision: 1, change: .transcriptAgeDays(90))
            }
            // A broken blocking flock cannot deadlock this test forever: the
            // independent Thread's watchdog releases its own lock, then the
            // unexpected update result and watchdog assertion both fail RED.
            holder.release()
            let joined = await holder.join()
            #expect(joined.acquired && joined.failureErrno == nil)
            #expect(!joined.watchdogFired)
            guard !joined.watchdogFired else { return } // no retry after defective blocking call
            #expect(try io.trace().isEmpty && Data(contentsOf: s.file) == bytes)
            // Holder FD is closed before this explicit retry.
            let saved = try await second.update(expectedRevision: 1, change: .transcriptAgeDays(90))
            #expect(saved.revision == 2)
        } catch {
            holder.release()
            let joined = await holder.join()
            #expect(!joined.watchdogFired && joined.failureErrno == nil)
            throw error
        }
    }

    @Test func independentBootstrapContenderCannotInitializeWinnersMetadata() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture("v1-original"); try s.seed(original)
        let pause = PausingBootstrapIO(), contenderIO = SettingsFaultIO()
        let winner = SettingsStore(url: s.file, io: pause)
        let contender = SettingsStore(url: s.file, io: contenderIO)
        _ = await winner.load(); _ = await contender.load()
        let task = Task { try await winner.update(expectedRevision: 0, change: .transcriptAgeDays(60)) }
        do {
            let entered = await pause.waitForEntry()
            if !entered {
                pause.release(); _ = await task.result
                Issue.record("Real bootstrap lock write was not reached within 2 seconds"); return
            }
            await expectStoreError(.unavailable) {
                _ = try await contender.update(expectedRevision: 0, change: .transcriptAgeDays(90))
            }
            #expect(contenderIO.trace().isEmpty)
            #expect(try Data(contentsOf: s.file) == original)
            #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.store.json").path))
            pause.release()
            let completed = await task.result
            let saved = try completed.get()
            #expect(saved.revision == 1 && saved.config.transcriptAgeThresholdDays == 60)
            await expectStoreError(.changedExternally) {
                _ = try await contender.update(expectedRevision: 0, change: .transcriptAgeDays(90))
            }
            #expect(await contender.load().envelope == saved)
        } catch {
            // Async-finally pattern: even a throwing Data read above must drain
            // the writer before the outer scratch-removal defer can execute.
            pause.release()
            _ = await task.result
            throw error
        }
    }

    @Test(arguments: SettingsIOFault.publication)
    func faultsPreserveEvidenceAndBlockFreshStore(fault: SettingsIOFault) async throws {
        #expect(geteuid() != 0, "Requires ordinary unprivileged test user")
        guard geteuid() != 0 else { return }
        let s = try SettingsScratch(); defer { s.remove() }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: s.root.path) }
        try s.seed(try fixture("v1-original"))
        let io = SettingsFaultIO(), store = SettingsStore(url: s.file)
        _ = await store.load()
        // Bootstrap and one successful production transaction establish revision1.
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(61))
        let old = try Data(contentsOf: s.file), priorBackup = try Data(contentsOf: s.backup)
        let lockPath = s.root.appendingPathComponent("config.lock")
        let lockAttributes = try FileManager.default.attributesOfItem(atPath: lockPath.path)
        let lockInode = try #require(lockAttributes[.systemFileNumber] as? NSNumber)
        let failing = SettingsStore(url: s.file, io: io); _ = await failing.load()
        io.arm(fault)
        let expected: SettingsStoreError
        switch fault {
        case .configRenameBefore, .configRenameAfter, .configDirectorySync: expected = .durabilityUncertain
        case .markerRemoval: expected = .finalizationBlocked
        default: expected = .writeFailed
        }
        await expectStoreError(expected) {
            _ = try await failing.update(expectedRevision: 1, change: .transcriptAgeDays(92))
        }
        try await expectExactFault(fault, io: io, store: failing)
        let pending = s.root.appendingPathComponent("config.pending.json")
        #expect(FileManager.default.fileExists(atPath: pending.path))
        let observed = try Data(contentsOf: s.file)
        let calls = io.trace()
        switch fault {
        case .configRenameAfter, .configDirectorySync, .markerRemoval:
            #expect(calls.contains("config.renamed"))
            #expect(observed != old)
            let candidate = try JSONDecoder().decode(SettingsEnvelope.self, from: observed)
            #expect(candidate.revision == 2 && candidate.config.transcriptAgeThresholdDays == 92)
            #expect(try Data(contentsOf: s.backup) == old)
        default:
            #expect(observed == old)
            if calls.contains("backup.renamed") { #expect(try Data(contentsOf: s.backup) == old) }
            else { #expect(try Data(contentsOf: s.backup) == priorBackup) }
        }
        if fault == .configDirectorySync {
            #expect(calls.contains("fault.errno.configDirectorySync.\(EBADF)"))
            #expect(!calls.contains("config.syncDirectory.succeeded"))
        }
        if fault == .markerRemoval {
            #expect(calls.contains("config.syncDirectory.succeeded"))
            #expect(calls.contains("markerRemoval.directoryMode500"))
        }
        let latched = await failing.load()
        #expect(latched.disposition == .recoveryReadOnly && latched.envelope == nil)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await failing.update(expectedRevision: 1, change: .transcriptAgeDays(93))
        }
        await expectStoreError(.readOnlyRecovery) { _ = try await failing.previewRollback() }
        // Restore scratch permission solely for inspection; never remove the marker.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: s.root.path)
        let fresh = SettingsStore(url: s.file)
        let reopened = await fresh.load()
        #expect(reopened.disposition == .recoveryReadOnly && reopened.envelope == nil)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await fresh.update(expectedRevision: 1, change: .transcriptAgeDays(94))
        }
        #expect(try Data(contentsOf: s.file) == observed)
        #expect(FileManager.default.fileExists(atPath: pending.path))
        let after = try FileManager.default.attributesOfItem(atPath: lockPath.path)
        #expect(after[.systemFileNumber] as? NSNumber == lockInode)
        #expect(try mode(lockPath) == 0o600 && mode(pending) == 0o600)
    }

    @Test func firstSaveFailureNeverBecomesDefaultsOnRelaunch() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let io = SettingsFaultIO(), store = SettingsStore(url: s.file, io: io)
        #expect(await store.load().disposition == .newDefaults)
        io.arm(.configDirectorySync)
        await expectStoreError(.durabilityUncertain) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        let candidate = try JSONDecoder().decode(SettingsEnvelope.self, from: Data(contentsOf: s.file))
        #expect(candidate.revision == 1)
        #expect(io.trace().contains("config.renamed"))
        #expect(io.trace().contains("fault.consumed.configDirectorySync"))
        #expect(io.trace().contains("fault.errno.configDirectorySync.\(EBADF)"))
        #expect(io.trace().filter { $0.hasPrefix("fault.consumed.") } == ["fault.consumed.configDirectorySync"])
        #expect(io.trace().last == "fault.errno.configDirectorySync.\(EBADF)")
        #expect(!io.trace().contains("config.syncDirectory.succeeded"))
        let failure = try #require(await store.lastPublicationFailure())
        #expect(failure.stage == "config.syncDirectory" && failure.errno == EBADF)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
    }

    @Test func rollbackFailurePreservesPreRollbackBytesAndBlocksOldPreview() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let io = SettingsFaultIO(), store = SettingsStore(url: s.file, io: io)
        let original = try fixture("v1-memory"); try s.seed(original); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let beforeRollback = try Data(contentsOf: s.file)
        let preview = try await store.previewRollback()
        io.arm(.configDirectorySync)
        await expectStoreError(.durabilityUncertain) {
            _ = try await store.rollback(expectedRevision: 1, preview: preview)
        }
        try await expectExactFault(.configDirectorySync, io: io, store: store)
        #expect(try Data(contentsOf: s.backup) == beforeRollback)
        let candidate = try JSONDecoder().decode(SettingsEnvelope.self, from: Data(contentsOf: s.file))
        #expect(candidate.revision == 2 && candidate.config.transcriptAgeThresholdDays == 120)
        #expect(candidate.config.appsApprovedForQuit == ["Old application name"])
        #expect(candidate.config.presets.first?.itemIDs.contains("unknown.preset.id") == true)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.rollback(expectedRevision: 1, preview: preview)
        }
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
    }

    @Test func completedTransactionReopensButInitializedMissingFilesDoNotReset() async throws {
        for missing in ["config.json", "config.lock", "config.store.json"] {
            let s = try SettingsScratch(); defer { s.remove() }
            try s.seed(try fixture("v1-original"))
            let store = SettingsStore(url: s.file); _ = await store.load()
            let saved = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
            #expect(await SettingsStore(url: s.file).load().envelope == saved)
            #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.pending.json").path))
            let removed = s.root.appendingPathComponent(missing)
            try FileManager.default.removeItem(at: removed) // exact disposable initialized fixture
            let result = await SettingsStore(url: s.file).load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            #expect(!FileManager.default.fileExists(atPath: removed.path))
        }
    }

    @Test func unknownMetadataAndMarkerArePreservedWithoutAutomaticFinalization() async throws {
        for name in ["config.lock", "config.store.json", "config.pending.json"] {
            let s = try SettingsScratch(); defer { s.remove() }
            try s.seed(try fixture("v1-original"))
            let store = SettingsStore(url: s.file); _ = await store.load()
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
            let bytes = Data("{\"schema\":999,\"unknown\":true}".utf8)
            let target = s.root.appendingPathComponent(name)
            try bytes.write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            let result = await SettingsStore(url: s.file).load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            #expect(try Data(contentsOf: target) == bytes)
        }
    }

    @Test(arguments: [Data(), Data("{\"schema\":1,".utf8)])
    func partialMarkerBlocksEvenWhenConfigAndBackupAreValid(bytes: Data) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let store = SettingsStore(url: s.file); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let config = try Data(contentsOf: s.file), backup = try Data(contentsOf: s.backup)
        let pending = s.root.appendingPathComponent("config.pending.json")
        try bytes.write(to: pending)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pending.path)
        let fresh = SettingsStore(url: s.file)
        #expect(await fresh.load().disposition == .recoveryReadOnly)
        await expectStoreError(.readOnlyRecovery) { _ = try await fresh.previewRollback() }
        #expect(try Data(contentsOf: s.file) == config && Data(contentsOf: s.backup) == backup)
        #expect(try Data(contentsOf: pending) == bytes)
    }
}
```

The matrix verifies a unique consumed fault, exact production failure stage/actual errno, ordered prerequisite operations and forbidden later operations for every case. Candidate short-write RED requires an actual one-byte write followed by the failing continuation; backup-after/directory-sync RED requires an actual backup rename while backup-before forbids it. A generic earlier failure cannot satisfy these assertions. The independent-store/descriptors tests establish A.2F contention and stale-write behavior only. They do not establish actual independent process lifetimes, abrupt-process crashes or physical power loss.

Policy non-commit remains a separate A.3 caller test; merely constructing SettingsStore does not prove app admission behavior. Tests remove only their exact owned UUID scratch roots after assertions and restore only their own permission fixture. PausingBootstrapIO's real-I/O pause has a5second timeout and wait-for-entry a2second deadline; the explicit do/catch async-finally pattern releases and awaits `task.result` on every exit, including a throwing inspection read, before the outer cleanup defer. No async defer that launches an unjoined Task is permitted.

The held-lock fixture uses a dedicated Thread which owns acquisition, unlock and close of its local FD. Explicit release or its2second monotonic watchdog ends the hold; `join()` returns only after that thread's FD work is complete. A defective blocking production flock can therefore unblock when the watchdog releases the real lock, and the test fails because `watchdogFired` must be false (and the expected immediate unavailable result was not returned). Join occurs before retry and on every throwing exit before scratch cleanup. No task-group cancellation, cross-thread close of a potentially reused FD, or assumed external bounded-runner command supplies this guarantee. These deadlines are not hard real-time promises under arbitrary OS stalls.

A.2P remains required for full A.2/T05 acceptance: actual two-process stable-lock/bootstrap contention, winner death during bootstrap, abrupt process exit at each P1–P5 prefix, and fault-free child-process reopen against retained artifacts. Supply the exact executable fixture, process lifetime/timeout/cleanup contract and complete failing tests **before A.2P implementation entry**. Those tests are not silently waived by this complete A.2F batch, nor claimed to exist here. No settings migration release is authorized before the complete A.2/A.3 acceptance gates.

Controller-scheduled A.2F focused command, only after this batch's entry review:

```sh
cd /private/tmp/tidy-headroom.wUbV9h/TidyCore
swift test --filter 'SettingsMigrationTests|SettingsPublicationTests' --jobs 2
```

The completed A.2F design/lifetime/FIFO review does not waive implementation review: reject source that writes bootstrap metadata before validating/encoding the complete edit, skips authoritative locked rechecks, auto-clears matching pending markers, treats missing initialized config as defaults, removes/replaces config.lock, returns success after a failed P4 sync, retries rollback without a new user action, or silently treats finalizationBlocked as a committed app policy. A.2F source entry remains conditional on A.1 and T04's single shared primitive implementation. A.2P requires its own complete RED/fixture review; A.3/B.1/B.2 remain independently gated.

## T05A.3 — T02 bridge handoff and real app wiring RED

This is a reviewed extension of T02, **not a second implementation of it**. Preserve exact coordinator beginPolicyUpdate / commitPolicyUpdate contracts, bridge return Task completion handle, latest-generation handling, app config didSet and single AppExecutionServices ownership. New proposal:

```swift
// Replace the bridge storage URL dependency with the already-loaded sole store.
ExecutionPolicyBridge.init(coordinator: ExecutionCoordinator, settings: SettingsStore,
    loaded: SettingsLoadResult, homeDirectory: String, detectedTools: Set<ToolchainID>)
// Existing public submit(config:) -> Task<Void, Never> remains synchronous.
// New observation on the same bridge (not another policy revision):
ExecutionPolicyBridge.durableSettingsRevision: UInt64?
ExecutionPolicyBridge.drain() async

// App-layer types; Paths has no default arguments and no filesystem work.
struct AppStoragePaths: Sendable {
    let home: URL
    let settings: URL
    let journal: URL
}
@MainActor final class AppExecutionServices {
    static func bootstrap(paths: AppStoragePaths) async -> AppExecutionServices
    let coordinator: ExecutionCoordinator
    let settings: SettingsStore
    let configStore: AppConfigStore
    let policyBridge: ExecutionPolicyBridge
}
```

Bootstrap calls one off-main async factory to load bounded settings and create the real coordinator/journal state, then constructs the MainActor observation wrapper. Do not merely wrap synchronous I/O in `Task {}` inheriting MainActor. App displays loading/recovery and disallows review/confirmation until ready; no default-config enabled interval. Recovery has no usable persisted envelope and remains disabled even if the user changes an in-memory control. Journal initialization is included in the off-main audit. Production storage path resolution is in TidyApp's explicit factory only; injectable Paths never defaults to NSHomeDirectory/ConfigStore.defaultURL. This is no discovery: tools snapshot literal [], no makeEnvironment, locator/detector, Process, cookie/process/simulator suggestions, onboarding or scan task during bootstrap/setters. T08 later owns explicit discovery.

In submit, disable immediately and beginPolicyUpdate synchronously before projection/task creation. Chain to the previous submission as T02 does. Inside that chain call `await settings.update(expectedRevision: lastSuccessfullyPersistedRevision, change: .legacyPreferences(config))`; advance stored revision only on actual persistence success, then call **the existing coordinator** commit with the original ticket and pure environment projected from the returned saved config. An older save may advance storage revision while its policy commit is superseded; it may never reopen latest admission. Failure leaves latest admission updating/disabled. A subsequent explicit valid edit uses the last successful storage revision. Apply a bounded pending-edit queue (at most32 snapshots of at most1 MiB); overflow synchronously invalidates and shows “Settings changes are pending; wait and save again,” never auto-enables or drops an acknowledged edit. Do not coalesce across user-observable saved/failed revisions without another review.

The following complete app test uses real services, store, bridge and coordinator. Create `TidyAppModelTests/SharedSettingsWiringTests.swift` and extend the **unhosted** target from `T02-app-confirmation-tests.md` with that exact file; no host module import. Its source membership already includes the same production AppExecutionServices/AppConfigStore used by Tidy. It does not initialize TidyApp, call real discovery, or claim an accepted mutation. No alternate policy/bridge implementation is test support.

```swift
import Foundation
import Darwin
import Testing
@testable import TidyCore

private func canonicalAppScratchBase() throws -> URL {
    var path = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath("/private/tmp", &path) != nil else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return URL(fileURLWithPath: String(cString: path), isDirectory: true)
}

@Suite("Shared settings app wiring") @MainActor
struct SharedSettingsWiringTests {
    @Test func twoWindowsUseOneSetterAndLatestPersistence() async throws {
        let root = try canonicalAppScratchBase()
            .appendingPathComponent("T05-App-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
        let paths = AppStoragePaths(home: home,
            settings: root.appendingPathComponent("settings/config.json"),
            journal: root.appendingPathComponent("journal"))
        let services = await AppExecutionServices.bootstrap(paths: paths)
        let windowA = services.configStore
        let windowB = services.configStore
        #expect(windowA === windowB)
        let c = services.coordinator
        // Explicit scratch-only catalog review; this is not launch discovery.
        let review = try await c.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                               tier: .safe, selectDefaults: false)
        let frozen = review.binding
        let token = try await c.confirm(binding: frozen) // genuine no-op core token
        windowA.config.transcriptAgeThresholdDays = 60
        #expect(c.policyAdmission() == .updating(revision: 2))
        windowB.config.transcriptAgeThresholdDays = 90
        #expect(c.policyAdmission() == .updating(revision: 3))
        #expect(windowA.config.transcriptAgeThresholdDays == 90)
        #expect(!services.policyBridge.isExecutionEnabled)
        // MainActor can handle another event without waiting for storage/discovery.
        var processedEvent = false
        await Task { @MainActor in processedEvent = true }.value
        #expect(processedEvent)
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
        do { _ = try await c.confirm(binding: frozen); Issue.record("Frozen review survived edit") }
        catch let error as ConfirmationError { #expect(error == .stalePolicy) }
        await services.policyBridge.drain()
        #expect(c.policyAdmission() == .ready(revision: 3))
        #expect(services.policyBridge.durableSettingsRevision == 2)
        let saved = await services.settings.load()
        #expect(saved.envelope?.config.transcriptAgeThresholdDays == 90)
        #expect(saved.envelope?.revision == 2)
    }
}
```

This event assertion proves progress at an ordinary fixture, not latency under blocked storage. **A.3 acceptance prerequisite:** add reviewed narrow I/O-boundary scheduling instrumentation and full tests before implementing the off-main move: suspend real persistence before publication, verify `Thread.isMainThread == false` at that boundary, deliver a main-actor event while suspended, submit a newer revision, release old save, and prove it cannot enable execution until the latest completes. The instrumentation may pause/observe only disk scheduling, never return fake persistence success or policy authority. The test above alone does not meet this gate. Do not claim a universal synchronous-disk latency bound; bounded bytes/queue are not a guarantee against a blocked filesystem syscall.

## T05B.1 — Separate fixed-scratch UI entry (foundation only)

The existing `TidyUITestHost/TestHostApp.swift` is an audited metadata-only **five-source** host at620×620pt, no resources, no settings/default paths/engine. Preserve it and its existing scheme. Do not compile TidyApp.swift, MenuBarContentView, ScanView, onboarding, or the current whole SettingsView into a new host: its suggestion buttons still call ambient cookie/project/process/simulator APIs. Extract only the pure existing `ThresholdsSection` into `Tidy/Settings/ThresholdsSection.swift`; both production SettingsView and the safety host use this same view. Give its steppers identifiers `threshold.staleDays` and `threshold.transcriptDays`, with no launch flag in the production file. A host button below exercises the **actual AppConfigStore setter**, not a copied setter; the shared section itself supplies the real user edit gate.

New files: `TidySafetyTestHost/SafetyHostApp.swift`, `TidyUITests/PlanSafetyUITests.swift`, and unhosted app test above. Modify project.yml and regenerate project only at entry. Do not modify the existing manual host's source membership. New app target `TidySafetyTestHost` explicitly includes only SafetyHostApp, production AppExecutionServices, AppConfigStore, ThresholdsSection, and any separately reviewed pure dependency files required by the landed T02 services. Never use `path: Tidy` for host membership. Unit/UI test resources stay outside Tidy. Scheme `TidySafetyTestHost` builds that app and tests `TidyUITests`; UI test target sets `TEST_TARGET_NAME: TidySafetyTestHost`. Model tests retain their separate unhosted TidyAppModelTests scheme. Use macOS14, Swift5, local TidyCore only. Production scheme does not include any host/test target.

Complete host entry below has no path argument or production fallback. Valid launch token is exactly `--t05-safety`; optional `--t05-safety` plus any extra application argument is denied. XCTest may inject environment variables, not extra application arguments. Root is freshly allocated beneath the OS temp directory and canonicalized; malformed input constructs no service/storage/engine. Automatic scratch deletion is deliberately absent on termination; the test runner retains its exact root for inspection, and the controller may remove only that validated UUID directory after evidence collection.

```swift
import SwiftUI
import Darwin
import Observation
import TidyCore

private func canonicalUIScratchBase() throws -> URL {
    var path = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath("/private/tmp", &path) != nil else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return URL(fileURLWithPath: String(cString: path), isDirectory: true)
}

@MainActor @Observable
final class SafetyHostState {
    var services: AppExecutionServices?
    var status = "Not started"
    var sentinelURL: URL?
    func start(arguments: [String]) async {
        guard services == nil, status == "Not started" else { return }
        guard arguments == ["--t05-safety"] else { status = "Launch denied"; return }
        status = "Loading scratch settings"
        do {
            let root = try canonicalUIScratchBase()
                .appendingPathComponent("T05-UI-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            let home = root.appendingPathComponent("home", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
            let sentinel = root.appendingPathComponent("preserve.txt")
            try Data("T05 preserve".utf8).write(to: sentinel)
            sentinelURL = sentinel
            services = await AppExecutionServices.bootstrap(paths: AppStoragePaths(
                home: home, settings: root.appendingPathComponent("settings/config.json"),
                journal: root.appendingPathComponent("journal")))
            status = "Scratch ready"
        } catch { status = "Scratch setup failed" }
    }
}

@main @MainActor
struct SafetyHostApp: App {
    @State private var state = SafetyHostState()
    var body: some Scene {
        WindowGroup("T05 Settings", id: "t05-settings") {
            SafetyWindow(state: state)
                .task { await state.start(arguments: Array(CommandLine.arguments.dropFirst())) }
        }
        .defaultSize(width: 620, height: 620)
    }
}

@MainActor
struct SafetyWindow: View {
    let state: SafetyHostState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack {
            Text("TIDY_SAFETY_FIXTURE_ONLY").accessibilityIdentifier("fixture.marker")
            Text(state.status).accessibilityIdentifier("fixture.status")
            if let services = state.services {
                @Bindable var config = services.configStore
                Form {
                    ThresholdsSection(staleNodeModulesDays: $config.config.staleNodeModulesThresholdDays,
                                      transcriptAgeDays: $config.config.transcriptAgeThresholdDays)
                }
                Text(String(config.config.transcriptAgeThresholdDays))
                    .accessibilityIdentifier("settings.transcriptDays")
                Text(services.policyBridge.policyUpdatePending ? "Updating" :
                     (services.policyBridge.isExecutionEnabled ? "Ready" : "Disabled"))
                    .accessibilityIdentifier("settings.admission")
                Button("Set 90 days") { config.config.transcriptAgeThresholdDays = 90 }
                    .accessibilityIdentifier("settings.set90")
                Button("Open second settings window") { openWindow(id: "t05-settings") }
                    .accessibilityIdentifier("settings.secondWindow")
            }
        }.padding().frame(minWidth: 620, minHeight: 620)
    }
}
```

This entry performs fixture setup I/O on MainActor; that is tiny **test-host setup**, not evidence that production startup is off-main. Move that setup into an explicit nonisolated async helper before using host timing as app latency evidence. Production bootstrap behavior is tested independently in A.3. Host contains no cleanup/confirm invocation path at all: it cannot be used to claim successful cleanup, selection rejection at an effect boundary or active-run close semantics.

Complete `PlanSafetyUITests.swift` for this entry:

```swift
import XCTest

final class PlanSafetyUITests: XCTestCase {
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }
    func testMalformedArgumentsNeverOpenServices() {
        for args in [[], ["--t05-safety", "--home", "/"], ["--unknown"]] {
            let app = launch(args)
            XCTAssertTrue(app.staticTexts["fixture.status"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["fixture.status"].label, "Launch denied")
            XCTAssertFalse(app.buttons["settings.set90"].exists)
            XCTAssertFalse(app.buttons["settings.secondWindow"].exists)
            app.terminate()
        }
    }
    func testTwoWindowsShareActualSettingsSetterAndSurviveOneClose() {
        let app = launch(["--t05-safety"])
        defer { app.terminate() }
        let first = app.windows.element(boundBy: 0)
        XCTAssertTrue(first.buttons["settings.secondWindow"].waitForExistence(timeout: 10))
        XCTAssertEqual(first.staticTexts["settings.transcriptDays"].label, "45")
        first.buttons["settings.secondWindow"].click()
        let twoWindows = NSPredicate(format: "count == 2")
        expectation(for: twoWindows, evaluatedWith: app.windows)
        waitForExpectations(timeout: 5)
        let second = app.windows.element(boundBy: 1)
        second.buttons["settings.set90"].click()
        XCTAssertEqual(first.staticTexts["settings.transcriptDays"].label, "90")
        XCTAssertEqual(second.staticTexts["settings.transcriptDays"].label, "90")
        let ready = NSPredicate(format: "label == 'Ready'")
        expectation(for: ready, evaluatedWith: second.staticTexts["settings.admission"])
        waitForExpectations(timeout: 10)
        first.buttons[XCUIIdentifierCloseWindow].click()
        let oneWindow = NSPredicate(format: "count == 1")
        expectation(for: oneWindow, evaluatedWith: app.windows)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.windows.element(boundBy: 0).staticTexts["settings.transcriptDays"].label, "90")
        XCTAssertTrue(app.buttons["settings.set90"].isEnabled)
    }
}
```

Before source implementation, supplement the host test with an interaction against the extracted real Stepper (increment via its actual AX increment child) after inspecting stable-OS AX output; do not substitute the harness's Set90 button for proof that production Form binding works. Exact stable-OS AX identity cannot be asserted from the current anomalous developer-OS capture. This is an explicit B.1 UI-entry review gate, not claimed complete production UI automation.

## T05B.2 — Acceptance that foundations cannot supply

The following boundaries remain open; do not fill them with a simulated accepted capability, hard-coded invocationCount0, fake parser, test executor bypass, or a production runtime test flag.

- **Targetless denied visibility now:** rerun the preserved manual host Safe/Normal/Deep/Custom checks for npm targetless and memory zero-byte rows, denial reasons, unknown preset IDs, disabled confirmation and620pt readable layout. Unknown preset selection remains zero; this is denied presentation evidence, not positive deselection/execution.
- **Actual confirmation dialog:** accepted `.M` fixture must go through real production parser/planner, coordinator and Clean/Custom view models. Freeze selected A/C (B deselected), open actual dialog, change settings in another window, and assert dialog dismissal plus old-token denial. Selecting no items never opens confirmation. No fabrication of RegisteredReview/ConfirmedPlan or injecting a claimed eligible ActionDescriptor.
- **Recording effect boundary:** the accepted adapter's effect-only transport records exact A/C identities, never B/new D; unknown imported IDs and maintenance/model-deletion requests cannot produce an invocation. The parser/resolver/registry/coordinator remain production. Import preview must parse actual bounded bytes, strip/inert local authority, require local reassociation for roots, keep authorization ledger bytes unchanged and still deny model mutation. The full portable import API is T07/T21 integration; T05A migration of local v1 is not a substitute for this end-to-end import test.
- **Window lifetime:** two actual Clean windows plus Custom share the one service/coordinator. Close idle window A: its review is discarded, B stays live. Close A during accepted in-flight effect: shared app/menu progress and cancel remain; no second hidden execution starts, B observes busy, current effect drains to accepted safe boundary. App quit drains or retains durable uncertainty. The settings-only close test above does not prove these mutation semantics.
- **Scrolling/accessibility:** retain `docs/verification/T01-B-manual-verification.md`'s unresolved AX endpoint-jump temporary blank Deep list. On supported stable OS repeat ordinary mouse scroll, keyboard navigation and AX endpoint navigation at620pt, top/bottom and after switching surfaces/expanding presets. Record video/screenshots and AX snapshots, recovery behavior, OS version and exact input path. A single ordinary scroll restoring rows is not evidence the anomaly is fixed. Native keyboard/VoiceOver text, disabled reasons, focus order, warning readability and window resize remain required.

## Exact safe commands and verification sequence

These replace the brief's dangling `Run UI command from 3` reference. Run only after controller schedules tests, T02 is idle, and the relevant entry gate is reviewed; all paths below refer to the isolated worktree, never the main checkout. No commands are executed by this card. At A.1 use only the named read-only GREEN subset above; the complete-suite command is the later A.2+ gate, not an A.1 acceptance command.

A.1 exact subset filter (the following parenthesis/end boundary excludes the separately named persistence methods):

```sh
cd /private/tmp/tidy-headroom.wUbV9h/TidyCore
swift test --filter '(missingOnlyCreatesInMemoryDefaults|bothHistoricalShapes|knownSchema2LoadsNonzeroRevisionWithoutWriting|ownedLegacy755DirectoryAnd644FileMigrateWithoutSilentChmod|recoveryPreservesBytes|existingInvalidIsNeverNewDefaults|symlinkDoesNotAuthorizeReadingOrReplacingDestination|unknownSchema2ExtensionAndNestedMismatchAreReadOnly|depthListAndStringBoundsRejectWithoutRewrite|groupWritableLegacyLocationIsReadOnly|unsafeExistingAuxiliaryFilesAreNotRepaired|oldReportsHaveUnavailableMemoryNotMeasuredZero)(\(|$)' --jobs 2
```

Confirm the runner actually selects all twelve named methods and every parameter value; zero tests or missing matches is not GREEN. A.2+ complete-suite command, only after its separate entry approval:

```sh
cd /private/tmp/tidy-headroom.wUbV9h/TidyCore
swift test --filter SettingsMigrationTests --jobs 2
```

After source membership and safe call-graph review, generate locally and build **without launch**:

```sh
cd /private/tmp/tidy-headroom.wUbV9h
xcodegen generate --spec project.yml
xcodebuild -project Tidy.xcodeproj -scheme TidySafetyTestHost -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-t05-build -jobs 2 build-for-testing CODE_SIGNING_ALLOWED=NO
```

Only after built host source/bundle audit excludes ambient default paths, production startup and effect callers:

```sh
cd /private/tmp/tidy-headroom.wUbV9h
xcodebuild -project Tidy.xcodeproj -scheme TidySafetyTestHost -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-t05-build -jobs 2 test-without-building -only-testing:TidyUITests/PlanSafetyUITests CODE_SIGNING_ALLOWED=NO
```

The shared app-model test remains unhosted and runs separately after extending that target's exact test-file allowlist:

```sh
cd /private/tmp/tidy-headroom.wUbV9h
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-t05-model-tests -jobs 2 test -only-testing:TidyAppModelTests -test-timeouts-enabled YES -default-test-execution-time-allowance 30 -maximum-test-execution-time-allowance 60 CODE_SIGNING_ALLOWED=NO
```

If the local XCTest runner needs signing/permissions, stop and report that requirement; do not alter production entitlements or signing to force a pass. Run full core only after the T01/T02 no-host-effect audit and controller authorization:

```sh
cd /private/tmp/tidy-headroom.wUbV9h/TidyCore
swift test --jobs 2
```

```sh
cd /private/tmp/tidy-headroom.wUbV9h
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-t05-production -jobs 2 build CODE_SIGNING_ALLOWED=NO
rg -n 'TIDY_SAFETY_FIXTURE_ONLY|T05-UI-|t05-safety|SafetyHostApp|TidyUITests' Tidy TidyCore/Sources
rg -a -n 'TIDY_SAFETY_FIXTURE_ONLY|T05-UI-|t05-safety|SafetyHostApp' /private/tmp/tidy-t05-production/Build/Products/Debug/Tidy.app
git diff --check
```

Both marker scans expect no matches (rg exit1); additionally inspect generated production Sources/Resources phases and bundle file listing, including debug dylib, for no fixture sources/resources/dispatch hooks. Grep absence alone is not transitive startup/effect safety proof. Record core/build/UI/device evidence separately. Require arm64 and x86_64 build plus physical8GiB Apple Silicon/Intel and macOS14/stable-current-OS observations; unavailable hardware remains an open gate.

## Entry review checklist and delivery language

- [ ] Reconcile all proposed names against landed T02 without editing its active source. Ask controller before resolving any genuine authority/store/report conflict.
- [ ] Independently review the newly specified complete FIFO addendum, then implement/run its A.1/A.2 phase-specific settings-reader RED/GREEN. It adapts T02's tested mechanism; neither that journal evidence nor existing A.1 JSON/mode tests close the settings-reader gate.
- [ ] A.2F foundation RED reviewed, including exact consumed-fault/stage/errno, bootstrap faults, validate-before-bootstrap, independent-store stale-write and descriptor/bootstrap contention. Shared T04 I/O primitive ownership resolved before A.2F source entry; A.1 read GREEN alone is insufficient.
- [ ] A.2P complete actual-two-process/crash-prefix fixture and RED reviewed before that unit's entry. Keep A.2/T05 full acceptance open until those tests pass; same-process foundation evidence does not remove this fulfillment gate.
- [ ] A.3 off-main suspended-I/O test is complete/reviewed before implementation entry; preserve ordered ticket commits and immediate latest-generation barrier.
- [ ] B.1 project membership, real control AX interaction and source bootstrap audit reviewed before host construction/launch; old manual host untouched.
- [ ] B.2 accepted-adapter fixture and full UI RED supplied at its own gate; no fake accepted capability or alternate executor authority.
- [ ] Independent review of source, focused tests and preserved-byte evidence before advancing each unit. No git commit authorized by this card.

Report exactly which units entered, implemented and verified. Acceptable interim wording: “T05 settings/UI foundation verified for the listed fixtures; accepted-action UI, import authority integration, in-flight close lifecycle and stable-OS AX anomaly remain open.” Do not say “T05 complete,” “migration safe for every failure,” “responsive on slow storage,” or “cleanup works” based on these foundation tests alone.
