import Foundation

public struct GitHousekeepingResult: Sendable {
    public let repoPath: String
    public let succeeded: Bool
    public let message: String?
}

/// Git housekeeping is quarantined. The public entry points preserve their
/// result shape but do not invoke Git or mutate repository files.
public enum GitHousekeeper: Sendable {
    /// Normal-tier legacy entry point; always denied pending an accepted
    /// exact-scope Git adapter contract.
    public static func runConservative(repoPath: String, commandRunner: any CleanupCommandRunning = SystemCleanupCommandRunner()) async -> GitHousekeepingResult {
        await run(repoPath: repoPath, reflogArguments: ["--expire=90.days", "--expire-unreachable=30.days", "--all"], commandRunner: commandRunner)
    }

    /// Deep-tier legacy entry point; always denied pending an accepted
    /// exact-scope Git adapter contract.
    public static func runAggressiveReflogExpiry(repoPath: String, commandRunner: any CleanupCommandRunning = SystemCleanupCommandRunner()) async -> GitHousekeepingResult {
        await run(repoPath: repoPath, reflogArguments: ["--expire=now", "--expire-unreachable=now", "--all"], commandRunner: commandRunner)
    }

    private static func run(repoPath: String, reflogArguments: [String], commandRunner: any CleanupCommandRunning) async -> GitHousekeepingResult {
        let action: CleanAction = reflogArguments.contains("--expire=now") ? .custom(.gitReflogExpireAggressive) : .custom(.gitRepoGC)
        let itemID = reflogArguments.contains("--expire=now") ? "deep.git.reflog-expire-all" : "normal.git.housekeeping"
        return GitHousekeepingResult(repoPath: repoPath, succeeded: false,
                                     message: CapabilityRegistry.denialReason(for: action, itemID: itemID) ?? CapabilityRegistry.quarantineReason)
    }
}
