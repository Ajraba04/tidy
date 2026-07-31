import Foundation

/// The full read-only "what's using space, what's still big, what's idle"
/// report — the app's Scan mode, and the shell script's sections 8–9. Zero
/// deletion code runs to produce this.
public struct ScanReport: Sendable {
    public let generatedAt: Date
    public let detectedTools: Set<ToolchainID>

    public let diskStats: DiskStats?
    public let memoryStats: MemoryStats
    public let swapStats: SwapStats?
    public let containerSpace: ContainerSpaceInfo?

    public let topLevelHomeRanking: [RankedItem]
    public let libraryRanking: [RankedItem]
    public let filesOver1GB: [RankedItem]

    public let localSnapshots: [LocalSnapshot]
    public let idleSimulatorRuntimes: [SimulatorRuntime]
    public let staleNodeModules: [TargetPath]
    public let launchAgents: [String]
    public let topMemoryConsumers: [ProcessUsage]

    public init(
        generatedAt: Date,
        detectedTools: Set<ToolchainID>,
        diskStats: DiskStats?,
        memoryStats: MemoryStats,
        swapStats: SwapStats?,
        containerSpace: ContainerSpaceInfo?,
        topLevelHomeRanking: [RankedItem],
        libraryRanking: [RankedItem],
        filesOver1GB: [RankedItem],
        localSnapshots: [LocalSnapshot],
        idleSimulatorRuntimes: [SimulatorRuntime],
        staleNodeModules: [TargetPath],
        launchAgents: [String],
        topMemoryConsumers: [ProcessUsage]
    ) {
        self.generatedAt = generatedAt
        self.detectedTools = detectedTools
        self.diskStats = diskStats
        self.memoryStats = memoryStats
        self.swapStats = swapStats
        self.containerSpace = containerSpace
        self.topLevelHomeRanking = topLevelHomeRanking
        self.libraryRanking = libraryRanking
        self.filesOver1GB = filesOver1GB
        self.localSnapshots = localSnapshots
        self.idleSimulatorRuntimes = idleSimulatorRuntimes
        self.staleNodeModules = staleNodeModules
        self.launchAgents = launchAgents
        self.topMemoryConsumers = topMemoryConsumers
    }
}
