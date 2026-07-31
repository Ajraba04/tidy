import Darwin
import Foundation

/// Live swap usage via `sysctlbyname("vm.swapusage")` instead of
/// spawning `sysctl`.
public struct SwapStats: Sendable, Equatable {
    public let totalBytes: Int64
    public let usedBytes: Int64

    public static func current() -> SwapStats? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return nil }
        return SwapStats(totalBytes: Int64(usage.xsu_total), usedBytes: Int64(usage.xsu_used))
    }
}
