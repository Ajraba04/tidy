import Darwin
import Foundation

/// One `host_statistics64(HOST_VM_INFO64)` call, shared by `MemoryStats` and
/// `SwapStats` so the kernel is asked once rather than twice, and so both
/// call sites see the same page size and the same instant's counters.
/// Internal: `MemoryStats.current()`/`SwapStats.current()` are the public
/// surface, and `SystemMonitor`'s `LiveSystemProbe` reads the cumulative
/// swap-out counter from here for the page-out pressure signal.
struct VMCounterSnapshot: Sendable, Equatable {
    let pageSizeBytes: UInt64
    let activePages: UInt64
    let wiredPages: UInt64
    let compressedPages: UInt64
    /// Cumulative count of pages swapped out since boot. Monotonic while the
    /// boot identity is unchanged; never decreases on its own.
    let swapOutsCumulative: UInt64

    static func current() -> VMCounterSnapshot? {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        guard pageSize > 0 else { return nil }

        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return VMCounterSnapshot(
            pageSizeBytes: UInt64(pageSize),
            activePages: UInt64(stats.active_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            swapOutsCumulative: UInt64(stats.swapouts)
        )
    }
}

/// Live RAM usage via `host_statistics64(HOST_VM_INFO64)` instead of
/// spawning `ps`/`vm_stat`.
public struct MemoryStats: Sendable, Equatable {
    public let totalBytes: Int64
    /// (active + wired + compressed) × page size: the same definition
    /// Activity Monitor uses for "Memory Used". `nil` when the kernel call
    /// failed -- reported as unavailable, never silently shown as zero.
    public let usedBytes: Int64?
    /// Set only when `usedBytes` is `nil`; explains why, for display.
    public let unavailableReason: String?

    public init(totalBytes: Int64, usedBytes: Int64?, unavailableReason: String? = nil) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.unavailableReason = unavailableReason
    }

    public static func current() -> MemoryStats {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard let vm = VMCounterSnapshot.current() else {
            return MemoryStats(totalBytes: total, usedBytes: nil,
                unavailableReason: "host_statistics64 denied or unavailable")
        }
        let used = Int64(vm.activePages + vm.wiredPages + vm.compressedPages) * Int64(vm.pageSizeBytes)
        return MemoryStats(totalBytes: total, usedBytes: used)
    }
}
