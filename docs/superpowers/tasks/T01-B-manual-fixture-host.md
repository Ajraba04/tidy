# T01.B Manual Fixture Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans after independent review and controller authorization. This is a document-only entry supplement, not source authority or verification evidence. The existing T01.B implementer remains the sole source owner; coordinate the extraction before editing. No build, launch or commit is authorized by preparation of this document.

**Goal:** Satisfy T01.B's manual review-screen inspection safely, without waiting for the T02-dependent full T05 UI safety suite.

**Architecture:** Extract Custom's review content into a production-shared native SwiftUI view. A separate fixture application compiles only the shared review views/model and supplies in-memory descriptive plans, immutable presets and zero-effect callbacks. Production containers retain their existing initialization, persistence and execution responsibilities; the host never instantiates them.

**Tech Stack:** Swift/SwiftUI, macOS 14+, existing local TidyCore, XcodeGen; no new dependencies.

## Global Constraints

- Native Swift/SwiftUI, macOS 14+, local TidyCore package, zero third-party runtime dependencies.
- Intel x86_64 and Apple Silicon arm64 supported; both require build and device evidence.
- No internet requests, telemetry, remote updates, repository fetches, model downloads, or remote package dependencies at runtime.
- Local IPC to an explicitly identified local tool service is allowed. No remote Docker contexts, TCP endpoints, SSH endpoints, or daemon auto-start during discovery.
- No repository deletion, database deletion, Docker volume deletion, local-model deletion, generic duplicate-file deletion, arbitrary scripts, or automatic force-quitting.
- No kernel tuning, swap-file manipulation, launch-agent disabling, privileged persistent helper, or changes to other tools' settings.
- No full-home scans on popover open or timers. No repository-supplied executable/config evaluation merely to discover a project.
- No change to signing, publishing, deployment, or remote Git state is authorized by this document.

Design S01–S16, the approved adapter appendix and the parent T01 card remain binding. This host additionally forbids application filesystem/settings reads or writes, discovery, IPC, executors and subprocesses entirely. Normal OS/framework window machinery is not a claim of zero OS-level I/O. Do not launch the normal app for fixture inspection, redirect HOME/CFFIXED_USER_HOME, add a runtime fixture flag, inject authority, or supply replacement mock implementations of actual app views/stores.

## Task 1: Review and establish the narrow shared-view interface

**Files:**

- Create: `Tidy/Custom/CustomPlanView.swift`.
- Modify: `Tidy/Custom/CustomView.swift` (already in T01.B scope).
- Consume without replacing: `Tidy/Clean/CleanPlanView.swift`, `Tidy/Clean/PlanReviewRow.swift`, `Tidy/Clean/PlanSelectionModel.swift` from T01.B.
- Create later: `TidyUITestHost/TestHostApp.swift`.
- Modify later: `project.yml`; regenerate `Tidy.xcodeproj/project.pbxproj` only through XcodeGen.

No AppConfigStore, ConfigStore, TidyApp, core authority, engine, settings schema, production initialization or production execution API changes belong to this supplement. No UI automation target is introduced yet. T05 may extend this separate host later under its own reviewed scope.

**Consumes:** T01.B's `PlanSelectionModel.init(plan: CleanPlan, selectDefaults: Bool)`, read-only `value: PlanSelection`, `setSelected(_:id:)`, `applyPresetIDs(_:)`; and `CleanPlanView(selection: PlanSelectionModel, onConfirm: @escaping () -> Void)`.

**Produces:** This exact Custom review interface, with no default callbacks or default configuration:

```swift
init(selection: PlanSelectionModel,
     presets: [CustomPreset],
     onSavePreset: @escaping (CustomPreset) -> Void,
     onConfirm: @escaping () -> Void)
```

Requiring explicit inputs prevents a seemingly harmless initializer from silently loading settings or executing commands. The production wrapper supplies real callbacks; only the separately compiled host supplies no-op callbacks. They are presentation dependencies, not authorization hooks.

- [ ] Independent reviewer approves this supplement, its interfaces, fixture semantics and exact target membership. Controller then authorizes source work and coordinates with the sole T01.B implementer.
- [ ] Confirm T01.B's model/row APIs exist. Before extraction, `test -f Tidy/Custom/CustomPlanView.swift` should exit 1: the shared-view prerequisite is absent. Record this as a structural prerequisite check, not behavioral RED or a UI test. T01.B's required core RED/GREEN remains separate; do not invent a successful UI test before the host exists. Build and manual integration checks below supply this presentation-only extraction's verification.
- [ ] Create `Tidy/Custom/CustomPlanView.swift` with this complete shared implementation:

```swift
import SwiftUI
import TidyCore

struct CustomPlanView: View {
    let selection: PlanSelectionModel
    let presets: [CustomPreset]
    let onSavePreset: (CustomPreset) -> Void
    let onConfirm: () -> Void

    @State private var showingConfirmation = false
    @State private var showingSavePreset = false
    @State private var presetName = ""

    init(selection: PlanSelectionModel, presets: [CustomPreset],
         onSavePreset: @escaping (CustomPreset) -> Void,
         onConfirm: @escaping () -> Void) {
        self.selection = selection
        self.presets = presets
        self.onSavePreset = onSavePreset
        self.onConfirm = onConfirm
    }

    private var uncategorizedItems: [PlannedItem] {
        let categorizedIDs = Set(CleanCatalog.categories.flatMap { $0.items.map(\.id) })
        return selection.value.reviewItems.filter { !categorizedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if !presets.isEmpty {
                    Section("Presets") {
                        ForEach(presets) { preset in
                            Button(preset.name) { selection.applyPresetIDs(preset.itemIDs) }
                        }
                    }
                }
                ForEach(CleanCatalog.categories) { category in
                    let ids = Set(category.items.map(\.id))
                    let items = selection.value.reviewItems.filter { ids.contains($0.id) }
                    if !items.isEmpty {
                        Section(category.title) {
                            ForEach(items) { item in
                                PlanReviewRow(item: item, isSelected: binding(for: item.id))
                            }
                        }
                    }
                }
                if !uncategorizedItems.isEmpty {
                    Section("Other") {
                        ForEach(uncategorizedItems) { item in
                            PlanReviewRow(item: item, isSelected: binding(for: item.id))
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Save Selection as Preset…") { showingSavePreset = true }
                    .disabled(selection.value.selectedCount == 0)
                Spacer()
                Text(ByteFormat.human(selection.value.selectedEstimatedBytes))
                    .foregroundStyle(.secondary)
                Button("Clean Selected (\(selection.value.selectedCount))") {
                    showingConfirmation = true
                }
                .disabled(selection.value.selectedCount == 0)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .confirmationDialog(
            "Delete \(selection.value.selectedCount) selected item(s), freeing about \(ByteFormat.human(selection.value.selectedEstimatedBytes))?",
            isPresented: $showingConfirmation, titleVisibility: .visible
        ) {
            Button("Clean Now", role: .destructive) { onConfirm() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingSavePreset) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save Preset").font(.headline)
                TextField("Preset name", text: $presetName)
                HStack {
                    Spacer()
                    Button("Cancel") { showingSavePreset = false }
                    Button("Save") {
                        onSavePreset(CustomPreset(name: presetName,
                            itemIDs: selection.value.selectedIDs))
                        presetName = ""
                        showingSavePreset = false
                    }
                    .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 320)
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(get: { selection.value.selectedIDs.contains(id) },
                set: { selection.setSelected($0, id: id) })
    }
}
```

- [ ] In `CustomView`, remove its moved confirmation/save-sheet state, selection body, private row and selection-binding helpers. Replace its selecting branch with exactly this production binding; retain all other phase handling, initialization, sizing, title and load task:

```swift
case .selecting:
    if let selection = model.selection {
        CustomPlanView(selection: selection,
                       presets: configStore.config.presets,
                       onSavePreset: { preset in
            configStore.config.presets.removeAll { $0.name == preset.name }
            configStore.config.presets.append(preset)
        }, onConfirm: {
            Task { await model.executeSelected() }
        })
    }
```

The phase must acquire its selection before entering `.selecting`, as required by T01.B. Review that invariant in the actual view-model diff. No changes to AppConfigStore's existing persistence behavior are needed. The fixture never compiles or instantiates this wrapper. Keep standard `CleanView` using the real `CleanPlanView` and its owned selection as specified in T01.B.

## Task 2: Add the fixture-only host and isolated target

- [ ] Create `TidyUITestHost/TestHostApp.swift` with this complete source. Catalog construction reads metadata only: it never calls `locate`, `discover`, `declaredRoot`, environment construction, tool detection or engine planning. All statuses are explicit descriptive fixture states, not discovery results. All are denied/nonselectable; no `.available` fixture exists. Catalog metadata construction itself must remain effect-free; review that invariant before launch.

```swift
import SwiftUI
import TidyCore

@main
@MainActor
struct TestHostApp: App {
    var body: some Scene {
        WindowGroup("Tidy: Manual Review Fixtures") {
            FixtureChooser()
        }
        .defaultSize(width: 680, height: 760)
    }
}

private enum FixtureSurface: String, CaseIterable, Identifiable {
    case safe = "Safe", normal = "Normal", deep = "Deep", custom = "Custom"
    var id: String { rawValue }
    var tier: Tier {
        switch self {
        case .safe: return .safe
        case .normal: return .normal
        case .deep, .custom: return .deep
        }
    }
}

private enum ReviewFixtures {
    static let marker = "TIDY_MANUAL_FIXTURE_HOST_ONLY"
    static let presets = [CustomPreset(name: "Fixture: unavailable + unknown IDs",
        itemIDs: ["safe.tool.npm-cache-clean", "deep.memory.purge-inactive",
                  "deep.simulator.erase-all", "unknown.preset.id"])]

    static func plan(for surface: FixtureSurface) -> CleanPlan {
        var rows = CleanCatalog.allItems.filter { $0.tier <= surface.tier }.map { item in
            let status: ReviewStatus
            let reason: String
            if case .unavailable(let tombstoneReason) = item.action {
                status = .unavailable
                reason = tombstoneReason
            } else {
                switch item.id {
                case "safe.cache.swiftpm-cache":
                    status = .noWork
                    reason = "No matching path exists."
                case "safe.cache.swiftpm-clones":
                    status = .blocked
                    reason = "One or more targets failed path protection checks."
                case "safe.cache.pip-cache":
                    status = .unavailable
                    reason = "Required toolchain is not available."
                default:
                    status = .unavailable
                    reason = CapabilityRegistry.quarantineReason
                }
            }
            return PlannedItem(id: item.id, title: item.title, tier: item.tier,
                dangerNote: item.dangerNote, costNote: item.costNote,
                targets: [], estimatedBytes: 0, action: item.action,
                review: ActionDescriptor(id: item.id, status: status, reason: reason,
                    requiresPerRunOptIn: item.action.requiresPerRunOptIn))
        }
        // A denied presentation-only row exercises Custom's Other section.
        // It is not registered in the production catalog or capability registry.
        if surface == .custom {
            let reason = "Fixture-only uncategorized row; no operation exists."
            rows.append(PlannedItem(id: "fixture.presentation.other",
                title: "Fixture: uncategorized unavailable row", tier: .deep,
                dangerNote: "Fixture warning: no change will run.",
                costNote: "Fixture cost note: no savings have been measured.",
                targets: [], estimatedBytes: 0, action: .unavailable(reason: reason),
                review: ActionDescriptor(id: "fixture.presentation.other",
                    status: .unavailable, reason: reason, requiresPerRunOptIn: false)))
        }
        return CleanPlan(tier: surface.tier, plannedItems: rows,
                         generatedAt: Date(timeIntervalSince1970: 0))
    }
}

@MainActor
private struct FixtureChooser: View {
    @State private var surface: FixtureSurface = .safe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual fixtures: no discovery, settings or cleanup")
                .font(.headline)
            Text("Descriptive data, not findings about this Mac. All actions are unavailable, blocked or no-work.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Review surface", selection: $surface) {
                ForEach(FixtureSurface.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.segmented)
            FixtureReviewSurface(surface: surface).id(surface)
            Text(ReviewFixtures.marker).font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 620, minHeight: 620)
    }
}

@MainActor
private struct FixtureReviewSurface: View {
    let surface: FixtureSurface
    @State private var selection: PlanSelectionModel

    init(surface: FixtureSurface) {
        self.surface = surface
        _selection = State(initialValue: PlanSelectionModel(
            plan: ReviewFixtures.plan(for: surface), selectDefaults: surface != .custom))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(surface.rawValue): \(selection.value.reviewItems.count) fixture rows · \(selection.value.selectedCount) selected · \(ByteFormat.human(selection.value.selectedEstimatedBytes)) selected")
                .font(.caption).monospacedDigit()
            if surface == .custom {
                DisclosureGroup("Fixture input preset IDs (immutable)") {
                    Text(ReviewFixtures.presets[0].itemIDs.sorted().joined(separator: "\n"))
                        .font(.caption).textSelection(.enabled)
                }
                CustomPlanView(selection: selection, presets: ReviewFixtures.presets,
                               onSavePreset: { _ in }, onConfirm: {})
            } else {
                CleanPlanView(selection: selection, onConfirm: {})
            }
        }
    }
}
```

Switching surfaces intentionally recreates selection from fixture data. This does not model production window lifetime. The source ignores all process arguments and never loads a file: missing or malformed launch arguments cannot fall back to a production path. Empty callbacks are intentional; callback invocation itself is not recorded or proven by this host.

- [ ] Append this exact target under the existing `targets:` mapping in `project.yml`, preserving the production target and all its settings. Append the top-level `schemes:` mapping below. Never use a recursive `Tidy` source entry for the host. The existing production `sources: - path: Tidy` excludes sibling `TidyUITestHost` by construction.

```yaml
  TidyUITestHost:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: TidyUITestHost/TestHostApp.swift
      - path: Tidy/Clean/CleanPlanView.swift
      - path: Tidy/Clean/PlanReviewRow.swift
      - path: Tidy/Clean/PlanSelectionModel.swift
      - path: Tidy/Custom/CustomPlanView.swift
    dependencies:
      - package: TidyCore
    settings:
      base:
        PRODUCT_NAME: TidyUITestHost
        PRODUCT_BUNDLE_IDENTIFIER: io.github.ajraba04.Tidy.ManualReviewFixtures
        SWIFT_VERSION: "5.0"
        GENERATE_INFOPLIST_FILE: YES
        MACOSX_DEPLOYMENT_TARGET: "14.0"

schemes:
  TidyUITestHost:
    build:
      targets:
        TidyUITestHost: all
    run:
      config: Debug
```

- [ ] After controller scheduling approval, run `xcodegen generate` from the worktree root. Inspect the generated diff before building. Host has exactly five app-source entries, no resources, no app dependencies and only local TidyCore. Production has no host source/resource membership or host target dependency. Its source list contains the new shared `CustomPlanView.swift`; its signing settings are unchanged. The generated host scheme builds only the host and its package dependency.
- [ ] Build the host after T01.B's shared APIs exist. Build production separately to verify the actual wrapper uses the shared Custom view. These commands do not launch either application:

```sh
xcodebuild -project Tidy.xcodeproj -scheme TidyUITestHost -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build CODE_SIGNING_ALLOWED=NO
```

Expected: both commands exit 0 with `BUILD SUCCEEDED`. Record actual architecture. Do not call this both-architecture evidence; separately scheduled builds/device runs are still required by the global plan. Do not alter signing or launch production to resolve a host launch failure.

- [ ] Inspect production target membership again in the regenerated project and inspect the built production bundle for fixture resources/entry types. Run these non-mutating checks (no match is the expected `rg` exit 1):

```sh
rg -n 'TestHostApp|TidyUITestHost|CustomPlanView|PlanSelectionModel' Tidy.xcodeproj/project.pbxproj
rg --files /private/tmp/tidy-headroom-build/Build/Products/Debug/Tidy.app
strings /private/tmp/tidy-headroom-build/Build/Products/Debug/Tidy.app/Contents/MacOS/Tidy | rg 'TIDY_MANUAL_FIXTURE_HOST_ONLY|FixtureReviewSurface|ReviewFixtures|TestHostApp'
```

The first command is a membership-audit starting point, not an automatic pass: resolve each matching build-file identifier through the respective PBXSourcesBuildPhase/target. Host references are expected in the project, but forbidden in production Sources/Resources/dependencies. The file list must contain no host source/resources/bundled host app; the strings command must return no fixture markers. Source inspection must also confirm there is no fixture dispatch flag in production. Bundle strings alone are not proof of source exclusion.

## Task 3: Manual screen and interaction acceptance

- [ ] Before launch, independent review verifies the actual host and transitive shared-view code have no application I/O, `.task` discovery, settings accesses, production-model callbacks or command execution; verify catalog metadata factories only construct data/closures. Linked TidyCore contains production capabilities but no host path invokes them. Verify every fixture status is nonselectable and production registry remains unchanged.
- [ ] Use the approved native app UI control/inspection workflow to launch only `/private/tmp/tidy-headroom-build/Build/Products/Debug/TidyUITestHost.app`. Ask for any required OS/tool approval. If launch is blocked, retain the gate as pending; do not launch normal Tidy or modify signing/security to bypass it.
- [ ] For each Safe, Normal and Deep surface, record a screenshot and observe the real `CleanPlanView`: all tier-inclusive catalog rows can be reached by scrolling; zero-byte/targetless rows are not hidden; row titles/reasons and available danger/cost notes are readable. The header's expected fixture row count is supporting data, not proof that the list rendered every row. Review the full scroll sequence and compare visible row IDs/titles to that tier's catalog list.
- [ ] Safe includes `safe.tool.npm-cache-clean` as targetless/unavailable; `safe.cache.swiftpm-cache` as no-work; `safe.cache.swiftpm-clones` as blocked; `safe.cache.pip-cache` as missing-tool/unavailable. Check each exact explanation. These are render cases, not assertions about host tools or paths.
- [ ] Deep and Custom show `deep.memory.purge-inactive` with zero bytes and both catalog warnings, and retain the disabled `deep.simulator.erase-all` tombstone with its actual reason. Read the restart cost copy; do not open settings or request restart.
- [ ] In Custom, verify real category grouping and the explicit Other row. Verify its danger and cost notes both render. Expand the immutable preset input disclosure; record all four IDs. Click the fixture preset button repeatedly and verify selection/footer stay 0/zero bytes, unknown ID does not become a selected row, and the original unknown/quarantined IDs remain visible in the disclosure. This proves in-memory input preservation only, not persisted configuration behavior.
- [ ] On all surfaces, attempt mouse and keyboard activation of representative disabled toggles and the primary cleanup button; selection remains zero and no confirmation dialog opens. Custom's save-preset button remains disabled. Verify keyboard navigation/accessible labels on reachable controls using the available native inspection workflow. Do not claim a full accessibility audit from this check.
- [ ] Switch between all four surfaces and repeat zero-count checks; narrow the window to its declared minimum and verify explanations/footer remain usable without content overlap. Record actual macOS version, machine architecture, host build path, screenshot paths and observed outcomes. No positive execution, callback recording or savings claim follows from zero selected counts.
- [ ] Close the fixture host after evidence capture. Keep any unmet check explicitly pending, including unavailable UI tooling or blocked launch. No commit is authorized by this supplement.

## Acceptance boundary and dependency accounting

This supplement provides actual manual render/interaction evidence for production-shared review content only. It does not prove discovery classification (covered separately by production-bound core tests), production container initialization/navigation, actual settings persistence/migration, production lifecycle/concurrency, positive selection/deselection or executor invocation, accepted targetless capability execution, sealed coordinator authority, interruption/recovery, full UI automation, or dual-architecture device behavior.

T01.B's existing standard/custom wrapper diff must still be reviewed and production-built. T01 overall remains open for accepted production capabilities and T02/T04 integration. T05 retains its schema migration, recording/coordinator UI tests, window/policy-update behavior and complete host safety suite. This is an independent early rendering slice, not completion of T05.

If this supplement is declined, explicitly move only the manual gate to a named T05 prerequisite and mark T01.B integration verification incomplete until that inspection happens. Such a dependency adjustment is honest but not technically necessary; neither a passing build nor source review may silently replace manual evidence.
