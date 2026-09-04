# T07.3a preimplementation card — registry-driven Settings UI foundation

Status: **PREIMPLEMENTATION ONLY — NOT IMPLEMENTED, TESTED, ACCESSIBILITY-ACCEPTED, OR RELEASED.**

This card is the bounded execution contract for the accepted `T07.3a — Registry-driven Settings UI foundation` entry in `docs/superpowers/tasks/T07-settings-customization-entry.md`. It authorizes no production or test change by itself. The implementation turn must first add the complete RED tests below, observe only the intended missing-API/failed-expectation failures, then implement to GREEN inside the exact allowlist.

## Goal

Replace the legacy, partly local-machine-driven Settings form with a pure registry-driven presentation over the accepted policy registry. The surface must make every current setting reachable, keep authority rows visible but unavailable, edit global P/R values only through the shared `AppConfigStore`, and do no scan, process, discovery, timer, or persistence work merely because Settings opened.

This checkpoint is a foundation, not the complete T07 workflow. Profile CRUD/activation/diff, import/export, collision confirmation, and selective reset remain entirely in T07.3b.

## Binding accepted-entry requirements

T07.3a is accepted only when all of the following are true together:

1. One pure presentation registry is keyed by exact `SettingID` or a grammar-checked dynamic pattern.
2. Matching is exactly one-to-one over:
   - every static `PolicyDefaults.rows` definition;
   - all four `PolicyDefaults.itemRows(catalogID:)` definitions for every current `CleanCatalog.allItems` ID;
   - `PolicyDefaults.volumeRow(id:)`, represented in coverage by the canonical sentinel UUID `00000000-0000-0000-0000-000000000001`;
   - every other finite family, which is already expanded into `PolicyDefaults.rows` today.
3. Coverage fails for a definition with zero or multiple presentation matches and for a presentation entry/pattern that matches no definition in the coverage universe.
4. Presentation metadata provides deterministic section/order, Basic/Advanced tier, localization keys, help/consequence keys, and applicability/availability explanation keys. It must not copy or redefine `SettingDefinition.defaultValue`, `rule`, `resolution`, `effect`, or `layers`.
5. Searchable Features, Scan, Cleanup, and Experience surfaces expose every row. A nonempty search searches both tiers even while “Show Advanced” is off.
6. Every rendered row shows the registry-derived default, current effective value, source, rule/range, consequence, and applicable/unavailable state.
7. Only global-layer preference/restriction controls are editable in 3a, and every edit calls `AppConfigStore.setGlobalPreference(_:to:)`. The UI must not construct or submit a bridge/store delta directly.
8. Authority rows remain visible and are explicitly unavailable/deferred. T07.3a invents no authority picker, consent, approval, or reassociation flow.
9. Opening Settings starts no scan, process survey, process, discovery, timer, task, or cleanup-plan generation.
10. Automated source/unit/render-host proof covers reachability, stable accessibility identifiers and labels, keyboard/focus order, accessibility text-size layout, and semantic light/dark contrast roles. Physical VoiceOver and device evidence remain separate gates and are not claimed by these tests.

## Inspected baseline and boundaries

- `Tidy/Settings/SettingsView.swift` is currently a legacy `Form` over `TidyConfig`. User actions can invoke cookie discovery, Git-root discovery, `simctl`, and process surveying. The new Settings surface replaces these sections; it does not move those effects elsewhere.
- `Tidy/Custom/CustomView.swift` deliberately starts plan construction with `.task`. It is a cleanup-review screen and remains untouched. Its behavior must not leak into Settings.
- `PolicyDefaults.rows` expands the finite feature, ecosystem, scope, cleanup, headroom, scan, monitor, budget, rescue, notification, maintenance, history, UI, and export families.
- The only current non-static policy definition families are the four catalog-item suffixes and `headroom.volumeOverrides.<UUID>`.
- `AppConfigStore` already owns shared optimistic settings state, exposes `preferences` and `effectivePolicy`, and submits global edits through `setGlobalPreference`. No second observable settings model or store is allowed.
- `Tidy.xcodeproj` uses explicit `PBXGroup` and source build phases, not filesystem-synchronized groups. Package sources/tests are discovered by SwiftPM. App and test-host sources require explicit build-phase membership.
- To minimize project changes, all app presentation/projection code stays in the existing `SettingsView.swift`. The existing `SettingsView.swift` is added to the app-model test target. The existing `SettingsView.swift` and `AppConfigStore.swift` are added to the fixture-host target. One new string catalog is added under the existing Resources group and copied into all three target bundles; no new PBX group or UI-automation target is created.

## Exact implementation allowlist

The implementation checkpoint may create or modify **only** these files:

1. `TidyCore/Sources/TidyCore/Policy/SettingsPresentation.swift` — new pure presentation registry.
2. `TidyCore/Tests/TidyCoreTests/SettingsPresentationTests.swift` — new focused RED/core tests.
3. `Tidy/Settings/SettingsView.swift` — replace the legacy Settings form and keep all 3a app projection/view helpers here.
4. `Tidy/Resources/Localizable.xcstrings` — new Base-English string catalog containing every registry key and dynamic template.
5. `TidyAppModelTests/SharedSettingsWiringTests.swift` — add the complete RED app-model/render/source-contract tests below and `import SwiftUI`.
6. `TidyUITestHost/TestHostApp.swift` — add a deterministic Settings fixture; no discovery, store write, or cleanup action.
7. `Tidy.xcodeproj/project.pbxproj` — exact source/resource membership only, as specified below.
8. `docs/verification/T07-3a-registry-settings-ui.md` — create only after GREEN to record commands and honest evidence/gates.

No other production, test, project, plan, bridge, store, coordinator, journal, persistence, profile, transfer, resource, or release file is in scope. In particular, do not edit `AppConfigStore.swift`, `CustomView.swift`, `CustomViewModel.swift`, `ExecutionPolicyBridge.swift`, `SettingsStore.swift`, or `SettingsEnvelope.swift`. A genuine compile-fixture defect must stop the checkpoint for a card amendment; it is not permission to broaden the allowlist.

### Exact Xcode project delta

Reuse the two existing Swift file references. Add exactly six fresh `PBXBuildFile` records:

- existing `SettingsView.swift` file reference -> `TidyAppModelTests` Sources;
- existing `SettingsView.swift` file reference -> `TidyUITestHost` Sources;
- existing `AppConfigStore.swift` file reference -> `TidyUITestHost` Sources.
- new `Localizable.xcstrings` file reference -> Tidy Resources;
- the same catalog file reference -> `TidyAppModelTests` Resources;
- the same catalog file reference -> `TidyUITestHost` Resources.

Add exactly one `PBXFileReference` for `Localizable.xcstrings` under the existing `80600A2F8A7596E62848CA07 /* Resources */` group. Reuse the existing Tidy resources phase. Add one empty-new `PBXResourcesBuildPhase` to `TidyAppModelTests` and one to `TidyUITestHost`, each containing only its catalog build-file reference, and add those phase IDs to the corresponding native target. Do not add a PBX group, target dependency, or UI-test automation target. Confirm every fresh 24-character ID is unique before editing.

The catalog’s source language is `en`. Every exact static entry contributes four nonempty English values, each catalog-item/volume pattern contributes four format templates, and `settings.copy.missing` is exactly “Description unavailable.” The English value must differ from its localization key. `SettingsCopy.resolve` constructs `String.LocalizationValue(key)`, resolves it with `String(localized:bundle:locale:)` against the injected target bundle, then applies arguments with `String(format:locale:arguments:)`. If resolution equals the key, it returns the separately localized `settings.copy.missing` value; it never displays the raw key. Exhaustive catalog coverage still fails acceptance for any production registry key that would take this fallback.

## Concrete core API

Create `SettingsPresentation.swift` with these public declarations. Stored presentation metadata is intentionally incapable of holding policy truth fields.

```swift
import Foundation

public enum SettingsPresentationSection: String, CaseIterable, Sendable {
    case features, scan, cleanup, experience
}

public enum SettingsPresentationTier: String, CaseIterable, Sendable {
    case basic, advanced
}

public enum SettingsPresentationPattern: Hashable, Sendable {
    case exact(SettingID)
    case catalogItem(suffix: String)
    case volumeOverride
}

public struct SettingsPresentationKeys: Equatable, Sendable {
    public let title: String
    public let help: String
    public let consequence: String
    public let applicability: String

    public init(title: String, help: String, consequence: String,
                applicability: String)
}

public struct SettingPresentation: Equatable, Sendable {
    public let pattern: SettingsPresentationPattern
    public let section: SettingsPresentationSection
    public let tier: SettingsPresentationTier
    public let order: Int
    public let keys: SettingsPresentationKeys

    public init(pattern: SettingsPresentationPattern,
                section: SettingsPresentationSection,
                tier: SettingsPresentationTier,
                order: Int,
                keys: SettingsPresentationKeys)
}

public struct PresentedSetting: Equatable, Sendable {
    public let definition: SettingDefinition
    public let presentation: SettingPresentation
    public let order: Int

    public init(definition: SettingDefinition,
                presentation: SettingPresentation,
                order: Int)
}

public enum SettingsPresentationCoverageError: Error, Equatable, Sendable {
    case missing(SettingID)
    case ambiguous(SettingID)
    case orphan(SettingsPresentationPattern)
    case duplicateOrder(SettingsPresentationSection, Int)
}

public enum SettingsPresentationRegistry {
    public static let validationVolumeID: UUID
    public static let entries: [SettingPresentation]
    public static let basicIDs: Set<SettingID>

    public static func validationUniverse() -> [SettingDefinition]

    public static func renderedUniverse(volumeIDs: [UUID]) -> [SettingDefinition]

    public static func validateCoverage(
        entries: [SettingPresentation],
        definitions: [SettingDefinition]
    ) throws

    public static func validateCoverage() throws

    public static func all(volumeIDs: [UUID] = []) throws -> [PresentedSetting]

    public static func presentation(
        for definition: SettingDefinition
    ) throws -> SettingPresentation

    public static func accessibilityIdentifier(for id: SettingID) -> String
}
```

### Exact registry construction and matching rules

- `entries` contains one `.exact` entry for every current static `PolicyDefaults.rows` definition, plus exactly four `.catalogItem` suffix patterns (`enabled`, `inactiveDays`, `minimumItemMiB`, `retainRecentArtifacts`) and one `.volumeOverride` pattern.
- Exact entries come from a closed, explicitly enumerated descriptor list containing every current static `SettingID`, its section, tier, order, and four keys. Do not generate that list by mapping `PolicyDefaults.rows`, and do not provide a prefix/group fallback for an unlisted static ID: a future unlisted policy row must produce `.missing` until presentation metadata is deliberately added. The list retains no default, rule, resolution, effect, layer set, range, or choice list, and registry initialization looks up the authoritative definition rather than reconstructing it.
- `.catalogItem(suffix:)` matches only the exact grammar `item.<current CleanCatalog ID>.<suffix>` and only the declared suffix. It must not use `hasSuffix` alone. Catalog IDs are compared against `Set(CleanCatalog.allItems.map(\.id))`.
- `.volumeOverride` matches only `headroom.volumeOverrides.<canonical UUID>`. Parse the tail as a UUID and require `parsed.uuidString == tail`; do not accept lowercase/noncanonical spelling or extra components.
- No wildcard/catch-all entry is allowed.
- `validationVolumeID` is exactly `00000000-0000-0000-0000-000000000001`. `validationUniverse()` always concatenates static rows, all current catalog expansions, and exactly that sentinel volume row. It is used only for bidirectional coverage/orphan validation.
- `renderedUniverse(volumeIDs:)` is separate. It concatenates static rows, all catalog expansions, and caller-supplied volume rows after stable first-occurrence UUID deduplication. Empty input contains no volume. `[sentinel]` adds exactly one. `[sentinel, sentinel]` is byte-for-byte/equality identical to `[sentinel]`.
- `all(volumeIDs:)` first calls the no-argument `validateCoverage()` against the fixed validation universe, then presents only `renderedUniverse(volumeIDs:)`. Thus `all([])` succeeds without making `.volumeOverride` look orphaned and renders no fake volume.
- Presentation metadata is the sole order authority. Static exact descriptors use unique orders `0..<100_000` within their section. Catalog patterns reserve cleanup orders `100_000...199_999`; final item order is the pattern’s metadata base plus `catalogIndex * 4`. Volume pattern reserves cleanup orders `200_000...299_999`; final order is its metadata base plus the stable-deduplicated input index. Ranges may not overlap and must accommodate current maximum counts with checked arithmetic.
- `all` sorts by section declaration index, then final presentation order, then UTF-8 `id.rawValue`. It does not consult `PolicyDefaults.rows` index as another authority. Calling it twice returns identical values.
- Duplicate `(section, final order)` values reject with `.duplicateOrder`, including collisions injected into exact metadata or reached through dynamic expansion. Tests never hide duplicates with `Dictionary(uniqueKeysWithValues:)`.
- `validateCoverage(entries:definitions:)` first checks every definition has exactly one match, then checks every entry matches at least one definition, then checks final section/order uniqueness. The no-argument overload supplies production entries and the fixed validation universe.
- `basicIDs` is exactly: `feature.headroom`, `feature.buildPrep`, `feature.projects`, `feature.rescue`, `feature.ecosystems`, `feature.budgets`, `feature.history`, `feature.maintenance`, `scan.preset`, `scan.defaultScope`, `cleanup.inactiveDays`, `cleanup.costCeiling`, `cleanup.requestedBatchGiB`, `headroom.targetGiB`, `headroom.warningGiB`, `notifications.enabled`, `ui.units`, and `ui.cards`. `ui.cards` is visible in Basic but read-only in bounded 3a because ordered reconfiguration is deferred. Every other static/dynamic row is Advanced.
- Sections are exact and exhaustive: `features` contains `feature.*`, `ecosystem.*`, and only `item.*.enabled`; `scan` contains `scan.*`, `monitor.*`, `scope.projectRoots`, `scope.externalVolumes`, and `scope.currentProject`; `cleanup` contains `cleanup.*`, `headroom.*`, `browsers.keepCookieDomains`, `scope.excludedRoots`, `scope.pinnedProjects`, and the other three item suffixes; `experience` contains every remaining exact rescue/budget/notification/maintenance/app/history/UI/export/local-authority row. The core test independently classifies every universe ID by this closed family contract and compares it with metadata.
- Keys use stable ASCII forms `settings.<stable-id>.title`, `.help`, `.consequence`, and `.applicability`. Each of the four catalog-item pattern templates contains exactly one positional `%@` for the real `CleanCatalog` item ID, and each of the four volume templates contains exactly one positional `%@` for the canonical volume UUID. `SettingsCopy` supplies that identity argument for every dynamic row. Two different real item IDs and two different UUIDs must therefore produce different output, and every output must visibly contain the supplied identity. Keys are metadata, not English copy and not policy truth.
- `accessibilityIdentifier(for:)` returns `settings.row.` plus the exact setting raw value. Control IDs use `settings.control.` plus the exact raw value in the app. IDs are not derived from localized text.

The explicit descriptor list is presentation metadata, not duplicated policy truth. Review must reject any descriptor that adds a default value, valid range, choice set, resolution, effect, or layer applicability.

## App projection and view contract

All declarations below stay package-internal in the existing `SettingsView.swift`; tests gain access by compiling that existing file into their targets.

```swift
enum SettingsRowAvailability: Equatable {
    case editable
    case notApplicable(String)
    case unavailable(String)
    case deferred(String)
}

enum SettingsSemanticTextRole: Equatable {
    case primary, secondary, warning
}

enum SettingsLayoutMode: Equatable {
    case columns, stacked
}

enum SettingsControlKind: Equatable {
    case toggle, integer, optionalInteger, choice, readOnly
}

enum SettingsVisualContract {
    static let titleRole = SettingsSemanticTextRole.primary
    static let metadataRole = SettingsSemanticTextRole.secondary
    static let unavailableRole = SettingsSemanticTextRole.warning
    static func layoutMode(for size: DynamicTypeSize) -> SettingsLayoutMode
}

enum SettingsSearch {
    static func normalize(_ value: String) -> String
    static func haystack(for row: SettingsSurfaceRow) -> [String]
}

enum SettingsCopy {
    static func resolve(_ key: String, arguments: [CVarArg] = [],
                        bundle: Bundle) -> String
}

struct SettingsSurfaceRow: Identifiable, Equatable {
    let setting: PresentedSetting
    let storedValue: SettingValue?
    let effectiveField: EffectiveField?
    let controlKind: SettingsControlKind
    let availability: SettingsRowAvailability
    let focusIndex: Int
    let title: String
    let help: String
    let consequence: String
    let defaultText: String
    let effectiveText: String
    let sourceText: String
    let ruleText: String
    let availabilityText: String
    let accessibilityLabel: String

    var id: SettingID { setting.definition.id }
    var accessibilityIdentifier: String {
        SettingsPresentationRegistry.accessibilityIdentifier(for: id)
    }
}

@MainActor
struct SettingsSurfaceModel {
    let store: AppConfigStore
    let bundle: Bundle

    init(store: AppConfigStore, bundle: Bundle = .main)

    func rows(query: String, showsAdvanced: Bool) -> [SettingsSurfaceRow]
    func submit(id: SettingID, value: SettingValue?) -> SettingsSubmissionAdmission?
}

struct RegistrySettingsSurface: View {
    let rows: [SettingsSurfaceRow]
    let submit: (SettingID, SettingValue?) -> Void
    var body: some View { /* implementation */ }
}
```

### Projection semantics

1. `SettingsView` owns only lightweight presentation state: selected section, search string, and `showsAdvanced`. It reads the shared environment `AppConfigStore`; it does not create or cache another store.
2. `SettingsSurfaceModel.rows` starts from `SettingsPresentationRegistry.all(volumeIDs: [])`. T07.3a has no selected-volume identity/picker, so the dynamic volume family is exhaustively registry-validated but is not rendered until a legitimate selected-volume input exists. No sentinel/fake volume UUID appears in production UI.
3. Stored values come from `store.preferences.global.fields`. Effective fields come from `store.effectivePolicy?.fields`.
4. Default, rule/range, resolution, effect, and layer applicability are formatted by pure exhaustive formatters over the corresponding core enums. The formatters read the `SettingDefinition`; they do not maintain parallel policy data.
5. Source text exhaustively formats every `FieldSource`; effective/unavailable text exhaustively formats every `EffectiveValue` and `FieldReason`.
6. Title/help/consequence/applicability copy resolves through `SettingsCopy` and the injected target bundle. Every result must be nonempty and differ from its key. Consequence copy receives the core `AuthorityEffect` as a formatting argument and distinguishes no invalidation, plan invalidation, and separate consent without claiming that consent exists.
7. Availability is exact:
   - `.deferred("Requires a separately accepted local-authority workflow.")` for every `.authority` definition;
   - `.unavailable("This setting is not editable at the global layer.")` when `.global` is absent from `definition.layers`;
   - `.unavailable("This value needs a bounded editor that is deferred from T07.3a.")` for `.readOnly` controls;
   - `.editable` for every `.preference` or `.restriction` with `.global` in `layers` and a supported control for its `ValueKind`/`Rule`, even when its current effective projection is not applicable;
   - a core-provided unavailable `EffectiveValue` is shown separately in `effectiveText` and `availabilityText` as not applicable; it does not silently disable an otherwise supported global editor.
8. `SettingsControlKind` is one exhaustive control classifier. It returns `.toggle` only for `.bool`/`.boolean`, `.integer` only for `.integer`/`.integer`, `.optionalInteger` for safe scalar optional/headroom/budget integer rules, and `.choice` only for `.choice` with a closed `.choices` rule. All other kind/rule combinations return `.readOnly`. Every globally applicable P/R row classified as one of the first four is `.editable`; no supported P/R row may be silently disabled. Ordered/set/domain/local-identity/project/volume/clock values are `.readOnly` with an exact explanation.
9. `ui.cards` remains Basic and visible but `.readOnly`; 3a does not misrepresent ordered cards as a single-choice picker and does not add reorder UI. `ui.ecosystemOrder`, lists, domains, exclusions/pins, project identity, and volume overrides are likewise visible/read-only or deferred as their authority dictates.
10. `submit(id:value:)` looks up the exact definition again, repeats the authority/global-layer/control-kind checks, validates the candidate through the existing policy validator, and returns `nil` without mutation for unavailable/read-only rows. Its only edit call is `store.setGlobalPreference(id, to: value)`. No direct `ExecutionPolicyBridge`, `SettingsStore`, delta, `TidyConfig`, profile, or authority write is allowed.
11. Rows are grouped into four top-level searchable surfaces in registry order. With empty trimmed search, the exact `basicIDs` rows show and Advanced rows remain hidden unless the toggle is on. With nonempty trimmed search, tier filtering is disabled. `SettingsSearch.normalize` trims, folds case and diacritics under `en_US_POSIX`, and collapses whitespace. The haystack includes raw ID, resolved title, help, consequence, default, effective, source, rule/range, and availability text; every field has a reachability assertion.
12. A search result remains in its original section/order. Search never changes IDs or focus order.

### UI and accessibility behavior

- Section picker identifiers: `settings.section.features`, `.scan`, `.cleanup`, `.experience`.
- Search identifier: `settings.search` and label “Search settings”.
- Advanced toggle identifier: `settings.showAdvanced` and label “Show Advanced”.
- Row identifier: `settings.row.<exact SettingID>`.
- Editable control identifier: `settings.control.<exact SettingID>`.
- Each row’s accessibility label is exactly a stable composition containing both the resolved title and exact raw setting ID; labels are globally unique across every rendered row. Default/effective/source/rule/consequence/availability are exposed in `accessibilityValue`/`accessibilityHelp`, not hidden as color-only state.
- SwiftUI declaration order is the registry’s visible row order. Do not synthesize arbitrary sort priorities. `focusIndex` is recomputed as `0..<visibleRows.count` after section/search/tier filtering and is used by tests and optional `@FocusState` movement.
- Tab/Shift-Tab follows the declaration order. Arrow-key movement within a section may use `focusIndex`, but must never skip unavailable rows’ readable content or place focus on a disabled nonexistent control.
- Layout uses adaptive `Grid`/`LabeledContent`, permits vertical growth, and never fixes row height. At accessibility text sizes metadata stacks below the title/control and remains visible at 480 points.
- Use semantic system roles only: `.primary` for title/value, `.secondary` for metadata, `.orange` plus a symbol/text label for unavailable/deferred warning, and system background/material. No opacity-only state and no hard-coded RGB/hex colors.
- `SettingsVisualContract.layoutMode(for:)` returns `.stacked` for every accessibility dynamic type size and `.columns` otherwise. `RegistrySettingsSurface` must use this exact result, not a separate width/type-size heuristic. The three semantic role constants likewise drive the actual foreground-style switch.
- The fixture host must expose both light and dark scheme toggles, 480/620 point width toggles, and the accessibility3 dynamic type fixture without querying the local machine.

## Zero-work-on-open boundary

The `SettingsView` body and every initializer/projection it calls must be synchronous and pure apart from reading the already-observed `AppConfigStore`. The Settings source must contain none of these on-open mechanisms or dependencies:

```text
.task    Task {    Task.detached    .onAppear    .onReceive
.refreshable    Timer    Process(    Process.
ProcessSurvey    CookieDomainSuggester    GitRootDiscovery
SimctlClient    CleanEngine    requestPlan    loadPlan
FileManager    URLSession    NSWorkspace    DispatchSource
NotificationCenter
```

Button-driven OS pickers are also out of scope because authority workflows are deferred. An edit may enqueue only the user-requested `AppConfigStore` preference write; rendering/opening may enqueue nothing.

The source-contract test is deliberately narrow to `SettingsView.swift`; it does not claim `CustomView` has no `.task`, because Custom Clean has a different accepted contract. It must still permit the literal, synchronous user-action path `store.setGlobalPreference`; do not ban `submit`, `Button`, bindings, or that exact shared-store call.

## Complete RED core test

Create `TidyCore/Tests/TidyCoreTests/SettingsPresentationTests.swift` exactly as follows before production code. Its first RED must be missing `SettingsPresentation*` APIs, not a syntax or fixture failure.

```swift
import Foundation
import Testing
@testable import TidyCore

@Suite("Settings presentation registry")
struct SettingsPresentationTests {
    private let volumeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let expectedBasic = Set([
        "feature.headroom", "feature.buildPrep", "feature.projects", "feature.rescue",
        "feature.ecosystems", "feature.budgets", "feature.history", "feature.maintenance",
        "scan.preset", "scan.defaultScope", "cleanup.inactiveDays", "cleanup.costCeiling",
        "cleanup.requestedBatchGiB", "headroom.targetGiB", "headroom.warningGiB",
        "notifications.enabled", "ui.units", "ui.cards"
    ].map { SettingID(rawValue: $0) })

    private func expectedSection(_ id: SettingID) -> SettingsPresentationSection {
        let raw = id.rawValue
        if raw.hasPrefix("feature.") || raw.hasPrefix("ecosystem.") ||
            (raw.hasPrefix("item.") && raw.hasSuffix(".enabled")) { return .features }
        if raw.hasPrefix("scan.") || raw.hasPrefix("monitor.") || [
            "scope.projectRoots", "scope.externalVolumes", "scope.currentProject"
        ].contains(raw) { return .scan }
        if raw.hasPrefix("cleanup.") || raw.hasPrefix("headroom.") ||
            raw == "browsers.keepCookieDomains" || [
                "scope.excludedRoots", "scope.pinnedProjects"
            ].contains(raw) || (raw.hasPrefix("item.") && !raw.hasSuffix(".enabled")) {
            return .cleanup
        }
        return .experience
    }

    @Test("fixed validation and rendered universes are separate and deterministic")
    func exhaustiveCoverage() throws {
        let universe = SettingsPresentationRegistry.validationUniverse()
        try SettingsPresentationRegistry.validateCoverage()
        #expect(SettingsPresentationRegistry.validationVolumeID == volumeID)
        #expect(universe.filter { $0.id == PolicyDefaults.volumeRow(id: volumeID).id }.count == 1)

        let withoutVolume = try SettingsPresentationRegistry.all()
        let withVolume = try SettingsPresentationRegistry.all(volumeIDs: [volumeID])
        let duplicateVolume = try SettingsPresentationRegistry.all(volumeIDs: [volumeID, volumeID])

        #expect(withoutVolume.allSatisfy {
            !$0.definition.id.rawValue.hasPrefix("headroom.volumeOverrides.")
        })
        #expect(withVolume.count == withoutVolume.count + 1)
        #expect(withVolume == duplicateVolume)
        #expect(Set(withVolume.map(\.definition.id)) == Set(universe.map(\.id)))
        #expect(Set(withVolume.map(\.definition.id)).count == universe.count)
        for section in SettingsPresentationSection.allCases {
            let orders = withVolume.filter { $0.presentation.section == section }.map(\.order)
            #expect(orders == orders.sorted())
            #expect(Set(orders).count == orders.count)
        }
        #expect(withVolume.filter { $0.presentation.pattern == .volumeOverride }
            .allSatisfy { (200_000..<300_000).contains($0.order) })
        #expect(withVolume.filter {
            if case .catalogItem = $0.presentation.pattern { return true }
            return false
        }.allSatisfy { (100_000..<200_000).contains($0.order) })
        #expect(withVolume.filter {
            if case .exact = $0.presentation.pattern { return true }
            return false
        }.allSatisfy { (0..<100_000).contains($0.order) })
        #expect(SettingsPresentationRegistry.basicIDs == expectedBasic)
        #expect(withVolume.allSatisfy {
            $0.presentation.section == expectedSection($0.definition.id)
        })
        #expect(withVolume.allSatisfy { !$0.presentation.keys.title.isEmpty })
        #expect(withVolume.allSatisfy { !$0.presentation.keys.help.isEmpty })
        #expect(withVolume.allSatisfy { !$0.presentation.keys.consequence.isEmpty })
        #expect(withVolume.allSatisfy { !$0.presentation.keys.applicability.isEmpty })

        for item in CleanCatalog.allItems {
            let expected = Set(PolicyDefaults.itemRows(catalogID: item.id).map(\.id))
            #expect(expected.count == 4)
            #expect(expected.isSubset(of: Set(withVolume.map(\.definition.id))))
        }
    }

    @Test("missing, ambiguous, orphan, and duplicate order entries reject")
    func negativeCoverage() throws {
        let universe = SettingsPresentationRegistry.validationUniverse()
        let first = try #require(SettingsPresentationRegistry.entries.first)
        let matching = universe.filter { definition in
            (try? SettingsPresentationRegistry.validateCoverage(
                entries: [first], definitions: [definition])) != nil
        }
        let matched = try #require(matching.first)

        #expect(throws: SettingsPresentationCoverageError.missing(matched.id)) {
            try SettingsPresentationRegistry.validateCoverage(
                entries: SettingsPresentationRegistry.entries.filter { $0 != first },
                definitions: universe)
        }
        #expect(throws: SettingsPresentationCoverageError.ambiguous(matched.id)) {
            try SettingsPresentationRegistry.validateCoverage(
                entries: SettingsPresentationRegistry.entries + [first],
                definitions: universe)
        }

        let orphan = SettingPresentation(
            pattern: .exact(SettingID(rawValue: "fixture.unknown")),
            section: .experience, tier: .advanced, order: Int.max,
            keys: SettingsPresentationKeys(
                title: "fixture.title", help: "fixture.help",
                consequence: "fixture.consequence",
                applicability: "fixture.applicability"))
        #expect(throws: SettingsPresentationCoverageError.orphan(orphan.pattern)) {
            try SettingsPresentationRegistry.validateCoverage(
                entries: SettingsPresentationRegistry.entries + [orphan],
                definitions: universe)
        }

        let firstDefinition = try #require(PolicyDefaults.rows.first)
        let firstPresentation = try SettingsPresentationRegistry.presentation(for: firstDefinition)
        let secondDefinition = try #require(PolicyDefaults.rows.dropFirst().first { definition in
            guard let candidate = try? SettingsPresentationRegistry.presentation(for: definition)
            else { return false }
            return candidate.section == firstPresentation.section
        })
        let secondPresentation = try SettingsPresentationRegistry.presentation(for: secondDefinition)
        let collision = SettingPresentation(
            pattern: secondPresentation.pattern, section: secondPresentation.section,
            tier: secondPresentation.tier, order: firstPresentation.order,
            keys: secondPresentation.keys)
        #expect(throws: SettingsPresentationCoverageError.duplicateOrder(
            firstPresentation.section, firstPresentation.order)) {
            try SettingsPresentationRegistry.validateCoverage(
                entries: [firstPresentation, collision],
                definitions: [firstDefinition, secondDefinition])
        }
    }

    @Test("dynamic patterns reject lookalikes and are stable")
    func exactDynamicGrammar() throws {
        let item = try #require(CleanCatalog.allItems.first)
        let real = try #require(PolicyDefaults.itemRows(catalogID: item.id).first)
        _ = try SettingsPresentationRegistry.presentation(for: real)
        _ = try SettingsPresentationRegistry.presentation(for: PolicyDefaults.volumeRow(id: volumeID))

        let lookalikes = [
            "item.unknown.enabled",
            "item.\(item.id).enabled.extra",
            "headroom.volumeOverrides.00000000-0000-0000-0000-000000000001.extra",
            "headroom.volumeOverrides.aaaaaaaa-0000-0000-0000-000000000001"
        ]
        for raw in lookalikes {
            let definition = SettingDefinition(
                id: SettingID(rawValue: raw), kind: .bool, defaultValue: .bool(false),
                rule: .boolean, resolution: .preference, effect: .none,
                layers: [.global], group: "fixture")
            #expect(throws: SettingsPresentationCoverageError.missing(definition.id)) {
                _ = try SettingsPresentationRegistry.presentation(for: definition)
            }
        }
    }

    @Test("stable accessibility IDs do not depend on copy")
    func stableAccessibilityIDs() {
        let id = SettingID(rawValue: "item.safe.cache.swiftpm-cache.inactiveDays")
        #expect(SettingsPresentationRegistry.accessibilityIdentifier(for: id)
                == "settings.row.item.safe.cache.swiftpm-cache.inactiveDays")
    }
}
```

The implementation should simplify the `negativeCoverage` matched-definition lookup by exposing a package-internal `matches(_:definition:)` only if Swift type checking requires it. Do not weaken the three exact error assertions.

## Complete RED app-model/render/source tests

Add `import SwiftUI` beside the existing imports in `SharedSettingsWiringTests.swift`, then append this extension. The implementation must use the exact API above; only existing fixture construction helpers may be substituted if their names differ.

```swift
extension SharedSettingsWiringTests {
    private func expectedSettingsControl(_ definition: SettingDefinition)
        -> SettingsControlKind {
        switch (definition.kind, definition.rule) {
        case (.bool, .boolean): return .toggle
        case (.integer, .integer(_, _)): return .integer
        case (.optionalInteger, .optionalInteger(_, _)),
             (.optionalInteger, .headroomTarget),
             (.optionalInteger, .headroomWarning),
             (.optionalInteger, .headroomClear),
             (.optionalInteger, .budgetHigh),
             (.optionalInteger, .budgetLow): return .optionalInteger
        case (.choice, .choices(_)): return .choice
        default: return .readOnly
        }
    }

    @MainActor
    func testSettingsRowsAreReachableSearchAdvancedAndAuthorityIsDeferred() async throws {
        try await run { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let model = SettingsSurfaceModel(store: services.configStore, bundle: bundle)
            let basic = model.rows(query: "", showsAdvanced: false)
            let all = model.rows(query: "", showsAdvanced: true)
            let universe = try SettingsPresentationRegistry.all(volumeIDs: [])
            XCTAssertEqual(Set(all.map(\.id)), Set(universe.map(\.definition.id)))
            XCTAssertEqual(Set(basic.map(\.id)), SettingsPresentationRegistry.basicIDs)
            XCTAssertTrue(basic.allSatisfy { $0.setting.presentation.tier == .basic })
            XCTAssertFalse(basic.contains { $0.setting.presentation.tier == .advanced })

            let advanced = try XCTUnwrap(all.first { row in
                row.setting.presentation.tier == .advanced
            })
            let searchFields = [advanced.id.rawValue, advanced.title, advanced.help,
                advanced.consequence, advanced.defaultText, advanced.effectiveText,
                advanced.sourceText, advanced.ruleText, advanced.availabilityText]
            for field in searchFields where !field.isEmpty {
                XCTAssertTrue(model.rows(query: field, showsAdvanced: false)
                    .contains { $0.id == advanced.id }, "search missed \(field)")
            }
            XCTAssertEqual(SettingsSearch.normalize("  RÉSUMÉ  VALUE "), "resume value")

            let beforePreferences = services.configStore.preferences
            let beforeGeneration = services.policyBridge.updateGeneration
            let beforeAdmission = services.coordinator.policyAdmission()
            let beforeExecutionEnabled = services.policyBridge.isExecutionEnabled
            let beforeRevision = services.policyBridge.durableSettingsRevision
            let authorityRows = all.filter {
                $0.setting.definition.resolution == .authority
            }
            XCTAssertFalse(authorityRows.isEmpty)
            for row in authorityRows {
                guard case .deferred = row.availability else {
                    return XCTFail("authority row not deferred: \(row.id.rawValue)")
                }
                XCTAssertNil(model.submit(id: row.id,
                    value: row.setting.definition.defaultValue))
                XCTAssertEqual(services.configStore.preferences, beforePreferences)
                XCTAssertEqual(services.policyBridge.updateGeneration, beforeGeneration)
                XCTAssertEqual(services.coordinator.policyAdmission(), beforeAdmission)
                XCTAssertEqual(services.policyBridge.isExecutionEnabled, beforeExecutionEnabled)
                XCTAssertEqual(services.policyBridge.durableSettingsRevision, beforeRevision)
                XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
                XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
                XCTAssertFalse(services.policyBridge.storageUpdatePending)
                XCTAssertFalse(services.policyBridge.policyUpdatePending)
            }

            let readOnlyGlobalRows = all.filter { row in
                let definition = row.setting.definition
                return definition.resolution != .authority &&
                    definition.layers.contains(.global) && row.controlKind == .readOnly
            }
            XCTAssertFalse(readOnlyGlobalRows.isEmpty)
            for row in readOnlyGlobalRows {
                guard case .unavailable = row.availability else {
                    return XCTFail("read-only global P/R row not unavailable: \(row.id.rawValue)")
                }
                XCTAssertNil(model.submit(id: row.id,
                    value: row.setting.definition.defaultValue))
                XCTAssertEqual(services.configStore.preferences, beforePreferences)
                XCTAssertEqual(services.policyBridge.updateGeneration, beforeGeneration)
                XCTAssertEqual(services.coordinator.policyAdmission(), beforeAdmission)
                XCTAssertEqual(services.policyBridge.isExecutionEnabled, beforeExecutionEnabled)
                XCTAssertEqual(services.policyBridge.durableSettingsRevision, beforeRevision)
                XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
                XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
                XCTAssertFalse(services.policyBridge.storageUpdatePending)
                XCTAssertFalse(services.policyBridge.policyUpdatePending)
            }
            XCTAssertTrue(basic.contains { $0.id.rawValue == "ui.cards" })
            let volume = PolicyDefaults.volumeRow(id:
                UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
            XCTAssertNil(model.submit(id: volume.id, value: .volume(.init(
                target: .automatic, warning: .automatic, clear: .automatic))))
            XCTAssertEqual(services.configStore.preferences, beforePreferences)
            XCTAssertEqual(services.policyBridge.updateGeneration, beforeGeneration)
            XCTAssertEqual(services.coordinator.policyAdmission(), beforeAdmission)
            XCTAssertEqual(services.policyBridge.isExecutionEnabled, beforeExecutionEnabled)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, beforeRevision)

            for row in all where row.setting.definition.resolution != .authority &&
                row.setting.definition.layers.contains(.global) && row.controlKind != .readOnly {
                XCTAssertEqual(row.controlKind,
                               expectedSettingsControl(row.setting.definition))
                guard case .editable = row.availability else {
                    return XCTFail("supported global P/R row is not editable: \(row.id.rawValue)")
                }
            }
            for row in all {
                XCTAssertEqual(row.controlKind,
                               expectedSettingsControl(row.setting.definition))
            }

            for row in all {
                XCTAssertNotEqual(row.title, row.setting.presentation.keys.title)
                XCTAssertNotEqual(row.help, row.setting.presentation.keys.help)
                XCTAssertNotEqual(row.consequence, row.setting.presentation.keys.consequence)
                XCTAssertNotEqual(row.availabilityText,
                                  row.setting.presentation.keys.applicability)
            }
        }
    }

    @MainActor
    func testSettingsRepresentativeGlobalControlsUseSharedStore() async throws {
        try await run { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let first = SettingsSurfaceModel(store: services.configStore, bundle: bundle)
            let second = SettingsSurfaceModel(store: services.configStore, bundle: bundle)
            let edits: [(String, SettingValue)] = [
                ("feature.headroom", .bool(false)),
                ("cleanup.inactiveDays", .integer(61)),
                ("cleanup.hardBatchGiB", .integer(20)),
                ("ui.units", .choice("decimal"))
            ]

            for (raw, value) in edits {
                let id = SettingID(rawValue: raw)
                let row = try XCTUnwrap(first.rows(query: raw, showsAdvanced: false)
                    .first { $0.id == id })
                guard case .editable = row.availability else {
                    return XCTFail("representative control unavailable: \(raw)")
                }
                let admission = try XCTUnwrap(first.submit(id: id, value: value))
                let outcome: SettingsIntentOutcome
                switch admission {
                case .accepted(_, let task): outcome = await task.value
                case .rejected(_, let reason):
                    return XCTFail("unexpected rejection for \(raw): \(reason)")
                }
                guard case .saved = outcome else { return XCTFail("\(raw) was not saved") }
                await services.policyBridge.drain()
                XCTAssertEqual(services.configStore.preferences.global.fields[id], value)
                XCTAssertEqual(second.rows(query: raw, showsAdvanced: false)
                    .first { $0.id == id }?.storedValue, value)
            }
        }
    }

    @MainActor
    func testSettingsAccessibilityFocusAndSemanticContrastContract() async throws {
        try await run { _, services, _ in
            let rows = SettingsSurfaceModel(store: services.configStore,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
                .rows(query: "", showsAdvanced: true)

            XCTAssertEqual(rows.map(\.focusIndex), Array(rows.indices))
            XCTAssertEqual(Set(rows.map(\.accessibilityIdentifier)).count, rows.count)
            XCTAssertEqual(Set(rows.map(\.accessibilityLabel)).count, rows.count)
            XCTAssertTrue(rows.allSatisfy {
                $0.accessibilityLabel.contains($0.title) &&
                $0.accessibilityLabel.contains($0.id.rawValue)
            })
            XCTAssertTrue(rows.allSatisfy { $0.accessibilityIdentifier ==
                "settings.row." + $0.id.rawValue })
            XCTAssertTrue(rows.allSatisfy { !$0.defaultText.isEmpty && !$0.effectiveText.isEmpty &&
                !$0.sourceText.isEmpty && !$0.ruleText.isEmpty && !$0.consequence.isEmpty })
            XCTAssertEqual(SettingsVisualContract.titleRole, .primary)
            XCTAssertEqual(SettingsVisualContract.metadataRole, .secondary)
            XCTAssertEqual(SettingsVisualContract.unavailableRole, .warning)
            XCTAssertEqual(SettingsVisualContract.layoutMode(for: .large), .columns)
            XCTAssertEqual(SettingsVisualContract.layoutMode(for: .accessibility1), .stacked)
        }
    }

    @MainActor
    func testSettingsAccessibilityTextLayoutRendersAtMinimumWidth() async throws {
        try await run { _, services, _ in
            let rows = SettingsSurfaceModel(store: services.configStore,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
                .rows(query: "", showsAdvanced: false)
            var submissions = 0
            let view = RegistrySettingsSurface(rows: rows) { _, _ in submissions += 1 }
                .environment(\.dynamicTypeSize, .accessibility3)
                .frame(width: 480, height: 900)
            let renderer = ImageRenderer(content: view)

            XCTAssertNotNil(renderer.cgImage)
            XCTAssertEqual(submissions, 0, "rendering/opening must not submit an edit")
        }
    }

    func testSettingsLocalizationCatalogCoversEveryRegistryKey() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf:
            repository.appendingPathComponent("Tidy/Resources/Localizable.xcstrings"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data)
            as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        var required = Set(SettingsPresentationRegistry.entries.flatMap { entry in
            [entry.keys.title, entry.keys.help, entry.keys.consequence,
             entry.keys.applicability]
        })
        required.insert("settings.copy.missing")
        XCTAssertTrue(required.isSubset(of: Set(strings.keys)))
        for key in required {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(value.isEmpty)
            XCTAssertNotEqual(value, key)
        }
    }

    func testSettingsDynamicLocalizationInterpolatesIdentityAndFallsBackSafely() throws {
        let bundle = Bundle(for: SharedSettingsWiringTests.self)
        func keys(_ presentation: SettingPresentation) -> [String] {
            [presentation.keys.title, presentation.keys.help,
             presentation.keys.consequence, presentation.keys.applicability]
        }
        func resolved(_ presentation: SettingPresentation, identity: String) -> [String] {
            keys(presentation).map {
                SettingsCopy.resolve($0, arguments: [identity], bundle: bundle)
            }
        }

        let items = Array(CleanCatalog.allItems.prefix(2))
        XCTAssertEqual(items.count, 2)
        let firstItem = try XCTUnwrap(items.first)
        let secondItem = try XCTUnwrap(items.last)
        XCTAssertNotEqual(firstItem.id, secondItem.id)
        let firstDefinitions = PolicyDefaults.itemRows(catalogID: firstItem.id)
        let secondDefinitions = PolicyDefaults.itemRows(catalogID: secondItem.id)
        XCTAssertEqual(firstDefinitions.count, 4)
        XCTAssertEqual(secondDefinitions.count, 4)
        for (firstDefinition, secondDefinition) in zip(firstDefinitions, secondDefinitions) {
            let firstPresentation = try SettingsPresentationRegistry.presentation(
                for: firstDefinition)
            let secondPresentation = try SettingsPresentationRegistry.presentation(
                for: secondDefinition)
            XCTAssertEqual(firstPresentation.pattern, secondPresentation.pattern,
                           "paired catalog rows must use the same suffix presentation")
            let firstCopy = resolved(firstPresentation, identity: firstItem.id)
            let secondCopy = resolved(secondPresentation, identity: secondItem.id)
            XCTAssertEqual(firstCopy.count, 4)
            XCTAssertEqual(secondCopy.count, 4)
            XCTAssertTrue(firstCopy.allSatisfy { $0.contains(firstItem.id) })
            XCTAssertTrue(secondCopy.allSatisfy { $0.contains(secondItem.id) })
            for (firstOutput, secondOutput) in zip(firstCopy, secondCopy) {
                XCTAssertNotEqual(firstOutput, secondOutput,
                                  "corresponding suffix/key output must include its identity")
            }
        }

        let sentinel = SettingsPresentationRegistry.validationVolumeID
        let other = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let sentinelCopy = resolved(try SettingsPresentationRegistry.presentation(
            for: PolicyDefaults.volumeRow(id: sentinel)), identity: sentinel.uuidString)
        let otherCopy = resolved(try SettingsPresentationRegistry.presentation(
            for: PolicyDefaults.volumeRow(id: other)), identity: other.uuidString)
        XCTAssertTrue(sentinelCopy.allSatisfy { $0.contains(sentinel.uuidString) })
        XCTAssertTrue(otherCopy.allSatisfy { $0.contains(other.uuidString) })
        XCTAssertNotEqual(sentinelCopy, otherCopy)

        XCTAssertEqual(SettingsCopy.resolve("settings.copy.missing", bundle: bundle),
                       "Description unavailable.")
        let missing = SettingsCopy.resolve("settings.fixture.does-not-exist", bundle: bundle)
        XCTAssertEqual(missing, "Description unavailable.")
        XCTAssertFalse(missing.contains("settings.fixture.does-not-exist"))
    }

    func testSettingsSourceHasNoOnOpenWorkTrigger() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf:
            repository.appendingPathComponent("Tidy/Settings/SettingsView.swift"),
            encoding: .utf8)
        let forbidden = [
            ".task", "Task {", "Task.detached", ".onAppear", ".onReceive",
            ".refreshable", "Timer", "Process(", "Process.", "ProcessSurvey",
            "CookieDomainSuggester", "GitRootDiscovery", "SimctlClient", "CleanEngine",
            "requestPlan", "loadPlan", "FileManager", "URLSession", "NSWorkspace",
            "DispatchSource", "NotificationCenter"
        ]
        for token in forbidden {
            XCTAssertFalse(source.contains(token), "Settings on-open source contains \(token)")
        }
        XCTAssertFalse(source.contains("ExecutionPolicyBridge"))
        XCTAssertFalse(source.contains("SettingsStore"))
        XCTAssertFalse(source.contains("Color(red:"))
        XCTAssertFalse(source.contains(".opacity("))
        XCTAssertTrue(source.contains("SettingsVisualContract.titleRole"))
        XCTAssertTrue(source.contains("SettingsVisualContract.layoutMode"))
        XCTAssertTrue(source.contains("store.setGlobalPreference"))
    }
}
```

The extension deliberately uses the file’s existing private `run` harness. Do not add a second bootstrap helper or instantiate an extra store merely to make the tests compile.

## Deterministic UI-host fixture

Modify the existing host, not the production environment:

- Add `settings = "Settings"` to `FixtureSurface` and give it no cleanup tier/use.
- Refactor the chooser’s cleanup tier switch so `.settings` does not construct a `CleanPlan`.
- `ReviewFixtures.settingsRows` builds rows solely from `SettingsPresentationRegistry.all(volumeIDs: [])`, the host bundle’s compiled string catalog, default `PolicyValues`, and a pure fixture `EffectivePolicy` projection. It does not instantiate `AppExecutionServices`, `SettingsStore`, `ExecutionPolicyBridge`, or discover the Mac.
- Render the actual `RegistrySettingsSurface` with a no-op submit closure that increments a visible fixture counter. Merely selecting/opening Settings must leave the counter at zero.
- Add scheme (`Light`/`Dark`), width (`480`/`620`), and text-size (`Default`/`Accessibility 3`) controls outside the surface.
- Preserve the marker `TIDY_MANUAL_FIXTURE_HOST_ONLY` and change the host disclaimer to “Manual fixtures: no discovery, persistence, settings write or cleanup.”
- Add stable fixture labels/IDs for human review. This is a source/render host; it is not an XCTest UI automation target and must not be reported as physical accessibility evidence.

## TDD execution sequence

Only one heavy test/build command may run at a time. Use two jobs where the tool accepts it.

### Step 1 — record baseline and add only RED tests/minimal source membership

```bash
git status --short
git diff --check
swift test --package-path TidyCore --jobs 2 --filter SettingsPresentationTests
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -maximum-concurrent-test-device-destinations 1 \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsRowsAreReachableSearchAdvancedAndAuthorityIsDeferred test
```

Required RED: missing `SettingsPresentation*`, `SettingsSurface*`, or `RegistrySettingsSurface` APIs. A project parse error, duplicate build file, missing pre-existing fixture, linker error unrelated to those APIs, or test syntax error is not an acceptable RED.

At this RED step, add only the two `SettingsView.swift` source memberships needed by the app-model/host compilers. Do not reference a nonexistent catalog or add its resource phases yet. Create the catalog and all three exact resource memberships during Step 3 before the app-model GREEN run; add the UI-host `AppConfigStore.swift` membership before Step 4.

### Step 2 — implement pure core registry and make focused core GREEN

```bash
swift test --package-path TidyCore --jobs 2 --filter SettingsPresentationTests
swift test --package-path TidyCore --jobs 2 --filter PolicyDefaultsTests
swift test --package-path TidyCore --jobs 2 --filter PolicyResolverTests
```

### Step 3 — implement app projection/surface and make focused app tests GREEN

```bash
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -maximum-concurrent-test-device-destinations 1 \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsRowsAreReachableSearchAdvancedAndAuthorityIsDeferred \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsRepresentativeGlobalControlsUseSharedStore \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsAccessibilityFocusAndSemanticContrastContract \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsAccessibilityTextLayoutRendersAtMinimumWidth \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsLocalizationCatalogCoversEveryRegistryKey \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsDynamicLocalizationInterpolatesIdentityAndFallsBackSafely \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsSourceHasNoOnOpenWorkTrigger test
```

Then run the entire containing suite:

```bash
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -maximum-concurrent-test-device-destinations 1 \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests test
```

### Step 4 — fixture host and ordinary verification

```bash
xcodebuild -project Tidy.xcodeproj -scheme TidyUITestHost -configuration Debug \
  -destination 'platform=macOS' -jobs 2 CODE_SIGNING_ALLOWED=NO build
swift test --package-path TidyCore --jobs 2
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -maximum-concurrent-test-device-destinations 1 test
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -jobs 2 CODE_SIGNING_ALLOWED=NO build
git diff --check
git status --short
```

Run the established relevant process acceptance partitions from the accepted T07/T06 cards after the ordinary package suite; do not invent a new partition or claim them through a filtered unit test. Record exact command, count, and result in the verification document.

### Step 5 — adversarial review before acceptance

Request a fresh adversarial source review against this card. The reviewer must inspect at least:

- registry one-to-one matching and orphan behavior;
- fixed sentinel validation versus empty/stable-deduplicated rendered volume universes;
- all current static/catalog/volume families;
- absence of duplicated policy truth;
- metadata-only collision-free ordering, exact Basic IDs, and exact sections;
- catalog resource membership, complete English copy, and no raw-key fallback;
- executable four-key interpolation for two real item IDs and two volume UUIDs;
- normalized all-field search-bypasses-tier behavior;
- exhaustive supported-control editability and read-only `ui.cards`;
- zero-state-change submission rejection for every authority and global read-only P/R row;
- authority/global-layer fail-closed edit preflight;
- absence of a second store or direct bridge/store submission;
- zero-work-on-open source and render proof;
- PBX membership exactness;
- stable accessibility IDs/labels/focus and semantic contrast/text-size proof boundaries;
- no profile/transfer/reset workflow leakage from 3b.

Fix every valid finding test-first inside the allowlist, rerun the focused containing suites and relevant partitions, then obtain final approval. Do not commit during delegated implementation unless the parent explicitly authorizes it.

## Automated acceptance matrix

| Requirement | Automated proof in 3a | Negative proof |
|---|---|---|
| Static/dynamic coverage | fixed validation universe covers all static/catalog rows plus sentinel pattern witness | rendered `all([])` has no volume; duplicate volume IDs stable-deduplicate; missing/ambiguous/orphan/lookalike reject |
| Deterministic ordering/tiering | metadata-only nonoverlapping static/item/volume ranges; exact Basic ID set and exact section-family mapping | duplicate section/order rejects |
| Search | every raw/copy/default/effective/source/rule/availability field reaches an Advanced row under normalized search | empty search exposes exactly Basic and hides Advanced |
| Every visible row explains policy | resolved catalog copy plus nonempty default/effective/source/rule/consequence/availability; all four item/volume templates interpolate identity | exact missing-copy fallback never exposes raw key; two item IDs/two UUIDs resolve differently |
| Shared owner | representative bool/integer/optional/restriction/choice edits save through two models over one `AppConfigStore` | every authority and every global read-only P/R rejects with preferences, bridge generation, queue and coordinator admission unchanged |
| No opening work | render counter remains zero; forbidden source dependencies absent | Custom Clean remains out of the assertion’s scope |
| Accessibility identifiers/labels/focus | exact IDs, unique labels, contiguous focus indices | localization text cannot change identifier |
| Text size | actual surface renders at 480 pt and accessibility3 | no fixed row-height contract |
| Contrast | semantic primary/secondary/warning roles and light/dark fixture | no hard-coded RGB/opacity-only state |

## Evidence boundary and gates that remain open

The following may be reported after GREEN:

- source inspection and pure registry coverage;
- focused and ordinary SwiftPM/XCTest results;
- actual SwiftUI render smoke at accessibility text size;
- deterministic fixture-host build and manual-fixture availability;
- unsigned arm64 app build;
- adversarial source-review result.

The following **must not** be inferred from those results and remain explicit later acceptance gates:

- physical VoiceOver reading order, rotor behavior, announcements, and edit feedback;
- actual keyboard traversal on supported physical hardware beyond source/model focus ordering;
- measured text clipping/contrast under every macOS appearance/accessibility combination;
- macOS 14 behavior;
- Intel build/runtime behavior;
- sustained operation on a physical 8 GiB Mac;
- signed/notarized/DMG/release behavior;
- profile, import/export, reset, local-authority, notification, maintenance, login-item, or data-clearing workflows.

The verification document must use those exact distinctions. “Rendered,” “built,” or “unit-tested” is not “VoiceOver accepted” or “8 GiB device accepted.”

## Definition of done for T07.3a

T07.3a is complete only when the RED sequence was observed, every allowed test/build above is GREEN with exact evidence, the actual Settings surface and deterministic host both compile, relevant process partitions remain GREEN, `git diff --check` is clean, the diff touches only the allowlist, a fresh adversarial review is Approved, and all physical/device/3b gates remain honestly open.

It is not complete merely because the presentation registry compiles, the host renders, or the app builds.
