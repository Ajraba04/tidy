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
    @MainActor func services() async -> AppExecutionServices {
        await AppExecutionServices.bootstrap(paths: AppStoragePaths(home: home,
            settings: configURL, journal: journal))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
final class ConfirmationLifecycleTests: XCTestCase {
    func testDirectTakeConsumesOnceWithoutAnyDismissalCallback() {
        let state = ConfirmationPresentationState()
        let frozen = display()
        state.present(frozen)
        XCTAssertEqual(state.take(), frozen)
        XCTAssertNil(state.take())
        XCTAssertNil(state.presentation)
        XCTAssertFalse(state.showingConfirmation)
    }

    func testRealModelReplacementUsesNewRegisteredProjection() async throws {
        let scratch = try AppModelScratch(); defer { scratch.remove() }
        let services = await scratch.services()
        let first = try await services.coordinator.prepareReview(
            engine: services.engine, tier: .safe, selectDefaults: false)
        let second = try await services.coordinator.prepareReview(
            engine: services.engine, tier: .deep, selectDefaults: false)
        let model = PlanSelectionModel(review: first) { _ in XCTFail("Replacement requested selection") }
        model.replace(review: second)
        XCTAssertEqual(model.value.plan.tier, .deep)
        XCTAssertEqual(model.value.reviewItems.count, second.plan.reviewItems.count)
        XCTAssertNil(model.frozenPresentation)
        XCTAssertFalse(model.canConfirm)
    }

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
        let services = await scratch.services()
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
        let services = await scratch.services(), bridge = services.policyBridge
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
        let services = await scratch.services()
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
        let services = await scratch.services()
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
        let services = await scratch.services(), bridge = services.policyBridge
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
        let persisted = await services.settings.load()
        XCTAssertEqual(persisted.envelope?.config.transcriptAgeThresholdDays, 90)
        XCTAssertEqual(persisted.envelope?.revision, 3)
    }
}
