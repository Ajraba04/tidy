import Foundation

public struct GitHousekeepingResult: Sendable {
    public let repoPath: String
    public let succeeded: Bool
    public let message: String?
}

/// Per-repo git maintenance: prune remote-tracking refs for branches
/// deleted upstream (so their objects become unreachable and `gc` can
/// actually reclaim them), expire reflogs, `gc --prune=now`, prune stale
/// worktrees, and clean up lock files left behind by an interrupted
/// operation, matching the shell script's git housekeeping.
public enum GitHousekeeper: Sendable {
    /// Normal tier: reflogs expire on the usual schedule (90 days
    /// reachable, 30 days unreachable), so `git reset`-based undo survives
    /// for a while.
    public static func runConservative(repoPath: String) async -> GitHousekeepingResult {
        await run(repoPath: repoPath, reflogArguments: ["--expire=90.days", "--expire-unreachable=30.days", "--all"])
    }

    /// Deep tier, opt-in: nothing survives. There is no `git reset` rescue
    /// after this.
    public static func runAggressiveReflogExpiry(repoPath: String) async -> GitHousekeepingResult {
        await run(repoPath: repoPath, reflogArguments: ["--expire=now", "--expire-unreachable=now", "--all"])
    }

    private static func run(repoPath: String, reflogArguments: [String]) async -> GitHousekeepingResult {
        guard let gitPath = ToolLocator.locate("git") else {
            return GitHousekeepingResult(repoPath: repoPath, succeeded: false, message: "git not found")
        }
        let git = URL(fileURLWithPath: gitPath)

        func runGit(_ arguments: [String]) async -> ProcessRunner.Output? {
            try? await ProcessRunner.run(executableURL: git, arguments: ["-C", repoPath] + arguments)
        }

        guard let remoteList = await runGit(["remote"]), remoteList.succeeded else {
            return GitHousekeepingResult(repoPath: repoPath, succeeded: false, message: "not a usable git repository")
        }

        let remotes = remoteList.standardOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for remote in remotes {
            _ = await runGit(["remote", "prune", remote])
        }

        _ = await runGit(["reflog", "expire"] + reflogArguments)
        let gcResult = await runGit(["gc", "--prune=now", "--quiet"])
        _ = await runGit(["worktree", "prune"])

        let fm = FileManager.default
        try? fm.removeItem(atPath: repoPath + "/.git/gc.log")
        try? fm.removeItem(atPath: repoPath + "/.git/index.lock")

        let succeeded = gcResult?.succeeded ?? false
        let message: String?
        if succeeded {
            message = nil
        } else if let stderr = gcResult?.standardError, !stderr.isEmpty {
            message = stderr
        } else {
            message = "git gc failed"
        }

        return GitHousekeepingResult(repoPath: repoPath, succeeded: succeeded, message: message)
    }
}
