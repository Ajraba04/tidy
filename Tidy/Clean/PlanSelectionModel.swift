import Foundation
import Observation
import TidyCore

/// Display-only data. It conveys no coordinator authority.
struct FrozenReviewPresentation: Equatable, Sendable {
    let binding: ReviewBinding
    let selectedCount: Int
    let estimatedBytes: Int64
}

@Observable @MainActor
final class ConfirmationPresentationState {
    private(set) var presentation: FrozenReviewPresentation?
    var showingConfirmation = false
    private var dismissalIdentity: UUID?

    func present(_ value: FrozenReviewPresentation) {
        dismissalIdentity = nil
        presentation = value
        showingConfirmation = true
    }
    func take() -> FrozenReviewPresentation? {
        let captured = presentation
        cancel()
        return captured
    }
    func cancel() {
        dismissalIdentity = nil
        presentation = nil
        showingConfirmation = false
    }
    func presentationDidDismiss() -> UUID {
        showingConfirmation = false
        let identity = UUID()
        dismissalIdentity = identity
        return identity
    }
    func settleDismissal(_ identity: UUID) {
        guard dismissalIdentity == identity else { return }
        cancel()
    }
}

struct ReviewRequestID: Equatable, Sendable { fileprivate let value: UUID }

/// Orders actual coordinator requests, not just their UI responses.
@MainActor
final class ReviewRequestLifetime {
    private var generation = ReviewRequestID(value: UUID())
    private var closed = false
    private var tail: Task<Void, Never>?
    private var closing: Task<Void, Never>?

    func enqueue(_ operation: @escaping @MainActor (ReviewRequestID) async -> Void) -> Task<Void, Never> {
        guard !closed else { return Task {} }
        invalidate()
        let request = generation
        let previous = tail
        let task = Task { [self] in
            await previous?.value
            guard isCurrent(request) else { return }
            await operation(request)
        }
        tail = task
        return task
    }
    func isCurrent(_ request: ReviewRequestID) -> Bool { !closed && generation == request }
    func invalidate() { generation = ReviewRequestID(value: UUID()) }
    func teardown(_ cleanup: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        if let closing { return closing }
        closed = true
        invalidate()
        let previous = tail
        let task = Task { await previous?.value; await cleanup() }
        closing = task
        tail = task
        return task
    }
    func drain() async { await tail?.value }
}

@Observable @MainActor
final class PlanSelectionModel {
    private(set) var value: PlanSelection
    private let presentationState = ConfirmationPresentationState()
    private var binding: ReviewBinding?
    private var onSelectionRequested: (@MainActor (Set<String>) -> Void)?
    private var executionEnabled = false
    private var confirmationSubmitted = false
    private(set) var updatePending = false
    var frozenPresentation: FrozenReviewPresentation? { presentationState.presentation }

    var showingConfirmation: Bool {
        get { presentationState.showingConfirmation }
        set {
            if newValue { beginConfirmation() }
            else {
                let identity = presentationState.presentationDidDismiss()
                Task { @MainActor [presentationState] in
                    await Task.yield()
                    presentationState.settleDismissal(identity)
                }
            }
        }
    }

    var canConfirm: Bool {
        binding != nil && executionEnabled && !updatePending && !confirmationSubmitted && value.selectedCount > 0
    }

    /// Fixture/local display initializer deliberately has no binding or authority.
    init(plan: CleanPlan, selectDefaults: Bool) {
        value = PlanSelection(plan: plan, selectDefaults: selectDefaults)
    }
    init(review: RegisteredReview, onSelectionRequested: @escaping @MainActor (Set<String>) -> Void) {
        value = review.selection
        binding = review.binding
        self.onSelectionRequested = onSelectionRequested
    }

    func setSelected(_ selected: Bool, id: String) {
        cancelConfirmation()
        var proposed = value
        proposed.setSelected(selected, id: id)
        request(proposed)
    }
    func applyPresetIDs(_ ids: Set<String>) {
        cancelConfirmation()
        var proposed = value
        proposed.applyPresetIDs(ids)
        request(proposed)
    }
    private func request(_ proposed: PlanSelection) {
        guard proposed.selectedIDs != value.selectedIDs else { return }
        value = proposed
        guard let onSelectionRequested, binding != nil else { return }
        updatePending = true
        onSelectionRequested(proposed.selectedIDs)
    }

    func beginConfirmation() {
        guard canConfirm, let binding else { cancelConfirmation(); return }
        presentationState.present(FrozenReviewPresentation(binding: binding,
            selectedCount: value.selectedCount, estimatedBytes: value.selectedEstimatedBytes))
    }
    func takeConfirmation() -> FrozenReviewPresentation? {
        guard canConfirm, let frozen = presentationState.take(), frozen.binding == binding else {
            cancelConfirmation()
            return nil
        }
        confirmationSubmitted = true
        return frozen
    }
    func cancelConfirmation() { presentationState.cancel() }
    func replace(review: RegisteredReview) {
        cancelConfirmation()
        value = review.selection
        binding = review.binding
        updatePending = false
        confirmationSubmitted = false
    }
    func invalidate(policyEnabled: Bool) {
        cancelConfirmation()
        executionEnabled = policyEnabled
        if !policyEnabled {
            binding = nil
            updatePending = false
        }
    }
}

func confirmationFailureMessage(_ error: Error) -> String {
    guard let error = error as? ConfirmationError else { return "Review could not be prepared. Try reviewing again." }
    switch error {
    case .unknownPlan, .staleReview, .unknownSelectedID:
        return "This review changed. Review the items again before confirming."
    case .stalePolicy:
        return "Settings changed. Save settings successfully, then review the items again."
    case .unavailableSelection:
        return "The selected action is unavailable. Nothing was run."
    case .busy:
        return "Another cleanup is running. Wait for it to finish, then review again."
    case .recoveryBlocked:
        return "An earlier operation may still be running. Cleanup is blocked until it can be reconciled."
    case .storageUnavailable:
        return "Execution records could not be validated. Cleanup remains blocked."
    }
}
