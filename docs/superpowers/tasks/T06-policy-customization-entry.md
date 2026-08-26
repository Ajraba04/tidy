# T06 Policy Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task, only after explicit controller entry approval. Steps use checkbox syntax. This card grants no source-entry authority.

**Goal:** One typed registry and pure effective-policy resolver covering every supported customization, with provenance and lossless schema2 preference persistence.

**Architecture:** Preferences replace, explicit restrictions intersect, and immutable constraints bound the result. Authority remains in its existing machine-local owner; this resolver produces observed policy data, not an accepted capability, execution ticket, root approval, or authority ledger. Extend T05's sole envelope/store additively, then hand policy-affecting edits through the existing T02/T05A.3 coordinator bridge.

**Tech Stack:** Swift, Swift Testing, Foundation; local TidyCore; native SwiftUI integration only at the separately approved app boundary.

## Global Constraints

- Native Swift/SwiftUI, macOS 14+, local TidyCore package, zero third-party runtime dependencies.
- Intel x86_64 and Apple Silicon arm64 supported; both require build and device evidence.
- No internet requests, telemetry, remote updates, repository fetches, model downloads, or remote package dependencies at runtime.
- Local IPC to an explicitly identified local tool service is allowed. No remote Docker contexts, TCP endpoints, SSH endpoints, or daemon auto-start during discovery.
- No repository deletion, database deletion, Docker volume deletion, local-model deletion, generic duplicate-file deletion, arbitrary scripts, or automatic force-quitting.
- No kernel tuning, swap-file manipulation, launch-agent disabling, privileged persistent helper, or changes to other tools' settings.
- No full-home scans on popover open or timers. No repository-supplied executable/config evaluation merely to discover a project.
- No change to signing, publishing, deployment, or remote Git state is authorized by this document.

Design S01–S16 apply unchanged. In particular, no setting circumvents reviewed targets, sealed/current confirmation, one mutator, anchored containment, running/unknown-state protection, regeneration evidence, cancellation/drain, quarantine, or unfinished-effect reconciliation. This task does not implement these mechanisms or claim their acceptance.

---

## Entry status and ownership

Documentation-only proposal. Read checkpoint: `SettingsStore.update`, `previewRollback`, and `rollback` throw unavailable; `SettingsDecoding` and private `SettingsJSON` are inside `Policy/SettingsEnvelope.swift`. The current schema2 root is exactly `{schemaVersion,revision,config}`. No persisted-two-volume or selective presentation-edit claim is possible against that checkpoint.

| Unit | Source entry prerequisite | Owns | Does not own |
|---|---|---|---|
| T06.1 registry/validation/resolution | Controller approval of this complete card and applicable preceding gate; an explicit split approval may admit pure work before storage integration | Seven new Policy files and three pure test files below | Store writer, app bridge, scheduler, authority ledger, adapter acceptance |
| T06.2 additive persistence | T05A.2 durable transaction/rollback AND T05A.3 single-writer cutover accepted; T06.1 accepted; additive-envelope review | Narrow envelope/decoder/change/rollback extension and real scratch-store RED | Replacing A.2's publication protocol or using legacy ConfigStore in parallel |
| T06.3 app revision handoff | T05A.3 single-store/bootstrap/ordering accepted; T06.2 accepted; explicit bridge review | Existing bridge's typed edit routing and immutable snapshot consumption | A second coordinator, revision engine, or public commit/capability initializer |

Unavailable Intel/8 GiB hardware does not block review or explicitly authorized source/test entry. It keeps full T06/product acceptance open. No automatic source entry follows completion of this documentation card.

**Exact files:**

- Create `TidyCore/Sources/TidyCore/Policy/PolicyDefaults.swift`: single registry assembly, exact factory templates, immutable scalar ceilings; no I/O.
- Create `TidyCore/Sources/TidyCore/Policy/PolicyValidator.swift`: typed key/layer/value validation and checked integer conversion; field-specific errors.
- Create `TidyCore/Sources/TidyCore/Policy/PolicyResolver.swift`: ordered replacement/intersection, provenance, selected-volume headroom and budget calculations.
- Create `TidyCore/Sources/TidyCore/Policy/FeatureSettings.swift`: feature/ecosystem/item IDs and their typed registry rows. No capabilities.
- Create `TidyCore/Sources/TidyCore/Policy/ScanSettings.swift`: scanner/cache/monitor rows and preset expansion.
- Create `TidyCore/Sources/TidyCore/Policy/CleanupSettings.swift`: cleanup/scope/headroom/budget rows, volume field type, per-item cleanup rows.
- Create `TidyCore/Sources/TidyCore/Policy/ExperienceSettings.swift`: rescue/notifications/maintenance/login/history/UI/export rows and preference document types.
- Create `TidyCore/Tests/TidyCoreTests/PolicyDefaultsTests.swift`, `PolicyResolutionTests.swift`, `PolicyValidationTests.swift`. Shared literal fixture/support below belongs at the bottom of `PolicyDefaultsTests.swift`, internal to the test target.
- T06.2 only: modify `TidyCore/Sources/TidyCore/Policy/SettingsEnvelope.swift` and `SettingsStore.swift`; create `TidyCore/Tests/TidyCoreTests/PolicyPersistenceTests.swift`.
- T06.3 only: modify the existing `ExecutionPolicyBridge` declaration and its existing owning source file after re-reading the landed A.3 implementation. Add tests to the A.3 unhosted `TidyAppModelTests/SharedSettingsWiringTests.swift`; do not invent a parallel bridge filename/constructor before that gate.

The four `*Settings` files contribute rows to `PolicyDefaults`, not four independent default stores. UI and Codable adapters consume this registry; they must not copy defaults. Tests intentionally repeat literal expectations independently.

## Small typed contract

These are proposed declarations, not existing source. All types below are `Equatable, Sendable`; persisted ones also conform to `Codable`. Swift code snippets omit repeated conformances only where explicitly marked. Public snapshot construction conveys no execution authority. No `Any`, arbitrary command text, custom validator closures, reflection, or general policy framework is needed.

```swift
public struct SettingID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}
public enum PolicyLayer: String, Codable, CaseIterable, Sendable {
    case global, profile, project, run
}
public enum ResolutionClass: String, Codable, Sendable { case preference, restriction, authority }
public enum AuthorityEffect: String, Codable, Sendable { case none, invalidate, consent }
public enum VolumeField: Equatable, Codable, Sendable {
    case inherit, automatic, fixedGiB(Int64)
}
public struct VolumeOverride: Equatable, Codable, Sendable {
    public var target: VolumeField
    public var warning: VolumeField
    public var clear: VolumeField
    public init(target: VolumeField, warning: VolumeField, clear: VolumeField) {
        self.target = target; self.warning = warning; self.clear = clear
    }
}
public enum SettingValue: Equatable, Codable, Sendable {
    case bool(Bool), integer(Int64), choice(String), strings([String]), null
    case volume(VolumeOverride)
}
public enum ValueKind: String, Codable, Sendable {
    case bool, integer, optionalInteger, choice, orderedIDs, setIDs, domains
    case optionalProjectID, volumeOverride, localIdentityList, clock
}
public enum Rule: Equatable, Codable, Sendable {
    case boolean, integer(Int64, Int64), optionalInteger(Int64, Int64)
    case choices([String]), identityList, domains, projectID, exclusions, pins
    case headroomTarget, headroomWarning, headroomClear, volumeOverride
    case budgetHigh, budgetLow, cards, ecosystemOrder, clock, quietEnd
}
public struct SettingDefinition: Equatable, Sendable {
    public let id: SettingID
    public let kind: ValueKind
    public let defaultValue: SettingValue
    public let rule: Rule
    public let resolution: ResolutionClass
    public let effect: AuthorityEffect
    public let layers: Set<PolicyLayer> // [] for machine-local A metadata
    public let group: String          // stable presentation group, localized label elsewhere
}
public struct PolicyValues: Equatable, Codable, Sendable {
    public var fields: [SettingID: SettingValue] // absent means inherit; no filled defaults
    public init(fields: [SettingID: SettingValue] = [:]) { self.fields = fields }
}
public struct SavedProfile: Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var values: PolicyValues
    public init(id: UUID, name: String, values: PolicyValues) {
        self.id = id; self.name = name; self.values = values
    }
}
public struct PolicyPreferences: Equatable, Codable, Sendable {
    public var global: PolicyValues
    public var profiles: [SavedProfile] // <=50; UUID unique; activation is session-only
    public var projects: [String: PolicyValues] // stable project IDs; no discovery
    public init(global: PolicyValues = .init(), profiles: [SavedProfile] = [],
                projects: [String: PolicyValues] = [:]) {
        self.global = global; self.profiles = profiles; self.projects = projects
    }
    public static func project(legacy: TidyConfig, saved: PolicyPreferences?) -> PolicyPreferences
    public mutating func selectPreset(_ preset: String, profileID: UUID? = nil) throws
}
public struct PolicyInputs: Equatable, Sendable {
    public var layers: [PolicyLayer: PolicyValues]
    public var selectedVolumeID: UUID?
    public var approvedVolumeIDs: Set<UUID> // internal read-only local-owner projection
    public var capacityBytes: Int64?
    public var logicalCPUCount: Int
    public var lowPower: Bool
    public var seriousThermal: Bool
    public var critical: Bool // critical thermal OR critical memory pressure
    public var mandatoryExclusions: Set<String> // supplied by protection owner, not import
    public init(layers: [PolicyLayer: PolicyValues], selectedVolumeID: UUID?,
                approvedVolumeIDs: Set<UUID>, capacityBytes: Int64?, logicalCPUCount: Int,
                lowPower: Bool, seriousThermal: Bool, critical: Bool,
                mandatoryExclusions: Set<String>) {
        self.layers = layers; self.selectedVolumeID = selectedVolumeID
        self.approvedVolumeIDs = approvedVolumeIDs; self.capacityBytes = capacityBytes
        self.logicalCPUCount = logicalCPUCount; self.lowPower = lowPower
        self.seriousThermal = seriousThermal; self.critical = critical
        self.mandatoryExclusions = mandatoryExclusions
    }
}
public enum FieldSource: Equatable, Sendable {
    case builtIn, layer(PolicyLayer), volume(PolicyLayer, UUID), immutable, localAuthority
}
public enum FieldReason: String, Sendable {
    case defaultValue, replaced, denied, union, strictestCap, automatic, inherited
    case preset, cpuCeiling, pressureCeiling, capacityUnavailable, invalidForVolume
    case unmatchedVolume, authorityUnavailable, protected, quarantine
    case notConfigured
}
public enum EffectiveValue: Equatable, Sendable {
    case stored(SettingValue), bytes(Int64), unavailable(FieldReason)
}
public struct EffectiveField: Equatable, Sendable {
    public let value: EffectiveValue
    public let sources: [FieldSource] // stable default/global/profile/project/run/H order
    public let reason: FieldReason
}
public enum ScanAdmission: Equatable, Sendable {
    case paused, userRequestedOnly, discretionaryAllowed
}
public struct EffectivePolicy: Equatable, Sendable {
    public let fields: [SettingID: EffectiveField]
    public let allowedFeatures: Set<String> // scheduling eligibility only, not mutation authority
    public let walkWorkers: Int           // 0 while critical/explicit pauseAll applies
    public let readOnlyProcesses: Int
    public let scanAdmission: ScanAdmission // observation only; never a scheduler permit
    public let manualBatchBytes: Int64
    public let manualBatchItems: Int
    public let exclusions: Set<String>
}
public struct PolicyFieldError: Error, Equatable, Sendable {
    public let id: SettingID
    public let reason: Reason
    public enum Reason: String, Sendable {
        case unknownKey, unsupportedLayer, authorityIsLocal, invalidType, outOfRange
        case invalidRelation, invalidIdentity, malformed, boundsUnavailable
    }
}
public enum PolicyDefaults {
    public static var rows: [SettingDefinition] { get } // finite rows, no dynamic fake catalog
    public static var hardLimits: [ImmutableLimit: Int64] { get }
    public static func itemRows(catalogID: String) -> [SettingDefinition]
    public static func volumeRow(id: UUID) -> SettingDefinition
    public static func factory(_ template: String) throws -> PolicyValues
}
public enum ImmutableLimit: String, Hashable, Sendable {
    case manualGiB, manualItems, automaticGiB, automaticItems, walkWorkers, commandJobs, rawHistoryMiB
}
public enum PolicyValidator {
    public static func validateStructure(_ values: PolicyValues, at layer: PolicyLayer) throws
    public static func validateEdit(_ values: PolicyValues, at layer: PolicyLayer,
        context: PolicyInputs) throws
    public static func integerInput(_ text: String, for id: SettingID) throws -> Int64
    public static func bytes(gib: Int64, for id: SettingID) throws -> Int64
}
public enum PolicyResolver {
    public static func resolve(_ inputs: PolicyInputs) throws -> EffectivePolicy
}
```

Known item membership is read only from `Set(CleanCatalog.allItems.map(\.id))` in `Catalog/CleanCatalog.swift`; `Model/CleanItem.swift` supplies `id`. Do not invoke `locate`, `discover`, `declaredRoot` or actions to read IDs. Tests use the actual existing `normal.extras.stale-node-modules` ID from `Catalog/CleanCatalog+Extras.swift`, never an invented accepted ID. All current effects remain subject to the existing CapabilityRegistry quarantine; membership means known data, not accepted mutation. Per-item values can be retained/displayed but cannot make an unaccepted item applicable for execution. `PolicyInputs` has only a read-only set for matching a volume; constructing that observation authorizes no I/O. A fields return `.unavailable(.authorityUnavailable)`/`.localAuthority` here. Real display state comes from owning local services later; no synthetic enabled A field is created. H is code-owned, not a writable `SettingID` family.

`validateStructure` checks known IDs, allowed layers, types, scalar ranges, UUID syntax and list bounds. A relation may be checked locally only when all its operands are explicitly co-present in that document: equal co-present quietStart/quietEnd throws `PolicyFieldError(id: notifications.quietEnd, reason: invalidRelation)`. A lone quietStart or quietEnd is checked for clock syntax/range, never against a built-in counterpart. It does not reject otherwise valid unmatched volume records or missing capacity. The storage actor calls this on every global/profile/project document, never probes a disk or chooses a volume.

Both `resolve` and `validateEdit` validate the effective non-capacity relations AFTER ordered layer replacement with defaults. The merged quietStart/quietEnd pair must be distinct even while quietHoursEnabled is false; equality always throws the same quietEnd/invalidRelation error, independent of which layer supplied either operand. Thus global start21:00 plus profile end21:00 rejects, while global end09:00 plus profile start08:00 succeeds. No layer is prematurely compared against the built-in end08:00.

`validateEdit` replaces the proposed whole layer in the supplied context, validates all resulting layer structures and merged non-capacity relations, then rejects invalid/unprovable bounds of edited headroom/budget fields with field-specific errors. Here edited means a present proposed value differs from the old value in `context.layers[layer]`; unchanged inert records may remain, and removing an override requires no proof of that volume's capacity. For each edited `headroom.volumeOverrides.<UUID>` record, first require that UUID equals selectedVolumeID and belongs to approvedVolumeIDs; otherwise throw at that exact override key with `boundsUnavailable`, before reading its capacity. A direct editor cannot validate volumeB using volumeA capacity. Matching identity but absent/nonpositive capacity also gives boundsUnavailable. An edit enabling a budget checks that budget's effective high/low as well: unavailable identity/capacity errors identify `budget.<id>.highGiB` with boundsUnavailable; a high outside capacity bounds identifies highGiB/outOfRange; low>=high identifies lowGiB/invalidRelation. Structural storage validation remains independent of selected volume. The pure resolver performs structural and merged non-capacity validation but reports missing/changed-capacity constraints as unavailable, not a thrown edit error. This permits lossless two-volume persistence without pretending the store has one capacity valid for both. Public constructors above construct inert data only; validation stays at these boundaries and no constructor grants local consent or execution authority.

### Wire form and revisions

Add optional top-level `preferences` to schema2. Absent means legacy-only projection, not malformed; explicit values must survive. Encode `PolicyValues.fields` as a JSON object keyed by exact raw stable IDs (custom Codable, not Swift's non-string-key alternating array). Encode values with explicit tagged cases; `volume` includes target/warning/clear tags. `null` is an explicit automatic value for generic optional headroom fields, not absence; volume `inherit` is distinct from `automatic`. Missing volume record remains absent. No A fields occur in this payload.

Exact extension shape:

```json
{"global":{"fields":{"headroom.targetGiB":{"integer":12},"headroom.volumeOverrides.11111111-1111-1111-1111-111111111111":{"volume":{"target":{"fixedGiB":30},"warning":{"inherit":true},"clear":{"automatic":true}}}}},"profiles":[],"projects":{}}
```

For scalar tags exactly one key is required: `bool`, `integer`, `choice`, `strings`, `null` (value `true`), or `volume`. The three `VolumeField` cases use exactly one `inherit:true`, `automatic:true`, or `fixedGiB:Int64`. No number strings, Float, NaN, Infinity, duplicate keys, unsupported layer placement, or arbitrary unknown envelope fields. Keep unknown imported keys in the import-preview's inert raw data, not executable preferences; direct persisted edits to unknown keys fail field-specific validation. An unrecognized typed extension/version opens recovery read-only rather than losing values on save. T06 is not the import UI task.

Every durable edit increments `SettingsEnvelope.revision` exactly once after successful publication. That is storage/preferences revision, not the coordinator's policy revision. `.none` edits persist without `beginPolicyUpdate`; `.invalidate` edits synchronously invalidate via the existing opaque ticket before asynchronous validation/save and commit only the latest durable snapshot. `.consent` is never a portable edit. Failure cannot restore old admission. Rollback/reset/import that alter any invalidating field invalidate even if another field is presentation-only. Conservative invalidation is acceptable until this selective path is reviewed, but cannot be reported as final presentation-only semantics.

The snapshot has no caller-set policy revision; existing coordinator tickets bind the immutable snapshot to the actual current policy revision. Storage revision, `EffectivePolicy`, and catalog membership never become authorization. A.3 pending queue bounds/order, disabled startup/recovery, no-main-thread I/O, latest-generation behavior and single-store ownership remain unchanged.

### Resolution algorithm and numeric behavior

1. Validate every explicit key/type/layer before any conversion. Validate Int64 token/range before multiplication; use `multipliedReportingOverflow`/`addingReportingOverflow`. For capacity fractions use division/remainder integer arithmetic (10%=capacity/10, 2%=capacity/50, 50%=capacity/2, 80%=high/5*4 + high%5*4/5). Never clamp persisted edits; only transient display controls may clamp.
2. Start with defaults as preferences/neutral restrictions. Visit global, profile, project, run exactly in that order. P replacement uses the last explicit value. Default false for `manualActions`/maintenance/budget means no opt-in, not a permanent deny: an explicit owning-global true may make policy eligibility true, but never bypass quarantine or grant A. Any explicit false at any applicable layer dominates later true. Explicit pauseAll dominates pauseDiscretionary; suppressHiddenSampling=true dominates false; exclusion/pin/domain protection sets union; explicit hard limits take min.
3. At EACH layer for selected approved volume: apply generic target/warning/clear first, then that layer's matching volume field. `inherit` leaves the value just produced by that layer's generic setting unchanged (or the lower layer if generic absent); `automatic` selects the formula; `fixedGiB` replaces. A later generic run value replaces an earlier volume-specific profile value. Unmatched/unapproved imported volume IDs remain persisted inert; no path matching, mounting, or inferred consent.
4. Resolve target `min(20*GiB,capacity/10)`; warning defaults to effective target; clear defaults to warning + `min(2*GiB,capacity/50)`. Fixed target 1...min(1024 GiB,capacity/2), fixed warning >=1 GiB, warning < clear <= capacity. Missing capacity leaves capacity-bound fields unavailable even for fixed values whose upper bound cannot be proved. A structurally valid saved value that becomes invalid after volume selection/capacity change is unavailable until corrected, never silently clamped. Edits requiring a presently unprovable bound fail `boundsUnavailable`; retained inert unmatched records can round-trip.
5. Budget high uses the exact inactive templates and must be 1...min(1024 GiB,capacity/2); low's null uses floor(80% of high bytes), not a rounded GiB integer. Explicit low is an integer GiB >=0 and <high. High1 GiB gives automatic low858993459 bytes. No selected volume or an unapproved selected UUID makes high/low unavailable(unmatchedVolume); an approved selected UUID with absent/nonpositive capacity gives capacityUnavailable. Invalid high/low bounds give invalidForVolume. In all three cases effective enabled is false even with owning-global true, and high/low carry the same unavailable reason; sources retain their contributing values plus immutable. Valid configured high fields remain stored integer GiB, low fields report bytes. Null unconfigured high/low remains notConfigured and disabled. Invalid small-volume templates remain disabled/unavailable, with a smaller-value request. No invented template for android/ides/git/data/other.
6. Apply immutable constraints: requested manual 10 GiB may become40; explicit8 cap limits40 to8; ceiling100 GiB/100items always applies. A readiness target is not a cleanup batch: xcode target15 plus cleanup hard cap8 remains target15 with executable batch<=8. Workers <=4 and logical CPU count; read-only commands <=2 and total command jobs including a mutator <=2 (scheduler owns actual permits). Critical pauses scans; low power/serious allows <=1 worker and no discretionary scans, or zero for pauseAll. The resolver exposes eligibility; it never starts/cancels jobs itself. Disabled features have no new scheduled work in later scheduler integration; an in-flight mutator drains safely.
7. Eco expands to1/1, Balanced2/2, Custom uses retained `scan.requestedWorkers`/`scan.readOnlyProcesses` values. Those two existing fields are the only stored Custom counts; there are no duplicate custom-count members. `selectPreset` validates the enum and changes ONLY `scan.preset` in global values or the exact saved profile UUID, preserving both count fields. Missing profile UUID rejects. Effective count rows show the preset expansion and preset-key source; actual worker/process fields then apply H/pressure caps. Factory count1/1 overrides are exact template values; switching the global preset does not erase stored4/2. Profile deactivation restores underlying global values.
8. Return every field's effective/default/source/range/reason using the finite rules below. `scope.excludedRoots` effective field includes the canonical sorted union INCLUDING mandatory protections and `.immutable` provenance; its independent registry default remains empty. R records every contributing explicit restriction and H records the limiting immutable source; equal-value later P replacements still identify their actual source. Imported pins cannot unpin existing protection; removing a local restriction requires editing its owning layer, never child replacement.

**Exact observation rules (no new registry keys or generic provenance engine):**

- All sources are de-duplicated in builtIn, global, profile, project, run, immutable order; within one layer generic precedes matching volume. A fields use localAuthority only. P uses its last explicit source with replaced, even when equal to the built-in/prior value; without an explicit source it uses builtIn/defaultValue unless a specific automatic/inherited/preset rule applies.
- Boolean enable R rows retain every explicit contributing layer. Default-false manualActions/maintenance/budget needs global true: without it include builtIn and report false/denied when a child tries true; an untouched false row stays builtIn/defaultValue. Global true alone reports true/replaced. Any explicit false makes false/denied and retains all explicit layers, including later true; builtIn is omitted when global explicitly supplies the owning value. Default-true rows use the same false dominance without a global opt-in requirement. These are policy observations, never effects.
- Exclusions, pins and domains return sorted unique strings, every explicit layer source and union. Nonempty mandatory exclusions add immutable and make the exclusion reason protected; an untouched empty set remains builtIn/defaultValue. Null hard caps contribute no restriction; non-null byte/item caps retain every contributing layer, return the minimum stored integer and strictestCap. Requested batch fields expose the final capped stored integer, retaining the winning request source plus all contributing hard-cap layers; strictestCap applies only when that cap reduces the request. Append immutable only when H strictly reduces the result. The scalar manualBatchBytes/items agree with those final fields.
- Eco/Balanced count fields use the winning scan.preset source (builtIn if absent) and preset, ignoring but preserving stored Custom counts. Custom count fields use the winning count-key source and replaced/defaultValue. Apply CPU/H then pressure to those effective count fields; append immutable only for a strict numeric reduction. A CPU reduction uses cpuCeiling; a further pressure reduction uses pressureCeiling. Equal limits do not invent a limiting source. This field describes the currently usable count, not a second stored Custom value.
- scanAdmission is discretionaryAllowed when no pressure observation applies, regardless of a configured pauseAll preference. Critical always makes paused with both counts0. Otherwise, an active lowPower or seriousThermal observation whose resolved rule is pauseAll makes paused with both counts0. Otherwise either active observation makes userRequestedOnly with walkWorkers<=1 (readOnlyProcesses keeps its existing <=2 bound). No active observation means discretionaryAllowed. Simultaneous observations take the most restrictive result. The scheduler must later consume this observation in addition to counts; this card implements no scheduling or resume timer. The two scan.on* fields still describe resolved configuration, not whether pressure is currently active.
- Automatic budget low sources combine the resolved high source and low's automatic-selection source (builtIn for default null), in the same order, with automatic. Budget invalid/unavailable observations append immutable to their existing high/low/enable sources and use the precise invalid/unavailable reason. They do not overwrite stored preferences.

## Complete registry schema and independent fixture

The table below is the independent RED expectation fixture. `G`=global/profile, `L`=global/profile/project/run, `A`=machine-local metadata only. Per-item age/size/retention are cleanup preferences, therefore L. Feature/ecosystem/item enables are G restrictions. `P/R/A`, effect `i/n/c` mean preference/restriction/authority and invalidate/none/consent. Group is the prefix before the first dot except `item`=>cleanup, `ecosystem`=>features, `feature`=>features, `scope`=>scope, `app`=>experience, `export`=>data. This is explicit presentation grouping, not authorization.

Expand finite families exactly as follows; no aliasing arbitrary strings:

- `F` = headroom,buildPrep,projects,rescue,ecosystems,budgets,history; plus explicit maintenance row.
- `E` = apple,android,node,languages,homebrew,docker,ides,models,git,data (also default UI ecosystem order).
- `B` = apple-derived-data,apple-simulators,android,docker,package-caches,models,ides,git,data,other.
- `I` = a locally known catalogID; no defaults instantiate an unknown catalog or make it accepted.
- `V` = UUID, matched only to the approved local volume set.

Value notation: `b` bool, `i` integer, `n` explicit null, `e` enum/string, `s` string list; `v` absent record descriptor. Rule notation is the exact `Rule` case, with inclusive ranges or exhaustive choices. `local` describes identity metadata only; no portable URL/string can satisfy consent. Every row includes default/provenance via the default assertion below; parameter families are tested with one valid literal ID and a separate unknown-ID rejection.

```swift
let registryFixture = """
# id|kind|default|rule|class|effect|layers
feature.F|bool|b:true|boolean|R|i|G
feature.maintenance|bool|b:false|boolean|R|i|G
ecosystem.E.inventory|bool|b:true|boolean|R|i|G
ecosystem.E.manualActions|bool|b:false|boolean|R|i|G
item.I.enabled|bool|b:true|boolean|R|i|G
scope.projectRoots|localIdentityList|s:|identityList|A|c|A
scope.externalVolumes|localIdentityList|s:|identityList|A|c|A
scope.excludedRoots|setIDs|s:|exclusions|R|i|L
scope.pinnedProjects|setIDs|s:|pins|R|i|L
scope.currentProject|optionalProjectID|n|projectID|P|i|L
browsers.keepCookieDomains|domains|s:|domains|R|i|G
simulators.approvedDeletionUDIDs|localIdentityList|s:|identityList|A|c|A
tools.approvedExecutables|localIdentityList|s:|identityList|A|c|A
docker.approvedEndpoints|localIdentityList|s:|identityList|A|c|A
cleanup.inactiveDays|integer|i:60|integer:7:365|P|i|L
cleanup.transcriptDays|integer|i:45|integer:7:365|P|i|L
cleanup.recentProtectionDays|integer|i:7|integer:1:90|P|i|L
cleanup.warmProjectCount|integer|i:5|integer:0:50|P|i|L
cleanup.minimumCandidateMiB|integer|i:100|integer:1:102400|P|i|L
cleanup.minimumItemMiB|integer|i:1|integer:0:102400|P|i|L
cleanup.retainRecentArtifacts|integer|i:2|integer:0:100|P|i|L
cleanup.costCeiling|choice|e:low|choices:low,medium,high|P|i|L
cleanup.requestedBatchGiB|integer|i:10|integer:1:100|P|i|L
cleanup.requestedBatchItems|integer|i:20|integer:1:100|P|i|L
cleanup.hardBatchGiB|optionalInteger|n|optionalInteger:1:100|R|i|L
cleanup.hardBatchItems|optionalInteger|n|optionalInteger:1:100|R|i|L
cleanup.manualInactiveAcknowledgementMinutes|integer|i:10|integer:1:30|P|i|L
scan.preset|choice|e:eco|choices:eco,balanced,custom|P|i|G
scan.requestedWorkers|integer|i:1|integer:1:4|P|i|G
scan.readOnlyProcesses|integer|i:1|integer:1:2|P|i|G
scan.defaultScope|choice|e:quick|choices:quick,selectedProjects|P|i|G
scan.sliceSeconds|integer|i:300|integer:30:1800|P|i|G
scan.uiBatchesPerSecond|integer|i:4|integer:1:4|P|n|G
scan.onLowPower|choice|e:pauseDiscretionary|choices:pauseAll,pauseDiscretionary|R|i|G
scan.onSeriousThermal|choice|e:pauseDiscretionary|choices:pauseAll,pauseDiscretionary|R|i|G
scan.resumeAfterCriticalSeconds|integer|i:120|integer:120:900|P|i|G
scan.cacheEnabled|bool|b:true|boolean|P|i|G
scan.cacheMiB|integer|i:64|integer:8:128|P|i|G
scan.cacheExpiryHours|integer|i:24|integer:1:48|P|i|G
monitor.backgroundEnabled|bool|b:false|boolean|A|c|A
monitor.visibleIntervalSeconds|integer|i:5|integer:2:60|P|n|G
monitor.hiddenIntervalSeconds|integer|i:60|integer:60:900|P|n|G
monitor.rawHistoryEnabled|bool|b:false|boolean|P|n|G
monitor.rawHistoryHours|integer|i:24|integer:1:24|P|n|G
headroom.targetGiB|optionalInteger|n|headroomTarget|P|i|L
headroom.warningGiB|optionalInteger|n|headroomWarning|P|i|L
headroom.clearGiB|optionalInteger|n|headroomClear|P|i|L
headroom.volumeOverrides.V|volumeOverride|v|volumeOverride|P|i|L
rescue.approvedApplications|localIdentityList|s:|identityList|A|c|A
rescue.showAdvancedMemoryActions|bool|b:false|boolean|P|i|G
rescue.quitTimeoutSeconds|integer|i:15|integer:5:60|P|i|G
budget.B.enabled|bool|b:false|boolean|R|i|G
budget.apple-derived-data.highGiB|optionalInteger|i:15|budgetHigh|P|i|G
budget.apple-simulators.highGiB|optionalInteger|i:25|budgetHigh|P|i|G
budget.android.highGiB|optionalInteger|n|budgetHigh|P|i|G
budget.docker.highGiB|optionalInteger|i:30|budgetHigh|P|i|G
budget.package-caches.highGiB|optionalInteger|i:10|budgetHigh|P|i|G
budget.models.highGiB|optionalInteger|i:50|budgetHigh|P|i|G
budget.ides.highGiB|optionalInteger|n|budgetHigh|P|i|G
budget.git.highGiB|optionalInteger|n|budgetHigh|P|i|G
budget.data.highGiB|optionalInteger|n|budgetHigh|P|i|G
budget.other.highGiB|optionalInteger|n|budgetHigh|P|i|G
budget.B.lowGiB|optionalInteger|n|budgetLow|P|i|G
notifications.enabled|bool|b:false|boolean|A|c|A
notifications.pressureSustainSeconds|integer|i:60|integer:30:600|P|n|G
notifications.recoverySeconds|integer|i:120|integer:60:900|P|n|G
notifications.cooldownMinutes|integer|i:60|integer:15:1440|P|n|G
notifications.quietHoursEnabled|bool|b:false|boolean|P|n|G
notifications.quietStart|clock|e:22:00|clock|P|n|G
notifications.quietEnd|clock|e:08:00|quietEnd|P|n|G
maintenance.mode|choice|e:off|choices:off,notifyOnly,authorizedCaches|A|c|A
maintenance.maxGiB|integer|i:1|integer:1:5|A|c|A
maintenance.maxItems|integer|i:5|integer:1:20|A|c|A
maintenance.deadlineSeconds|integer|i:60|integer:30:120|A|c|A
maintenance.minimumAgeDays|integer|i:30|integer:30:365|A|c|A
maintenance.minimumIntervalHours|integer|i:24|integer:24:168|A|c|A
app.launchAtLogin|bool|b:false|boolean|A|c|A
history.enabled|bool|b:true|boolean|P|n|G
history.retentionDays|integer|i:30|integer:1:90|P|n|G
history.maxMiB|integer|i:10|integer:1:50|P|n|G
ui.density|choice|e:compact|choices:compact,detailed|P|n|G
ui.units|choice|e:binary|choices:binary,decimal|P|n|G
ui.cards|orderedIDs|s:disk,memoryPressure,swap,thermal,power|cards|P|n|G
ui.ecosystemOrder|orderedIDs|s:apple,android,node,languages,homebrew,docker,ides,models,git,data|ecosystemOrder|P|n|G
monitor.suppressHiddenSampling|bool|b:false|boolean|R|n|G
ui.showBadges|bool|b:true|boolean|P|n|G
ui.advancedSettings|bool|b:false|boolean|P|n|G
export.redactDiagnostics|bool|b:true|boolean|P|n|G
item.I.inactiveDays|optionalInteger|n|optionalInteger:7:365|P|i|L
item.I.minimumItemMiB|optionalInteger|n|optionalInteger:0:102400|P|i|L
item.I.retainRecentArtifacts|optionalInteger|n|optionalInteger:0:100|P|i|L
"""
```

No rule loses these semantic constraints: approved roots local/non-provider/non-network/non-system; excluded roots canonical and union mandatory exclusions; pins cannot be removed by import; domains exact validated domain text; UUID/executable/socket/application authorities local identity only; transcript memory directories always protected; recency running/pinned always protected; unknown bytes never become eligible zero; retention only mapped inactive artifacts, never archives/models/databases; acknowledgement never unattended eligibility; read-only jobs share total2 permits; cache64 MiB includes WAL/temp and is not background consent; raw history cap5 MiB; quiet start/end distinct and DST-aware civil time; maintenance deadline is scheduling only; history bounds optional completed reports only and never unfinished recovery evidence; export even with redaction false excludes credentials/cookies/env/argv/remotes. T04's separately approved ledger/diagnostic budget remains outside `history.maxMiB`.

Factory templates (literal test expectation, omitted keys inherit): xcode target15, android20, flutter20, web5, localAI30; all have `scan.preset=eco`, workers1, processes1. xcode/android/flutter/web have cost low and warm5; localAI does not add these two keys. Order moves apple first / android first / android then apple / node first / models first respectively, preserving the remaining registry order. Battery has no target/order/cost/warm override: Eco1/1, `scan.onLowPower=pauseAll`, `monitor.suppressHiddenSampling=true`, `scan.defaultScope=quick`. No profile contains A or H or enables maintenance/rescue. Stored UUIDs are independent of stable factory template keys.

## T06.1 — Complete RED test code

- [ ] Add the declarations and tests only after entry approval; first compile should fail because the Policy types do not exist. Do not run these snippets during this documentation task.
- [ ] In `PolicyDefaultsTests.swift`, include the complete `registryFixture` declaration above verbatim, followed by the complete parser and assertions below. This is one independent literal fixture, not runtime reading the production registry/spec; no expected values are computed from production defaults.

```swift
import Foundation
import Testing
@testable import TidyCore

let GiB: Int64 = 1_073_741_824
let volumeA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let volumeB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
let ecosystems = "apple,android,node,languages,homebrew,docker,ides,models,git,data".components(separatedBy: ",")
let budgets = "apple-derived-data,apple-simulators,android,docker,package-caches,models,ides,git,data,other".components(separatedBy: ",")
func key(_ s: String) -> SettingID { .init(rawValue: s) }
func values(_ pairs: [String: SettingValue]) -> PolicyValues {
    .init(fields: Dictionary(uniqueKeysWithValues: pairs.map { (key($0.key), $0.value) }))
}
func input(_ layers: [PolicyLayer: PolicyValues] = [:], capacity: Int64? = 200 * GiB,
           selected: UUID? = volumeA, approved: Set<UUID> = [volumeA, volumeB]) -> PolicyInputs {
    PolicyInputs(layers: layers, selectedVolumeID: selected, approvedVolumeIDs: approved,
        capacityBytes: capacity, logicalCPUCount: 8, lowPower:false, seriousThermal:false, critical:false,
        mandatoryExclusions: ["/fixture/protected"])
}
func fixtureValue(_ s: String) -> SettingValue {
    if s == "n" || s == "v" { return .null }
    let p = s.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    switch p[0] {
    case "b": return .bool(p[1] == "true")
    case "i": return .integer(Int64(p[1])!)
    case "e": return .choice(p[1])
    case "s": return .strings(p[1].isEmpty ? [] : p[1].components(separatedBy: ","))
    default: preconditionFailure("Bad independent fixture")
    }
}
func fixtureRule(_ s: String) -> Rule {
    let p = s.components(separatedBy: ":")
    switch p[0] {
    case "boolean": return .boolean
    case "integer": return .integer(Int64(p[1])!, Int64(p[2])!)
    case "optionalInteger": return .optionalInteger(Int64(p[1])!, Int64(p[2])!)
    case "choices": return .choices(p[1].components(separatedBy: ","))
    case "identityList": return .identityList
    case "domains": return .domains
    case "projectID": return .projectID
    case "exclusions": return .exclusions
    case "pins": return .pins
    case "headroomTarget": return .headroomTarget
    case "headroomWarning": return .headroomWarning
    case "headroomClear": return .headroomClear
    case "volumeOverride": return .volumeOverride
    case "budgetHigh": return .budgetHigh
    case "budgetLow": return .budgetLow
    case "cards": return .cards
    case "ecosystemOrder": return .ecosystemOrder
    case "clock": return .clock
    case "quietEnd": return .quietEnd
    default: preconditionFailure("Bad independent rule")
    }
}
func fixtureRows() -> [SettingDefinition] {
    registryFixture.split(separator: "\n").filter { !$0.hasPrefix("#") }.flatMap { line in
        let p = line.components(separatedBy: "|")
        let expansions: [(String, [String])] = [
            (".F", "headroom,buildPrep,projects,rescue,ecosystems,budgets,history".components(separatedBy: ",")),
            (".E.", ecosystems), (".B.", budgets), (".I.", ["normal.extras.stale-node-modules"]),
            (".V", [volumeA.uuidString])]
        var ids = [p[0]]
        for (marker, members) in expansions where p[0].contains(marker) {
            let trailing = marker.hasSuffix(".") ? "." : ""
            ids = members.map { p[0].replacingOccurrences(of: marker, with: "." + $0 + trailing) }
        }
        return ids.map { id in
            let prefix = String(id.split(separator: ".")[0])
            let group = ["feature":"features", "ecosystem":"features", "item":"cleanup",
                         "app":"experience", "export":"data"][prefix] ?? prefix
            return SettingDefinition(id: key(id), kind: ValueKind(rawValue: p[1])!,
                defaultValue: fixtureValue(p[2]), rule: fixtureRule(p[3]),
                resolution: ["P":.preference, "R":.restriction, "A":.authority][p[4]]!,
                effect: ["i":.invalidate, "n":.none, "c":.consent][p[5]]!,
                layers: p[6] == "A" ? [] : p[6] == "G" ? [.global,.profile] : Set(PolicyLayer.allCases),
                group: group)
        }
    }
}
@Suite struct PolicyDefaultsTests {
    @Test func everyRegistryRowAndDefaultIsIndependent() throws {
        let expected = fixtureRows()
        let actual = PolicyDefaults.rows + PolicyDefaults.itemRows(catalogID: "normal.extras.stale-node-modules") +
            [PolicyDefaults.volumeRow(id: volumeA)]
        #expect(Set(actual.map(\.id)).count == actual.count)
        #expect(actual.sorted { $0.id.rawValue < $1.id.rawValue } == expected.sorted { $0.id.rawValue < $1.id.rawValue })
        let snapshot = try PolicyResolver.resolve(input())
        for row in expected where row.kind != .volumeOverride {
            let field = try #require(snapshot.fields[row.id])
            if row.resolution == .authority {
                #expect(field == EffectiveField(value: .unavailable(.authorityUnavailable), sources: [.localAuthority], reason: .authorityUnavailable))
            } else if row.id.rawValue == "scope.excludedRoots" {
                #expect(field.value == .stored(.strings(["/fixture/protected"])))
                #expect(field.sources == [.immutable]); #expect(field.reason == .protected)
            } else if row.id.rawValue.hasPrefix("item.") && row.defaultValue == .null {
                let inherited: [String:Int64] = ["inactiveDays":60,"minimumItemMiB":1,"retainRecentArtifacts":2]
                let suffix = String(row.id.rawValue.split(separator:".").last!)
                #expect(field.value == .stored(.integer(inherited[suffix]!)))
                #expect(field.sources == [.builtIn]); #expect(field.reason == .inherited)
            } else if row.id.rawValue.hasPrefix("headroom.") {
                let expectedBytes: [String:Int64] = ["headroom.targetGiB":20*GiB,"headroom.warningGiB":20*GiB,"headroom.clearGiB":22*GiB]
                #expect(field.value == .bytes(expectedBytes[row.id.rawValue]!))
                #expect(field.sources == [.builtIn]); #expect(field.reason == .automatic)
            } else if row.id.rawValue.hasPrefix("budget.") && row.id.rawValue.hasSuffix("lowGiB") {
                let lows: [String:Int64] = ["apple-derived-data":12,"apple-simulators":20,"docker":24,"package-caches":8,"models":40]
                let id = row.id.rawValue.components(separatedBy: ".")[1]
                #expect(field.value == (lows[id].map { .bytes($0*GiB) } ?? .unavailable(.notConfigured)))
                #expect(field.sources == [.builtIn])
            } else if row.id.rawValue.hasPrefix("budget.") && row.id.rawValue.hasSuffix("highGiB") && row.defaultValue == .null {
                #expect(field.value == .unavailable(.notConfigured)); #expect(field.sources == [.builtIn])
            } else {
                #expect(field.value == .stored(row.defaultValue)); #expect(field.sources == [.builtIn])
            }
        }
        #expect(snapshot.manualBatchBytes == 10*GiB); #expect(snapshot.manualBatchItems == 20)
        #expect(snapshot.walkWorkers == 1); #expect(snapshot.readOnlyProcesses == 1)
        #expect(snapshot.exclusions == ["/fixture/protected"])
        #expect(snapshot.fields[key("headroom.volumeOverrides.\(volumeA.uuidString)")] == nil)
        #expect(PolicyDefaults.hardLimits == [.manualGiB:100,.manualItems:100,
            .automaticGiB:5,.automaticItems:20,.walkWorkers:4,.commandJobs:2,.rawHistoryMiB:5])
    }
    @Test func exactFactoryProfiles() throws {
        let cases: [(String, Int64, [String], Bool)] = [
            ("xcode",15,["apple"],true),("android",20,["android"],true),
            ("flutter",20,["android","apple"],true),("web",5,["node"],true),
            ("localAI",30,["models"],false)]
        for (name, target, first, cost) in cases {
            var expected: [String:SettingValue] = ["headroom.targetGiB":.integer(target),
                "scan.preset":.choice("eco"),"scan.requestedWorkers":.integer(1),
                "scan.readOnlyProcesses":.integer(1),
                "ui.ecosystemOrder":.strings(first + ecosystems.filter { !first.contains($0) })]
            if cost { expected["cleanup.costCeiling"] = .choice("low"); expected["cleanup.warmProjectCount"] = .integer(5) }
            #expect(try PolicyDefaults.factory(name) == values(expected))
        }
        #expect(try PolicyDefaults.factory("battery") == values([
            "scan.preset":.choice("eco"),"scan.requestedWorkers":.integer(1),
            "scan.readOnlyProcesses":.integer(1),"scan.onLowPower":.choice("pauseAll"),
            "monitor.suppressHiddenSampling":.bool(true),"scan.defaultScope":.choice("quick")]))
    }
    @Test func legacyProjectionPreservesNondefaultsWithoutAuthority() throws {
        var legacy = TidyConfig(schemaVersion:2)
        legacy.staleNodeModulesThresholdDays = 90
        legacy.transcriptAgeThresholdDays = 120
        legacy.keepCookieDomains = ["keep.invalid"]
        legacy.gitRoots = ["/fixture/legacy-root"]
        legacy.appsApprovedForQuit = ["Old application name"]
        legacy.simulatorsApprovedForDeletion = ["Old simulator name"]
        legacy.allowRestartToReclaimSwap = true
        let projected = PolicyPreferences.project(legacy:legacy,saved:nil)
        #expect(projected.global.fields == values([
            "cleanup.transcriptDays":.integer(120),
            "item.normal.extras.stale-node-modules.inactiveDays":.integer(90),
            "browsers.keepCookieDomains":.strings(["keep.invalid"]),
            "rescue.showAdvancedMemoryActions":.bool(true)]).fields)
        let result = try PolicyResolver.resolve(input([.global:projected.global]))
        #expect(result.fields[key("cleanup.transcriptDays")]?.value == .stored(.integer(120)))
        #expect(result.fields[key("cleanup.inactiveDays")]?.value == .stored(.integer(60)))
        #expect(result.fields[key("item.normal.extras.stale-node-modules.inactiveDays")]?.value == .stored(.integer(90)))
        #expect(result.fields[key("scope.projectRoots")]?.value == .unavailable(.authorityUnavailable))
        #expect(result.fields[key("rescue.approvedApplications")]?.value == .unavailable(.authorityUnavailable))
        var newer = projected
        newer.global.fields[key("cleanup.transcriptDays")] = .integer(150)
        #expect(PolicyPreferences.project(legacy:legacy,saved:newer).global.fields[key("cleanup.transcriptDays")] == .integer(150))
    }
    @Test func presetSwitchesRetainOneStoredCustomPair() throws {
        var preferences = PolicyPreferences(global:values([
            "scan.preset":.choice("custom"),"scan.requestedWorkers":.integer(4),
            "scan.readOnlyProcesses":.integer(2)]),profiles:[],projects:[:])
        for (preset, workers, processes) in [("eco",1,1),("balanced",2,2),("custom",4,2)] {
            try preferences.selectPreset(preset)
            #expect(preferences.global.fields[key("scan.requestedWorkers")] == .integer(4))
            #expect(preferences.global.fields[key("scan.readOnlyProcesses")] == .integer(2))
            let result = try PolicyResolver.resolve(input([.global:preferences.global]))
            #expect(result.walkWorkers == workers); #expect(result.readOnlyProcesses == processes)
        }
        let profileID = UUID(uuidString:"33333333-3333-3333-3333-333333333333")!
        preferences.profiles = [SavedProfile(id:profileID,name:"Fixture",values:preferences.global)]
        try preferences.selectPreset("eco",profileID:profileID)
        #expect(preferences.global.fields[key("scan.preset")] == .choice("custom"))
        #expect(preferences.profiles[0].values.fields[key("scan.requestedWorkers")] == .integer(4))
        try preferences.selectPreset("custom",profileID:profileID)
        #expect(preferences.profiles[0].values.fields[key("scan.preset")] == .choice("custom"))
    }
}
```

- [ ] Add `PolicyResolutionTests.swift` exactly below. These test pure values, not authority, hardware, or scheduler execution.

```swift
import Foundation
import Testing
@testable import TidyCore
@Suite struct PolicyResolutionTests {
    @Test func defaultFalseRequiresOwningGlobalAndFalseDominates() throws {
        for id in ["ecosystem.docker.manualActions", "feature.maintenance", "budget.docker.enabled"] {
            let enabled = try PolicyResolver.resolve(input([.global:values([id:.bool(true)])]))
            #expect(enabled.fields[key(id)] == EffectiveField(value:.stored(.bool(true)),
                sources:[.layer(.global)],reason:.replaced))
            let childOnly = try PolicyResolver.resolve(input([.profile:values([id:.bool(true)])]))
            #expect(childOnly.fields[key(id)] == EffectiveField(value:.stored(.bool(false)),
                sources:[.builtIn,.layer(.profile)],reason:.denied))
            let denied = try PolicyResolver.resolve(input([
                .global:values([id:.bool(false)]),.profile:values([id:.bool(true)])]))
            #expect(denied.fields[key(id)] == EffectiveField(value:.stored(.bool(false)),
                sources:[.layer(.global),.layer(.profile)],reason:.denied))
        }
    }
    @Test func unionsCapsAndEqualReplacementsHaveLiteralProvenance() throws {
        let result = try PolicyResolver.resolve(input([
            .global:values(["scope.excludedRoots":.strings(["/fixture/z"]),
                "scope.pinnedProjects":.strings(["project-b"]),
                "browsers.keepCookieDomains":.strings(["b.invalid"]),
                "cleanup.requestedBatchGiB":.integer(40),"cleanup.requestedBatchItems":.integer(80),
                "cleanup.hardBatchGiB":.integer(8),"cleanup.hardBatchItems":.integer(10),
                "ui.units":.choice("binary")]),
            .profile:values(["scope.excludedRoots":.strings(["/fixture/a","/fixture/z"]),
                "scope.pinnedProjects":.strings(["project-a","project-b"]),
                "browsers.keepCookieDomains":.strings(["a.invalid","b.invalid"]),
                "cleanup.hardBatchGiB":.integer(12),"cleanup.hardBatchItems":.integer(6),
                "ui.units":.choice("binary")])]))
        #expect(result.fields[key("scope.excludedRoots")] == EffectiveField(
            value:.stored(.strings(["/fixture/a","/fixture/protected","/fixture/z"])),
            sources:[.layer(.global),.layer(.profile),.immutable],reason:.protected))
        #expect(result.fields[key("scope.pinnedProjects")] == EffectiveField(
            value:.stored(.strings(["project-a","project-b"])),
            sources:[.layer(.global),.layer(.profile)],reason:.union))
        #expect(result.fields[key("browsers.keepCookieDomains")] == EffectiveField(
            value:.stored(.strings(["a.invalid","b.invalid"])),
            sources:[.layer(.global),.layer(.profile)],reason:.union))
        for (id,amount) in [("cleanup.hardBatchGiB",Int64(8)),("cleanup.hardBatchItems",6),
                            ("cleanup.requestedBatchGiB",8),("cleanup.requestedBatchItems",6)] {
            #expect(result.fields[key(id)] == EffectiveField(value:.stored(.integer(amount)),
                sources:[.layer(.global),.layer(.profile)],reason:.strictestCap))
        }
        #expect(result.manualBatchBytes == 8*GiB); #expect(result.manualBatchItems == 6)
        #expect(result.fields[key("ui.units")] == EffectiveField(value:.stored(.choice("binary")),
            sources:[.layer(.profile)],reason:.replaced))
    }
    @Test func scanAdmissionAndNumericProvenanceAreDistinct() throws {
        var eco = input()
        let normal = try PolicyResolver.resolve(eco)
        #expect(normal.scanAdmission == .discretionaryAllowed)
        #expect(normal.fields[key("scan.requestedWorkers")] == EffectiveField(
            value:.stored(.integer(1)),sources:[.builtIn],reason:.preset))
        eco.lowPower = true
        let lowEco = try PolicyResolver.resolve(eco)
        #expect(lowEco.scanAdmission == .userRequestedOnly)
        #expect(lowEco.walkWorkers == 1); #expect(lowEco.readOnlyProcesses == 1)
        #expect(lowEco.fields[key("scan.requestedWorkers")] == EffectiveField(
            value:.stored(.integer(1)),sources:[.builtIn],reason:.preset))
        var i = input([.global:values(["scan.preset":.choice("custom"),
            "scan.requestedWorkers":.integer(4),"scan.readOnlyProcesses":.integer(2)]),
            .profile:values(["scan.preset":.choice("balanced")])])
        let balanced = try PolicyResolver.resolve(i)
        for id in ["scan.requestedWorkers","scan.readOnlyProcesses"] {
            #expect(balanced.fields[key(id)] == EffectiveField(value:.stored(.integer(2)),
                sources:[.layer(.profile)],reason:.preset))
        }
        i.logicalCPUCount = 1
        let cpu = try PolicyResolver.resolve(i)
        #expect(cpu.fields[key("scan.requestedWorkers")] == EffectiveField(value:.stored(.integer(1)),
            sources:[.layer(.profile),.immutable],reason:.cpuCeiling))
        i.logicalCPUCount = 8; i.lowPower = true
        let low = try PolicyResolver.resolve(i)
        #expect(low.scanAdmission == .userRequestedOnly)
        #expect(low.fields[key("scan.requestedWorkers")] == EffectiveField(value:.stored(.integer(1)),
            sources:[.layer(.profile),.immutable],reason:.pressureCeiling))
        #expect(low.fields[key("scan.readOnlyProcesses")] == EffectiveField(value:.stored(.integer(2)),
            sources:[.layer(.profile)],reason:.preset))
        i.layers[.profile] = values(["scan.preset":.choice("balanced"),
            "scan.onLowPower":.choice("pauseAll")])
        i.lowPower = false
        #expect(try PolicyResolver.resolve(i).scanAdmission == .discretionaryAllowed)
        i.lowPower = true; i.seriousThermal = true
        let paused = try PolicyResolver.resolve(i)
        #expect(paused.scanAdmission == .paused)
        #expect(paused.walkWorkers == 0); #expect(paused.readOnlyProcesses == 0)
        for id in ["scan.requestedWorkers","scan.readOnlyProcesses"] {
            #expect(paused.fields[key(id)] == EffectiveField(value:.stored(.integer(0)),
                sources:[.layer(.profile),.immutable],reason:.pressureCeiling))
        }
        i.layers[.profile] = values(["scan.onSeriousThermal":.choice("pauseAll")])
        #expect(try PolicyResolver.resolve(i).scanAdmission == .paused)
        i.layers[.profile] = values([:])
        #expect(try PolicyResolver.resolve(i).scanAdmission == .userRequestedOnly)
        i.lowPower = false; i.seriousThermal = false; i.critical = true
        let critical = try PolicyResolver.resolve(i)
        #expect(critical.scanAdmission == .paused)
        #expect(critical.walkWorkers == 0); #expect(critical.readOnlyProcesses == 0)
        for id in ["scan.requestedWorkers","scan.readOnlyProcesses"] {
            #expect(critical.fields[key(id)] == EffectiveField(value:.stored(.integer(0)),
                sources:[.layer(.global),.immutable],reason:.pressureCeiling))
        }
    }
    @Test func budgetByteRoundingAndUnavailableObservations() throws {
        let fractional = try PolicyResolver.resolve(input([.global:values([
            "budget.docker.enabled":.bool(true),"budget.docker.highGiB":.integer(1)])]))
        #expect(fractional.fields[key("budget.docker.highGiB")] == EffectiveField(
            value:.stored(.integer(1)),sources:[.layer(.global)],reason:.replaced))
        #expect(fractional.fields[key("budget.docker.lowGiB")] == EffectiveField(
            value:.bytes(858_993_459),sources:[.builtIn,.layer(.global)],reason:.automatic))
        #expect(fractional.fields[key("budget.docker.enabled")] == EffectiveField(
            value:.stored(.bool(true)),sources:[.layer(.global)],reason:.replaced))
        let enabled = values(["budget.models.enabled":.bool(true)])
        let cases: [(PolicyInputs,FieldReason)] = [
            (input([.global:enabled],capacity:40*GiB),.invalidForVolume),
            (input([.global:enabled],capacity:nil),.capacityUnavailable),
            (input([.global:enabled],selected:nil),.unmatchedVolume),
            (input([.global:enabled],selected:volumeB,approved:[volumeA]),.unmatchedVolume)]
        for (context,reason) in cases {
            let result = try PolicyResolver.resolve(context)
            #expect(result.fields[key("budget.models.enabled")] == EffectiveField(
                value:.stored(.bool(false)),sources:[.layer(.global),.immutable],reason:reason))
            for id in ["budget.models.highGiB","budget.models.lowGiB"] {
                #expect(result.fields[key(id)] == EffectiveField(value:.unavailable(reason),
                    sources:[.builtIn,.immutable],reason:reason))
            }
        }
    }
    @Test func replacementsAndIndependentRestrictions() throws {
        let ordered: [(PolicyLayer, Int64)] = [(.global,20),(.profile,30),(.project,35),(.run,40)]
        var layers: [PolicyLayer:PolicyValues] = [:]
        for (layer, amount) in ordered {
            layers[layer] = values(["cleanup.requestedBatchGiB":.integer(amount)])
            let result = try PolicyResolver.resolve(input(layers))
            #expect(result.manualBatchBytes == amount*GiB)
            #expect(result.fields[key("cleanup.requestedBatchGiB")]?.sources == [.layer(layer)])
        }
        layers[.global] = values(["cleanup.hardBatchGiB":.integer(8),"scope.excludedRoots":.strings(["/fixture/one"])])
        layers[.profile] = values(["cleanup.hardBatchGiB":.integer(12),"scope.excludedRoots":.strings(["/fixture/two"])])
        let capped = try PolicyResolver.resolve(input(layers))
        #expect(capped.manualBatchBytes == 8*GiB)
        #expect(capped.exclusions == ["/fixture/protected","/fixture/one","/fixture/two"])
        let ready = try PolicyResolver.resolve(input([
            .global:values(["cleanup.hardBatchGiB":.integer(8)]),
            .profile:PolicyDefaults.factory("xcode")]))
        #expect(ready.fields[key("headroom.targetGiB")]?.value == .bytes(15*GiB))
        #expect(ready.manualBatchBytes == 8*GiB)
        let disabled = try PolicyResolver.resolve(input([
            .global:values(["feature.projects":.bool(false)]),
            .profile:values(["feature.projects":.bool(true)])]))
        #expect(!disabled.allowedFeatures.contains("projects"))
        #expect(disabled.fields[key("feature.projects")]?.reason == .denied)
        let battery = try PolicyResolver.resolve(input([.profile:PolicyDefaults.factory("battery")]))
        #expect(battery.fields[key("monitor.suppressHiddenSampling")]?.value == .stored(.bool(true)))
        #expect(battery.fields[key("maintenance.mode")]?.value == .unavailable(.authorityUnavailable))
    }
    @Test func genericThenVolumeAtEveryLayer() throws {
        for layer in PolicyLayer.allCases {
            let fields: [(String,Int64,Int64)] = [("target",12,20),("warning",16,12),("clear",40,18)]
            for (name,inherited,automatic) in fields {
                let cases: [(VolumeField,Int64)] = [(.inherit,inherited),(.automatic,automatic),(.fixedGiB(30),30)]
                for (field,expected) in cases {
                    var override = VolumeOverride(target:.inherit,warning:.inherit,clear:.inherit)
                    switch name {
                    case "target": override.target = field
                    case "warning": override.warning = field
                    default: override.clear = field
                    }
                    let result = try PolicyResolver.resolve(input([layer:values([
                        "headroom.targetGiB":.integer(12),"headroom.warningGiB":.integer(16),
                        "headroom.clearGiB":.integer(40),
                        "headroom.volumeOverrides.\(volumeA.uuidString)":.volume(override)])]))
                    let resolved = try #require(result.fields[key("headroom.\(name)GiB")])
                    #expect(resolved.value == .bytes(expected*GiB))
                    #expect(resolved.sources == (field == .inherit ? [.layer(layer)] : [.volume(layer,volumeA)]))
                }
            }
        }
        let result = try PolicyResolver.resolve(input([
            .global:values(["headroom.targetGiB":.integer(10)]),
            .profile:values(["headroom.volumeOverrides.\(volumeA.uuidString)":.volume(.init(target:.fixedGiB(30),warning:.inherit,clear:.inherit))]),
            .run:values(["headroom.targetGiB":.integer(40)])]))
        #expect(result.fields[key("headroom.targetGiB")]?.value == .bytes(40*GiB))
        #expect(result.fields[key("headroom.targetGiB")]?.sources == [.layer(.run)])
    }
    @Test func unavailableAndUnmatchedAreNotZeroOrAuthorization() throws {
        for requested in [SettingValue.null, .integer(10)] {
            let result = try PolicyResolver.resolve(input([.global:values(["headroom.targetGiB":requested])],capacity:nil))
            #expect(result.fields[key("headroom.targetGiB")]?.value == .unavailable(.capacityUnavailable))
        }
        let retained = values(["headroom.volumeOverrides.\(volumeB.uuidString)":.volume(.init(target:.fixedGiB(30),warning:.inherit,clear:.inherit))])
        let result = try PolicyResolver.resolve(input([.global:retained],selected:volumeB,approved:[volumeA]))
        #expect(result.fields[key("headroom.targetGiB")]?.value == .unavailable(.unmatchedVolume))
        let small = try PolicyResolver.resolve(input([.profile:PolicyDefaults.factory("localAI")],capacity:40*GiB))
        #expect(small.fields[key("headroom.targetGiB")]?.value == .unavailable(.invalidForVolume))
        #expect(small.fields[key("budget.models.enabled")]?.value == .stored(.bool(false)))
    }
    @Test func immutablePressureAndCPUCeilings() throws {
        var i = input([.global:values(["scan.preset":.choice("custom"),"scan.requestedWorkers":.integer(4),"scan.readOnlyProcesses":.integer(2)])])
        i.logicalCPUCount = 2
        #expect(try PolicyResolver.resolve(i).walkWorkers == 2)
        i.lowPower = true
        #expect(try PolicyResolver.resolve(i).walkWorkers == 1)
        i.layers[.profile] = try PolicyDefaults.factory("battery")
        #expect(try PolicyResolver.resolve(i).walkWorkers == 0)
        i.seriousThermal = true
        #expect(try PolicyResolver.resolve(i).walkWorkers == 0)
        i.layers[.profile] = values(["scan.onLowPower":.choice("pauseDiscretionary"),
            "scan.onSeriousThermal":.choice("pauseAll")])
        #expect(try PolicyResolver.resolve(i).walkWorkers == 0)
        i.critical = true
        #expect(try PolicyResolver.resolve(i).walkWorkers == 0)
        #expect(try PolicyResolver.resolve(i).readOnlyProcesses == 0)
    }
}
```

- [ ] Add `PolicyValidationTests.swift` exactly below; optional numeric defaults exercise both absent and explicit null. Relational checks operate on resolved values in the current selected-volume context.

```swift
import Foundation
import Testing
@testable import TidyCore
@Suite struct PolicyValidationTests {
    @Test func quietRelationUsesMergedOperandsNotLayerDefaults() throws {
        let start = values(["notifications.quietStart":.choice("21:00")])
        let end = values(["notifications.quietEnd":.choice("21:00")])
        try PolicyValidator.validateStructure(start,at:.global)
        try PolicyValidator.validateStructure(end,at:.profile)
        let error = PolicyFieldError(id:key("notifications.quietEnd"),reason:.invalidRelation)
        #expect(throws:error) {
            try PolicyResolver.resolve(input([.global:start,.profile:end]))
        }
        #expect(throws:error) {
            try PolicyValidator.validateEdit(end,at:.profile,context:input([.global:start]))
        }
        #expect(throws:error) {
            try PolicyValidator.validateStructure(values([
                "notifications.quietStart":.choice("21:00"),
                "notifications.quietEnd":.choice("21:00")]),at:.global)
        }
        let global = values(["notifications.quietEnd":.choice("09:00")])
        let profile = values(["notifications.quietStart":.choice("08:00")])
        try PolicyValidator.validateStructure(profile,at:.profile)
        try PolicyValidator.validateEdit(profile,at:.profile,context:input([.global:global]))
        let valid = try PolicyResolver.resolve(input([.global:global,.profile:profile]))
        #expect(valid.fields[key("notifications.quietStart")] == EffectiveField(
            value:.stored(.choice("08:00")),sources:[.layer(.profile)],reason:.replaced))
        #expect(valid.fields[key("notifications.quietEnd")] == EffectiveField(
            value:.stored(.choice("09:00")),sources:[.layer(.global)],reason:.replaced))
    }
    @Test func unmatchedVolumeCanPersistButCannotBorrowAnotherCapacity() throws {
        let id = key("headroom.volumeOverrides.\(volumeB.uuidString)")
        let retained = PolicyValues(fields:[id:.volume(.init(
            target:.fixedGiB(30),warning:.inherit,clear:.inherit))])
        try PolicyValidator.validateStructure(retained,at:.global)
        let bytes = try JSONEncoder().encode(retained)
        #expect(try JSONDecoder().decode(PolicyValues.self,from:bytes) == retained)
        #expect(throws:PolicyFieldError(id:id,reason:.boundsUnavailable)) {
            try PolicyValidator.validateEdit(retained,at:.global,context:input(selected:volumeA))
        }
        #expect(throws:PolicyFieldError(id:id,reason:.boundsUnavailable)) {
            try PolicyValidator.validateEdit(retained,at:.global,
                context:input(selected:volumeB,approved:[volumeA]))
        }
        try PolicyValidator.validateEdit(retained,at:.global,context:input(selected:volumeB))
        var edited = retained
        edited.fields[key("ui.units")] = .choice("decimal")
        try PolicyValidator.validateEdit(edited,at:.global,
            context:input([.global:retained],selected:volumeA))
    }
    @Test func budgetEnableErrorsIdentifyTheBoundNotAnUnrelatedField() {
        let enabled = values(["budget.models.enabled":.bool(true)])
        #expect(throws:PolicyFieldError(id:key("budget.models.highGiB"),reason:.outOfRange)) {
            try PolicyValidator.validateEdit(enabled,at:.global,context:input(capacity:40*GiB))
        }
        #expect(throws:PolicyFieldError(id:key("budget.models.highGiB"),reason:.boundsUnavailable)) {
            try PolicyValidator.validateEdit(enabled,at:.global,context:input(capacity:nil))
        }
    }
    @Test func everyNumericRangeRejectsBothNeighbors() throws {
        for row in fixtureRows() where row.resolution != .authority {
            let bounds: (Int64,Int64)?
            switch row.rule {
            case .integer(let a, let b), .optionalInteger(let a, let b): bounds = (a,b)
            default: bounds = nil
            }
            guard let (low,high) = bounds else { continue }
            for value in [low-1,high+1] {
                #expect(throws: PolicyFieldError(id:row.id,reason:.outOfRange)) {
                    try PolicyValidator.validateStructure(.init(fields:[row.id:.integer(value)]),at:.global)
                }
            }
        }
    }
    @Test func nonIntegralAndOverflowInputsNeverReachMultiplication() {
        for raw in ["NaN","Infinity","-Infinity","1.5","1e309","9223372036854775808"] {
            #expect(throws: PolicyFieldError.self) { try PolicyValidator.integerInput(raw,for:key("cleanup.requestedBatchGiB")) }
        }
        #expect(throws: PolicyFieldError.self) { try PolicyValidator.bytes(gib:Int64.max,for:key("cleanup.requestedBatchGiB")) }
    }
    @Test func keyLayerAuthorityAndIdentityTable() {
        let cases: [(String,SettingValue,PolicyLayer,PolicyFieldError.Reason)] = [
            ("feature.unknown",.bool(true),.global,.unknownKey),
            ("item.unknown.enabled",.bool(true),.global,.unknownKey),
            ("ui.units",.choice("binary"),.run,.unsupportedLayer),
            ("scan.sliceSeconds",.integer(300),.project,.unsupportedLayer),
            ("notifications.enabled",.bool(true),.global,.authorityIsLocal),
            ("scope.externalVolumes",.strings([volumeA.uuidString]),.profile,.authorityIsLocal),
            ("maintenance.mode",.choice("authorizedCaches"),.global,.authorityIsLocal),
            ("scan.defaultScope",.choice("fullHome"),.global,.outOfRange),
            ("ui.cards",.strings(["disk","disk"]),.global,.invalidIdentity),
            ("ui.ecosystemOrder",.strings(["apple"]),.global,.invalidIdentity),
            ("browsers.keepCookieDomains",.strings(["https://example.invalid/path"]),.global,.invalidIdentity),
            ("notifications.quietStart",.choice("24:00"),.global,.outOfRange)]
        for (id,value,layer,reason) in cases {
            #expect(throws: PolicyFieldError(id:key(id),reason:reason)) {
                try PolicyValidator.validateStructure(values([id:value]),at:layer)
            }
        }
    }
    @Test func relationsAndUnavailableBounds() {
        let cases: [([String:SettingValue],Int64?)] = [
            (["headroom.targetGiB":.integer(101)],200*GiB),
            (["headroom.warningGiB":.integer(20),"headroom.clearGiB":.integer(20)],200*GiB),
            (["headroom.clearGiB":.integer(201)],200*GiB),
            (["headroom.targetGiB":.integer(10)],nil),
            (["budget.docker.highGiB":.integer(30),"budget.docker.lowGiB":.integer(30)],200*GiB),
            (["notifications.quietStart":.choice("22:00"),"notifications.quietEnd":.choice("22:00")],200*GiB)]
        for (fields,capacity) in cases {
            #expect(throws: PolicyFieldError.self) {
                try PolicyValidator.validateEdit(values(fields),at:.global,context:input(capacity:capacity))
            }
        }
    }
}
```

- [ ] Run `cd TidyCore && swift test --filter 'PolicyResolutionTests|PolicyDefaultsTests|PolicyValidationTests'`. RED must identify missing production types/behavior, not an accidental missing import, malformed fixture, or fabricated passing stub.
- [ ] Implement only the declarations, registry rows, and eight-step algorithm above; use field-specific switch cases for the finite Rule enum. Do not add generic expression evaluation, mutable H rows, a second migration engine, or an authority store.
- [ ] Run the same focused command to GREEN, then `cd TidyCore && swift test`. Review exact row equality, all finite-family expansions, unknown-key denial, provenance, unavailable states, and factory dictionaries. Record actual output; this document claims none.
- [ ] Review the intentional file allowlist before any later commit; controller's current no-Git restriction remains in force until explicitly lifted.

## T06.2 — Real persistence extension RED and preservation

Consumes the actual accepted A.2 `SettingsStore(url:)`, `load()`, `update(expectedRevision:change:)`, explicit rollback APIs AND A.3's sole-writer app cutover. Keep checked revisions, owner-only bounded bytes, exact-old backup, descriptor/nonblocking reads, transaction marker/recovery, and no automatic repair. Extend `SettingsEnvelope` with `preferences: PolicyPreferences?`; extend `SettingsRollbackPreview` to expose the same optional preferences from the frozen preview. The exact change enum becomes:

```swift
public enum SettingsChange: Equatable, Sendable {
    case transcriptAgeDays(Int)
    case legacyPreferences(TidyConfig)
    case preferences(PolicyPreferences)
}
```

The two existing cases and T05 tests retain their signatures. `expectedRevision` must identify the revision on which this whole-config edit was based; a stale revision rejects without publication. Never automatically rebase stale whole config onto a newer revision. A rollback restores both config and preferences as one saved snapshot at a NEW storage revision; never restore the old revision number.

`PolicyPreferences.project(legacy:saved:)` is actor-free and consumes the actual envelope's config plus optional preferences. Start with saved extension or empty values, then fill ONLY missing global entries: transcript threshold -> `cleanup.transcriptDays`; stale-node threshold -> `item.normal.extras.stale-node-modules.inactiveDays`; keep domains -> `browsers.keepCookieDomains`; old restart bool -> `rescue.showAdvancedMemoryActions` (visibility only). Use actual legacy90/120, never registry60/45 to replace those edits. Existing config fields, legacy preset IDs, paths and old app/simulator names remain unchanged/inert; no mapping fabricates authority. The app passes projected global/profile/project values into `PolicyInputs`; it must not resolve raw defaults instead of the migrated envelope.

Both legacy setter cases update the corresponding explicit global entries coherently while preserving all other preferences/volumes/profiles/Custom count fields. A whole-value update is accepted only against its actual base storage revision. It cannot infer field intent from stale config; the bridge may not relabel its revision to make it pass. Reverse projection of explicit global registry edits updates matching legacy transcript/stale/domains/visibility fields in the same transaction; project/run edits do not rewrite config. New registry age values outrank fallback legacy values because `project` only fills absent keys. Mixing live registry/legacy UI edits is not entry-approved until T06.3's base-bound delta handoff is reviewed. No dual-writer interval or accepted effect is introduced.

Complete `PolicyPersistenceTests.swift` below uses actual scratch I/O and fresh actor relaunch, never a fake in-memory store. Entry depends on A.2/A.3 and additive-envelope review; it cannot pass on the current reader-only implementation. It proves core persistence, not actual app relaunch/UI evidence.

```swift
import Foundation
import Testing
@testable import TidyCore
@Suite struct PolicyPersistenceTests {
    @Test func twoVolumesSurviveEveryLegacyEditAndRelaunch() async throws {
        let root = URL(fileURLWithPath:"/private/tmp",isDirectory:true)
            .appendingPathComponent("T06-Policy-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("config.json")
        let store = SettingsStore(url:url)
        let initial = try #require(await store.load().envelope)
        let original = PolicyPreferences(global:values([
            "ui.units":.choice("decimal"),"scan.preset":.choice("custom"),
            "scan.requestedWorkers":.integer(4),"scan.readOnlyProcesses":.integer(2),
            "headroom.volumeOverrides.\(volumeA.uuidString)":.volume(.init(target:.fixedGiB(12),warning:.automatic,clear:.inherit)),
            "headroom.volumeOverrides.\(volumeB.uuidString)":.volume(.init(target:.fixedGiB(30),warning:.inherit,clear:.automatic))]),
            profiles:[],projects:[:])
        let one = try await store.update(expectedRevision:initial.revision,change:.preferences(original))
        #expect(one.revision == initial.revision+1)
        let two = try await store.update(expectedRevision:one.revision,change:.transcriptAgeDays(90))
        var expected = original
        expected.global.fields[key("cleanup.transcriptDays")] = .integer(90)
        #expect(two.preferences == expected)
        expected.global.fields[key("item.normal.extras.stale-node-modules.inactiveDays")] = .integer(150)
        let registryUpdated = try await store.update(expectedRevision:two.revision,change:.preferences(expected))
        var stale = two.config
        stale.transcriptAgeThresholdDays = 120
        do {
            _ = try await store.update(expectedRevision:two.revision,change:.legacyPreferences(stale))
            Issue.record("Stale whole-config edit was accepted")
        } catch let error as SettingsStoreError { #expect(error == .staleRevision) }
        var legacy = registryUpdated.config
        legacy.transcriptAgeThresholdDays = 120
        let three = try await store.update(expectedRevision:registryUpdated.revision,
            change:.legacyPreferences(legacy))
        expected.global.fields[key("cleanup.transcriptDays")] = .integer(120)
        #expect(three.preferences == expected)
        #expect(three.config.staleNodeModulesThresholdDays == 150)
        let reopened = SettingsStore(url:url)
        let loaded = try #require(await reopened.load().envelope)
        #expect(loaded.preferences == expected); #expect(loaded.revision == initial.revision+4)
        for (volume, amount) in [(volumeA,Int64(12)),(volumeB,Int64(30))] {
            let resolved = try PolicyResolver.resolve(input([.global:try #require(loaded.preferences).global],selected:volume))
            #expect(resolved.fields[key("headroom.targetGiB")]?.value == .bytes(amount*GiB))
        }
        let preview = try await reopened.previewRollback()
        #expect(preview.preferences == registryUpdated.preferences)
        let restored = try await reopened.rollback(expectedRevision:loaded.revision,preview:preview)
        #expect(restored.preferences == registryUpdated.preferences)
        #expect(restored.revision == loaded.revision+1)
        #expect(await SettingsStore(url:url).load().envelope?.preferences == registryUpdated.preferences)
    }
    @Test func absentAndTaggedInheritanceRemainDistinct() throws {
        let original = PolicyPreferences(global:values([
            "headroom.targetGiB":.null,
            "headroom.volumeOverrides.\(volumeB.uuidString)":.volume(.init(target:.inherit,warning:.automatic,clear:.fixedGiB(35)))]),
            profiles:[],projects:[:])
        let encoded = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(PolicyPreferences.self,from:encoded) == original)
        #expect(original.global.fields[key("headroom.warningGiB")] == nil)
        #expect(original.global.fields[key("headroom.targetGiB")] == .null)
    }
}
```

The JSON round-trip alone is not bounded settings-parser evidence: also run all accepted T05 malformed/duplicate/depth/size/UTF-8/unknown-envelope fixtures through the extended `SettingsDecoding.load`. Unknown preference keys or tag/version shape must return recoveryReadOnly with original bytes untouched, not defaults. Add `preferences` to the exact accepted envelope key set, not unrestricted dictionary decoding. A T05-only binary remains recoveryReadOnly for this new field.

## T06.3 — Handoff and remaining acceptance

This section defines dependency obligations, not permission to edit an unaccepted bridge. At A.3 review extend its real shared-services tests with two typed edits: `ui.units` changes storage revision only and preserves current confirmation; `cleanup.requestedBatchGiB` changes storage and policy revision, immediately disables admission, and rejects the frozen old confirmation. Use existing opaque coordinator tickets and the real serialized store queue. Two windows observe one store, with no fabricated accepted item, consent, process, discovery, or production home path. Complete executable A.3-bound test code must be attached at that gate using its landed bridge API; this card does not invent a public `submit(preferences:)` capability to bypass it.

The stale-whole-config limitation requires a separately reviewed base-bound delta handoff at T06.3: capture `(baseConfig, baseStorageRevision, editedConfig)` at the actual shared setter, derive only changed fields from base→edited, and queue that intent without pretending it was based on a later saved revision. A candidate `SettingsChange.legacyPreferenceDelta(baseRevision: UInt64, base: TidyConfig, edited: TidyConfig)` is an interface-review obligation, NOT an added case in T06.2. The landed A.3 queue must define conflict/retry behavior and complete tests before source entry: unrelated intervening registry edits survive, conflicting touched fields report a stale-edit failure, failed edits never reopen admission, and no acknowledged edit silently vanishes. Existing whole-value cases/tests remain unchanged until that coordinated cutover; no automatic rebase is authorized by this card.

Open implementation decisions are narrow: the exact existing bridge method name for typed edits depends on the accepted A.3 source; the owning local services determine how A metadata is displayed. Neither changes the product default values or permits T06 to invent an authority ledger. There is no unresolved numeric product default in this registry. Full-home remains an explicit one-run scan request outside persisted `scan.defaultScope`.

- [ ] At pure GREEN: independent full-row metadata/default/effective/source fixture, all volume/layer modes, deny/union/cap/NaN/overflow/unavailable/unknown-key behavior and exact factories pass.
- [ ] At storage GREEN: A.2 fault matrix remains passing; real two-volume edit/relaunch/rollback test passes and no edits are discarded; Custom4/2 survives preset changes and relaunch.
- [ ] At app integration GREEN: full frozen-plan/presentation-vs-policy revision and two-window event-order tests pass under actual blocked-I/O instrumentation from A.3. No disabled feature schedules new work in scheduler integration; active mutations drain. No timer is added by T06.
- [ ] At feature acceptance: every control can show default/effective/source/range/consequence; advanced controls searchable; nonapplicable/unavailable explicit; exact profile preview retains Custom; imports/reset preserve protections and transfer no authority.
- [ ] Full tests, arm64 and x86_64 app builds, macOS14/current-OS smoke and physical8GiB Apple Silicon/Intel evidence remain required. Unavailable hardware is reported as incomplete acceptance, not an impossible precondition to authorized pure source entry. Performance figures in design §7 are proposed release measurements, not achieved numbers.

Documentation completion is not T06 implementation, persistence, app integration, full customization, acceptance, or release completion.
