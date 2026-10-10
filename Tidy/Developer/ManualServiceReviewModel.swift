import Foundation
import Observation
import TidyCore

/// Shared app-owned presentation state. Candidate bindings and checkbox choices
/// are display data; only the retained real bridge facade owns a review lifecycle.
@Observable @MainActor
final class ManualServiceReviewModel {
    typealias FacadeProvider = @MainActor () -> BridgeManualServices?
    typealias CandidateReader = @MainActor () async throws -> [ManualServiceOperationBinding]
    typealias ExecutionStarter = @MainActor (BridgeManualServices, ManualServiceReview) throws
        -> Task<ManualServiceExecutionReport, Error>

    private(set) var candidate: ManualServiceOperationBinding?
    private(set) var candidates: [ManualServiceOperationBinding] = []
    private(set) var reviewSummary: ManualServiceReviewSummary?
    private(set) var isPreparing = false
    private(set) var isRefreshing = false
    private(set) var isExecuting = false
    private(set) var operationMessage: String?
    var isSelected = false
    var consequencesAcknowledged = false

    @ObservationIgnored private let facadeProvider: FacadeProvider?
    @ObservationIgnored private let candidateReader: CandidateReader?
    @ObservationIgnored private let executionStarter: ExecutionStarter?
    @ObservationIgnored private let executionOwnerAvailable: @MainActor () -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var prepared: (facade: BridgeManualServices, review: ManualServiceReview)?

    init(facadeProvider: FacadeProvider? = nil, candidateReader: CandidateReader? = nil,
         executionStarter: ExecutionStarter? = nil,
         executionOwnerAvailable: @escaping @MainActor () -> Bool = { true }) {
        self.facadeProvider = facadeProvider
        self.candidateReader = candidateReader
        self.executionStarter = executionStarter
        self.executionOwnerAvailable = executionOwnerAvailable
    }

    var unavailableReason: String? {
        guard let candidate else { return nil }
        if let reason = candidate.executionUnavailableReason { return reason }
        if executionStarter == nil || !executionOwnerAvailable() {
            return "Local execution controls are unavailable or another app-owned operation is active."
        }
        return nil
    }

    /// Display choices only enable asking the retained owner to confirm. Core
    /// still checks expiry, policy, exact authority and producer acceptance.
    var canExecute: Bool {
        guard let candidate, candidate.executionUnavailableReason == nil,
              isSelected, consequencesAcknowledged, !isPreparing, !isRefreshing, !isExecuting,
              executionStarter != nil, executionOwnerAvailable(), let prepared,
              prepared.review.summary.binding == candidate,
              (try? candidate.canonicalDigest()) == prepared.review.summary.bindingDigest else { return false }
        let now = DispatchTime.now().uptimeNanoseconds
        return now >= prepared.review.summary.issuedAtMonotonicNanoseconds
            && now < prepared.review.summary.expiresAtMonotonicNanoseconds
    }
    var canPrepareReview: Bool {
        candidate != nil && isSelected && !isPreparing && !isRefreshing && !isExecuting
            && facadeProvider != nil && executionOwnerAvailable()
    }
    var canRefreshCandidates: Bool {
        candidateReader != nil && !isPreparing && !isRefreshing && !isExecuting && executionOwnerAvailable()
    }

    func inspect(_ binding: ManualServiceOperationBinding) {
        supersede()
        do {
            _ = try binding.canonicalDigest()
            candidate = binding
            operationMessage = nil
        } catch {
            candidate = nil
            operationMessage = "This candidate description is incomplete or unsupported. Refresh explicit inventory before reviewing."
        }
    }

    func dismiss() {
        supersede()
        candidate = nil
        operationMessage = nil
    }

    /// Parent composition calls this when the approved set, acknowledged policy
    /// or actor-issued local consent changes. No replacement read starts here.
    func invalidateCandidates() {
        supersede()
        candidate = nil; candidates = []
        operationMessage = "Candidate scope changed. Refresh explicit inventory before reviewing."
    }

    @discardableResult
    func refreshCandidates() -> Task<Void, Never>? {
        guard let candidateReader, canRefreshCandidates else { return nil }
        supersede()
        candidate = nil; candidates = []; operationMessage = nil
        isRefreshing = true
        let capturedGeneration = generation
        task = Task { @MainActor [weak self] in
            do {
                let values = try await candidateReader()
                guard let self, self.generation == capturedGeneration, !Task.isCancelled else { return }
                guard values.count <= ManualServiceReviewSummary.maximumPendingReviewCount else {
                    self.isRefreshing = false
                    self.operationMessage = "The candidate list exceeds the review limit. Refine explicit inventory before reviewing."
                    return
                }
                var digests: Set<Data> = []
                for value in values {
                    guard digests.insert(try value.canonicalDigest()).inserted else {
                        self.isRefreshing = false
                        self.operationMessage = "Candidate descriptions were duplicated. Refresh explicit inventory before reviewing."
                        return
                    }
                }
                self.candidates = values
                self.isRefreshing = false
                self.operationMessage = values.isEmpty ? "No eligible manual candidates were returned by this explicit inventory read." : nil
            } catch {
                guard let self, self.generation == capturedGeneration, !Task.isCancelled else { return }
                self.isRefreshing = false
                self.operationMessage = "Candidate inventory could not be read. Check current local consent and refresh explicitly."
            }
        }
        return task
    }

    @discardableResult
    func prepareReview() -> Task<Void, Never>? {
        guard canPrepareReview, let candidate else { return nil }
        guard let facade = facadeProvider?() else {
            operationMessage = "Local review controls are unavailable. Check current local consent before preparing a review."
            return nil
        }
        cancelPreparedReview()
        isPreparing = true; operationMessage = nil
        let capturedGeneration = generation
        task = Task { @MainActor [weak self] in
            do {
                let review = try await facade.prepare(binding: candidate)
                guard let self, self.generation == capturedGeneration, !Task.isCancelled else {
                    try? await facade.cancelReview(review)
                    return
                }
                self.prepared = (facade, review)
                self.reviewSummary = review.summary
                self.isPreparing = false
                self.operationMessage = candidate.executionUnavailableReason == nil
                    ? "Review prepared. It expires within 60 seconds. Confirming execution rechecks current permissions and producer state."
                    : "Review prepared. It expires within 60 seconds. This producer has no accepted manual operation contract; execution remains unavailable."
            } catch {
                guard let self, self.generation == capturedGeneration, !Task.isCancelled else { return }
                self.isPreparing = false
                self.operationMessage = Self.reviewFailureMessage(error)
            }
        }
        return task
    }

    @discardableResult
    func execute() -> Task<Void, Never>? {
        guard canExecute, let held = prepared, let executionStarter else { return nil }
        let execution: Task<ManualServiceExecutionReport, Error>
        do {
            execution = try executionStarter(held.facade, held.review)
        } catch {
            operationMessage = Self.reviewFailureMessage(error)
            return nil
        }
        // Ownership of confirmation has moved to the app task. Subsequent UI
        // invalidation must not cancel its review or its retained execution.
        prepared = nil
        reviewSummary = nil
        isExecuting = true
        operationMessage = "The app is confirming current permissions and producer state."
        let capturedGeneration = generation
        let binding = held.review.summary.binding
        task = Task { @MainActor [weak self] in
            do {
                let report = try await execution.value
                guard let self, self.generation == capturedGeneration, !Task.isCancelled,
                      self.candidate == binding else { return }
                self.isExecuting = false
                self.isSelected = false; self.consequencesAcknowledged = false
                guard report.binding == binding else {
                    self.operationMessage = "The execution result did not match this review. Check app recovery before continuing."
                    return
                }
                self.operationMessage = report.message
            } catch {
                guard let self, self.generation == capturedGeneration, !Task.isCancelled,
                      self.candidate == binding else { return }
                self.isExecuting = false
                self.isSelected = false; self.consequencesAcknowledged = false
                self.operationMessage = error is CancellationError
                    ? "Execution was cancelled. Check the app's execution and recovery status before preparing another review."
                    : Self.reviewFailureMessage(error)
            }
        }
        return task
    }

    func cancelReview() {
        supersede()
        operationMessage = "Review cancelled. Preparing another review requires current policy and local consent."
    }

    private func supersede() {
        if generation < UInt64.max { generation += 1 }
        task?.cancel(); task = nil
        isPreparing = false; isRefreshing = false; isExecuting = false
        isSelected = false; consequencesAcknowledged = false
        cancelPreparedReview()
    }

    private func cancelPreparedReview() {
        reviewSummary = nil
        guard let prepared else { return }
        self.prepared = nil
        // Retain the original facade's owner while cancellation completes,
        // independently of whichever window currently displays this model.
        Task { @MainActor in try? await prepared.facade.cancelReview(prepared.review) }
    }

    private static func reviewFailureMessage(_ error: Error) -> String {
        guard let error = error as? ManualServiceReviewError else {
            return "Review could not be prepared. Check current local consent and refresh explicit inventory."
        }
        switch error {
        case .policyDisabled: return "Manual review is disabled by the acknowledged settings."
        case .policyUnavailable, .stalePolicy: return "Acknowledged settings changed or are unavailable. Prepare a fresh review."
        case .authorityDenied, .wrongInstallation: return "Exact local consent is unavailable or changed. Review local consent before continuing."
        case .wrongOwner, .wrongCoordinator, .unknownReview, .expiredReview: return "This review is no longer available to this owner. Prepare a fresh review."
        case .bindingMismatch: return "The candidate identity changed. Refresh explicit inventory before reviewing."
        case .providerUnavailable: return "This producer has no accepted manual operation contract. Execution remains unavailable."
        case .busy: return "Finish or cancel the current app-owned operation before preparing a review."
        case .recoveryBlocked: return "Unresolved work requires recovery verification before another review."
        case .storageUnavailable: return "Private review or recovery storage is unavailable."
        case .capacity: return "The pending review limit was reached. Cancel an existing review before preparing another."
        }
    }
}
