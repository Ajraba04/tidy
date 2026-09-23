import Foundation

/// Identifies one boot of the kernel, so a monitor can tell "the counter
/// went down because the machine slept and swap was cleared at wake/reboot"
/// apart from "the counter went down, which should be impossible." Sourced
/// from `sysctl(kern.boottime)`; two snapshots taken across a sleep/wake
/// cycle on the same boot report the same identity, while a restart changes
/// it.
public struct BootIdentity: Sendable, Equatable {
    public let bootTime: TimeInterval

    public init(bootTime: TimeInterval) {
        self.bootTime = bootTime
    }
}

/// A push-notification memory-pressure level (`DispatchSource.makeMemoryPressureSource`),
/// not a number Tidy computed itself.
public enum MemoryPressureLevel: String, Sendable, Equatable, Codable {
    case normal, warning, critical
}

/// One volume's disk observation inside a `SystemSnapshot`. Optional and
/// timestamped like every other field here: a denied or unsupported query
/// reports `nil` with a reason, never a fabricated zero.
public struct VolumeObservation: Sendable, Equatable, Identifiable {
    public var id: String { volumeIdentity }
    /// Stable identity for this volume (its UUID when the filesystem
    /// reports one, otherwise the mount path). Used to match a saved
    /// per-volume override; never assumed stable across every macOS
    /// version or filesystem.
    public let volumeIdentity: String
    public let displayPath: String
    public let disk: DiskStats?
    public let unavailableReason: String?

    public init(volumeIdentity: String, displayPath: String, disk: DiskStats?,
                unavailableReason: String? = nil) {
        self.volumeIdentity = volumeIdentity
        self.displayPath = displayPath
        self.disk = disk
        self.unavailableReason = unavailableReason
    }
}

/// One optional, timestamped observation of the system and its mounted
/// volumes -- deliberately NOT a composite "health score." Every field is
/// independently optional and independently explained when unavailable;
/// nothing here is combined into a single number, because a single number
/// would hide exactly which signal was denied, unsupported, or stale.
///
/// Nothing on this type, or anything that produces one, ever samples the
/// process list. Process polling is a separate, explicit action gated on a
/// visible selected rescue screen -- see `RescuePlanner` (T14) -- never
/// something a stats tick does on the side.
public struct SystemSnapshot: Sendable, Equatable {
    public let observedAt: Date
    /// `nil` only when the boot-time sysctl itself was denied/unsupported;
    /// when that happens, cumulative counters (page-out rate) cannot be
    /// trusted across samples and are reported as unavailable too.
    public let bootIdentity: BootIdentity?
    public let volumes: [VolumeObservation]
    public let memory: MemoryStats?
    public let memoryUnavailableReason: String?
    public let swap: SwapStats?
    public let swapUnavailableReason: String?
    /// Bytes per second currently being paged out, derived from two
    /// consecutive cumulative-counter samples on the same boot identity.
    /// A pressure indicator only: rising means the kernel is actively
    /// swapping right now. It is never labelled as exact SSD write bytes,
    /// and a falling or zero rate is never presented as proof that swap
    /// has been, or can be, cleared -- only a restart does that, and even
    /// then only usually (see `RestartReclaimSurvey`).
    public let pageOutRatePerSecond: Double?
    public let memoryPressureLevel: MemoryPressureLevel?
    public let thermalState: ProcessInfo.ThermalState?
    public let isLowPowerModeEnabled: Bool?
    /// Set when policy forbids the observation itself. In this state the
    /// monitor intentionally invokes no operating-system probes.
    public let unavailableReason: String?

    public init(observedAt: Date, bootIdentity: BootIdentity?, volumes: [VolumeObservation],
                memory: MemoryStats?, memoryUnavailableReason: String?,
                swap: SwapStats?, swapUnavailableReason: String?,
                pageOutRatePerSecond: Double?, memoryPressureLevel: MemoryPressureLevel?,
                thermalState: ProcessInfo.ThermalState?, isLowPowerModeEnabled: Bool?,
                unavailableReason: String? = nil) {
        self.observedAt = observedAt
        self.bootIdentity = bootIdentity
        self.volumes = volumes
        self.memory = memory
        self.memoryUnavailableReason = memoryUnavailableReason
        self.swap = swap
        self.swapUnavailableReason = swapUnavailableReason
        self.pageOutRatePerSecond = pageOutRatePerSecond
        self.memoryPressureLevel = memoryPressureLevel
        self.thermalState = thermalState
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.unavailableReason = unavailableReason
    }
}

/// A safe rate from two cumulative-counter samples. This is the one
/// contract every cumulative-counter reading in this module goes through:
///
/// - a non-finite or non-positive elapsed time can't produce a rate;
/// - a counter that went down (`after < before`) is not "negative
///   pressure" -- it means the counter was reset (sleep/wake, reboot, or a
///   process restart), and the honest answer is "no rate yet," not a
///   fabricated negative number.
public func counterRate(before: UInt64, after: UInt64, seconds: Double) -> Double? {
    guard seconds.isFinite, seconds > 0, after >= before else { return nil }
    return Double(after - before) / seconds
}

/// Whether a headroom target is currently met by strict available space on
/// one volume. Deliberately binary and named "target met" rather than any
/// stronger claim: this is a live snapshot, not a guarantee that a build
/// that needs that much space will still fit by the time it runs, and it is
/// never presented as "buildable" or "safe to build now."
public enum HeadroomReadiness: Sendable, Equatable {
    case targetMet
    case belowTarget(shortfallBytes: Int64)
    case unavailable

    public static func evaluate(targetBytes: Int64?, availableBytes: Int64?) -> HeadroomReadiness {
        guard let targetBytes, targetBytes >= 0, let availableBytes, availableBytes >= 0 else {
            return .unavailable
        }
        return availableBytes >= targetBytes ? .targetMet : .belowTarget(shortfallBytes: targetBytes - availableBytes)
    }
}
