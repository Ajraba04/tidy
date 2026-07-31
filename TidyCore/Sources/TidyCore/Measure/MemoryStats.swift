import Darwin
import Foundation

/// Live RAM usage via `host_statistics64(HOST_VM_INFO64)` instead of
/// spawning `ps`/`vm_stat`.
public struct MemoryStats: Sendable, Equatable {
    public let totalBytes: Int64
    /// (active + wired + compressed) × page size: the same definition
    /// Activity Monitor uses for "Memory Used".
    public let usedBytes: Int64

    public static func current() -> MemoryStats {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryStats(totalBytes: total, usedBytes: 0)
        }

        let active = Int64(stats.active_count)
        let wired = Int64(stats.wire_count)
        let compressed = Int64(stats.compressor_page_count)
        let used = (active + wired + compressed) * Int64(pageSize)

        return MemoryStats(totalBytes: total, usedBytes: used)
    }
}
