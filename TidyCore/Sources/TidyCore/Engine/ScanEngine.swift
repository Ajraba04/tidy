import Foundation

/// Runs every read-only scan concurrently and assembles a `ScanReport`.
/// Nothing here writes to disk.
public enum ScanEngine: Sendable {
    private static let largeFileThreshold: Int64 = 1_073_741_824

    public static func run(environment: CleanEnvironment) async -> ScanReport {
        let homeDirectory = environment.homeDirectory
        let protectedRoots = environment.protectedRoots

        async let diskStats = try? DiskStats.current()
        async let containerSpace = ContainerSpaceInfo.current()
        async let localSnapshots = SnapshotLister.listLocalSnapshots()
        async let idleRuntimes = SimctlClient.idleRuntimes()
        async let launchAgents = LaunchAgentsSurvey.userLaunchAgents(homeDirectory: homeDirectory)
        async let topProcesses = ProcessSurvey.topMemoryConsumers()
        async let restartOnly = RestartReclaimSurvey.current()
        async let staleNodeModules = StaleNodeModulesScanner.find(
            roots: environment.gitRoots,
            olderThanDays: environment.staleNodeModulesThresholdDays
        )

        // One walk per top-level entry, each producing its total, its large
        // files, and -- for `~/Library` only -- its per-child breakdown.
        // Previously this was three traversals that overlapped: the
        // top-level pass already covered `~/Library`, the Library pass
        // covered it again, and the large-file pass walked all of `$HOME` a
        // third time.
        let libraryPath = homeDirectory + "/Library"
        let includedEntries = LargestItemsScanner.homeTopLevelEntries(homeDirectory: homeDirectory)
        let excludedEntries = LargestItemsScanner.homeExcludedTopLevelEntries(homeDirectory: homeDirectory)

        let surveys = await withTaskGroup(of: (String, Bool, HomeSurvey.Result).self) { group in
            for path in includedEntries {
                group.addTask(priority: .utility) {
                    (path, true, HomeSurvey.walk(
                        root: path,
                        protectedRoots: protectedRoots,
                        largeFileThreshold: largeFileThreshold,
                        breakOutChildren: path == libraryPath
                    ))
                }
            }
            // Ranked nowhere, but still swept for large files, exactly as
            // the old whole-home walk did.
            for path in excludedEntries {
                group.addTask(priority: .utility) {
                    (path, false, HomeSurvey.walk(
                        root: path,
                        protectedRoots: protectedRoots,
                        largeFileThreshold: largeFileThreshold,
                        breakOutChildren: false
                    ))
                }
            }
            var collected: [(String, Bool, HomeSurvey.Result)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        let topLevelRanking = surveys
            .filter { $0.1 }
            .map { RankedItem(path: $0.0, bytes: $0.2.totalBytes) }
            .sorted { $0.bytes > $1.bytes }
            .prefix(8)

        // Kept as its own ranking rather than merged with the one above:
        // `~/Library` appears in both, and co-sorting them would present
        // the same bytes twice as if they were independent.
        let libraryRanking = (surveys.first { $0.0 == libraryPath }?.2.childTotals ?? [])
            .sorted { $0.bytes > $1.bytes }
            .prefix(6)

        let filesOver1GB = surveys
            .flatMap { $0.2.largeFiles }
            .sorted { $0.bytes > $1.bytes }
            .prefix(8)

        let measuredPaths = Dictionary(
            surveys.filter { $0.1 }.map { ($0.0, $0.2.totalBytes) },
            uniquingKeysWith: { first, _ in first }
        )
        async let unclaimed = UnclaimedSpaceScanner.find(
            measuredPaths: measuredPaths,
            environment: environment
        )

        return ScanReport(
            generatedAt: Date(),
            detectedTools: environment.detectedTools,
            diskStats: await diskStats,
            memoryStats: .current(),
            swapStats: SwapStats.current(),
            containerSpace: await containerSpace,
            topLevelHomeRanking: Array(topLevelRanking),
            libraryRanking: Array(libraryRanking),
            filesOver1GB: Array(filesOver1GB),
            localSnapshots: await localSnapshots,
            idleSimulatorRuntimes: await idleRuntimes,
            staleNodeModules: await staleNodeModules,
            launchAgents: await launchAgents,
            topMemoryConsumers: await topProcesses,
            restartOnlyReclaim: await restartOnly,
            unclaimedBySize: await unclaimed
        )
    }
}
