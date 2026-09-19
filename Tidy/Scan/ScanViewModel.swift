import Foundation
import Observation
import TidyCore

@Observable
@MainActor
final class ScanViewModel {
    enum Phase {
        case idle
        case running
        case runningPartial(CoreScanResult)
        case partial(CoreScanResult)
        case paused
        case cancelled
        case complete(ScanReport)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private let services: AppExecutionServices
    private let ownerID = UUID()

    /// Only a session/subscription ID and the cumulative bounded presentation the subscription
    /// delivers are stored here — never the registry or façade themselves.
    private var sessionID: UUID?
    private var subscription: ScanSubscription?
    private var streamTask: Task<Void, Never>?
    private var startingRequestID: UUID?
    private var cancelRequestedForStartID: UUID?

    init(services: AppExecutionServices) {
        self.services = services
    }

    /// Attaches to the app's already-running scan, if any, without starting new work. This lets
    /// a second window opened against the same session converge on identical terminal state
    /// instead of launching a duplicate walk.
    func attachToActiveScanIfNeeded() {
        guard startingRequestID == nil, sessionID == nil,
              let activeID = services.activeScanSessionID else { return }
        phase = .running
        attach(sessionID: activeID)
    }

    func runScan() async {
        await start(request: .policyDefault)
    }

    func runFullHomeScan() async {
        guard startingRequestID == nil else { return }
        do {
            let consent = try services.issueFullHomeScanConsent(ownerID: ownerID)
            await start(request: .fullHome(consent))
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    private func start(request: AppScanRequest) async {
        guard startingRequestID == nil else { return }
        let requestID = UUID()
        startingRequestID = requestID
        cancelRequestedForStartID = nil
        detachSubscription()
        sessionID = nil
        phase = .running
        let environment = services.configStore.config.makePolicyEnvironment(
            homeDirectory: services.paths.home.path, detectedTools: [])
        do {
            let handle = try await services.beginScan(environment: environment,
                request: request, ownerID: ownerID)
            guard startingRequestID == requestID else { return }
            let shouldCancel = cancelRequestedForStartID == requestID
            startingRequestID = nil
            cancelRequestedForStartID = nil
            attach(sessionID: handle.sessionID)
            if shouldCancel { await services.cancelActiveScan() }
        } catch CoreOrchestrationError.policyPaused {
            guard startingRequestID == requestID else { return }
            startingRequestID = nil
            cancelRequestedForStartID = nil
            phase = .paused
        } catch ScanAvailabilityError.policyNotInstalled {
            guard startingRequestID == requestID else { return }
            startingRequestID = nil
            cancelRequestedForStartID = nil
            phase = .failed("Tidy needs settings saved once before it can scan. Open Settings, save, then try again.")
        } catch {
            guard startingRequestID == requestID else { return }
            startingRequestID = nil
            cancelRequestedForStartID = nil
            phase = .failed(String(describing: error))
        }
    }

    /// Targets the active session by ID only — this never touches the T04 process gate or a
    /// mutator, and it remains available through the global/menu owner after this window closes.
    func cancelScan() async {
        if let startingRequestID {
            cancelRequestedForStartID = startingRequestID
            return
        }
        guard sessionID != nil else { return }
        await services.cancelActiveScan()
    }

    func continueScan() async {
        guard startingRequestID == nil else { return }
        let requestID = UUID()
        startingRequestID = requestID
        cancelRequestedForStartID = nil
        detachSubscription()
        sessionID = nil
        phase = .running
        do {
            let handle = try await services.continueActiveScan()
            guard startingRequestID == requestID else { return }
            let shouldCancel = cancelRequestedForStartID == requestID
            startingRequestID = nil
            cancelRequestedForStartID = nil
            attach(sessionID: handle.sessionID)
            if shouldCancel { await services.cancelActiveScan() }
        } catch {
            guard startingRequestID == requestID else { return }
            startingRequestID = nil
            cancelRequestedForStartID = nil
            phase = .failed(String(describing: error))
        }
    }

    /// Detaches only this window's subscription. The session — and any other subscriber — is
    /// left completely untouched; this must never cancel the session itself.
    func detachSubscription() {
        streamTask?.cancel()
        streamTask = nil
        guard let current = subscription else { return }
        subscription = nil
        Task { await current.cancel() }
    }

    private func attach(sessionID: UUID) {
        self.sessionID = sessionID
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard !Task.isCancelled else { return }
                let subscription = try await self.services.scanRegistry.subscribe(sessionID: sessionID)
                guard !Task.isCancelled, self.sessionID == sessionID else {
                    await subscription.cancel(); return
                }
                self.subscription = subscription
                for await event in subscription.stream {
                    guard self.sessionID == sessionID, event.sessionID == sessionID else { break }
                    await self.apply(event, sessionID: sessionID)
                }
            } catch {
                guard self.sessionID == sessionID else { return }
                self.phase = .failed(String(describing: error))
            }
        }
    }

    private func apply(_ event: ScanSessionEvent, sessionID: UUID) async {
        switch event.kind {
        case .progress:
            if let result = await services.latestScanResult(sessionID: sessionID) {
                phase = .runningPartial(result)
            }
        case .terminal(let terminal):
            switch terminal {
            case .complete:
                if let result = await services.latestScanResult(sessionID: sessionID) {
                    phase = .complete(result.report)
                } else {
                    phase = .failed("Scan completed without a retained result.")
                }
            case .partial:
                if let result = await services.latestScanResult(sessionID: sessionID) {
                    phase = .partial(result)
                } else {
                    phase = .failed("Scan ended partially without a retained result.")
                }
            case .cancelled:
                phase = .cancelled
            case .failed:
                phase = .failed("Scan failed before completion.")
            }
        }
    }
}
