import Foundation

/// Wires each `CustomOperationID` the catalog references to its real
/// implementation. Kept separate from `CleanEngine` itself so the engine
/// never has to import browser- or git-specific logic directly.
public enum DefaultCustomActionExecutors: Sendable {
    public static func registerAll(on engine: CleanEngine, commandRunner: any CleanupCommandRunning = SystemCleanupCommandRunner()) async {
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
            let result = await GitHousekeeper.runConservative(repoPath: target.path, commandRunner: commandRunner)
            return CustomActionOutcome(freedBytes: 0, succeeded: result.succeeded, message: result.message)
        }

        await engine.register(.gitReflogExpireAggressive) { target, _ in
            let result = await GitHousekeeper.runAggressiveReflogExpiry(repoPath: target.path, commandRunner: commandRunner)
            return CustomActionOutcome(freedBytes: 0, succeeded: result.succeeded, message: result.message)
        }

        await engine.register(.simulatorPrune) { target, _ in
            // target.path carries the device UDID, not a filesystem path.
            // See CleanCatalog+Xcode.swift, which sets isFilesystemPath:
            // false for exactly this reason.
            let succeeded = await SimulatorPruner.deleteDevice(udid: target.path, commandRunner: commandRunner)
            return CustomActionOutcome(freedBytes: 0, succeeded: succeeded, message: succeeded ? nil : "could not delete \(target.label)")
        }

        await engine.register(.apfsSnapshots) { _, _ in
            return CustomActionOutcome(freedBytes: 0, succeeded: false, message: CapabilityRegistry.quarantineReason)
        }

        await engine.register(.purgeInactiveMemory) { _, _ in
            let outcome = await MemoryReclaimer.purgeInactiveMemory(commandRunner: commandRunner)
            return mapMemoryOutcome(outcome)
        }

        await engine.register(.quitMemoryHog) { target, _ in
            // target.path carries the application name, not a path.
            let outcome = await MemoryReclaimer.quitApplication(named: target.path, commandRunner: commandRunner)
            return mapMemoryOutcome(outcome)
        }

        await engine.register(.restartToReclaimSwap) { _, _ in
            let outcome = await MemoryReclaimer.restartToReclaimSwap(commandRunner: commandRunner)
            return mapMemoryOutcome(outcome)
        }
    }

    /// Memory outcomes report zero disk bytes by construction: freeing RAM
    /// frees no disk, and letting a memory figure reach `freedBytes` would
    /// inflate the disk total the results screen shows.
    private static func mapMemoryOutcome(_ outcome: MemoryReclaimer.Outcome) -> CustomActionOutcome {
        CustomActionOutcome(
            freedBytes: 0,
            reclaimedMemoryBytes: outcome.reclaimedMemoryBytes,
            succeeded: outcome.succeeded,
            message: outcome.message
        )
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
