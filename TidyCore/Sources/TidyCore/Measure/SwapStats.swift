import Darwin
import Foundation

/// Live swap usage via `sysctlbyname("vm.swapusage")` instead of
/// spawning `sysctl`.
public struct SwapStats: Sendable, Equatable {
    public let totalBytes: Int64
    public let usedBytes: Int64
    /// Cumulative pages swapped out since boot, from the same
    /// `host_statistics64` call `MemoryStats` uses -- not from
    /// `vm.swapusage`, which only ever reports a current gauge. This is a
    /// pressure indicator only: a rising rate across two samples means the
    /// kernel is actively swapping, but the count itself is never a measure
    /// of exact SSD writes and never proof that swap must be, or will be,
    /// cleared. `nil` when the counter could not be read; a monitor should
    /// treat that as "unknown", not zero.
    public let pageOutsCumulative: UInt64?
    /// The page size the cumulative counter is denominated in. Needed to
    /// convert a page-count delta into a byte rate; deliberately not
    /// assumed to be 4 KiB, since Apple Silicon and future hardware are not
    /// guaranteed to use that page size.
    public let pageSizeBytes: UInt64?

    public init(totalBytes: Int64, usedBytes: Int64,
                pageOutsCumulative: UInt64? = nil, pageSizeBytes: UInt64? = nil) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.pageOutsCumulative = pageOutsCumulative
        self.pageSizeBytes = pageSizeBytes
    }

    public static func current() -> SwapStats? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return nil }
        let counters = VMCounterSnapshot.current()
        return SwapStats(totalBytes: Int64(usage.xsu_total), usedBytes: Int64(usage.xsu_used),
            pageOutsCumulative: counters?.swapOutsCumulative, pageSizeBytes: counters?.pageSizeBytes)
    }
}
