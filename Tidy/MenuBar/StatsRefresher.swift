import Foundation
import Observation
import TidyCore

/// Holds the live disk/memory/swap gauges shown in the menu bar popover.
/// Refreshes on a timer: every 5 seconds while the popover is visible, every
/// 60 seconds otherwise. Every refresh is a handful of syscalls
/// (`DiskStats`/`MemoryStats`/`SwapStats`) — never file-tree I/O.
@Observable
@MainActor
final class StatsRefresher {
    private(set) var disk: DiskStats?
    private(set) var memory: MemoryStats = .current()
    private(set) var swap: SwapStats?

    private var timer: Timer?
    private var isPopoverVisible = false

    func onPopoverAppear() {
        isPopoverVisible = true
        refresh()
        rescheduleTimer()
    }

    func onPopoverDisappear() {
        isPopoverVisible = false
        rescheduleTimer()
    }

    func refresh() {
        disk = try? DiskStats.current()
        memory = .current()
        swap = SwapStats.current()
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        let interval: TimeInterval = isPopoverVisible ? 5 : 60
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }
}
