# T07.3b preimplementation card — profile, transfer and reset workflows

Status: **PREIMPLEMENTATION ONLY — NOT IMPLEMENTED, TESTED, ACCESSIBILITY-ACCEPTED, OR RELEASED.**

> **For agentic workers:** REQUIRED SUB-SKILL: use `test-driven-development`, then `executing-plans`; request a fresh adversarial source review after GREEN.

**Goal:** Add bounded profile create/clone/value-update/rename/delete/activation/diff, exact issued import preview with outcome-bound completion, portable export, and selective reset workflows to registry-driven Settings without adding authority, a second settings owner, or work on open.

**Architecture:** A new pure `SettingsWorkflow` converts one exact `SettingsEnvelope` and explicit request into a reviewable base-bound `PreferencesDocumentDelta`. Shared `AppConfigStore` remains the only app owner and submits that delta or an exact T07.2 actor-issued import preview. A bounded controller in `SettingsView.swift` owns presentation state and requires preview plus explicit confirmation before mutation.

**Tech stack:** Swift 5.10, Swift Testing, XCTest, Observation, SwiftUI, UniformTypeIdentifiers, macOS 14+.

## Binding constraints

- TDD: install the complete RED tests below first; intended RED is missing APIs/expectations only.
- Reuse `SessionProfiles`, `SettingsTransfer`, `PreferencesDocumentProjection`, `AppConfigStore`, and T07.2 bridge issuance. No second parser/store/bridge/coordinator/resolver/writer/profile cache/authority ledger.
- Shared environment `AppConfigStore` is the only UI owner. Writes are exact document deltas or exact `issueImportPreview` results.
- Opening/rendering Settings starts no scan, process, discovery, timer, file read, import analysis, export encoding, plan, or persistence.
- User-selected import bytes remain capped by accepted 1 MiB/depth/member/string limits and are released immediately after analysis; UI retains bounded rows only.
- Create, clone, and import never activate. Transfer never changes config, active selection, projects, authority/local identity, journal, history/index, diagnostics, or App Support location.
- Local reassociation stays visibly unavailable until T22.3. History/index clearing stays visibly unavailable until T07.3d. The mandatory journal is immutable.
- No T07.3d/T22.3/T22.4, adapter, consent, maintenance, notification, login-item, README, GitHub, signing, DMG, or release work.
- At most 50 profiles; duplicate names allowed; trimmed nonempty names <=4,096 UTF-8 bytes. Reset selection <=1,000 IDs.
- Lazy bounded lists, no polling, and no high-frequency observation. Preserve all T07.3a registry/search/accessibility/localization/cache contracts.
- No commit.

## Exact allowlist

Only these files may change:

1. `TidyCore/Sources/TidyCore/Policy/SessionProfile.swift` — reviewed monotone profile-value update transform.
2. `TidyCore/Sources/TidyCore/Policy/SettingsWorkflow.swift` — new pure projections.
3. `TidyCore/Tests/TidyCoreTests/SettingsWorkflowTests.swift` — new core RED, including the direct update-transform contract.
4. `Tidy/Settings/AppConfigStore.swift` — shared-owner preview/commit/export methods.
5. `Tidy/Settings/SettingsView.swift` — bounded controller and workflows UI.
6. `Tidy/Resources/Localizable.xcstrings` — workflow copy.
7. `TidyAppModelTests/SharedSettingsWiringTests.swift` — shared/two-window/render/source RED.
8. `TidyUITestHost/TestHostApp.swift` — deterministic fixtures.
9. `docs/verification/T07-3b-profile-transfer-workflows.md` — only after GREEN.

Do not edit envelope/transfer/settings-store/bridge/coordinator/journal/history/index/bootstrap/custom-view/plan/spec/entry/release files. `SessionProfile.swift` receives only the exact `update` API below; no other session-profile behavior changes.

### PBX/resource delta

Exactly none. SwiftPM discovers the two new core files. T07.3a already compiles `SettingsView.swift` and `AppConfigStore.swift` into app/AppModel/UIHost and copies the existing catalog into all three bundles. Any `.pbxproj`, target, group, resource, dependency, or new app-file change stops for card amendment.

## Existing APIs that must be composed, not replaced

```swift
SessionProfiles.create(id:name:values:inherited:in:)
SessionProfiles.clone(sourceID:newID:name:inherited:in:)
SessionProfiles.createFactory(key:id:name:inherited:in:)
SessionProfiles.update(id:values:inherited:in:)
SessionProfiles.rename(id:name:inherited:in:)
SessionProfiles.delete(id:inherited:in:)
SessionProfiles.diff(base:candidate:inherited:)
SessionProfiles.previewReset(id:fieldIDs:includeOwnedRestrictions:inherited:in:)
SettingsTransfer.export(_:)
AppConfigStore.submit(document:)
AppConfigStore.analyzeImport(bytes:)
AppConfigStore.issueImportPreview(analysisID:choices:)
AppConfigStore.commitImport(_:)
AppConfigStore.cancelImport(analysisID:)
AppConfigStore.cancelImport(previewID:)
```

UI never calls pure `SettingsTransfer.resolve` and never constructs/reconstructs `SettingsImportPreview`.

## Exact reviewed `SessionProfiles.update` API

```swift
public extension SessionProfiles {
    static func update(id: UUID, values: PolicyValues,
                       inherited: PolicyValues,
                       in profiles: [SavedProfile]) throws -> [SavedProfile]
}
```

The implementation first runs the existing collection validation, requires exactly one matching ID, preserves that profile's ID/name and the collection's order, and validates every proposed field at the profile layer. Preferences may change freely within registry validation. Restrictions are monotone relative to the current profile's effective value: for every profile-capable restriction in the union of old and proposed explicit IDs, compare `proposed.fields[id] ?? inherited.fields[id] ?? definition.defaultValue` against `current.fields[id] ?? inherited.fields[id] ?? definition.defaultValue` with `PolicyRestrictionValidator.relation`; `.weaker` throws `SessionProfileError.protectionWeakening(id)`. Thus deleting a stricter explicit restriction is rejected when inheritance is weaker, equal removal is allowed, and stronger updates are allowed. The helper performs no I/O and neither activates nor renames.

## Exact new core API

```swift
import Foundation

public enum SettingsProfileWorkflowRequest: Equatable, Sendable {
    case create(id: UUID, name: String, values: PolicyValues)
    case createFactory(key: String, id: UUID, name: String)
    case clone(sourceID: UUID, newID: UUID, name: String)
    case update(id: UUID, values: PolicyValues)
    case rename(id: UUID, name: String)
    case delete(id: UUID)
    case activate(UUID?)
}
public enum SettingsProfileWorkflowKind: String, Equatable, Sendable {
    case create, createFactory, clone, update, rename, delete, activate, deactivate
}
public struct SettingsProfileWorkflowPreview: Equatable, Sendable {
    public let kind: SettingsProfileWorkflowKind
    public let baseRevision: UInt64
    public let profileID: UUID?
    public let before: SavedProfile?
    public let after: SavedProfile?
    public let activeProfileBefore: UUID?
    public let activeProfileAfter: UUID?
    public let fieldChanges: [ProfileFieldDiff]
    public let effect: AuthorityEffect
    public let delta: PreferencesDocumentDelta
}
public enum SettingsResetBoundary: String, CaseIterable, Equatable, Hashable, Sendable {
    case mandatoryJournal, appSupportRoot, projects, globalRestrictions
    case localIdentities, authority, inertQuarantine
}
public struct SettingsSelectiveResetRequest: Equatable, Sendable {
    public let globalPreferenceIDs: Set<SettingID>
    public let profileID: UUID?
    public let profileFieldIDs: Set<SettingID>
    public let includeOwnedProfileRestrictions: Bool
    public init(globalPreferenceIDs: Set<SettingID> = [], profileID: UUID? = nil,
                profileFieldIDs: Set<SettingID> = [],
                includeOwnedProfileRestrictions: Bool = false)
}
public struct SettingsSelectiveResetPreview: Equatable, Sendable {
    public let baseRevision: UInt64
    public let globalChanges: [ProfileFieldDiff]
    public let profileReset: ProfileResetPreview?
    public let immutableBoundaries: Set<SettingsResetBoundary>
    public let effect: AuthorityEffect
    public let delta: PreferencesDocumentDelta
}
public struct SettingsImportUISummary: Equatable, Sendable {
    public let analysisID: SettingsImportAnalysisID
    public let rows: [SettingsImportRow]
    public let collisions: [ProfileImportCollision]
    public init(_ analysis: SettingsImportAnalysis) throws
}
public enum SettingsWorkflowError: Error, Equatable, Sendable {
    case missingProfile(UUID), duplicateProfile(UUID), invalidActivation(UUID)
    case ineligibleGlobalReset(SettingID), profileRequired, emptyConfirmation
    case tooManySelectedFields, missingAnalysisID, tooManyImportRows
    case tooManyImportCollisions, unsupportedAuthority
}
public enum SettingsWorkflow {
    public static let maximumSelectedResetFields: Int
    public static let maximumPresentedImportRows: Int
    public static let maximumPresentedImportCollisions: Int
    public static let immutableResetBoundaries: Set<SettingsResetBoundary>
    public static func previewProfile(_ request: SettingsProfileWorkflowRequest,
                                      current: SettingsEnvelope) throws
        -> SettingsProfileWorkflowPreview
    public static func previewSelectiveReset(_ request: SettingsSelectiveResetRequest,
                                             current: SettingsEnvelope) throws
        -> SettingsSelectiveResetPreview
    public static func exportPortable(current: SettingsEnvelope) throws -> Data
}
```

### Projection rules

- Use `current.preferences ?? PolicyPreferences()` and its global as inherited input; reject duplicate persisted profile IDs.
- Call the matching `SessionProfiles` transform exactly once. `.update` calls only the reviewed monotone `SessionProfiles.update`; it never reconstructs a profile in the workflow layer. Emit one exact insert/update/delete, except activation (no profile edit). Activation accepts nil or one existing ID.
- Create/factory/clone never touch active. Delete-active atomically deletes and edits active to nil; delete-inactive leaves active untouched. Rename has empty field diff.
- Create/clone diff valid empty same-ID profile -> result; delete reverses; update uses `SessionProfiles.diff(base:candidate:inherited:)` and exposes every changed value/source/rule/effect; rename alone has an empty field diff. Stable UTF-8 ID ordering.
- Classify projected before/after with `PreferencesDocumentEffect.classify`; consent/authority rejects. Preserve config/global/projects/inert unless explicitly eligible global reset.
- Reset accepts <=1,000 unique IDs across the union of global and profile selections. Global reset removes only explicitly stored known portable global `.preference` fields with no consent. Global restriction/authority/identity/unknown/absent rejects.
- Combined reset is one atomic projection with a binding order: validate and remove selected global values first; derive `candidateGlobal` from that intermediate envelope; pass `candidateGlobal` as `inherited` to `SessionProfiles.previewReset`, `SessionProfiles.diff`, and final full-envelope validation. Never diff a profile against the pre-reset global layer. This preserves truthful same-ID provenance and prevents a removed global value from being reported as the profile's new inherited source.
- After constructing the single combined delta, call `PreferencesDocumentProjection.apply(delta, to: current)` once and take the returned effect; this is the final whole-candidate persisted-state validation. Do not hand-roll a partial validator or classify an independently reconstructed candidate.
- Any nonempty `profileFieldIDs` without `profileID` throws `.profileRequired`; an unknown profile throws `.missingProfile`. Owned restrictions require the explicit Boolean. Reset never weakens the candidate global inheritance.
- Empty reset rejects. Delta has no inert edits and never touches active/config/projects/authority.
- Every reset preview returns exactly `Set(SettingsResetBoundary.allCases)`.
- Export is exactly `SettingsTransfer.export(PortableSettingsState(preferences: current.preferences ?? .init(), inertImports: current.inertImports))`; accepted export strips projects and excludes config/active/authority.
- `SettingsImportUISummary` copies only a nonnil actor-issued ID plus public `rows` and `collisions`; reject over 1,000 rows or 50 collisions. It never stores or exposes `committableImported`, `importedInert`, `current`, source bytes, or candidate bytes.
- Pure preview/export performs no I/O and grants no commit authority.

## Exact AppConfigStore additions

```swift
var settingsRevision: UInt64 { displayed.revision }
var profiles: [SavedProfile] { preferences.profiles }
var hasPendingSettingsWrites: Bool { !pendingOrder.isEmpty }
func previewProfileWorkflow(_ request: SettingsProfileWorkflowRequest) throws
    -> SettingsProfileWorkflowPreview
@discardableResult func commitProfileWorkflow(_ preview: SettingsProfileWorkflowPreview)
    -> SettingsSubmissionAdmission
func previewSelectiveReset(_ request: SettingsSelectiveResetRequest) throws
    -> SettingsSelectiveResetPreview
@discardableResult func commitSelectiveReset(_ preview: SettingsSelectiveResetPreview)
    -> SettingsSubmissionAdmission
func exportPortableSettings() throws -> Data
func analyzeImportSummary(bytes: Data) async throws -> SettingsImportUISummary
```

Preview derives from current `displayed`; commit passes only preview.delta to existing `submit(document:)`. Do not rerun or mutate transformations at commit. Revision changes on exact acknowledged outcomes; optimistic replay remains existing T07.2 behavior and all windows share one store/bridge owner.

`analyzeImportSummary(bytes:)` is exactly `try SettingsImportUISummary(try await analyzeImport(bytes: bytes))`; the full actor result is a stack-local temporary and is released before return. `SettingsWorkflowImportOperations.live(store:)` delegates only to that summary method plus the existing issue/cancel methods and `commitImport`; its `submit` closure returns the exact store admission without wrapping or observing it. `init(store:bundle:)` retains the supplied bundle and always installs `.live(store:)`; production defaults to `.main`. Only RED uses the explicitly labeled internal `init(testing:importOperations:bundle:)`, whose bundle is mandatory. Every controller copy/failure/descriptor resolution uses that retained bundle, never `.main` or `Bundle.module` behind the injected value. The injectable operations value is a deterministic timing/outcome seam, owns no durable or optimistic settings state, and is never constructed by the production surface or fixture host.

## Exact app presentation API

```swift
enum SettingsWorkflowTab: String, CaseIterable, Equatable, Hashable { case profiles, transfer, reset }
enum SettingsImportPresentationState: Equatable {
    case idle, analyzing, analysis(SettingsImportUISummary)
    case issuingPreview(SettingsImportUISummary), confirmation(SettingsImportPreview)
    case submitting(SettingsImportPreviewID), failed(String)
}
enum SettingsWorkflowConfirmation: Equatable {
    case profile(SettingsProfileWorkflowPreview), reset(SettingsSelectiveResetPreview)
}
enum SettingsDeferredWorkflow: String, CaseIterable, Equatable, Hashable {
    case localReassociation, historyAndIndexClearing
}
enum SettingsWorkflowControlRole: String, CaseIterable, Equatable, Hashable {
    case profilesTab, transferTab, resetTab, createProfile, createFactory
    case cloneProfile, renameProfile, deleteProfile, activateProfile, deactivateProfile
    case profileNameEditor, profileValueEditor, confirmProfile, cancelProfile
    case chooseImport, issueImport, confirmImport, cancelImport, exportPortable
    case collisionKeepLocal, collisionReplace, collisionClone
    case resetGlobalField, resetProfileField, resetRestrictionOptIn
    case previewReset, confirmReset, cancelReset, localReassociation, historyAndIndexClearing
}
enum SettingsWorkflowControlAvailability: Equatable {
    case enabled
    case unavailable(reasonKey: String, label: String)
}
enum SettingsWorkflowImportPhase: CaseIterable, Equatable, Hashable {
    case idle, analyzing, analysis, issuing, confirmation, submitting, failed
}
enum SettingsWorkflowEditorTarget: Equatable, Hashable {
    case newProfile
    case profile(UUID)
}
struct SettingsWorkflowProfileEditorContext: Equatable {
    let target: SettingsWorkflowEditorTarget
    let valueFieldIDs: [SettingID]
}
enum SettingsWorkflowControlIdentity: Equatable, Hashable {
    case profile(UUID)
    case factory(String)
    case collision(UUID, ProfileCollisionControlChoice)
    case globalResetField(SettingID)
    case profileResetField(UUID, SettingID)
    case restrictionOptIn(UUID, SettingID)
    case profileName(SettingsWorkflowEditorTarget)
    case profileValue(SettingsWorkflowEditorTarget, SettingID)
}
enum ProfileCollisionControlChoice: String, CaseIterable, Equatable, Hashable {
    case keepLocal, replace, clone
}
struct SettingsWorkflowControlContext: Equatable {
    let profileIDs: [UUID]
    let activeProfileID: UUID?
    let profileEditor: SettingsWorkflowProfileEditorContext?
    let importPhase: SettingsWorkflowImportPhase
    let collisions: [ProfileImportCollision]
    let hasCompleteCollisionChoices: Bool
    let hasPreparedProfile: Bool
    let resetGlobalFieldIDs: [SettingID]
    let resetProfileID: UUID?
    let resetProfileFieldIDs: [SettingID]
    let ownedRestrictionFieldIDs: Set<SettingID>
    let hasResetSelection: Bool
    let hasPreparedReset: Bool
}
struct SettingsWorkflowControlDescriptor: Identifiable, Equatable {
    let id: String
    let role: SettingsWorkflowControlRole
    let titleKey: String
    let label: String
    let availability: SettingsWorkflowControlAvailability
    let focusOrder: Int
    let identity: SettingsWorkflowControlIdentity?
}
enum SettingsWorkflowPresentationError: Error, Equatable {
    case tooManyProfiles, duplicateCollision(UUID), tooManyCollisions
    case tooManyEditorFields, tooManyResetFields, tooManyControls
    case invalidActiveProfile(UUID), invalidEditorTarget(UUID)
    case invalidEditorField(SettingID), profileRequired, missingResetProfile(UUID)
    case invalidResetField(SettingID), invalidRestrictionOptIn(SettingID)
}
struct SettingsImportOutcomePresentation: Identifiable, Equatable {
    let outcome: SettingsImportOutcome
    let titleKey: String
    let explanationKey: String
    let count: Int
    var id: String { outcome.rawValue }
}
enum SettingsWorkflowPresentation {
    static let importOutcomeOrder: [SettingsImportOutcome]
    static let maximumControlDescriptors: Int // exactly 3_423
    static func importOutcomes(_ summary: SettingsImportUISummary)
        -> [SettingsImportOutcomePresentation]
    static func canIssuePreview(summary: SettingsImportUISummary,
                                choices: [UUID: ProfileCollisionChoice]) -> Bool
    static func controls(context: SettingsWorkflowControlContext,
                         localize: (String) -> String) throws
        -> [SettingsWorkflowControlDescriptor]
    static func accessibilityID(for outcome: SettingsImportOutcome) -> String
    static func deferredExplanationKey(_ workflow: SettingsDeferredWorkflow) -> String
    static func deferredExplanation(_ workflow: SettingsDeferredWorkflow,
                                    bundle: Bundle) -> String
}
struct SettingsWorkflowImportOperations {
    let analyze: @MainActor (Data) async throws -> SettingsImportUISummary
    let issue: @MainActor (SettingsImportAnalysisID,
                           [UUID: ProfileCollisionChoice]) async throws -> SettingsImportPreview
    let cancelAnalysis: @MainActor (SettingsImportAnalysisID) async -> Void
    let cancelPreview: @MainActor (SettingsImportPreviewID) async -> Void
    let submit: @MainActor (SettingsImportPreview) -> SettingsSubmissionAdmission
    @MainActor static func live(store: AppConfigStore) -> Self
}
@Observable @MainActor final class SettingsWorkflowController {
    let store: AppConfigStore
    let bundle: Bundle
    private(set) var importState: SettingsImportPresentationState
    private(set) var collisionChoices: [UUID: ProfileCollisionChoice]
    private(set) var confirmation: SettingsWorkflowConfirmation?
    private(set) var lastExportByteCount: Int?
    private var operationGeneration: UInt64
    private let importOperations: SettingsWorkflowImportOperations
    init(store: AppConfigStore, bundle: Bundle = .main)
    internal init(testing store: AppConfigStore,
                  importOperations: SettingsWorkflowImportOperations,
                  bundle: Bundle)
    func prepareProfile(_ request: SettingsProfileWorkflowRequest) throws
    func prepareReset(_ request: SettingsSelectiveResetRequest) throws
    func cancelConfirmation()
    func confirmPreparedChange() -> SettingsSubmissionAdmission?
    func chooseCollision(profileID: UUID, choice: ProfileCollisionChoice)
    @discardableResult func beginImportSelection(bytes: Data) -> Task<Void, Never>
    @discardableResult func beginImportPreviewIssuance() -> Task<Void, Never>
    @discardableResult func beginImportConfirmation() -> Task<Void, Never>
    @discardableResult func beginImportCancellation() -> Task<Void, Never>
    func makeExportDocument() throws -> PortableSettingsDocument
}
struct PortableSettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data)
    init(configuration: ReadConfiguration) throws
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper
}
struct SettingsWorkflowSurface: View {
    let store: AppConfigStore
    init(store: AppConfigStore, bundle: Bundle = .main,
         initialTab: SettingsWorkflowTab = .profiles)
}
```

### UI behavior

- Outcome order is exactly: committable, collision, inert, redacted, requiresLocalReassociation, rejectedAuthority, rejectedProtectionWeakening, rejectedInvalid, rejectedNonPortable, rejectedUnsupportedLayer. Render all ten, even count zero, IDs `settings.import.outcome.<rawValue>`.
- File reading occurs only in explicit `fileImporter` completion with paired security-scoped access. Pass `Data` immediately to `beginImportSelection`, release it when the operation returns, and retain only `SettingsImportUISummary`; no UI property may have type `SettingsImportAnalysis`, `PortableSettingsState`, or `Data`.
- The only `Task {}` launches are the bodies of the four synchronous task-return methods `beginImportSelection`, `beginImportPreviewIssuance`, `beginImportConfirmation`, and `beginImportCancellation`, placed between literal outer delimiters `// SETTINGS_WORKFLOW_TASK_BOUNDARIES_BEGIN` and `// SETTINGS_WORKFLOW_TASK_BOUNDARIES_END`. Each method is additionally wrapped by exact `// SETTINGS_WORKFLOW_TASK_BEGIN_<method>` and `// SETTINGS_WORKFLOW_TASK_END_<method>` delimiters. Each extracted helper contains its matching declaration and exactly one `Task {}`; the confirmation helper's `.rejected` branch contains `await importOperations.cancelPreview(preview.id)`, and every helper decides its `.submitting` no-op before any `operationGeneration &+=`. After removing the four extracted helper regions and outer markers, the outer block is whitespace-only. `Task {` is absent outside the block. The existing T07.3a test receives only this exact structural correction; `.task`, `Task.detached`, lifecycle, receive, refresh, timer, and process work remain forbidden.
- Analysis is not commit-capable. Every collision requires explicit keep-local/replace/clone; clone UUID is generated once and displayed. Issue using only analysisID + choices.
- Increment `operationGeneration` with wrapping arithmetic synchronously before each permitted new selection, issuance, import confirmation, and pre-submission cancellation. Each task captures the generation; after every await it updates state only on an exact match. New selection/cancel sends the matching cancellation for any retained summary/preview. If stale analysis or issuance still returns an actor token, cancel that returned analysis/preview ID before discarding it. New selection supersedes prior selection, cancel during analysis/issuance leaves `.idle`, stale success/failure cannot restore older state, and a queued/live issuance rejection becomes bounded `.failed` without confirmation or retained preview. Once submission is accepted, all four public import boundaries are fail-closed no-ops: none increments the generation, analyzes/issues/submits/cancels again, or supersedes the accepted completion.
- Each boundary method snapshots the prior summary/preview before clearing presentation state. Selection cancels that prior token before analyzing new bytes; pre-submission cancellation awaits the matching cancel and remains idle; cancellation invoked while `.submitting` is a fail-closed no-op that does not change state, generation, token accounting, or the accepted task. Issuance passes only the summary ID and choices. Issuance failure cancels the summary ID best-effort, clears choices, and stores only localized bounded failure copy. Confirmation awaits its one accepted outcome task. These awaits all remain inside the same four tasks—never spawn cleanup tasks.
- Failure state stores exactly resolved `settings.import.failure`; it never retains an arbitrary error description, bytes, analysis, candidate, or actor error object.
- A task checks its captured generation before every actor call as well as after every await, so a superseded task that has not begun exits without analysis or cancellation work. No polling, sleeping, detached work, retry loop, or unbounded continuation collection is permitted.
- Only actor-issued `.confirmation(preview)` enables import. Show source/candidate digests, all outcomes and choices. `beginImportConfirmation` snapshots that exact preview, increments/captures generation, enters `.submitting(preview.id)`, calls only `importOperations.submit(preview)` (which is exactly `store.commitImport(preview)` in `.live`), and awaits the accepted completion task. On a generation-matching `.saved` it clears all import state to `.idle`; matching `.conflict`, `.invalid`, or `.failed` clears the preview/choices and becomes resolved bounded `.failed`. For every synchronous `.rejected` admission, regardless of rejection reason, the same confirmation task first awaits exactly one `importOperations.cancelPreview(preview.id)`, then—only if its generation still matches—clears choices and enters resolved bounded `.failed`; it never exposes failure while the issued binding may still be retained. It never presents saved/idle before `.saved`, never retries or reconstructs a preview, and a second use of the same token is rejected without a write. Cancel before submission calls the matching actor cancel and writes nothing. New selection cancels an unsubmitted old token. Cancel/new selection cannot supersede an already accepted write.
- While import phase is `.submitting`, every interactive descriptor—including tabs, profile/factory/editor/actions, import, export, collision, reset fields/actions, and create—is present but unavailable with exact reason key `settings.control.unavailable.submitting`; no button, picker, editor, file importer/exporter, or submission action remains enabled. Readable outcome/diff/digest/immutable-boundary copy remains visible, and the two deferred descriptors remain visible with their ordinary deferred-unavailable reason. The surface lock lifts only after the accepted task reports an outcome.
- Profile create (blank/six factories), clone, monotone value update, rename, delete, activate/deactivate all preview base revision, UUID/name before/after, active before/after, sorted field diff/default/rule/effect/provenance, and invalidation. Cancel writes nothing; confirm once.
- Reset is initially empty and has no reset-all. Only explicit eligible global P and profile-owned fields are selectable. Owned restrictions require a second opt-in. Preview lists immutable boundaries and exact inherited/default result.
- Local reassociation row says unavailable until T22.3 picker/ledger and that import cannot authorize this Mac. History/index row says unavailable until optional report store + T09 index and journal is never cleared. IDs: `settings.deferred.localReassociation`, `settings.deferred.historyAndIndexClearing`.
- `SettingsWorkflowPresentation.controls` is the only control-list authority. It stable-first-occurrence-deduplicates then canonical-sorts all dynamic identities and assigns contiguous `focusOrder == indices`. It validates at most 50 unique profiles/collisions, at most 1,000 reset IDs across global/profile, and at most 1,000 editor value fields; bound preflights occur before per-item registry validity. Duplicate collision IDs reject, and every collision ID must name an existing profile; reset profile fields require one existing profile; owned restriction IDs must be a subset of reset profile fields and actual profile-layer restrictions; editor targets must be new or an existing profile and editor fields must be known editable profile P/R rows. Failures use the exact `SettingsWorkflowPresentationError` cases above, never traps or silent omission. `maximumControlDescriptors == 3_423`: 16 finite + 6 factories + 50×5 profile actions + one name/1,000 value editors + 50×3 collision choices + 1,000 reset fields + 1,000 restriction opt-ins. Checked addition rejects rather than truncates.
- Dynamic descriptors are exhaustive: exactly six `SessionProfiles.factoryKeys` controls; five actions per profile; one name plus every requested value editor; keep-local/replace/clone per collision; every requested global/profile reset field; and one opt-in per owned restriction. Profile value editors submit `.update(id:values:)` with the complete validated draft; they never bypass preview/confirmation. Stable IDs are exact: `settings.workflow.tab.<rawValue>`, `settings.profile.action.<role>.<UUID>`, `settings.profile.action.create`, `settings.profile.factory.<key>`, `settings.profile.editor.name.<new|UUID>`, `settings.profile.editor.value.<new|UUID>.<SettingID>`, `settings.import.collision.<UUID>.<choice>`, `settings.import.{choose,issue,confirm,cancel}`, `settings.export.choose`, `settings.reset.global.<SettingID>`, `settings.reset.profile.<UUID>.<SettingID>`, `settings.reset.restrictionOptIn.<UUID>.<SettingID>`, `settings.reset.{preview,confirm,cancel}`, and both deferred IDs. Labels contain resolved title plus every raw dynamic identity; collision labels also contain both local/imported names. Unavailable controls retain label/focus position and a resolved reason. The view renders editors, collision decisions, reset selectors, and actions only from these descriptors—no hand-built parallel controls.
- Availability is exact: profile actions/factories/name/value editors are enabled only without a prepared profile preview; profile confirm/cancel only with one. Issue is enabled only for `.analysis` plus complete collision choices; per-collision choices only during `.analysis`; import confirm only for `.confirmation`; import cancel only for analyzing/analysis/issuing/confirmation. Reset field selectors/restriction opt-ins are enabled only without a prepared reset; reset preview only with a nonempty selection; reset confirm/cancel only with a prepared reset. Activate is unavailable for the active profile and deactivate is enabled only for it when profile editing is otherwise enabled. Both deferred roles are always unavailable. Choose/import-new, export, tabs, and create remain enabled except for the exact `.submitting` whole-surface lock above.
- Use semantic colors, lazy rows, and adaptive 480-point accessibility layout. Controller initialization performs no work.

## Localization

Add non-key Base-English values for tabs/revision; every profile action/confirm/cancel/diff; import choose/analyze/issue/confirm/cancel/failure/digests; three collision choices; title+explanation for all ten outcomes; export choose/ready/failure; reset selection/restriction opt-in/preview/confirm/cancel/immutable boundaries; and title+explanation for both deferred rows. Copy must not imply authority, activation, clearing, execution, or persisted success before saved outcome.

The catalog key set is exact and namespaced. Add `settings.workflow.tab.{profiles,transfer,reset}`, `settings.workflow.revision`, `settings.profile.{create,createFactory,clone,rename,delete,activate,deactivate,preview,confirm,cancel,diff,activeBefore,activeAfter,editor.name,editor.value,factory.xcode,factory.android,factory.flutter,factory.web,factory.localAI,factory.battery}`, `settings.import.{choose,analyze,issue,confirm,cancel,failure,sourceDigest,candidateDigest,collision.keepLocal,collision.replace,collision.clone}`, `settings.import.outcome.<rawValue>.{title,explanation}` for every value in `SettingsWorkflowPresentation.importOutcomeOrder`, `settings.export.{choose,ready,failure}`, `settings.reset.{select,ownedRestrictionOptIn,field.global,field.profile,preview,confirm,cancel,immutable}`, `settings.reset.boundary.<rawValue>` for every `SettingsResetBoundary`, `settings.control.unavailable.{noProfile,activeProfile,importAnalysis,issuedPreview,resetSelection,resetPreview,deferred,submitting}`, and `settings.deferred.<rawValue>.{title,explanation}` for both deferred workflows. `deferredExplanationKey` returns the exact explanation key; `deferredExplanation` resolves that key with its supplied bundle through `SettingsCopy.resolve`. Tests resolve every key through the T07.3a resolver and require nonempty English output different from the key and `Description unavailable.`.

## Complete RED core test

Create `SettingsWorkflowTests.swift`:

```swift
import Foundation
import Testing
@testable import TidyCore

@Suite("Settings workflow") struct SettingsWorkflowTests {
    let p = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let q = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let inactive = SettingID(rawValue: "cleanup.inactiveDays")
    let workers = SettingID(rawValue: "scan.requestedWorkers")
    let roots = SettingID(rawValue: "scope.projectRoots")
    func envelope(_ profile: SavedProfile? = nil, active: UUID? = nil,
                  global: PolicyValues = .init(), revision: UInt64 = 7,
                  projects: [String: PolicyValues] = [:]) -> SettingsEnvelope {
        SettingsEnvelope(schemaVersion: 2, revision: revision,
            config: TidyConfig(schemaVersion: 2),
            preferences: PolicyPreferences(global: global,
                profiles: profile.map { [$0] } ?? [], projects: projects),
            activeProfileID: active)
    }

    @Test func lifecycleExactDeltas() throws {
        let base = envelope(global: .init(fields: [inactive: .integer(60)]))
        let create = try SettingsWorkflow.previewProfile(.create(id: p, name: " Build ",
            values: .init(fields: [workers: .integer(2)])), current: base)
        #expect(create.kind == .create && create.after?.name == "Build")
        #expect(create.delta.profiles == [.insert(create.after!)])
        #expect(!create.delta.touchesActiveProfile && create.activeProfileAfter == nil)
        #expect(create.fieldChanges.map(\.id) == [workers])
        let current = envelope(create.after, global: .init(fields: [inactive: .integer(60)]))
        let replacement = PolicyValues(fields: [workers: .integer(4)])
        let untouched = SavedProfile(id: q, name: "Other", values: .init())
        let direct = try SessionProfiles.update(id: p, values: replacement,
            inherited: current.preferences!.global, in: [untouched, create.after!])
        #expect(direct == [untouched,
            SavedProfile(id: p, name: "Build", values: replacement)])
        let update = try SettingsWorkflow.previewProfile(.update(id: p, values: replacement),
                                                           current: current)
        #expect(update.kind == .update && update.before == create.after)
        #expect(update.after == direct[1] && update.activeProfileAfter == nil)
        #expect(update.delta.profiles == [.update(id: p, base: create.after!, edited: direct[1])])
        #expect(update.fieldChanges.map(\.id) == [workers])
        #expect(update.fieldChanges.first?.oldValue == .integer(2))
        #expect(update.fieldChanges.first?.newValue == .integer(4))
        let factory = try SettingsWorkflow.previewProfile(.createFactory(key: "xcode", id: q,
            name: "Xcode"), current: current)
        #expect(factory.kind == .createFactory && factory.after?.id == q)
        #expect(factory.after?.values.fields.isEmpty == false)
        #expect(factory.activeProfileAfter == nil && !factory.delta.touchesActiveProfile)
        let clone = try SettingsWorkflow.previewProfile(.clone(sourceID: p, newID: q,
                                                                 name: "Clone"), current: current)
        #expect(clone.after?.id == q && clone.after?.values == create.after?.values)
        #expect(clone.activeProfileAfter == nil)
        let rename = try SettingsWorkflow.previewProfile(.rename(id: p, name: "Renamed"),
                                                           current: current)
        #expect(rename.before?.name == "Build" && rename.after?.name == "Renamed")
        #expect(rename.fieldChanges.isEmpty && rename.effect == .none)
        let activate = try SettingsWorkflow.previewProfile(.activate(p), current: current)
        #expect(activate.delta.profiles.isEmpty && activate.delta.touchesActiveProfile)
        #expect(activate.delta.activeProfileEdit == p && activate.effect == .invalidate)
        let active = envelope(create.after, active: p)
        let delete = try SettingsWorkflow.previewProfile(.delete(id: p), current: active)
        #expect(delete.delta.profiles == [.delete(id: p, base: create.after!)])
        #expect(delete.delta.touchesActiveProfile && delete.delta.activeProfileEdit == nil)
        #expect(delete.effect == .invalidate)
    }

    @Test func lifecycleNegatives() throws {
        let profile = SavedProfile(id: p, name: "One", values: .init())
        #expect(throws: SettingsWorkflowError.invalidActivation(q)) {
            _ = try SettingsWorkflow.previewProfile(.activate(q), current: envelope(profile))
        }
        #expect(throws: SessionProfileError.duplicateID(p)) {
            _ = try SettingsWorkflow.previewProfile(.create(id: p, name: "Again",
                values: .init()), current: envelope(profile))
        }
        let lowPower = SettingID(rawValue: "scan.onLowPower")
        let protected = SavedProfile(id: p, name: "Protected",
            values: .init(fields: [lowPower: .choice("pauseAll")]))
        #expect(throws: SessionProfileError.protectionWeakening(lowPower)) {
            _ = try SessionProfiles.update(id: p, values: .init(), inherited: .init(),
                                           in: [protected])
        }
        #expect(throws: SessionProfileError.protectionWeakening(lowPower)) {
            _ = try SettingsWorkflow.previewProfile(.update(id: p, values: .init()),
                                                     current: envelope(protected))
        }
        let equalRemoval = try SessionProfiles.update(id: p, values: .init(),
            inherited: .init(fields: [lowPower: .choice("pauseAll")]), in: [protected])
        #expect(equalRemoval[0].values.fields[lowPower] == nil)
        let strengthened = try SessionProfiles.update(id: p,
            values: .init(fields: [lowPower: .choice("pauseAll")]), inherited: .init(),
            in: [profile])
        #expect(strengthened[0].values.fields[lowPower] == .choice("pauseAll"))
        #expect(throws: SessionProfileError.missingProfile(q)) {
            _ = try SessionProfiles.update(id: q, values: .init(), inherited: .init(),
                                           in: [profile])
        }
        #expect(throws: SessionProfileError.duplicateID(p)) {
            _ = try SessionProfiles.update(id: p, values: .init(), inherited: .init(),
                                           in: [profile, profile])
        }
        let duplicate = SettingsEnvelope(schemaVersion: 2, revision: 7,
            config: TidyConfig(schemaVersion: 2),
            preferences: PolicyPreferences(profiles: [profile, profile]))
        #expect(throws: SettingsWorkflowError.duplicateProfile(p)) {
            _ = try SettingsWorkflow.previewProfile(.activate(nil), current: duplicate)
        }
    }

    @Test func selectiveResetPreservesImmutableState() throws {
        let profile = SavedProfile(id: p, name: "Build",
            values: .init(fields: [workers: .integer(1)]))
        let projects = ["local": PolicyValues(fields: [workers: .integer(3)])]
        let current = envelope(profile, global: .init(fields: [
            inactive: .integer(90), workers: .integer(3)]),
                               projects: projects)
        let preview = try SettingsWorkflow.previewSelectiveReset(.init(
            globalPreferenceIDs: [inactive, workers], profileID: p,
            profileFieldIDs: [workers]), current: current)
        #expect(preview.immutableBoundaries == Set(SettingsResetBoundary.allCases))
        #expect(Set(preview.globalChanges.map(\.id)) == Set([inactive, workers]))
        #expect(preview.profileReset?.changes.map(\.id) == [workers])
        let sameID = try #require(preview.profileReset?.changes.first)
        #expect(sameID.oldValue == .integer(1) && sameID.newValue == nil)
        #expect(sameID.oldSource == .explicit && sameID.newSource == .registryDefault)
        #expect(preview.delta.global.contains(.init(id: inactive,
            baseValue: .integer(90), editedValue: nil)))
        #expect(preview.delta.global.contains(.init(id: workers,
            baseValue: .integer(3), editedValue: nil)))
        #expect(preview.delta.inert.isEmpty && !preview.delta.touchesActiveProfile)
        let applied = try PreferencesDocumentProjection.apply(preview.delta, to: current)
        #expect(applied.envelope.preferences?.global.fields[inactive] == nil)
        #expect(applied.envelope.preferences?.global.fields[workers] == nil)
        #expect(applied.envelope.preferences?.profiles.first?.values.fields[workers] == nil)
        #expect(applied.envelope.preferences?.projects == projects)
        #expect(applied.envelope.config == current.config)
    }

    @Test func resetNegatives() throws {
        let globalRestriction = SettingID(rawValue: "scan.onLowPower")
        let current = envelope(global: .init(fields: [
            inactive: .integer(90), globalRestriction: .choice("pauseAll")]))
        #expect(throws: SettingsWorkflowError.ineligibleGlobalReset(roots)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                globalPreferenceIDs: [roots]), current: current)
        }
        let unknown = SettingID(rawValue: "fixture.unknown")
        #expect(throws: SettingsWorkflowError.ineligibleGlobalReset(unknown)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                globalPreferenceIDs: [unknown]), current: current)
        }
        #expect(throws: SettingsWorkflowError.ineligibleGlobalReset(globalRestriction)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                globalPreferenceIDs: [globalRestriction]), current: current)
        }
        #expect(throws: SettingsWorkflowError.emptyConfirmation) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(), current: current)
        }
        let absentKnown = envelope(global: .init(fields: [globalRestriction: .choice("pauseAll")]))
        #expect(throws: SettingsWorkflowError.ineligibleGlobalReset(inactive)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                globalPreferenceIDs: [inactive]), current: absentKnown)
        }
        #expect(throws: SettingsWorkflowError.profileRequired) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                profileFieldIDs: [workers]), current: current)
        }
        #expect(throws: SettingsWorkflowError.missingProfile(q)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(profileID: q,
                profileFieldIDs: [workers]), current: current)
        }
        let excessive = Set((0...1_000).map {
            SettingID(rawValue: "fixture.reset.\($0)")
        })
        #expect(throws: SettingsWorkflowError.tooManySelectedFields) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                globalPreferenceIDs: excessive), current: current)
        }
        let restriction = SettingID(rawValue: "feature.headroom")
        let protected = SavedProfile(id: p, name: "Protected",
            values: .init(fields: [restriction: .bool(false)]))
        #expect(throws: SessionProfileError.restrictionResetRequiresPreview(restriction)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(profileID: p,
                profileFieldIDs: [restriction]), current: envelope(protected))
        }
        let optedIn = try SettingsWorkflow.previewSelectiveReset(.init(profileID: p,
            profileFieldIDs: [restriction], includeOwnedProfileRestrictions: true),
            current: envelope(protected))
        #expect(optedIn.profileReset?.changes.map(\.id) == [restriction])
        #expect(SettingsWorkflow.maximumSelectedResetFields == 1_000)
    }

    @Test func importUISummaryIsPublicBoundedAndMinimal() throws {
        let analysisID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let row = SettingsImportRow(scope: .global, profileID: nil, id: "future.safe",
            idDigest: nil, outcome: .inert, value: .bool(true), valueKind: nil,
            valueDigest: nil)
        let analysis = SettingsImportAnalysis(analysisID: analysisID, rows: [row], collisions: [],
            committableImported: .init(), importedInert: [], current: .init())
        let summary = try SettingsImportUISummary(analysis)
        #expect(summary.analysisID == analysisID && summary.rows == [row])
        #expect(Set(Mirror(reflecting: summary).children.compactMap { $0.label }) ==
            Set(["analysisID", "rows", "collisions"]))
        let noID = SettingsImportAnalysis(rows: [], collisions: [], committableImported: .init(),
            importedInert: [], current: .init())
        #expect(throws: SettingsWorkflowError.missingAnalysisID) {
            _ = try SettingsImportUISummary(noID)
        }
        let overRows = SettingsImportAnalysis(analysisID: analysisID,
            rows: Array(repeating: row, count: 1_001), collisions: [],
            committableImported: .init(), importedInert: [], current: .init())
        #expect(throws: SettingsWorkflowError.tooManyImportRows) {
            _ = try SettingsImportUISummary(overRows)
        }
        let collisions = (0...50).map { index in
            ProfileImportCollision(profileID: UUID(uuidString: String(format:
                "90000000-0000-0000-0000-%012d", index))!, localName: "L", importedName: "I")
        }
        let overCollisions = SettingsImportAnalysis(analysisID: analysisID, rows: [],
            collisions: collisions, committableImported: .init(), importedInert: [], current: .init())
        #expect(throws: SettingsWorkflowError.tooManyImportCollisions) {
            _ = try SettingsImportUISummary(overCollisions)
        }
    }

    @Test func exportBoundary() throws {
        var config = TidyConfig(schemaVersion: 2); config.gitRoots = ["/secret/root"]
        let authority = SettingID(rawValue: "maintenance.mode")
        let localIdentity = SettingID(rawValue: "scope.currentProject")
        let inert = InertPortableSetting(scope: .global, profileID: nil,
            id: "future.safe", value: .bool(true), valueKind: nil,
            valueDigest: nil, redacted: false)
        let profile = SavedProfile(id: p, name: "Build",
            values: .init(fields: [workers: .integer(2)]))
        let current = SettingsEnvelope(schemaVersion: 2, revision: 9, config: config,
            preferences: .init(global: .init(fields: [inactive: .integer(90),
                authority: .choice("off"), localIdentity: .choice("private-project")]),
                profiles: [profile], projects: ["local": .init()]), activeProfileID: p,
            inertImports: [inert])
        let text = try #require(String(data:
            SettingsWorkflow.exportPortable(current: current), encoding: .utf8))
        #expect(text.contains("cleanup.inactiveDays"))
        #expect(!text.contains("/secret/root") && !text.contains("activeProfileID"))
        #expect(!text.contains("projects") && !text.contains("TidyConfig"))
        #expect(!text.contains(authority.rawValue) && !text.contains(localIdentity.rawValue))
        #expect(!text.contains("private-project"))
        #expect(text.contains("future.safe"))
    }
}
```

RED command: `swift test --package-path TidyCore --jobs 2 --filter SettingsWorkflowTests`. Expected: missing `SettingsWorkflow*` APIs only.

## Complete RED app-model/render extension

First make this **genuine T07.3a contract correction** in the existing `testSettingsSourceHasNoOnOpenWorkTrigger`: remove only `"Task {"` from its `forbidden` array, then copy the delimited-block assertions from the new source test below. The corrected test requires exactly four `Task {}` occurrences inside the named synchronous task-return boundary and zero outside. This is necessary because SwiftUI synchronous actions must bridge analysis, issuance, accepted-outcome confirmation, and cancellation into the accepted async T07.2 actor/bridge while `.task` and every implicit lifecycle trigger remain forbidden. No other existing assertion is weakened.

Append to `SharedSettingsWiringTests.swift`:

```swift
private enum SettingsWorkflowGatePoint: Hashable {
    case analyzeA, analyzeB, analyzeCancel, issue, submit, rejectCancel
}

@MainActor private final class SettingsWorkflowAsyncGate {
    private var entered: Set<SettingsWorkflowGatePoint> = []
    private var blocked: [SettingsWorkflowGatePoint: CheckedContinuation<Void, Never>] = [:]
    private var entryWaiters: [SettingsWorkflowGatePoint: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<SettingsWorkflowGatePoint> = []
    private(set) var cancelledAnalysisIDs: [SettingsImportAnalysisID] = []
    private(set) var cancelledPreviewIDs: [SettingsImportPreviewID] = []

    func suspend(at point: SettingsWorkflowGatePoint) async {
        entered.insert(point)
        entryWaiters.removeValue(forKey: point)?.resume()
        if released.remove(point) != nil { return }
        await withCheckedContinuation { continuation in
            guard blocked[point] == nil else {
                XCTFail("Duplicate bounded blocker: \(point)")
                continuation.resume(); return
            }
            blocked[point] = continuation
        }
    }

    func waitUntilEntered(_ point: SettingsWorkflowGatePoint) async {
        if entered.contains(point) { return }
        await withCheckedContinuation { continuation in
            guard entryWaiters[point] == nil else {
                XCTFail("Duplicate bounded entry waiter: \(point)")
                continuation.resume(); return
            }
            entryWaiters[point] = continuation
        }
    }

    func release(_ point: SettingsWorkflowGatePoint) {
        guard let waiter = blocked.removeValue(forKey: point) else {
            released.insert(point); return
        }
        waiter.resume()
    }

    func recordAnalysisCancellation(_ id: SettingsImportAnalysisID) {
        cancelledAnalysisIDs.append(id)
    }

    func recordPreviewCancellation(_ id: SettingsImportPreviewID) {
        cancelledPreviewIDs.append(id)
    }
}

private enum SettingsWorkflowFixtureError: Error { case failedAnalysis, failedIssuance }

extension SharedSettingsWiringTests {
    private func workflowSummary(_ id: UUID,
                                 collisions: [ProfileImportCollision] = []) throws
        -> SettingsImportUISummary {
        try SettingsImportUISummary(SettingsImportAnalysis(analysisID: id, rows: [],
            collisions: collisions, committableImported: .init(), importedInert: [], current: .init()))
    }

    private func workflowPreview(_ summary: SettingsImportUISummary) -> SettingsImportPreview {
        SettingsImportPreview(id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            analysisID: summary.analysisID, rows: summary.rows,
            collisions: summary.collisions, choices: [:], candidate: .init(),
            sourceDigest: String(repeating: "a", count: 64),
            candidateDigest: String(repeating: "b", count: 64))
    }

    @MainActor func testWorkflowPreviewConfirmCancelAndTwoWindows() async throws {
        try await run { _, services, _ in
            let store = services.configStore
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let c = SettingsWorkflowController(store: store,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
            let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
            let factoryID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
            let cloneID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
            var expectedRevision = store.settingsRevision
            let before = store.preferences
            try c.prepareProfile(.create(id: id, name: "Build", values: .init()))
            XCTAssertEqual(store.preferences, before)
            c.cancelConfirmation(); XCTAssertNil(c.confirmPreparedChange())
            XCTAssertEqual(store.preferences, before)
            try c.prepareProfile(.create(id: id, name: "Build", values: .init()))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain()
            expectedRevision += 1
            XCTAssertEqual(store.profiles.first?.id, id); XCTAssertNil(store.activeProfileID)
            XCTAssertEqual(store.settingsRevision, expectedRevision)
            XCTAssertEqual(second.settingsRevision, expectedRevision)
            try c.prepareProfile(.rename(id: id, name: "Renamed"))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertEqual(store.profiles.first(where: { $0.id == id })?.name, "Renamed")
            XCTAssertEqual(second.settingsRevision, expectedRevision)
            let workers = SettingID(rawValue: "scan.requestedWorkers")
            try c.prepareProfile(.update(id: id,
                values: .init(fields: [workers: .integer(2)])))
            guard case .profile(let updatePreview)? = c.confirmation else { return XCTFail() }
            XCTAssertEqual(updatePreview.kind, .update)
            XCTAssertEqual(updatePreview.fieldChanges.map(\.id), [workers])
            c.cancelConfirmation()
            XCTAssertNil(store.profiles.first(where: { $0.id == id })?.values.fields[workers])
            try c.prepareProfile(.update(id: id,
                values: .init(fields: [workers: .integer(2)])))
            guard case .some(.accepted(_, let updateTask)) = c.confirmPreparedChange(),
                  case .saved = await updateTask.value else { return XCTFail("Update not saved") }
            expectedRevision += 1
            XCTAssertEqual(store.profiles.first(where: { $0.id == id })?.values.fields[workers],
                           .integer(2))
            XCTAssertEqual(second.profiles, store.profiles)
            XCTAssertEqual(second.settingsRevision, expectedRevision)
            try c.prepareProfile(.createFactory(key: "xcode", id: factoryID, name: "Xcode"))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertNotNil(store.profiles.first(where: { $0.id == factoryID }))
            XCTAssertNil(store.activeProfileID); XCTAssertEqual(second.settingsRevision, expectedRevision)
            try c.prepareProfile(.clone(sourceID: id, newID: cloneID, name: "Clone"))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertEqual(store.profiles.first(where: { $0.id == cloneID })?.values,
                           store.profiles.first(where: { $0.id == id })?.values)
            XCTAssertNil(store.activeProfileID); XCTAssertEqual(second.settingsRevision, expectedRevision)
            try c.prepareProfile(.activate(id))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            XCTAssertFalse(services.policyBridge.isExecutionEnabled)
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertEqual(store.activeProfileID, id); XCTAssertEqual(second.activeProfileID, id)
            XCTAssertEqual(second.settingsRevision, expectedRevision)
            try c.prepareProfile(.activate(nil))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertNil(store.activeProfileID); XCTAssertNil(second.activeProfileID)
            try c.prepareProfile(.activate(id))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            try c.prepareProfile(.delete(id: factoryID))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertEqual(store.activeProfileID, id)
            XCTAssertNil(store.profiles.first(where: { $0.id == factoryID }))
            try c.prepareProfile(.delete(id: id))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertNil(store.profiles.first(where: { $0.id == id }))
            XCTAssertEqual(Set(store.profiles.map(\.id)), Set([cloneID]))
            XCTAssertNil(store.activeProfileID)
            XCTAssertEqual(store.settingsRevision, expectedRevision)
            XCTAssertEqual(second.settingsRevision, expectedRevision)
        }
    }

    @MainActor func testStaleProfilePreviewsConflictAndPreserveOtherWindow() async throws {
        let id = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let original = SavedProfile(id: id, name: "Original", values: .init())
        let seed = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [original])))

        try await run(seed: seed) { _, services, _ in
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let a = SettingsWorkflowController(store: first, bundle: bundle)
            let b = SettingsWorkflowController(store: second, bundle: bundle)
            try a.prepareProfile(.rename(id: id, name: "Stale rename"))
            try b.prepareProfile(.delete(id: id))
            guard case .some(.accepted(_, let bTask)) = b.confirmPreparedChange()
            else { return XCTFail("B delete rejected") }
            guard case .saved = await bTask.value else { return XCTFail("B delete not saved") }
            guard case .some(.rejected(_, .invalid)) = a.confirmPreparedChange()
            else { return XCTFail("A stale rename was not synchronously rejected") }
            await services.policyBridge.drain()
            XCTAssertTrue(first.profiles.isEmpty); XCTAssertTrue(second.profiles.isEmpty)
            let durable = await services.settings.load()
            XCTAssertTrue(durable.envelope?.preferences?.profiles.isEmpty == true)
        }

        try await run(seed: seed) { _, services, _ in
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let a = SettingsWorkflowController(store: first, bundle: bundle)
            let b = SettingsWorkflowController(store: second, bundle: bundle)
            try a.prepareProfile(.delete(id: id))
            try b.prepareProfile(.rename(id: id, name: "B wins"))
            guard case .some(.accepted(_, let bTask)) = b.confirmPreparedChange(),
                  case .saved = await bTask.value else { return XCTFail("B rename not saved") }
            guard case .some(.rejected(_, .invalid)) = a.confirmPreparedChange()
            else { return XCTFail("A stale delete was not synchronously rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(first.profiles, [SavedProfile(id: id, name: "B wins", values: .init())])
            XCTAssertEqual(second.profiles, first.profiles)
            let durable = await services.settings.load()
            XCTAssertEqual(durable.envelope?.preferences?.profiles ?? [], first.profiles)
        }

        try await run(seed: seed) { _, services, _ in
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let a = SettingsWorkflowController(store: first, bundle: bundle)
            let b = SettingsWorkflowController(store: second, bundle: bundle)
            let workers = SettingID(rawValue: "scan.requestedWorkers")
            try a.prepareProfile(.update(id: id,
                values: .init(fields: [workers: .integer(2)])))
            try b.prepareProfile(.update(id: id,
                values: .init(fields: [workers: .integer(4)])))
            guard case .some(.accepted(_, let bTask)) = b.confirmPreparedChange(),
                  case .saved = await bTask.value else { return XCTFail("B update not saved") }
            guard case .some(.rejected(_, .invalid)) = a.confirmPreparedChange()
            else { return XCTFail("A stale value update was not rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(first.profiles.first?.values.fields[workers], .integer(4))
            XCTAssertEqual(second.profiles, first.profiles)
            let durable = await services.settings.load()
            XCTAssertEqual(durable.envelope?.preferences?.profiles, first.profiles)
        }
    }

    @MainActor func testOlderUnrelatedPreviewRebasesAndPendingInterleaveConverges() async throws {
        let id = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let units = SettingID(rawValue: "ui.units")
        let original = SavedProfile(id: id, name: "Original", values: .init())
        let seed = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [original])))

        try await run(seed: seed) { _, services, _ in
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let a = SettingsWorkflowController(store: first,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
            try a.prepareProfile(.rename(id: id, name: "A"))
            guard case .accepted(_, let bTask) = second.setGlobalPreference(
                units, to: .choice("decimal")), case .saved = await bTask.value
            else { return XCTFail("Unrelated B save failed") }
            guard case .some(.accepted(_, let aTask)) = a.confirmPreparedChange(),
                  case .saved = await aTask.value else {
                return XCTFail("Older unrelated A delta did not rebase")
            }
            await services.policyBridge.drain()
            XCTAssertEqual(first.profiles.first?.name, "A")
            XCTAssertEqual(first.preferences.global.fields[units], .choice("decimal"))
            XCTAssertEqual(second.preferences, first.preferences)
        }

        try await run(stops: ["config.1"], seed: seed) { _, services, io in
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let a = SettingsWorkflowController(store: first,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
            try a.prepareProfile(.rename(id: id, name: "Queued A"))
            guard case .accepted = second.setGlobalPreference(units, to: .choice("decimal"))
            else { return XCTFail("Queued B save rejected") }
            try await io.probe.waitFor("config.1")
            guard case .some(.accepted) = a.confirmPreparedChange()
            else { return XCTFail("Pending A save rejected") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 2)
            io.probe.release("config.1")
            await services.policyBridge.drain()
            XCTAssertEqual(first.profiles.first?.name, "Queued A")
            XCTAssertEqual(first.preferences.global.fields[units], .choice("decimal"))
            XCTAssertEqual(second.preferences, first.preferences)
            XCTAssertEqual(first.settingsRevision, 2)
            XCTAssertEqual(second.settingsRevision, 2)
        }
    }

    @MainActor func testImportTaxonomyIssueConfirmCancelAndNoActivation() async throws {
        try await run { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            let profileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
            try c.prepareProfile(.create(id: profileID, name: "Collision", values: .init()))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain()
            let data = try services.configStore.exportPortableSettings()
            let before = services.configStore.preferences
            let revision = services.configStore.settingsRevision
            await c.beginImportSelection(bytes: data).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            let shown = SettingsWorkflowPresentation.importOutcomes(summary)
            XCTAssertEqual(shown.map(\.outcome), SettingsWorkflowPresentation.importOutcomeOrder)
            XCTAssertEqual(Set(shown.map(\.outcome.rawValue)), Set([
                SettingsImportOutcome.committable, .collision, .inert, .redacted, .requiresLocalReassociation,
                .rejectedAuthority, .rejectedProtectionWeakening, .rejectedInvalid,
                .rejectedNonPortable, .rejectedUnsupportedLayer].map(\.rawValue)))
            XCTAssertTrue(shown.allSatisfy { SettingsWorkflowPresentation.accessibilityID(
                for: $0.outcome) == "settings.import.outcome." + $0.outcome.rawValue })
            XCTAssertEqual(summary.collisions.map(\.profileID), [profileID])
            XCTAssertEqual(SettingsWorkflowPresentation.canIssuePreview(
                summary: summary, choices: [:]), false)
            c.chooseCollision(profileID: profileID, choice: .keepLocal)
            XCTAssertTrue(SettingsWorkflowPresentation.canIssuePreview(
                summary: summary, choices: c.collisionChoices))
            await c.beginImportCancellation().value
            XCTAssertEqual(c.importState, .idle); XCTAssertEqual(services.configStore.preferences, before)
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            await c.beginImportSelection(bytes: data).value
            guard case .analysis(let secondAnalysis) = c.importState else { return XCTFail() }
            for collision in secondAnalysis.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .replace)
            }
            await c.beginImportPreviewIssuance().value
            guard case .confirmation = c.importState else { return XCTFail() }
            await c.beginImportCancellation().value
            XCTAssertEqual(services.configStore.preferences, before)
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            await c.beginImportSelection(bytes: data).value
            guard case .analysis(let thirdAnalysis) = c.importState else { return XCTFail() }
            let cloneID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
            for collision in thirdAnalysis.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .clone(cloneID))
            }
            XCTAssertEqual(c.collisionChoices[profileID], .clone(cloneID))
            await c.beginImportPreviewIssuance().value
            guard case .confirmation(let preview) = c.importState else { return XCTFail() }
            let active = services.configStore.activeProfileID
            XCTAssertEqual(preview.candidate.preferences.projects, [:])
            XCTAssertNotNil(preview.candidate.preferences.profiles.first(where: {
                $0.id == cloneID
            }))
            await c.beginImportConfirmation().value
            XCTAssertEqual(c.importState, .idle)
            XCTAssertEqual(services.configStore.activeProfileID, active)
            XCTAssertNotNil(services.configStore.profiles.first(where: { $0.id == cloneID }))
            XCTAssertEqual(services.configStore.settingsRevision, revision + 1)
            let generation = services.policyBridge.updateGeneration
            await c.beginImportConfirmation().value
            XCTAssertEqual(c.importState, .idle)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
        }
    }

    @MainActor func testImportConfirmationAwaitsSavedAndConsumesTokenOnce() async throws {
        let profileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let cloneID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let seed = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [
                SavedProfile(id: profileID, name: "Local", values: .init())])))
        try await run(stops: ["config.1"], seed: seed) { _, services, io in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            let bytes = try services.configStore.exportPortableSettings()
            await c.beginImportSelection(bytes: bytes).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            for collision in summary.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .clone(cloneID))
            }
            await c.beginImportPreviewIssuance().value
            guard case .confirmation(let preview) = c.importState else { return XCTFail() }
            let revision = services.configStore.settingsRevision
            let confirmation = c.beginImportConfirmation()
            try await io.probe.waitFor("config.1")
            XCTAssertEqual(c.importState, .submitting(preview.id),
                           "UI claimed saved before the accepted outcome")
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            io.probe.release("config.1")
            await confirmation.value
            XCTAssertEqual(c.importState, .idle)
            XCTAssertEqual(services.configStore.settingsRevision, revision + 1)
            XCTAssertNotNil(services.configStore.profiles.first(where: { $0.id == cloneID }))
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Consumed import token was accepted twice") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
        }
    }

    @MainActor func testImportConfirmationConflictAndPersistenceFailureNeverClaimSaved() async throws {
        let profileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let cloneID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let seed = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [
                SavedProfile(id: profileID, name: "Local", values: .init())])))

        try await run(seed: seed) { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            let bytes = try services.configStore.exportPortableSettings()
            await c.beginImportSelection(bytes: bytes).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            for collision in summary.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .clone(cloneID))
            }
            await c.beginImportPreviewIssuance().value
            guard case .confirmation(let preview) = c.importState else { return XCTFail() }
            guard case .accepted(_, let otherTask) = services.configStore.setGlobalPreference(
                SettingID(rawValue: "ui.units"), to: .choice("decimal")),
                  case .saved = await otherTask.value else { return XCTFail("Other save failed") }
            let revision = services.configStore.settingsRevision
            await c.beginImportConfirmation().value
            XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                "settings.import.failure", bundle: bundle)))
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            XCTAssertNil(services.configStore.profiles.first(where: { $0.id == cloneID }))
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Invalidated token remained usable") }
        }

        try await run(seed: seed, fault: .configReplaceNumber(1)) { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            let before = services.configStore.preferences
            let revision = services.configStore.settingsRevision
            let bytes = try services.configStore.exportPortableSettings()
            await c.beginImportSelection(bytes: bytes).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            for collision in summary.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .clone(cloneID))
            }
            await c.beginImportPreviewIssuance().value
            guard case .confirmation(let preview) = c.importState else { return XCTFail() }
            await c.beginImportConfirmation().value
            XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                "settings.import.failure", bundle: bundle)))
            XCTAssertEqual(services.configStore.preferences, before)
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            XCTAssertNil(services.configStore.profiles.first(where: { $0.id == cloneID }))
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Failed import token remained reusable") }
        }
    }

    @MainActor func testLiveRejectedConfirmationClearsIssuedBindingWithoutRetention() async throws {
        let profileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let cloneID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let seed = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [
                SavedProfile(id: profileID, name: "Local", values: .init())])))
        try await run(stops: ["config.1"], seed: seed) { _, services, io in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            let bytes = try services.configStore.exportPortableSettings()
            await c.beginImportSelection(bytes: bytes).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            for collision in summary.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .clone(cloneID))
            }
            await c.beginImportPreviewIssuance().value
            guard case .confirmation(let oldPreview) = c.importState else { return XCTFail() }
            guard case .accepted = services.configStore.setGlobalPreference(
                SettingID(rawValue: "ui.units"), to: .choice("decimal"))
            else { return XCTFail("Unrelated write was not enqueued") }
            try await io.probe.waitFor("config.1")
            let retainedCount = services.policyBridge.pendingSnapshotCount
            let retainedBytes = services.policyBridge.pendingSnapshotBytes
            XCTAssertEqual(retainedCount, 1); XCTAssertGreaterThan(retainedBytes, 0)
            let rejection = c.beginImportConfirmation()
            XCTAssertEqual(c.importState, .submitting(oldPreview.id))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, retainedCount)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, retainedBytes,
                           "Rejected import retained payload bytes")
            io.probe.release("config.1")
            await rejection.value
            await services.policyBridge.drain()
            XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                "settings.import.failure", bundle: bundle)))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            guard case .rejected(_, .invalid) = services.configStore.commitImport(oldPreview)
            else { return XCTFail("Cancelled issued preview binding remained reusable") }
            XCTAssertNil(services.configStore.profiles.first(where: { $0.id == cloneID }))
        }
    }

    @MainActor func testImportConfirmationHandlesEveryAcceptedNonSavedOutcome() async throws {
        try await run { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let summary = try self.workflowSummary(UUID(uuidString:
                "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
            let preview = self.workflowPreview(summary)
            let intent = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
            let outcomes: [SettingsIntentOutcome] = [
                .conflict(intent), .invalid(intent), .failed(intent, recoveryRequired: true)
            ]
            for outcome in outcomes {
                var submissionCount = 0
                let operations = SettingsWorkflowImportOperations(
                    analyze: { _ in summary }, issue: { _, _ in preview },
                    cancelAnalysis: { _ in }, cancelPreview: { _ in },
                    submit: { _ in
                        submissionCount += 1
                        return .accepted(intent, Task { outcome })
                    })
                let c = SettingsWorkflowController(testing: services.configStore,
                    importOperations: operations, bundle: bundle)
                let revision = services.configStore.settingsRevision
                await c.beginImportSelection(bytes: Data([1])).value
                await c.beginImportPreviewIssuance().value
                await c.beginImportConfirmation().value
                XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                    "settings.import.failure", bundle: bundle)))
                XCTAssertEqual(submissionCount, 1)
                XCTAssertEqual(services.configStore.settingsRevision, revision)
                await c.beginImportConfirmation().value
                XCTAssertEqual(submissionCount, 1, "Non-saved preview was submitted twice")
            }
        }
    }

    @MainActor func testSynchronousImportRejectionCancelsIssuedPreviewExactlyOnce() async throws {
        try await run { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let summary = try self.workflowSummary(UUID(uuidString:
                "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
            let preview = self.workflowPreview(summary)
            let intent = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
            let reasons: [SettingsSubmissionRejection] = [
                .invalid, .unsupportedAuthority, .queueFull, .unavailable
            ]
            for reason in reasons {
                let gate = SettingsWorkflowAsyncGate()
                let operations = SettingsWorkflowImportOperations(
                    analyze: { _ in summary }, issue: { _, _ in preview },
                    cancelAnalysis: { _ in },
                    cancelPreview: { id in
                        gate.recordPreviewCancellation(id)
                        await gate.suspend(at: .rejectCancel)
                    },
                    submit: { _ in .rejected(intent, reason) })
                let c = SettingsWorkflowController(testing: services.configStore,
                    importOperations: operations, bundle: bundle)
                await c.beginImportSelection(bytes: Data([1])).value
                await c.beginImportPreviewIssuance().value
                let confirmation = c.beginImportConfirmation()
                await gate.waitUntilEntered(.rejectCancel)
                XCTAssertEqual(c.importState, .submitting(preview.id),
                               "Failure was shown before cancellation for \(reason)")
                XCTAssertEqual(gate.cancelledPreviewIDs, [preview.id])
                gate.release(.rejectCancel); await confirmation.value
                XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                    "settings.import.failure", bundle: bundle)))
                XCTAssertEqual(gate.cancelledPreviewIDs, [preview.id])
                await c.beginImportConfirmation().value
                XCTAssertEqual(gate.cancelledPreviewIDs, [preview.id])
            }
        }
    }

    @MainActor func testImportGenerationSupersedesAndCancelsDeterministically() async throws {
        try await run { _, services, _ in
            let gate = SettingsWorkflowAsyncGate()
            let a = try self.workflowSummary(UUID(uuidString:
                "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
            let b = try self.workflowSummary(UUID(uuidString:
                "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
            let preview = self.workflowPreview(b)
            let intent = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
            var acceptedSubmissionCount = 0
            let operations = SettingsWorkflowImportOperations(
                analyze: { data in
                    switch data.first {
                    case 1:
                        await gate.suspend(at: .analyzeA)
                        throw SettingsWorkflowFixtureError.failedAnalysis
                    case 2:
                        await gate.suspend(at: .analyzeB); return b
                    case 3:
                        await gate.suspend(at: .analyzeCancel); return a
                    default: return b
                    }
                },
                issue: { _, _ in await gate.suspend(at: .issue); return preview },
                cancelAnalysis: { gate.recordAnalysisCancellation($0) },
                cancelPreview: { gate.recordPreviewCancellation($0) },
                submit: { _ in
                    acceptedSubmissionCount += 1
                    return .accepted(intent, Task {
                        await gate.suspend(at: .submit); return .invalid(intent)
                    })
                })

            let testBundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(testing: services.configStore,
                                               importOperations: operations,
                                               bundle: testBundle)
            XCTAssertTrue(c.bundle === testBundle)
            let first = c.beginImportSelection(bytes: Data([1]))
            await gate.waitUntilEntered(.analyzeA)
            let second = c.beginImportSelection(bytes: Data([2]))
            await gate.waitUntilEntered(.analyzeB)
            gate.release(.analyzeB); await second.value
            XCTAssertEqual(c.importState, .analysis(b))
            gate.release(.analyzeA); await first.value
            XCTAssertEqual(c.importState, .analysis(b), "stale failure replaced newer success")

            let cancelDuringAnalysis = c.beginImportSelection(bytes: Data([3]))
            await gate.waitUntilEntered(.analyzeCancel)
            await c.beginImportCancellation().value
            XCTAssertEqual(c.importState, .idle)
            XCTAssertTrue(gate.cancelledAnalysisIDs.contains(b.analysisID))
            gate.release(.analyzeCancel); await cancelDuringAnalysis.value
            XCTAssertEqual(c.importState, .idle, "cancelled analysis completed into UI")
            XCTAssertTrue(gate.cancelledAnalysisIDs.contains(a.analysisID),
                          "stale returned analysis token was retained")

            await c.beginImportSelection(bytes: Data([9])).value
            XCTAssertEqual(c.importState, .analysis(b))
            let issuing = c.beginImportPreviewIssuance()
            await gate.waitUntilEntered(.issue)
            await c.beginImportCancellation().value
            XCTAssertEqual(c.importState, .idle)
            gate.release(.issue); await issuing.value
            XCTAssertEqual(c.importState, .idle, "cancelled issuance restored preview")
            XCTAssertTrue(gate.cancelledPreviewIDs.contains(preview.id))

            await c.beginImportSelection(bytes: Data([9])).value
            let issueForConfirmation = c.beginImportPreviewIssuance()
            await gate.waitUntilEntered(.issue); gate.release(.issue)
            await issueForConfirmation.value
            guard case .confirmation = c.importState else { return XCTFail() }
            let confirming = c.beginImportConfirmation()
            await gate.waitUntilEntered(.submit)
            let previewCancellationCount = gate.cancelledPreviewIDs.count
            await c.beginImportSelection(bytes: Data([9])).value
            await c.beginImportPreviewIssuance().value
            await c.beginImportConfirmation().value
            await c.beginImportCancellation().value
            XCTAssertEqual(c.importState, .submitting(preview.id),
                           "A public boundary superseded an accepted write")
            XCTAssertEqual(acceptedSubmissionCount, 1,
                           "Accepted preview was submitted more than once")
            XCTAssertEqual(gate.cancelledPreviewIDs.count, previewCancellationCount,
                           "Submitting cancellation touched an accepted token")
            gate.release(.submit); await confirming.value
            XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                "settings.import.failure", bundle: testBundle)),
                "Accepted invalid outcome was generation-suppressed")

            let cancellationCount = gate.cancelledAnalysisIDs.count
            let failing = SettingsWorkflowImportOperations(analyze: { _ in b },
                issue: { _, _ in throw SettingsWorkflowFixtureError.failedIssuance },
                cancelAnalysis: { gate.recordAnalysisCancellation($0) },
                cancelPreview: { gate.recordPreviewCancellation($0) },
                submit: { services.configStore.commitImport($0) })
            let failed = SettingsWorkflowController(testing: services.configStore,
                                                    importOperations: failing,
                                                    bundle: testBundle)
            await failed.beginImportSelection(bytes: Data([9])).value
            await failed.beginImportPreviewIssuance().value
            guard case .failed(let message) = failed.importState else { return XCTFail() }
            XCTAssertEqual(message, SettingsCopy.resolve("settings.import.failure",
                bundle: testBundle))
            XCTAssertEqual(gate.cancelledAnalysisIDs.count, cancellationCount + 1)
        }
    }

    @MainActor func testLiveImportIssuanceRejectsWhileSettingsWriteIsQueued() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore,
                bundle: bundle)
            XCTAssertTrue(c.bundle === bundle)
            let bytes = try services.configStore.exportPortableSettings()
            await c.beginImportSelection(bytes: bytes).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            guard case .accepted = services.configStore.setGlobalPreference(
                SettingID(rawValue: "ui.units"), to: .choice("decimal"))
            else { return XCTFail("Queue head rejected") }
            try await io.probe.waitFor("config.1")
            let generation = services.policyBridge.updateGeneration
            await c.beginImportPreviewIssuance().value
            guard case .failed(let message) = c.importState else { return XCTFail() }
            XCTAssertEqual(message, SettingsCopy.resolve("settings.import.failure",
                bundle: bundle))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 1)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            io.probe.release("config.1")
            await services.policyBridge.drain()
            do {
                _ = try await services.configStore.issueImportPreview(
                    analysisID: summary.analysisID, choices: [:])
                XCTFail("Queued issuance left its analysis token usable")
            } catch {
                XCTAssertEqual(error as? SettingsStoreError, .invalidChange)
            }
        }
    }

    @MainActor func testResetExportAndDeferredBoundaries() async throws {
        try await run { _, services, _ in
            let id = SettingID(rawValue: "cleanup.inactiveDays")
            _ = services.configStore.setGlobalPreference(id, to: .integer(90))
            await services.policyBridge.drain()
            let config = services.configStore.config, inert = services.configStore.inertImports
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            try c.prepareReset(.init(globalPreferenceIDs: [id]))
            guard case .reset(let preview)? = c.confirmation else { return XCTFail() }
            XCTAssertEqual(preview.immutableBoundaries, Set(SettingsResetBoundary.allCases))
            XCTAssertTrue(preview.delta.inert.isEmpty && !preview.delta.touchesActiveProfile)
            c.cancelConfirmation(); XCTAssertEqual(services.configStore.config, config)
            XCTAssertEqual(services.configStore.inertImports, inert)
            let revision = services.configStore.settingsRevision
            try c.prepareReset(.init(globalPreferenceIDs: [id]))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain()
            XCTAssertNil(services.configStore.preferences.global.fields[id])
            XCTAssertEqual(services.configStore.settingsRevision, revision + 1)
            XCTAssertEqual(services.configStore.config, config)
            XCTAssertEqual(services.configStore.inertImports, inert)
            let a = try services.configStore.exportPortableSettings()
            let b = try services.configStore.exportPortableSettings()
            XCTAssertEqual(a, b); XCTAssertLessThanOrEqual(a.count, 1_048_576)
            for deferred in SettingsDeferredWorkflow.allCases {
                let key = "settings.deferred.\(deferred.rawValue).explanation"
                XCTAssertEqual(SettingsWorkflowPresentation.deferredExplanationKey(deferred), key)
                let copy = SettingsWorkflowPresentation.deferredExplanation(
                    deferred, bundle: bundle)
                XCTAssertFalse(copy.isEmpty)
                XCTAssertNotEqual(copy, key)
                XCTAssertNotEqual(copy, "Description unavailable.")
                XCTAssertTrue(copy.localizedCaseInsensitiveContains("unavailable"))
            }
        }
    }

    func testSyntheticImportTaxonomyHasExactOrderCountsAndCollisions() throws {
        let order = SettingsWorkflowPresentation.importOutcomeOrder
        XCTAssertEqual(order, [.committable, .collision, .inert, .redacted,
            .requiresLocalReassociation, .rejectedAuthority, .rejectedProtectionWeakening,
            .rejectedInvalid, .rejectedNonPortable, .rejectedUnsupportedLayer])
        var rows: [SettingsImportRow] = []
        for (index, outcome) in order.enumerated() {
            rows += (0...index).map { occurrence in
                SettingsImportRow(scope: .global, profileID: nil,
                    id: "fixture.\(outcome.rawValue).\(occurrence)", idDigest: nil,
                    outcome: outcome, value: nil, valueKind: nil, valueDigest: nil)
            }
        }
        let collisions = [
            ProfileImportCollision(profileID: UUID(uuidString:
                "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, localName: "A", importedName: "A2"),
            ProfileImportCollision(profileID: UUID(uuidString:
                "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, localName: "B", importedName: "B2"),
            ProfileImportCollision(profileID: UUID(uuidString:
                "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!, localName: "D", importedName: "D2")
        ]
        let analysis = SettingsImportAnalysis(analysisID: UUID(uuidString:
            "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!, rows: rows,
            collisions: collisions, committableImported: .init(), importedInert: [], current: .init())
        let summary = try SettingsImportUISummary(analysis)
        let shown = SettingsWorkflowPresentation.importOutcomes(summary)
        XCTAssertEqual(shown.map(\.outcome), order)
        XCTAssertEqual(shown.map(\.count), Array(1...10))
        XCTAssertEqual(summary.collisions, collisions)
        XCTAssertEqual(summary.collisions.count, 3)
        XCTAssertEqual(shown.first(where: { $0.outcome == .collision })?.count, 2)
        XCTAssertEqual(shown.map(\.id), order.map(\.rawValue))
    }

    func testWorkflowControlProjectionIsExhaustiveStableAndContiguous() throws {
        let a = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let b = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let globalField = SettingID(rawValue: "cleanup.inactiveDays")
        let profileField = SettingID(rawValue: "scan.requestedWorkers")
        let restriction = SettingID(rawValue: "feature.headroom")
        let collisions = [
            ProfileImportCollision(profileID: b, localName: "B", importedName: "Imported B"),
            ProfileImportCollision(profileID: a, localName: "A", importedName: "Imported A")
        ]
        let localize: (String) -> String = { "Resolved " + $0 }
        let empty = try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: [], activeProfileID: nil, profileEditor: nil,
            importPhase: .idle, collisions: [], hasCompleteCollisionChoices: false,
            hasPreparedProfile: false, resetGlobalFieldIDs: [], resetProfileID: nil,
            resetProfileFieldIDs: [], ownedRestrictionFieldIDs: [], hasResetSelection: false,
            hasPreparedReset: false), localize: localize)
        let full = try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: [b, a, b], activeProfileID: a,
            profileEditor: .init(target: .profile(a),
                                 valueFieldIDs: [restriction, profileField, restriction]),
            importPhase: .analysis, collisions: collisions,
            hasCompleteCollisionChoices: true, hasPreparedProfile: true,
            resetGlobalFieldIDs: [globalField, globalField], resetProfileID: a,
            resetProfileFieldIDs: [restriction, profileField, restriction],
            ownedRestrictionFieldIDs: [restriction], hasResetSelection: true,
            hasPreparedReset: true), localize: localize)
        for controls in [empty, full] {
            XCTAssertEqual(controls.map(\.focusOrder), Array(controls.indices))
            XCTAssertEqual(Set(controls.map(\.id)).count, controls.count)
            XCTAssertTrue(controls.allSatisfy { !$0.label.isEmpty && $0.label != $0.titleKey })
            for descriptor in controls {
                if case .unavailable(let key, let label) = descriptor.availability {
                    XCTAssertFalse(key.isEmpty); XCTAssertFalse(label.isEmpty)
                    XCTAssertNotEqual(key, label)
                }
            }
        }
        XCTAssertEqual(Set(empty.map(\.role)).union(full.map(\.role)),
                       Set(SettingsWorkflowControlRole.allCases))
        XCTAssertEqual(SettingsWorkflowPresentation.maximumControlDescriptors, 3_423)
        XCTAssertLessThanOrEqual(full.count, SettingsWorkflowPresentation.maximumControlDescriptors)
        let factories = full.filter { $0.role == .createFactory }
        XCTAssertEqual(factories.count, 6)
        XCTAssertEqual(Set(factories.compactMap(\.identity)),
                       Set(SessionProfiles.factoryKeys.map {
                           SettingsWorkflowControlIdentity.factory($0)
                       }))
        for key in SessionProfiles.factoryKeys {
            let descriptor = try XCTUnwrap(factories.first { $0.identity == .factory(key) })
            XCTAssertEqual(descriptor.id, "settings.profile.factory." + key)
            XCTAssertTrue(descriptor.label.contains(key))
            XCTAssertEqual(descriptor.availability, .unavailable(
                reasonKey: "settings.control.unavailable.issuedPreview",
                label: "Resolved settings.control.unavailable.issuedPreview"))
        }
        for role in [SettingsWorkflowControlRole.cloneProfile, .renameProfile,
                     .deleteProfile, .activateProfile, .deactivateProfile] {
            let actions = full.filter { $0.role == role }
            XCTAssertEqual(actions.count, 2)
            XCTAssertEqual(actions.compactMap(\.identity), [
                SettingsWorkflowControlIdentity.profile(a), .profile(b)
            ])
            XCTAssertEqual(actions.map(\.id), [a, b].map {
                "settings.profile.action.\(role.rawValue).\($0.uuidString)"
            })
            XCTAssertTrue(actions.allSatisfy { descriptor in
                guard case .profile(let id)? = descriptor.identity else { return false }
                return descriptor.label.contains(id.uuidString)
            })
        }
        let name = try XCTUnwrap(full.first { $0.role == .profileNameEditor })
        XCTAssertEqual(name.id, "settings.profile.editor.name." + a.uuidString)
        XCTAssertEqual(name.identity, .profileName(.profile(a)))
        XCTAssertTrue(name.label.contains(a.uuidString))
        XCTAssertEqual(name.availability, .unavailable(
            reasonKey: "settings.control.unavailable.issuedPreview",
            label: "Resolved settings.control.unavailable.issuedPreview"))
        let values = full.filter { $0.role == .profileValueEditor }
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(Set(values.map(\.id)), Set([profileField, restriction].map {
            "settings.profile.editor.value.\(a.uuidString).\($0.rawValue)"
        }))
        XCTAssertTrue(values.allSatisfy { descriptor in
            descriptor.label.contains(a.uuidString) &&
                [profileField.rawValue, restriction.rawValue].contains(where: {
                    descriptor.label.contains($0)
                })
        })
        XCTAssertTrue(values.allSatisfy {
            $0.availability == .unavailable(
                reasonKey: "settings.control.unavailable.issuedPreview",
                label: "Resolved settings.control.unavailable.issuedPreview")
        })
        let newEditor = try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: [a], activeProfileID: nil,
            profileEditor: .init(target: .newProfile, valueFieldIDs: [profileField]),
            importPhase: .idle, collisions: [], hasCompleteCollisionChoices: false,
            hasPreparedProfile: false, resetGlobalFieldIDs: [], resetProfileID: nil,
            resetProfileFieldIDs: [], ownedRestrictionFieldIDs: [], hasResetSelection: false,
            hasPreparedReset: false), localize: localize)
        XCTAssertEqual(newEditor.first { $0.role == .profileNameEditor }?.id,
                       "settings.profile.editor.name.new")
        XCTAssertEqual(newEditor.first { $0.role == .profileValueEditor }?.id,
                       "settings.profile.editor.value.new." + profileField.rawValue)
        XCTAssertTrue(newEditor.filter {
            $0.role == .profileNameEditor || $0.role == .profileValueEditor
        }.allSatisfy { $0.label.contains("new") })
        for (role, choice) in [
            (SettingsWorkflowControlRole.collisionKeepLocal,
             ProfileCollisionControlChoice.keepLocal),
            (.collisionReplace, .replace), (.collisionClone, .clone)
        ] {
            let choices = full.filter { $0.role == role }
            XCTAssertEqual(choices.count, 2)
            XCTAssertEqual(choices.compactMap(\.identity), [
                SettingsWorkflowControlIdentity.collision(a, choice), .collision(b, choice)
            ])
            XCTAssertEqual(choices.map(\.id), [a, b].map {
                "settings.import.collision.\($0.uuidString).\(choice.rawValue)"
            })
            XCTAssertTrue(choices.allSatisfy { descriptor in
                guard case .collision(let id, _)? = descriptor.identity else { return false }
                guard let collision = collisions.first(where: { $0.profileID == id }) else {
                    return false
                }
                return descriptor.label.contains(choice.rawValue) &&
                    descriptor.label.contains(id.uuidString) &&
                    descriptor.label.contains(collision.localName) &&
                    descriptor.label.contains(collision.importedName)
            })
            XCTAssertTrue(choices.allSatisfy { $0.availability == .enabled })
        }
        XCTAssertEqual(full.filter { $0.role == .resetGlobalField }.map(\.id),
                       ["settings.reset.global." + globalField.rawValue])
        let resetFields = full.filter {
            $0.role == .resetGlobalField || $0.role == .resetProfileField
        }
        XCTAssertTrue(resetFields.allSatisfy { descriptor in
            switch descriptor.identity {
            case .some(.globalResetField(let id)): return descriptor.label.contains(id.rawValue)
            case .some(.profileResetField(let profileID, let id)):
                return descriptor.label.contains(profileID.uuidString) &&
                    descriptor.label.contains(id.rawValue)
            default: return false
            }
        })
        XCTAssertTrue(resetFields.allSatisfy { $0.availability == .unavailable(
            reasonKey: "settings.control.unavailable.resetPreview",
            label: "Resolved settings.control.unavailable.resetPreview") })
        XCTAssertEqual(Set(full.filter { $0.role == .resetProfileField }.map(\.id)),
            Set([profileField, restriction].map {
                "settings.reset.profile.\(a.uuidString).\($0.rawValue)"
            }))
        let optIn = try XCTUnwrap(full.first { $0.role == .resetRestrictionOptIn })
        XCTAssertEqual(optIn.id,
            "settings.reset.restrictionOptIn.\(a.uuidString).\(restriction.rawValue)")
        XCTAssertTrue(optIn.label.contains(a.uuidString))
        XCTAssertTrue(optIn.label.contains(restriction.rawValue))
        XCTAssertEqual(optIn.availability, .unavailable(
            reasonKey: "settings.control.unavailable.resetPreview",
            label: "Resolved settings.control.unavailable.resetPreview"))
        XCTAssertEqual(full.first(where: { $0.role == .issueImport })?.availability, .enabled)
        XCTAssertEqual(full.first(where: { $0.role == .confirmProfile })?.availability, .enabled)
        guard case .some(.unavailable) = empty.first(where: {
            $0.role == .confirmProfile
        })?.availability
        else { return XCTFail("Profile confirmation enabled without a preview") }
        XCTAssertEqual(empty.first(where: { $0.role == .issueImport })?.availability,
                       .unavailable(reasonKey: "settings.control.unavailable.importAnalysis",
                                    label: "Resolved settings.control.unavailable.importAnalysis"))
        for role in [SettingsWorkflowControlRole.localReassociation,
                     .historyAndIndexClearing] {
            guard case .some(.unavailable) = full.first(where: {
                $0.role == role
            })?.availability
            else { return XCTFail("Deferred control became available: \(role)") }
        }
        var confirmationDescriptorIDs: [String] = []
        for phase in SettingsWorkflowImportPhase.allCases {
            let controls = try SettingsWorkflowPresentation.controls(context: .init(
                profileIDs: [a], activeProfileID: a,
                profileEditor: .init(target: .profile(a), valueFieldIDs: [profileField]),
                importPhase: phase, collisions: [collisions[1]],
                hasCompleteCollisionChoices: true, hasPreparedProfile: true,
                resetGlobalFieldIDs: [globalField], resetProfileID: a,
                resetProfileFieldIDs: [profileField], ownedRestrictionFieldIDs: [],
                hasResetSelection: true,
                hasPreparedReset: true), localize: localize)
            let enabled: (SettingsWorkflowControlRole) -> Bool = { role in
                controls.first(where: { $0.role == role })?.availability == .enabled
            }
            if phase == .confirmation { confirmationDescriptorIDs = controls.map(\.id) }
            if phase == .submitting {
                XCTAssertEqual(controls.map(\.id), confirmationDescriptorIDs,
                               "Submitting removed readable/focus-stable rows")
                for descriptor in controls {
                    if Set([SettingsWorkflowControlRole.localReassociation,
                            .historyAndIndexClearing]).contains(descriptor.role) {
                        XCTAssertEqual(descriptor.availability, .unavailable(
                            reasonKey: "settings.control.unavailable.deferred",
                            label: "Resolved settings.control.unavailable.deferred"))
                    } else {
                        XCTAssertEqual(descriptor.availability, .unavailable(
                            reasonKey: "settings.control.unavailable.submitting",
                            label: "Resolved settings.control.unavailable.submitting"),
                            descriptor.id)
                    }
                    XCTAssertFalse(descriptor.label.isEmpty)
                }
                continue
            }
            XCTAssertEqual(enabled(.issueImport), phase == .analysis)
            XCTAssertEqual(enabled(.confirmImport), phase == .confirmation)
            XCTAssertEqual(enabled(.cancelImport),
                Set([.analyzing, .analysis, .issuing, .confirmation]).contains(phase))
            for role in [SettingsWorkflowControlRole.collisionKeepLocal,
                         .collisionReplace, .collisionClone] {
                XCTAssertEqual(enabled(role), phase == .analysis)
            }
            XCTAssertTrue(enabled(.previewReset)); XCTAssertTrue(enabled(.confirmReset))
            XCTAssertFalse(enabled(.resetGlobalField)); XCTAssertFalse(enabled(.resetProfileField))
            XCTAssertFalse(enabled(.profileNameEditor)); XCTAssertFalse(enabled(.profileValueEditor))
        }
        let actionable = try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: [a], activeProfileID: a, profileEditor: nil,
            importPhase: .idle, collisions: [], hasCompleteCollisionChoices: false,
            hasPreparedProfile: false, resetGlobalFieldIDs: [], resetProfileID: nil,
            resetProfileFieldIDs: [], ownedRestrictionFieldIDs: [], hasResetSelection: false,
            hasPreparedReset: false), localize: localize)
        let activeActions = actionable.filter { $0.identity == .profile(a) }
        XCTAssertEqual(activeActions.first(where: { $0.role == .activateProfile })?.availability,
                       .unavailable(reasonKey: "settings.control.unavailable.activeProfile",
                                    label: "Resolved settings.control.unavailable.activeProfile"))
        XCTAssertEqual(activeActions.first(where: { $0.role == .deactivateProfile })?.availability,
                       .enabled)
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: [], activeProfileID: a, profileEditor: nil,
            importPhase: .idle, collisions: [], hasCompleteCollisionChoices: false,
            hasPreparedProfile: false, resetGlobalFieldIDs: [], resetProfileID: nil,
            resetProfileFieldIDs: [], ownedRestrictionFieldIDs: [], hasResetSelection: false,
            hasPreparedReset: false), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError,
                               .invalidActiveProfile(a))
            }
        let tooMany = (0...50).map { index in UUID(uuidString: String(format:
            "A0000000-0000-0000-0000-%012d", index))! }
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: tooMany, activeProfileID: nil, profileEditor: nil,
            importPhase: .idle, collisions: [], hasCompleteCollisionChoices: false,
            hasPreparedProfile: false, resetGlobalFieldIDs: [], resetProfileID: nil,
            resetProfileFieldIDs: [], ownedRestrictionFieldIDs: [], hasResetSelection: false,
            hasPreparedReset: false), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError, .tooManyProfiles)
            }
    }

    func testWorkflowControlDynamicBoundsRejectWithoutTruncation() throws {
        let profile = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let localize: (String) -> String = { "Resolved " + $0 }
        func context(collisions: [ProfileImportCollision] = [],
                     editorFields: [SettingID] = [], resetGlobal: [SettingID] = [],
                     resetProfile: [SettingID] = [], restrictions: Set<SettingID> = [])
            -> SettingsWorkflowControlContext {
            .init(profileIDs: [profile], activeProfileID: nil,
                profileEditor: editorFields.isEmpty ? nil : .init(
                    target: .profile(profile), valueFieldIDs: editorFields),
                importPhase: .analysis, collisions: collisions,
                hasCompleteCollisionChoices: true, hasPreparedProfile: false,
                resetGlobalFieldIDs: resetGlobal,
                resetProfileID: resetProfile.isEmpty ? nil : profile,
                resetProfileFieldIDs: resetProfile,
                ownedRestrictionFieldIDs: restrictions,
                hasResetSelection: !resetGlobal.isEmpty || !resetProfile.isEmpty,
                hasPreparedReset: false)
        }
        let collision = ProfileImportCollision(profileID: profile,
            localName: "Local", importedName: "Imported")
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(
            context: context(collisions: [collision, collision]), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError,
                               .duplicateCollision(profile))
            }
        let tooManyCollisions = (0...50).map { index in
            ProfileImportCollision(profileID: UUID(uuidString: String(format:
                "B0000000-0000-0000-0000-%012d", index))!,
                localName: "L", importedName: "I")
        }
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(
            context: context(collisions: tooManyCollisions), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError, .tooManyCollisions)
            }
        let tooManyFields = (0...1_000).map {
            SettingID(rawValue: "fixture.field.\($0)")
        }
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(
            context: context(editorFields: tooManyFields), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError, .tooManyEditorFields)
            }
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(
            context: context(resetGlobal: tooManyFields), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError, .tooManyResetFields)
            }
        let preference = SettingID(rawValue: "scan.requestedWorkers")
        let restriction = SettingID(rawValue: "feature.headroom")
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(context: context(
            resetProfile: [preference], restrictions: [restriction]), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError,
                               .invalidRestrictionOptIn(restriction))
            }
        let valid = try SettingsWorkflowPresentation.controls(context: context(
            editorFields: [preference], resetProfile: [preference, restriction],
            restrictions: [restriction]), localize: localize)
        XCTAssertLessThanOrEqual(valid.count,
            SettingsWorkflowPresentation.maximumControlDescriptors)
    }

    @MainActor func testWorkflowRenderDoesZeroWork() async throws {
        try await run { _, services, _ in
            let generation = services.policyBridge.updateGeneration
            let revision = services.configStore.settingsRevision
            let admission = services.coordinator.policyAdmission()
            for tab in SettingsWorkflowTab.allCases {
                for scheme in [ColorScheme.light, .dark] {
                    for width in [CGFloat(480), 620] {
                        for size in [DynamicTypeSize.large, .accessibility3] {
                            let view = SettingsWorkflowSurface(store: services.configStore,
                                bundle: Bundle(for: SharedSettingsWiringTests.self),
                                                               initialTab: tab)
                            .frame(width: width, height: 900)
                            .environment(services.configStore)
                            .environment(\.colorScheme, scheme)
                            .environment(\.dynamicTypeSize, size)
                            XCTAssertNotNil(ImageRenderer(content: view).cgImage,
                                "\(tab) \(scheme) \(width) \(size)")
                        }
                    }
                }
            }
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            XCTAssertEqual(services.coordinator.policyAdmission(), admission)
            XCTAssertFalse(services.configStore.hasPendingSettingsWrites)
        }
    }

    func testWorkflowLocalizationIsCompleteAndResolved() throws {
        let bundle = Bundle(for: SharedSettingsWiringTests.self)
        var keys = [
            "settings.workflow.tab.profiles", "settings.workflow.tab.transfer",
            "settings.workflow.tab.reset", "settings.workflow.revision",
            "settings.profile.create", "settings.profile.createFactory",
            "settings.profile.clone", "settings.profile.rename", "settings.profile.delete",
            "settings.profile.activate", "settings.profile.deactivate",
            "settings.profile.preview", "settings.profile.confirm", "settings.profile.cancel",
            "settings.profile.diff", "settings.profile.activeBefore",
            "settings.profile.activeAfter", "settings.profile.editor.name",
            "settings.profile.editor.value", "settings.import.choose", "settings.import.analyze",
            "settings.import.issue", "settings.import.confirm", "settings.import.cancel",
            "settings.import.failure", "settings.import.sourceDigest",
            "settings.import.candidateDigest", "settings.import.collision.keepLocal",
            "settings.import.collision.replace", "settings.import.collision.clone",
            "settings.export.choose", "settings.export.ready", "settings.export.failure",
            "settings.reset.select", "settings.reset.ownedRestrictionOptIn",
            "settings.reset.field.global", "settings.reset.field.profile",
            "settings.reset.preview", "settings.reset.confirm", "settings.reset.cancel",
            "settings.reset.immutable", "settings.control.unavailable.noProfile",
            "settings.control.unavailable.activeProfile",
            "settings.control.unavailable.importAnalysis",
            "settings.control.unavailable.issuedPreview",
            "settings.control.unavailable.resetSelection",
            "settings.control.unavailable.resetPreview",
            "settings.control.unavailable.deferred",
            "settings.control.unavailable.submitting"
        ]
        keys += SessionProfiles.factoryKeys.map { "settings.profile.factory." + $0 }
        keys += SettingsWorkflowPresentation.importOutcomeOrder.flatMap {
            ["settings.import.outcome.\($0.rawValue).title",
             "settings.import.outcome.\($0.rawValue).explanation"]
        }
        keys += SettingsResetBoundary.allCases.map {
            "settings.reset.boundary." + $0.rawValue
        }
        keys += SettingsDeferredWorkflow.allCases.flatMap {
            ["settings.deferred.\($0.rawValue).title",
             "settings.deferred.\($0.rawValue).explanation"]
        }
        XCTAssertEqual(keys.count, Set(keys).count)
        for key in keys {
            let value = SettingsCopy.resolve(key, bundle: bundle)
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertNotEqual(value, key)
            XCTAssertNotEqual(value, "Description unavailable.", key)
        }
    }

    func testWorkflowFixtureHostIsDeterministicBoundedAndInert() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "TidyUITestHost/TestHostApp.swift"), encoding: .utf8)
        for state in ["profilesEmpty", "profilesTwo", "profilesActive",
                      "activeDeleteConfirmation", "profileFieldDiff", "importAllOutcomes",
                      "importIncompleteCollision", "importIssuedConfirmation", "importSubmitting",
                      "importMalformedFailure", "resetEmpty", "resetSelected",
                      "resetOwnedRestriction", "immutableAndDeferred"] {
            XCTAssertTrue(source.contains("case " + state), state)
        }
        XCTAssertTrue(source.contains("settings.workflow.fixture.state"))
        XCTAssertTrue(source.contains("settings.workflow.fixture.workCount"))
        XCTAssertTrue(source.contains("Workflow fixture work: 0"))
        for token in ["UUID()", "Date()", "Data(contentsOf:", "SettingsStore(",
                      "ExecutionPolicyBridge(", "SettingsTransfer.", "requestPlan",
                      "loadPlan", "CleanEngine", "SettingsWorkflowController(testing:"] {
            XCTAssertFalse(source.contains(token), token)
        }
    }

    func testWorkflowSourceHasNoOpenWorkOrSecondOwner() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Tidy/Settings/SettingsView.swift"), encoding: .utf8)
        for token in [".task", ".onAppear", ".onReceive", ".refreshable", "Timer",
                      "Process(", "Process.", "ProcessSurvey", "CookieDomainSuggester",
                      "GitRootDiscovery", "SimctlClient", "CleanEngine", "requestPlan",
                      "loadPlan", "FileManager", "URLSession", "NSWorkspace",
                      "DispatchSource", "NotificationCenter", "SettingsStore(",
                      "ExecutionPolicyBridge(", "SettingsTransfer.resolve"] {
            XCTAssertFalse(source.contains(token), token)
        }
        XCTAssertFalse(source.contains("Task.detached"))
        let begin = "// SETTINGS_WORKFLOW_TASK_BOUNDARIES_BEGIN"
        let end = "// SETTINGS_WORKFLOW_TASK_BOUNDARIES_END"
        XCTAssertEqual(source.components(separatedBy: begin).count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: end).count - 1, 1)
        let beginRange = try XCTUnwrap(source.range(of: begin))
        let endRange = try XCTUnwrap(source.range(of: end))
        XCTAssertLessThan(beginRange.lowerBound, endRange.lowerBound)
        let block = String(source[beginRange.lowerBound..<endRange.upperBound])
        let beforeBlock = String(source[..<beginRange.lowerBound])
        let afterBlock = String(source[endRange.upperBound...])
        XCTAssertEqual(block.components(separatedBy: "Task {").count - 1, 4)
        XCTAssertFalse(beforeBlock.contains("Task {"))
        XCTAssertFalse(afterBlock.contains("Task {"))
        var remainder = block
        for helper in ["beginImportSelection", "beginImportPreviewIssuance",
                       "beginImportConfirmation", "beginImportCancellation"] {
            let helperBegin = "// SETTINGS_WORKFLOW_TASK_BEGIN_" + helper
            let helperEnd = "// SETTINGS_WORKFLOW_TASK_END_" + helper
            XCTAssertEqual(block.components(separatedBy: helperBegin).count - 1, 1)
            XCTAssertEqual(block.components(separatedBy: helperEnd).count - 1, 1)
            let helperBeginRange = try XCTUnwrap(remainder.range(of: helperBegin))
            let helperEndRange = try XCTUnwrap(remainder.range(of: helperEnd))
            XCTAssertLessThan(helperBeginRange.lowerBound, helperEndRange.lowerBound)
            let extracted = String(remainder[
                helperBeginRange.lowerBound..<helperEndRange.upperBound])
            XCTAssertTrue(extracted.contains("func " + helper), helper)
            XCTAssertEqual(extracted.components(separatedBy: "Task {").count - 1, 1,
                           helper)
            if helper == "beginImportConfirmation" {
                let rejected = try XCTUnwrap(extracted.range(of: "case .rejected"))
                let cancellation = try XCTUnwrap(extracted.range(
                    of: "await importOperations.cancelPreview(preview.id)"))
                XCTAssertLessThan(rejected.lowerBound, cancellation.lowerBound)
            }
            let submitting = try XCTUnwrap(extracted.range(of: "case .submitting"))
            let increment = try XCTUnwrap(extracted.range(of: "operationGeneration &+="))
            XCTAssertLessThan(submitting.lowerBound, increment.lowerBound,
                "\(helper) must decide submitting no-op before generation supersession")
            remainder.replaceSubrange(
                helperBeginRange.lowerBound..<helperEndRange.upperBound, with: "")
        }
        remainder = remainder.replacingOccurrences(of: begin, with: "")
            .replacingOccurrences(of: end, with: "")
        XCTAssertTrue(remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "Statements exist outside the four task helpers")
        XCTAssertTrue(source.contains("fileImporter")); XCTAssertTrue(source.contains("fileExporter"))
        XCTAssertTrue(source.contains("startAccessingSecurityScopedResource"))
        XCTAssertTrue(source.contains("stopAccessingSecurityScopedResource"))
        XCTAssertTrue(source.contains("Data(contentsOf:"))
        XCTAssertTrue(source.contains("operationGeneration &+="))
        XCTAssertTrue(source.contains("let bundle: Bundle"))
        XCTAssertTrue(source.contains("bundle: Bundle = .main"))
        XCTAssertTrue(source.contains("SettingsImportUISummary"))
        XCTAssertTrue(source.contains("SettingsWorkflowPresentation.controls(context:"))
        XCTAssertTrue(source.contains("beginImportConfirmation"))
        XCTAssertTrue(source.contains("deferredExplanationKey"))
        XCTAssertTrue(source.contains("deferredExplanation("))
        XCTAssertTrue(source.contains("bundle: bundle"))
        XCTAssertFalse(source.contains("case analysis(SettingsImportAnalysis)"))
        XCTAssertFalse(source.contains("case issuingPreview(SettingsImportAnalysis)"))
        XCTAssertFalse(source.contains("PortableSettingsState"))
        XCTAssertFalse(source.contains("var importBytes"))
        XCTAssertFalse(source.contains("var sourceBytes"))
        XCTAssertFalse(source.contains("SettingsWorkflowController(testing:"))
        XCTAssertTrue(source.contains("store.commitImport"))
        XCTAssertTrue(source.contains("store.commitProfileWorkflow"))
        XCTAssertTrue(source.contains("store.commitSelectiveReset"))
        for id in ["settings.deferred.localReassociation",
                   "settings.deferred.historyAndIndexClearing",
                   "settings.profile.confirm", "settings.import.confirm",
                   "settings.reset.confirm"] {
            XCTAssertTrue(source.contains(id), id)
        }
    }
}
```

The focused RED must be missing T07.3b APIs only. Existing async `Task` use may be added solely inside explicit button/file-panel actions; `.task`/appearance work remains forbidden and render counters prove zero work.

## Deterministic fixture-host proof

Extend the existing Settings fixture with `private enum SettingsWorkflowFixtureState: String, CaseIterable, Identifiable` and exactly these cases: `profilesEmpty`, `profilesTwo`, `profilesActive`, `activeDeleteConfirmation`, `profileFieldDiff`, `importAllOutcomes`, `importIncompleteCollision`, `importIssuedConfirmation`, `importSubmitting`, `importMalformedFailure`, `resetEmpty`, `resetSelected`, `resetOwnedRestriction`, `immutableAndDeferred`. A picker with ID `settings.workflow.fixture.state` switches constant presentation-only models; a label with ID `settings.workflow.fixture.workCount` reads exactly `Workflow fixture work: 0`. The submitting fixture keeps digests/outcomes/deferred explanations readable while every interactive workflow descriptor is visibly disabled with the submitting reason. Use fixed UUIDs/digests/revisions and existing light/dark, 480/620, accessibility3 controls. Fixture must not read files, invoke store/bridge/transfer, generate IDs/dates, submit, analyze, export, or build a cleanup plan. Its visible submission/work counter stays zero.

## Execution and commands

1. Add core RED; run focused RED; implement pure projection; focused GREEN.
2. Add app RED; run focused RED; implement store/controller/UI/catalog; containing GREEN.
3. Add fixture; build host/app; run compatibility; request adversarial review; fix test-first; then create verification doc. Never commit.

One heavy command at a time, jobs 2:

```bash
swift test --package-path TidyCore --jobs 2 --filter SettingsWorkflowTests
swift test --package-path TidyCore --jobs 2 --filter SessionProfileTests
swift test --package-path TidyCore --jobs 2 --filter SettingsTransferTests
swift test --package-path TidyCore --jobs 2 --filter SettingsProfilePersistenceTests
swift test --package-path TidyCore --jobs 2 --filter PolicyDefaultsTests
swift test --package-path TidyCore --jobs 2 --filter PolicyResolutionTests
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testStaleProfilePreviewsConflictAndPreserveOtherWindow CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testImportConfirmationAwaitsSavedAndConsumesTokenOnce CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testImportConfirmationConflictAndPersistenceFailureNeverClaimSaved CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testLiveRejectedConfirmationClearsIssuedBindingWithoutRetention CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testImportConfirmationHandlesEveryAcceptedNonSavedOutcome CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSynchronousImportRejectionCancelsIssuedPreviewExactlyOnce CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testImportGenerationSupersedesAndCancelsDeterministically CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testWorkflowControlProjectionIsExhaustiveStableAndContiguous CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testWorkflowControlDynamicBoundsRejectWithoutTruncation CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testWorkflowRenderDoesZeroWork CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme TidyUITestHost -destination 'platform=macOS,arch=arm64' -parallelizeTargets -jobs 2 build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme Tidy -destination 'platform=macOS,arch=arm64' -parallelizeTargets -jobs 2 build CODE_SIGNING_ALLOWED=NO
plutil -lint Tidy.xcodeproj/project.pbxproj
python3 -m json.tool Tidy/Resources/Localizable.xcstrings >/dev/null
git diff --check
```

Prove changed paths are the allowlist and `.pbxproj` is unchanged from T07.3a. Run relevant ordinary core and isolated process partitions; do not claim combined full-core GREEN if a process timing test passes only isolated.

## Acceptance and honest gates

Automated acceptance requires: preview/confirm/cancel and exact revisions for every profile mutation including monotone value update, deactivate, and delete-inactive; direct `SessionProfiles.update` preservation/validation/stronger/equal/weaker proof; no create/clone/import activation; active-delete global fallback; synchronous stale rename/delete/value-update rejection preserving the other window and durable bytes, unrelated older-delta rebasing and pending two-window convergence; exact synthetic taxonomy row counts independent of three collision objects; actor-issued collision confirmation/cancel; import submission stays visibly submitting until `.saved`, handles synchronous invalid plus every accepted conflict/invalid/failure without false saved state, survives persistence failure, consumes its token once, and generation-discards only pre-acceptance stale work; all four boundaries during `.submitting` are generation-preserving no-ops and the one accepted outcome still controls idle/failure; every synchronous admission rejection awaits exactly one preview cancellation before failure, and the live pending-write rejection retains no import payload/binding and cannot reuse the old preview; generation-safe new-selection/cancel/issuance/failure/queued-rejection races with unusable stale tokens; retained injected localization bundle, resolved deferred explanation key/copy, and no retained full analysis/source bytes; deterministic authority-free export; ordered combined reset with same-ID provenance and all immutable exclusions; the sole exhaustive descriptor projection covering six factories, five actions/profile, name/value editors, three choices/collision, reset global/profile fields and restriction opt-ins with checked bounds, unique IDs, resolved identity labels, exact availability and contiguous focus, plus exact whole-surface `.submitting` lock without hiding readable/deferred rows; independently delimited four one-Task helpers with whitespace-only outer remainder and rejection/no-op ordering proof; visible unavailable deferred rows; zero work on open; every tab rendered in light/dark at 480/620 and default/accessibility3; core/app/host builds GREEN; adversarial review Approved.

Still separate and unclaimed: physical VoiceOver/keyboard/dialog focus, real NSOpenPanel/NSSavePanel security-scope on macOS 14, manual light/dark contrast, physical 8 GiB cold-open and worst-case 1 MiB/50-profile CPU/RSS/latency/cancel measurements, Intel, T22.3, T07.3d, T22.4, README/GitHub/signing/notarization/DMG/release.
