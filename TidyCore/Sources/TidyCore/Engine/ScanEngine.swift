import Foundation

/// Runs every read-only scan concurrently and assembles a `ScanReport`.
/// Nothing here writes to disk.
public enum ScanEngine: Sendable {
    public static func run(environment: CleanEnvironment, sizeScanner: SizeScanner) async -> ScanReport {
        let homeDirectory = environment.homeDirectory
        let protectedRoots = environment.protectedRoots

        async let diskStats = try? DiskStats.current()
        async let containerSpace = ContainerSpaceInfo.current()
        async let localSnapshots = SnapshotLister.listLocalSnapshots()
        async let idleRuntimes = SimctlClient.idleRuntimes()
        async let launchAgents = LaunchAgentsSurvey.userLaunchAgents(homeDirectory: homeDirectory)
        async let topProcesses = ProcessSurvey.topMemoryConsumers()
        async let staleNodeModules = StaleNodeModulesScanner.find(
            roots: environment.gitRoots,
            olderThanDays: environment.staleNodeModulesThresholdDays
        )
        async let filesOver1GB = LargestItemsScanner.filesAtLeast(
            1_073_741_824,
            homeDirectory: homeDirectory,
            protectedRoots: protectedRoots,
            limit: 8
        )

        let topLevelPaths = LargestItemsScanner.homeTopLevelEntries(homeDirectory: homeDirectory)
        let libraryPaths = LargestItemsScanner.libraryEntries(homeDirectory: homeDirectory)

        async let topLevelResults = sizeScanner.scan(paths: topLevelPaths, protectedRoots: protectedRoots)
        async let libraryResults = sizeScanner.scan(paths: libraryPaths, protectedRoots: protectedRoots)

        let topLevelRanking = await topLevelResults
            .sorted { $0.bytes > $1.bytes }
            .prefix(8)
            .map { RankedItem(path: $0.path, bytes: $0.bytes) }

        let libraryRanking = await libraryResults
            .sorted { $0.bytes > $1.bytes }
            .prefix(6)
            .map { RankedItem(path: $0.path, bytes: $0.bytes) }

        return ScanReport(
            generatedAt: Date(),
            detectedTools: environment.detectedTools,
            diskStats: await diskStats,
            memoryStats: .current(),
            swapStats: SwapStats.current(),
            containerSpace: await containerSpace,
            topLevelHomeRanking: Array(topLevelRanking),
            libraryRanking: Array(libraryRanking),
            filesOver1GB: await filesOver1GB,
            localSnapshots: await localSnapshots,
            idleSimulatorRuntimes: await idleRuntimes,
            staleNodeModules: await staleNodeModules,
            launchAgents: await launchAgents,
            topMemoryConsumers: await topProcesses
        )
    }
}
