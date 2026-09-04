import Foundation

/// Legacy memory actions are quarantined. Every public helper reports the
/// fixed denial without executing a system command, quitting an application,
/// restarting macOS, or measuring reclaimed memory.
public enum MemoryReclaimer: Sendable {
    public struct Outcome: Sendable, Equatable {
        public let succeeded: Bool
        /// Always zero while memory actions are quarantined. It remains
        /// separate from disk bytes for source compatibility.
        public let reclaimedMemoryBytes: Int64
        public let message: String?

        public init(succeeded: Bool, reclaimedMemoryBytes: Int64, message: String?) {
            self.succeeded = succeeded
            self.reclaimedMemoryBytes = reclaimedMemoryBytes
            self.message = message
        }
    }

    /// Legacy purge entry point; always denied without a command or memory
    /// measurement.
    public static func purgeInactiveMemory(commandRunner: any CleanupCommandRunning = SystemCleanupCommandRunner()) async -> Outcome {
        deniedOutcome(action: .custom(.purgeInactiveMemory), itemID: "deep.memory.purge-inactive")
    }

    /// Legacy application-quit entry point; always denied without contacting
    /// the target application.
    public static func quitApplication(named name: String, commandRunner: any CleanupCommandRunning = SystemCleanupCommandRunner()) async -> Outcome {
        deniedOutcome(action: .custom(.quitMemoryHog), itemID: "deep.memory.quit-approved-apps")
    }

    /// Legacy restart entry point; always denied without restarting macOS or
    /// claiming any reclaimed swap.
    public static func restartToReclaimSwap(commandRunner: any CleanupCommandRunning = SystemCleanupCommandRunner()) async -> Outcome {
        deniedOutcome(action: .custom(.restartToReclaimSwap), itemID: "deep.memory.restart-for-swap")
    }

    private static func deniedOutcome(action: CleanAction, itemID: String) -> Outcome {
        Outcome(succeeded: false, reclaimedMemoryBytes: 0,
                message: CapabilityRegistry.denialReason(for: action, itemID: itemID) ?? CapabilityRegistry.quarantineReason)
    }
}
