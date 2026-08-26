# T02 — Unhosted app confirmation lifecycle test entry

> **For agentic workers:** Use executing-plans only after independent review. This is a documentation-only proposed API/test entry, not source implementation or passing evidence. It supplements T02-sealed-execution.md; it does not authorize accepted capabilities or source commits.

**Goal:** Capture actual app-model RED before wiring dialogs: immutable synchronous confirmation capture, explicit cancellation, lifetime-wide stale-response rejection, ordered coordinator requests, and observable shared policy invalidation.

**Architecture:** Compile the real app models into an unhosted macOS XCTest bundle, with real TidyCore coordinator/bridge and explicit scratch services. Small app-local presentation and scheduling helpers live in the existing PlanSelectionModel.swift and are used by the real model/VMs. They carry untrusted presentation data and scheduling identity only, never tokens or eligibility authority.

**Tech stack:** macOS14+, Swift5/SwiftUI/Observation, XCTest, local TidyCore only. No runtime third-party dependencies, network, production launch, ambient executable, daemon, scans or default home/settings/journal paths.

All design S01–S16 and T02's safety constraints remain binding. This entry is a narrow prerequisite for T02 shared-view wiring while its core implementation proceeds. Do not edit or launch the existing manual host: it remains exactly five-source, all rows denied/no-work/blocked, callbacks no-op, nil binding, execution disabled, original public initializers retained.

## Files and exact build isolation

Modify only after review: `Tidy/Clean/PlanSelectionModel.swift`, `CleanViewModel.swift`, `Tidy/Custom/CustomViewModel.swift`, `Tidy/Settings/AppConfigStore.swift`, T02's new `Tidy/Execution/AppExecutionServices.swift`, core `Execution/ExecutionPolicyBridge.swift`; then the actual dialog owners `CleanPlanView.swift`/`CustomPlanView.swift`, their parent views and TidyApp wiring already covered by T02. Create `TidyAppModelTests/ConfirmationLifecycleTests.swift`; add this target/scheme to project.yml and regenerate the project with XcodeGen. No fixture resource phase.

Exact new target and scheme entries (merge under existing keys, never replace existing Tidy/manual host entries):

```yaml
targets:
  TidyAppModelTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: TidyAppModelTests/ConfirmationLifecycleTests.swift
      - path: Tidy/Clean/PlanSelectionModel.swift
      - path: Tidy/Clean/CleanViewModel.swift
      - path: Tidy/Custom/CustomViewModel.swift
      - path: Tidy/Execution/AppExecutionServices.swift
      - path: Tidy/Settings/AppConfigStore.swift
    dependencies:
      - package: TidyCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.github.ajraba04.Tidy.AppModelTests
        SWIFT_VERSION: "5.0"
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: ""
        BUNDLE_LOADER: ""
schemes:
  TidyAppModelTests:
    build:
      targets:
        TidyAppModelTests: all
    test:
      targets:
        - TidyAppModelTests
```

These test sources share a module with the compiled app sources; no fake host module or `@testable import Tidy` is needed. TidyCore remains a local package. Exclude TidyApp.swift, all SwiftUI scene/view files, Scan/Onboarding, app resources, manual host and safety host. If the landed model imports another app helper, inspect and explicitly add only its pure dependency file, then re-review this allowlist; never replace it with `path: Tidy`. Verify no TEST_HOST expansion, app target dependency, app launch, default initializer or static startup work before running. A bare test target compile failure due to missing source is not lifecycle RED; record it separately.

Reuse this **unhosted** target for later T05 A.3 app-model tests after its APIs land; do not make T02 depend on T05's not-yet-built hosted UI target. T05 B.1 remains a separate app/UI runner and does not change this target to hosted execution.

## Exact proposed model interfaces

All types below are app-internal; only T02's production coordinator can confirm/execute. Existing fixture-facing `PlanSelectionModel.init(plan:selectDefaults:)`, CleanPlanView and CustomPlanView initializer/no-op callback signatures remain unchanged.

```swift
struct FrozenReviewPresentation: Equatable, Sendable {
    let binding: ReviewBinding
    let selectedCount: Int
    let estimatedBytes: Int64
}

@Observable @MainActor
final class ConfirmationPresentationState {
    init() // empty presentation, showingConfirmation=false
    private(set) var presentation: FrozenReviewPresentation?
    var showingConfirmation: Bool
    func present(_ value: FrozenReviewPresentation)
    func take() -> FrozenReviewPresentation?
    func cancel()
    func presentationDidDismiss() -> UUID
    func settleDismissal(_ identity: UUID)
}

struct ReviewRequestID: Equatable, Sendable { fileprivate let value: UUID }
@MainActor final class ReviewRequestLifetime {
    init() // open lifetime, fresh generation, empty tail
    func enqueue(_ operation: @escaping @MainActor (ReviewRequestID) async -> Void) -> Task<Void, Never>
    func isCurrent(_ request: ReviewRequestID) -> Bool
    func invalidate()
    func teardown(_ cleanup: @escaping @MainActor () async -> Void) -> Task<Void, Never>
    func drain() async
}

// Add to the real PlanSelectionModel, retaining value/setSelected/applyPresetIDs:
PlanSelectionModel.init(review: RegisteredReview,
    onSelectionRequested: @escaping @MainActor (Set<String>) -> Void)
PlanSelectionModel.frozenPresentation: FrozenReviewPresentation? // read-only
PlanSelectionModel.updatePending: Bool // model-controlled
PlanSelectionModel.showingConfirmation: Bool // presentation adapter only
PlanSelectionModel.canConfirm: Bool // current binding && enabled && !pending && count>0
PlanSelectionModel.beginConfirmation()
PlanSelectionModel.takeConfirmation() -> FrozenReviewPresentation?
PlanSelectionModel.cancelConfirmation()
PlanSelectionModel.replace(review: RegisteredReview)
PlanSelectionModel.invalidate(policyEnabled: Bool)

// Both real VMs, with Clean also taking tier:
CleanViewModel.init(tier: Tier, services: AppExecutionServices)
CustomViewModel.init(services: AppExecutionServices)
// Both expose the following identically:
ViewModel.requestLoad() -> Task<Void, Never> // synchronous enqueue before return
ViewModel.confirm() // synchronous take BEFORE Task creation, never async
ViewModel.policyDidChange() // synchronous model/lifetime invalidation; no scan
ViewModel.teardown() -> Task<Void, Never> // ordered discard; no cancellation of other windows
ViewModel.selection: PlanSelectionModel? // private(set)

// Exact scratch-friendly constructor; production also calls it with resolved values.
AppExecutionServices.init(config: TidyConfig, configURL: URL?,
    homeDirectory: String, journalDirectory: URL)
AppExecutionServices.coordinator: ExecutionCoordinator
AppExecutionServices.policyBridge: ExecutionPolicyBridge
AppExecutionServices.configStore: AppConfigStore
ExecutionPolicyBridge.updateGeneration: UUID // public private(set), Observable
```

`ViewModel` above denotes the identical methods on **both** named classes, not a new invented base class. An optional old `loadPlan() async` wrapper may await `requestLoad().value`; the new synchronous method supplies deterministic queued-work lifecycle tests. Services has no default arguments, config load, discovery or RunLog default path in this constructor. It constructs one coordinator + one bridge + one AppConfigStore from supplied config/home and tools literal[]; no side-effecting property initializer. Production-only default path resolution stays in TidyApp, outside the unhosted test module. If report writing is retained by VMs, service owns an explicit scratch-derived run-log URL and passes it; neither VM may call RunLog.append with its ambient default URL. Tests never reach successful mutation/report effects.

### Presentation state contract

`present` copies binding/count/bytes and opens presentation; `take` synchronously removes it and hides presentation, returning it exactly once. It does not mint a ConfirmedPlan. PlanSelectionModel can call present only after checking its real current eligible nonempty production selection. Helpers accept untrusted presentation values for pure lifecycle tests; tests never install them into coordinator/registry or enable actual execution. `takeConfirmation` also disables repeated model confirmation immediately; the VM freezes its returned value into a local **before** creating a Task. Inside the Task, call real coordinator.confirm(binding:) and execute; never reread mutable selection to reconstruct binding/count/bytes.

Do not clear authorization merely because SwiftUI automatically sets showingConfirmation=false during a button action. `presentationDidDismiss` changes visual state only and returns a fresh dismissal identity tied to the current presentation; `settleDismissal(identity)` clears only that same still-unconsumed presentation. Explicit Cancel clears synchronously. The real dialog adapter defers settle to the next MainActor turn so the button's synchronous confirm can consume first. New present/cancel/take invalidates any old dismissal identity. This also prevents an outside-click/Escape dismissal from leaving a reusable frozen selection. The exact ordering of SwiftUI's native dismissal/action callbacks remains a real-dialog UI gate; deterministic helper tests establish the intended mechanism, not undocumented OS behavior.

Selection/preset changes, config policy changes, review replacement, cancellation and teardown call cancel synchronously. Confirmation submission invalidates the review request lifetime so late async results cannot repopulate selection/dialog. A rejected attempt cannot leave an enabled stale dialog. Keep count/estimatedBytes frozen alongside binding rather than rendering current mutable selection values in the dialog.

Denied/unknown selection or preset requests that leave the eligible ID set unchanged invalidate presentation but do not call `onSelectionRequested`; the callback count for the all-denied fixture is exactly zero. This is a no-change contract, not evidence that a nonempty selection request was dispatched. Actual accepted selection dispatch remains adapter-gated.

### Ordered request and lifetime contract

`enqueue` synchronously changes the generation UUID and captures the prior tail Task. Its new task awaits the prior task, checks isCurrent, then invokes operation. A stale request not started is skipped (coalescing), but an already-started coordinator operation drains; later requests cannot overtake it. The operation must check `isCurrent(request)` again **after every await before installing UI**, including error paths. A queued task is never canceled to pretend the coordinator request was canceled. `invalidate` changes generation immediately. `teardown` permanently closes that VM lifetime, changes generation, awaits all prior operations and invokes cleanup once; future enqueue skips. A new window gets a new model, never reopens a closed lifetime.

Use this same queue for new prepareReview loads, coordinator setSelection, discard/replacement and teardown. A late prepareReview that registered a plan must discard that exact returned plan before completion when no longer current. Keep old plan discard ordered after its pending selection, before new preparation. Generation guards alone are insufficient: an out-of-order older setSelection must never become coordinator's final registered state. No automatic new review/discovery on policyDidChange; require explicit refresh. Only current plan + current policy + current request may be installed.

Bridge sets observable updateGeneration to a new UUID synchronously on **every** submit, including identical config, before any Task. Actual shared views observe that property (`onChange`), then call VM.policyDidChange and read the bridge's enabled/pending/error state. `policyAdmission()` is a locked getter, not Observable. A rapid pending→ready cycle still changes updateGeneration; it cannot leave an old dialog alive. VM entry + coordinator checks remain authoritative if a view notification is delayed.

## Complete unhosted RED test source

Create the entire following file before changing app model source. These tests intentionally use empty/default-denied real reviews and pure untrusted display data. No trusted test IDs, eligible catalog rows or coordinator replacement is provided.

```swift
import Foundation
import Darwin
import Observation
import XCTest
import TidyCore

private func canonicalScratchBase() throws -> URL {
    var path = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath("/private/tmp", &path) != nil else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return URL(fileURLWithPath: String(cString: path), isDirectory: true)
}

private final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func mark() { lock.lock(); value = true; lock.unlock() }
    func read() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}

private actor AsyncLatch {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private struct AppModelScratch {
    let root: URL
    var home: URL { root.appendingPathComponent("home", isDirectory: true) }
    var configURL: URL { root.appendingPathComponent("config.json") }
    var journal: URL { root.appendingPathComponent("journal", isDirectory: true) }
    init() throws {
        root = try canonicalScratchBase()
            .appendingPathComponent("T02-AppModels-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
    }
    @MainActor func services() -> AppExecutionServices {
        AppExecutionServices(config: TidyConfig(), configURL: configURL,
                             homeDirectory: home.path, journalDirectory: journal)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
final class ConfirmationLifecycleTests: XCTestCase {
    private func display(_ count: Int = 2, bytes: Int64 = 123) -> FrozenReviewPresentation {
        // Untrusted UI data only. This unknown plan cannot mint a token.
        FrozenReviewPresentation(binding: ReviewBinding(planID: UUID(), planRevision: 7,
            policyRevision: 3, selectedIDs: ["untrusted.display.a", "untrusted.display.c"]),
            selectedCount: count, estimatedBytes: bytes)
    }

    func testAutomaticDismissalCannotEraseActionBeforeSynchronousTake() {
        let state = ConfirmationPresentationState()
        let frozen = display(); state.present(frozen)
        let dismissal = state.presentationDidDismiss()
        XCTAssertFalse(state.showingConfirmation)
        let captured = state.take() // same synchronous event; no Task or await
        XCTAssertEqual(captured, frozen)
        XCTAssertNil(state.take()) // duplicate submission already blocked
        state.settleDismissal(dismissal)
        XCTAssertNil(state.presentation)
        XCTAssertEqual(captured?.selectedCount, 2)
        XCTAssertEqual(captured?.estimatedBytes, 123)
    }

    func testCancelAndSettledOutsideDismissalCannotReusePresentation() {
        let state = ConfirmationPresentationState()
        state.present(display()); state.cancel()
        XCTAssertNil(state.take())
        state.present(display())
        let dismissal = state.presentationDidDismiss()
        state.settleDismissal(dismissal)
        XCTAssertNil(state.take())
        XCTAssertFalse(state.showingConfirmation)
    }

    func testOldDeferredDismissalDoesNotClearNewPresentation() {
        let state = ConfirmationPresentationState()
        state.present(display())
        let oldDismissal = state.presentationDidDismiss()
        let fresh = display(3, bytes: 456)
        state.present(fresh)
        state.settleDismissal(oldDismissal)
        XCTAssertEqual(state.take(), fresh)
    }

    func testFixtureModelNeverConfirmsOrRequestsExecution() {
        let plan = CleanPlan(tier: .safe, plannedItems: [], generatedAt: Date(timeIntervalSince1970: 0))
        let model = PlanSelectionModel(plan: plan, selectDefaults: false)
        XCTAssertFalse(model.canConfirm)
        model.beginConfirmation()
        XCTAssertNil(model.frozenPresentation)
        XCTAssertNil(model.takeConfirmation())
        model.applyPresetIDs(["unknown.preset.id"])
        model.setSelected(true, id: "unknown.preset.id")
        XCTAssertEqual(model.value.selectedCount, 0)
        XCTAssertFalse(model.canConfirm)
    }

    func testStartedSelectionDrainsBeforeNewerSelectionAndLateUIIsRejected() async {
        let lifetime = ReviewRequestLifetime()
        let started = AsyncLatch(), release = AsyncLatch()
        var dispatches: [Int] = [], installed: [Int] = []
        let first = lifetime.enqueue { request in
            dispatches.append(1)
            await started.open(); await release.wait()
            if lifetime.isCurrent(request) { installed.append(1) }
        }
        await started.wait()
        let second = lifetime.enqueue { request in
            dispatches.append(2)
            if lifetime.isCurrent(request) { installed.append(2) }
        }
        XCTAssertEqual(dispatches, [1])
        await release.open(); await first.value; await second.value
        XCTAssertEqual(dispatches, [1, 2])
        XCTAssertEqual(installed, [2])
    }

    func testUnstartedRequestsCoalesceAndReplacementRunsLast() async {
        let lifetime = ReviewRequestLifetime()
        let started = AsyncLatch(), release = AsyncLatch()
        var order: [String] = []
        let active = lifetime.enqueue { _ in
            order.append("old-selection")
            await started.open(); await release.wait()
        }
        await started.wait()
        let skipped = lifetime.enqueue { _ in order.append("obsolete-selection") }
        let replacement = lifetime.enqueue { request in
            order.append("discard-old-and-load-new")
            XCTAssertTrue(lifetime.isCurrent(request))
        }
        await release.open(); await active.value; await skipped.value; await replacement.value
        XCTAssertEqual(order, ["old-selection", "discard-old-and-load-new"])
    }

    func testPolicyAndConfirmationLifetimeInvalidationRejectLateResults() async {
        for reason in ["policy", "confirmation", "review replacement"] {
            let lifetime = ReviewRequestLifetime()
            let started = AsyncLatch(), release = AsyncLatch()
            var installed = false
            let load = lifetime.enqueue { request in
                await started.open(); await release.wait()
                if lifetime.isCurrent(request) { installed = true }
            }
            await started.wait(); lifetime.invalidate()
            await release.open(); await load.value
            XCTAssertFalse(installed, reason)
        }
    }

    func testTeardownWaitsForActiveOperationDiscardsOnceAndCannotReopen() async {
        let lifetime = ReviewRequestLifetime()
        let started = AsyncLatch(), release = AsyncLatch()
        var order: [String] = []
        let load = lifetime.enqueue { request in
            await started.open(); await release.wait()
            order.append("load-drained")
            XCTAssertFalse(lifetime.isCurrent(request))
        }
        await started.wait()
        let close = lifetime.teardown { order.append("discard") }
        let ignored = lifetime.enqueue { _ in order.append("reopened") }
        await release.open(); await load.value; await close.value; await ignored.value
        let secondClose = lifetime.teardown { order.append("duplicate-discard") }
        await secondClose.value
        XCTAssertEqual(order, ["load-drained", "discard"])
    }

    func testRealRegisteredDeniedModelAndUnknownPresetStayNonEntitling() async throws {
        let scratch = try AppModelScratch(); defer { scratch.remove() }
        let services = scratch.services()
        let review = try await services.coordinator.prepareReview(
            engine: CleanEngine(sizeScanner: SizeScanner()), tier: .deep, selectDefaults: false)
        var requested: [Set<String>] = []
        let model = PlanSelectionModel(review: review) { requested.append($0) }
        model.invalidate(policyEnabled: true)
        model.replace(review: review)
        model.applyPresetIDs(["unknown.preset.id", "deep.simulator.erase-all"])
        model.beginConfirmation()
        XCTAssertNil(model.frozenPresentation)
        XCTAssertNil(model.takeConfirmation())
        XCTAssertFalse(model.canConfirm)
        XCTAssertEqual(model.value.selectedCount, 0)
        XCTAssertEqual(requested.count, 0) // denied/unchanged requests do not dispatch
        model.cancelConfirmation()
        XCTAssertNil(model.frozenPresentation)
        XCTAssertFalse(model.showingConfirmation)
        model.replace(review: review)
        XCTAssertEqual(model.value.reviewItems.count, review.plan.reviewItems.count)
        XCTAssertFalse(model.canConfirm) // actual registered review is still empty
        model.invalidate(policyEnabled: false)
        XCTAssertFalse(model.canConfirm)
        XCTAssertNil(model.takeConfirmation())
        let forbidden = ReviewBinding(planID: UUID(), planRevision: 1,
            policyRevision: 1, selectedIDs: ["untrusted.display.a"])
        do {
            _ = try await services.coordinator.confirm(binding: forbidden)
            XCTFail("Untrusted display data minted authority")
        } catch let error as ConfirmationError { XCTAssertEqual(error, .unknownPlan) }
    }

    func testObservableGenerationChangesForIdenticalEditsAndRealBarrierInvalidates() async throws {
        let scratch = try AppModelScratch(); defer { scratch.remove() }
        let services = scratch.services(), bridge = services.policyBridge
        let before = bridge.updateGeneration
        let observed = ObservationFlag()
        withObservationTracking { _ = bridge.updateGeneration } onChange: { observed.mark() }
        let first = bridge.submit(config: services.configStore.config)
        let firstID = bridge.updateGeneration
        XCTAssertNotEqual(before, firstID)
        XCTAssertTrue(observed.read())
        XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 2))
        let second = bridge.submit(config: services.configStore.config)
        XCTAssertNotEqual(firstID, bridge.updateGeneration)
        XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 3))
        await first.value; await second.value
        XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 3))
    }

    func testRealBothVMLifetimesDoNotInstallQueuedLoadAfterPolicyChangeOrClose() async throws {
        let scratch = try AppModelScratch(); defer { scratch.remove() }
        let services = scratch.services()
        let clean = CleanViewModel(tier: .safe, services: services)
        let custom = CustomViewModel(services: services)
        let cleanLoad = clean.requestLoad()
        let customLoad = custom.requestLoad()
        // No await: neither queued MainActor load can have started.
        clean.policyDidChange(); custom.policyDidChange()
        await cleanLoad.value; await customLoad.value
        XCTAssertNil(clean.selection)
        XCTAssertNil(custom.selection)
        let cleanReload = clean.requestLoad(), customReload = custom.requestLoad()
        let cleanClose = clean.teardown(), customClose = custom.teardown()
        await cleanReload.value; await customReload.value
        await cleanClose.value; await customClose.value
        XCTAssertNil(clean.selection)
        XCTAssertNil(custom.selection)
        clean.confirm(); custom.confirm() // synchronous denied entries, no effects
        XCTAssertNil(clean.selection)
        XCTAssertNil(custom.selection)
    }

    func testBothRealVMsInstallRegisteredDeniedReviewsThenInvalidateAndClose() async throws {
        let scratch = try AppModelScratch(); defer { scratch.remove() }
        let services = scratch.services()
        let clean = CleanViewModel(tier: .safe, services: services)
        let custom = CustomViewModel(services: services)
        await clean.requestLoad().value
        await custom.requestLoad().value
        let cleanSelection = try XCTUnwrap(clean.selection)
        let customSelection = try XCTUnwrap(custom.selection)
        XCTAssertFalse(cleanSelection.value.reviewItems.isEmpty)
        XCTAssertFalse(customSelection.value.reviewItems.isEmpty)
        XCTAssertTrue(customSelection.value.reviewItems.contains { $0.id == "deep.simulator.erase-all" })
        XCTAssertFalse(cleanSelection.canConfirm)
        XCTAssertFalse(customSelection.canConfirm)
        cleanSelection.beginConfirmation(); customSelection.beginConfirmation()
        XCTAssertNil(cleanSelection.frozenPresentation)
        XCTAssertNil(customSelection.frozenPresentation)
        clean.policyDidChange(); custom.policyDidChange()
        XCTAssertFalse(cleanSelection.canConfirm)
        XCTAssertFalse(customSelection.canConfirm)
        XCTAssertNil(cleanSelection.frozenPresentation)
        XCTAssertNil(customSelection.frozenPresentation)
        // An explicit reload may install a fresh denied review while policy is ready.
        await clean.requestLoad().value; await custom.requestLoad().value
        XCTAssertNotNil(clean.selection); XCTAssertNotNil(custom.selection)
        await clean.teardown().value; await custom.teardown().value
        XCTAssertNil(clean.selection); XCTAssertNil(custom.selection)
        await clean.requestLoad().value; await custom.requestLoad().value
        XCTAssertNil(clean.selection); XCTAssertNil(custom.selection)
    }

    func testActualConfigStoreSettersInvalidateSynchronouslyAndPersistInOrder() async throws {
        let scratch = try AppModelScratch(); defer { scratch.remove() }
        let services = scratch.services(), bridge = services.policyBridge
        let firstWindow = services.configStore, secondWindow = services.configStore
        XCTAssertTrue(firstWindow === secondWindow)
        let initial = bridge.updateGeneration
        firstWindow.config.transcriptAgeThresholdDays = 60
        let firstID = bridge.updateGeneration
        XCTAssertNotEqual(initial, firstID)
        XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 2))
        XCTAssertFalse(bridge.isExecutionEnabled)
        secondWindow.config.transcriptAgeThresholdDays = 90
        XCTAssertNotEqual(firstID, bridge.updateGeneration)
        XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 3))
        XCTAssertEqual(firstWindow.config.transcriptAgeThresholdDays, 90)
        // A third actual submit joins the private ordered chain; all saves finish
        // before scratch deletion. This intentionally advances policy to revision4.
        let joined = bridge.submit(config: services.configStore.config)
        XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 4))
        await joined.value
        XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 4))
        XCTAssertTrue(bridge.isExecutionEnabled)
        XCTAssertEqual(ConfigStore.load(from: scratch.configURL).transcriptAgeThresholdDays, 90)
    }
}
```

The Observation test uses a lock-protected Sendable flag rather than weakening production isolation. Darwin realpath canonicalizes the known scratch base before appending the UUID directory; Foundation URL symlink normalization is not sufficient evidence for T02's no-follow journal walk. No test may inject a settings-save-success closure, trusted review constructor or accepted registry entry.

## Implementation sequence and source acceptance

- [ ] Review proposed signatures/source membership against actual landed T02 core. Resolve conflicts with controller before edits. Add complete test file/project target; build-for-testing compile RED should name missing app helper/API, not missing host/app launch.
- [ ] Implement the two helpers in PlanSelectionModel.swift and use them in the actual PlanSelectionModel/VMs, not an unused test replica. Run focused tests, record behavioral RED/GREEN for dismissal-before-action, duplicate consume, late response and queue ordering.
- [ ] Implement explicit services constructor and actual AppConfigStore setter bridge routing; observe updateGeneration in both shared dialog-owning view hierarchies. Changes are to the existing bridge, not an alternate policy authority.
- [ ] Review each real VM callsite: synchronous take before Task; install/error guards after every await; coordinator setSelection/prepare/discard all serialized; no direct raw execute/default RunLog path. Bind policy callbacks to the Observable bridge generation, not only a locked getter or pending Bool.
- [ ] Wire actual CleanPlanView/CustomPlanView dialog: frozen text, onConfirm synchronous VM method, Cancel synchronous invalidation, automatic dismissal deferred settlement, lifecycle teardown. Preserve manual host constructors/default nil-binding execution-disabled state and no-op callbacks; no settings/services dependencies added to the manual host target.
- [ ] Add exact real-model caller tests for every new setter/preset/replace/cancel branch introduced during implementation if helper tests do not execute that caller. Do not describe helper-only tests as full VM or native dialog coverage.
- [ ] Independent review of tests, target membership and actual call graph before host/device UI verification. No source commit authorized here.

## Safe commands (controller schedules; no production launch)

```sh
cd /private/tmp/tidy-headroom.wUbV9h
xcodegen generate --spec project.yml
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build-for-testing CODE_SIGNING_ALLOWED=NO
```

Inspect generated target is unhosted, its six-source allowlist and only local TidyCore dependency; inspect model/services initialization for default paths/discovery. Then:

```sh
cd /private/tmp/tidy-headroom.wUbV9h
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 test-without-building -only-testing:TidyAppModelTests/ConfirmationLifecycleTests -test-timeouts-enabled YES -default-test-execution-time-allowance 30 -maximum-test-execution-time-allowance 60 CODE_SIGNING_ALLOWED=NO
```

No normal Tidy or manual/safety host is launched. If local XCTest requires signing/permissions, report it instead of altering production entitlements. Core tests remain separately scheduled; these commands do not authorize cleanup, remote changes or a full suite with unaudited host-effect tests.

The shared DerivedData path is independently approved for disk/cache reuse only. Controller serializes every build/test using it. A successful current build-for-testing and inspection of the generated six-source unhosted target, empty TEST_HOST/BUNDLE_LOADER, dependencies and selected test bundle are required before test-without-building. Existing production/manual-host products in that directory are not dependencies or permission to launch them. Preserve existing artifacts/evidence; no broad clean is authorized.

The explicit XCTest runner timeout is mandatory for the latch/Task.value RED tests: malformed queue implementations may never resume a continuation. Do not replace it with a task-group race whose losing uncancellable continuation still hangs. Verify local xcodebuild accepts these timeout options before running; otherwise stop and establish an equivalent process-bounded unhosted runner. A timeout is a failed test, not canceled/passing evidence. On normal completion all active latches are released and tasks awaited; teardown drains its current chain exactly once. If the runner kills a hung test bundle, preserve the exact UUID scratch directory for inspection instead of performing broad cleanup.

## Deliberately unclosed gates

Default-denied production reviews cannot produce a positive `canConfirm`, selected action, accepted execution or genuine nonempty native confirmation dialog. The pure presentation helper can test immutable capture/dismissal using untrusted model data; it cannot substitute for a positive selection fixture. Accepted `.M` adapter + T03/T04 remain necessary to test real selected/deselected A/C versus B, native dialog lifecycle, cross-window active-run busy/drain/close, and actual effect recording. Keep the T05 stable-OS ordinary/keyboard/AX scrolling anomaly reproduction gate. Passing this bundle means “T02 app-model lifecycle foundation tested,” not “full T02/T05 UI safety verified” or “cleanup works.”
