import Foundation
import Observation
import TidyCore

/// Presentation state for `HeadroomView`. Owns no probe, no timer, and no
/// scheduling decision of its own -- it only forwards window visibility and
/// the resolved policy to the app's one shared `SystemMonitor`
/// (`AppExecutionServices.systemMonitor`) and republishes whatever it
/// publishes, the same T08.5 ownership shape `StatsRefresher` follows for
/// the menu bar popover.
@Observable
@MainActor
final class HeadroomViewModel {
    private(set) var snapshot: SystemSnapshot?
    /// `ui.cards` order from the effective policy, resolved once at
    /// construction; a settings change is picked up the next time the
    /// window opens, the same cadence `StatsRefresher` uses for policy.
    private(set) var cardOrder: [String]

    private let visibilityID = UUID()
    private let monitor: SystemMonitor
    // Written once in init and read in the nonisolated deinit, where a
    // main-actor property cannot be referenced; Task handles are Sendable and
    // cancel() is thread-safe, so the unsafe opt-out is sound here.
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?

    init(monitor: SystemMonitor, cardOrder: [String]) {
        self.monitor = monitor
        self.cardOrder = cardOrder.isEmpty ? HeadroomViewModel.defaultCardOrder : cardOrder
        // `monitor` (a value copy of the actor reference, not `self`) is the
        // only thing this task needs to obtain its OWN subscription; `self`
        // is re-resolved weakly on every iteration below, so this task never
        // holds `self` alive for the stream's unbounded lifetime. Cancelling
        // `observationTask` (from `deinit`) ends the suspended `for await`
        // via the stream's own cancellation handling, which in turn fires
        // `SystemMonitor.subscribe()`'s `onTermination` and deregisters this
        // consumer -- so a torn-down view model never leaks a subscriber.
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
        let monitor = monitor
        let id = visibilityID
        Task { await monitor.setWindowVisible(false, consumer: id) }
    }

    static let defaultCardOrder = ["disk", "memoryPressure", "swap", "thermal", "power"]

    func applyPolicy(_ policy: EffectivePolicy?) {
        cardOrder = resolvedUICardOrder(policy)
    }

    func onAppear(policy: EffectivePolicy?) {
        applyPolicy(policy)
        let monitor = monitor
        let configuration = SystemMonitor.Configuration.resolve(policy)
        let visibilityID = visibilityID
        Task {
            await monitor.applyConfiguration(configuration)
            await monitor.setWindowVisible(true, consumer: visibilityID)
            await monitor.requestSnapshot()
        }
    }

    /// Window closed: this is the point at which background sampling stops
    /// entirely unless `monitor.backgroundEnabled` is explicitly on.
    func onDisappear() {
        let monitor = monitor
        let visibilityID = visibilityID
        Task { await monitor.setWindowVisible(false, consumer: visibilityID) }
    }

    /// One explicit re-read, for a manual refresh control -- never on a
    /// timer this view model owns.
    func refreshNow() {
        let monitor = monitor
        Task { await monitor.requestSnapshot() }
    }

    var primaryVolume: VolumeObservation? { snapshot?.volumes.first }

    /// "Target met," never "buildable": see `HeadroomReadiness`.
    func readiness(targetBytes: Int64?) -> HeadroomReadiness {
        HeadroomReadiness.evaluate(targetBytes: targetBytes, availableBytes: primaryVolume?.disk?.availableBytes)
    }
}

/// Reads the resolved `headroom.targetGiB` byte figure from an
/// `EffectivePolicy`. `PolicyResolver` resolves this field to
/// `.bytes(Int64)` (already converted from GiB, and only once a selected
/// volume and its capacity are known -- see `PolicyResolver.resolveHeadroom`),
/// never `.stored(.integer)`, so this reads the same `EffectiveValue.bytes`
/// case the T13 Build Prep planner will read. Until the app resolves an
/// actual selected volume/capacity into `PolicyInputs` (`AppConfigStore`
/// does not yet, as of T10), this honestly resolves to `nil` rather than
/// guessing -- matching the "target not set / unavailable" wording in
/// `HeadroomView`.
func resolvedHeadroomTargetBytes(_ policy: EffectivePolicy?) -> Int64? {
    guard let policy, case .bytes(let value)? =
        policy.fields[SettingID(rawValue: "headroom.targetGiB")]?.value else { return nil }
    return value
}

func resolvedUICardOrder(_ policy: EffectivePolicy?) -> [String] {
    guard let policy, case .stored(.strings(let values))? =
        policy.fields[SettingID(rawValue: "ui.cards")]?.value else { return HeadroomViewModel.defaultCardOrder }
    return values
}
