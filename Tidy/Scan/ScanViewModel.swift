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

    /// Only a session/subscription ID and the cumulative bounded presentation the subscription
    /// delivers are stored here — never the registry or façade themselves.
    private var sessionID: UUID?
    private var subscription: ScanSubscription?
    private var streamTask: Task<Void, Never>?

    init(services: AppExecutionServices) {
        self.services = services
    }

    /// Attaches to the app's already-running scan, if any, without starting new work. This lets
    /// a second window opened against the same session converge on identical terminal state
    /// instead of launching a duplicate walk.
    func attachToActiveScanIfNeeded() {
        guard streamTask == nil, let activeID = services.activeScanSessionID ?? sessionID else { return }
        phase = .running
        attach(sessionID: activeID)
    }

    func runScan() async {
        detachSubscription()
        phase = .running
        do {
            let handle = try await services.beginScan()
            attach(sessionID: handle.sessionID)
        } catch CoreOrchestrationError.policyPaused {
            phase = .paused
        } catch ScanAvailabilityError.policyNotInstalled {
            phase = .failed("Settings are not available for scanning. Complete onboarding or resolve the settings recovery message, then try again.")
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Targets the active session by ID only — this never touches the T04 process gate or a
    /// mutator, and it remains available through the global/menu owner after this window closes.
    func cancelScan() async {
        guard let sessionID else { return }
        try? await services.scanRegistry.cancel(sessionID: sessionID)
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
            guard let registry = self?.services.scanRegistry else { return }
            do {
                let subscription = try await registry.subscribe(sessionID: sessionID)
                guard !Task.isCancelled, self?.sessionID == sessionID else { await subscription.cancel(); return }
                self?.subscription = subscription
                for await event in subscription.stream {
                    guard !Task.isCancelled, let self, self.sessionID == sessionID,
                          event.sessionID == sessionID else { break }
                    await self.apply(event, sessionID: sessionID)
                }
                await subscription.cancel()
            } catch {
                guard self?.sessionID == sessionID else { return }
                self?.phase = .failed(String(describing: error))
            }
        }
    }

    private func apply(_ event: ScanSessionEvent, sessionID: UUID) async {
        switch event.kind {
        case .progress:
            if let result = await services.latestScanResult(sessionID: sessionID) {
                guard self.sessionID == sessionID else { return }
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
