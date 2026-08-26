import Foundation

/// Source-compatible denied registrations. Callbacks grant no capability and
/// cannot replace a coordinator-sealed operation.
public enum DefaultCustomActionExecutors: Sendable {
    public static func registerAll(on engine: CleanEngine, commandRunner: any CleanupCommandRunning = SystemCleanupCommandRunner()) async {
        for operation in CustomOperationID.allCases {
            await engine.register(operation) { _, _ in
                CustomActionOutcome(freedBytes: 0, succeeded: false, message: CapabilityRegistry.quarantineReason)
            }
        }
    }
}
