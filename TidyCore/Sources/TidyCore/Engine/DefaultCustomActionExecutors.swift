import Foundation

/// Wires each `CustomOperationID` the catalog references to its real
/// implementation. Kept separate from `CleanEngine` itself so the engine
/// never has to import browser- or git-specific logic directly.
public enum DefaultCustomActionExecutors: Sendable {
    public static func registerAll(on engine: CleanEngine) async {
        await engine.register(.chromeCookies) { target, environment in
            await Task.detached(priority: .utility) {
                let profile = ChromeProfile(name: (target.path as NSString).lastPathComponent, path: target.path)
                let outcome = ChromiumCookieCleaner.clean(
                    profile: profile,
                    keepDomains: environment.keepCookieDomains,
                    homeDirectory: environment.homeDirectory
                )
                return mapChromeCookieOutcome(outcome)
            }.value
        }

        await engine.register(.gitRepoGC) { target, _ in
            let result = await GitHousekeeper.runConservative(repoPath: target.path)
            return CustomActionOutcome(freedBytes: 0, succeeded: result.succeeded, message: result.message)
        }
    }

    private static func mapChromeCookieOutcome(_ outcome: ChromeCookieOutcome) -> CustomActionOutcome {
        switch outcome {
        case .skipped(let reason):
            return CustomActionOutcome(freedBytes: 0, succeeded: true, message: "skipped: \(reason)")
        case .cleaned(let total, let kept, let deleted):
            let message = deleted == 0
                ? "nothing to remove (\(kept) kept)"
                : "\(deleted) of \(total) cookies removed, \(kept) kept"
            return CustomActionOutcome(freedBytes: 0, succeeded: true, message: message)
        case .failed(let reason):
            return CustomActionOutcome(freedBytes: 0, succeeded: false, message: reason)
        case .failedAndNotRestored(let reason, let backupPath):
            return CustomActionOutcome(freedBytes: 0, succeeded: false, message: "\(reason) (unrestored backup at \(backupPath))")
        }
    }
}
