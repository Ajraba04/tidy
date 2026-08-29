import Foundation
import Observation
import TidyCore

/// Thin `@MainActor` presentation wrapper around `TidyCore.SystemMonitor`
/// for the menu bar popover's disk/memory/swap gauges.
///
/// All scheduling authority -- whether a repeating background sample loop
/// may exist at all, and at what cadence -- lives in `SystemMonitor`. This
/// class owns none of it: it only forwards window visibility and the
/// resolved policy, and republishes whatever the monitor publishes. That
/// keeps app code from becoming a second scheduler, per the T08.5
/// AppExecutionServices-ownership pattern this app already follows for
/// scanning.
@Observable
@MainActor
final class StatsRefresher {
    private(set) var snapshot: SystemSnapshot?

    private let monitor: SystemMonitor
    // Written once in init and read in the nonisolated deinit, where a
    // main-actor property cannot be referenced; Task handles are Sendable and
    // cancel() is thread-safe, so the unsafe opt-out is sound here.
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        // `monitor` (a value copy of the actor reference, not `self`) is the
        // only thing this task needs to obtain its OWN subscription; `self`
        // is re-resolved weakly on every iteration below, so this task never
        // holds `self` alive for the stream's unbounded lifetime. Cancelling
        // `observationTask` (from `deinit`) ends the suspended `for await`
        // via the stream's own cancellation handling, which in turn fires
        // `SystemMonitor.subscribe()`'s `onTermination` and deregisters this
        // consumer -- so a torn-down `StatsRefresher` never leaks a
        // subscriber, and other open windows keep receiving updates on
        // their own independent subscriptions.
        observationTask = Task { @MainActor [weak self, monitor] in
            let stream = await monitor.subscribe()
            for await value in stream {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                self.snapshot = value
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    /// The popover became visible: switch to the visible sampling cadence
    /// and take one immediate reading.
    func onPopoverAppear() {
        let monitor = monitor
        Task {
            await monitor.setWindowVisible(true)
            await monitor.requestSnapshot()
        }
    }

    /// The popover closed. If background monitoring isn't explicitly
    /// enabled (it defaults to off), this is the point at which
    /// `SystemMonitor` tears its repeating loop down entirely -- not just
    /// slows it.
    func onPopoverDisappear() {
        let monitor = monitor
        Task { await monitor.setWindowVisible(false) }
    }

    /// Re-reads the effective policy's monitoring settings. Cheap and
    /// idempotent, so callers can call it on every popover appearance
    /// rather than standing up a separate settings-change subscription.
    func applyPolicy(_ policy: EffectivePolicy?) {
        let monitor = monitor
        let configuration = SystemMonitor.Configuration.resolve(policy)
        Task { await monitor.applyConfiguration(configuration) }
    }
}
