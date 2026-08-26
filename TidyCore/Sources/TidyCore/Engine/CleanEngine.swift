import Foundation

/// The result of a custom action running against one target.
public struct CustomActionOutcome: Sendable {
    public let freedBytes: Int64
    /// RAM returned, tracked separately from `freedBytes` so disk and
    /// memory are never summed into one figure. A combined total would
    /// overstate the disk result and misrepresent the memory one.
    public let reclaimedMemoryBytes: Int64
    public let succeeded: Bool
    public let message: String?

    public init(
        freedBytes: Int64,
        reclaimedMemoryBytes: Int64 = 0,
        succeeded: Bool,
        message: String? = nil
    ) {
        self.freedBytes = freedBytes
        self.reclaimedMemoryBytes = reclaimedMemoryBytes
        self.succeeded = succeeded
        self.message = message
    }
}

/// A `CustomOperationID`'s real implementation, registered with the engine
/// so bespoke logic (Chrome cookies, simulator pruning, git gc, APFS
/// snapshots) never has to live inside the engine itself.
public typealias CustomActionExecutor = @Sendable (TargetPath, CleanEnvironment) async -> CustomActionOutcome

/// Enumerates catalog items into a confirmable plan. Execution currently
/// stops at the fixed quarantine boundary; no current plan gains cleanup
/// authority.
public actor CleanEngine {
    private let sizeScanner: SizeScanner
    private let commandRunner: any CleanupCommandRunning
    private var customExecutors: [CustomOperationID: CustomActionExecutor] = [:]

    public init(sizeScanner: SizeScanner, commandRunner: any CleanupCommandRunning = SystemCleanupCommandRunner()) {
        self.sizeScanner = sizeScanner
        self.commandRunner = commandRunner
    }

    public func register(_ operation: CustomOperationID, executor: @escaping CustomActionExecutor) {
        customExecutors[operation] = executor
    }

    public func hasExecutor(for operation: CustomOperationID) -> Bool {
        customExecutors[operation] != nil
    }

    /// Locates and measures every relevant item's targets. Read-only:
    /// nothing is deleted, moved, or modified.
    ///
    /// Tiers are cumulative, matching the shell script, where sections 1-3
    /// and most of 5-7 run on every invocation and only a handful of
    /// flags are opt-in. A Normal plan includes Safe items too, and a
    /// Deep plan includes Safe and Normal. `Tier` is `Comparable` in
    /// exactly this order for that reason.
    public func makePlan(items: [CleanItem], tier: Tier, environment: CleanEnvironment) async -> CleanPlan {
        let relevantItems = items.filter { $0.tier <= tier }

        var plannedItems: [PlannedItem] = []
        plannedItems.reserveCapacity(relevantItems.count)

        for item in relevantItems {
            let declaredRoot = item.declaredRoot(environment)
            let discovery: ActionDiscovery
            if let requiredTool = item.requires, !environment.hasTool(requiredTool) {
                discovery = ActionDiscovery(status: .unavailable, reason: "Required toolchain is not available.", targets: [])
            } else if case .unavailable(let reason) = item.action {
                discovery = ActionDiscovery(status: .unavailable, reason: reason, targets: [])
            } else if let explicitDiscovery = item.discover {
                discovery = explicitDiscovery(environment)
            } else {
                switch item.action {
                case .deletePath, .deleteContents:
                    let targets = item.locate(environment)
                    discovery = targets.isEmpty
                        ? ActionDiscovery(status: .unavailable, reason: CapabilityRegistry.quarantineReason, targets: [])
                        : ActionDiscovery(status: .available, reason: "Path found; execution requires an accepted contract.", targets: targets)
                case .runTool, .custom, .unavailable:
                    discovery = ActionDiscovery(status: .unavailable, reason: CapabilityRegistry.quarantineReason, targets: [])
                }
            }

            let guardian = PathGuard(protectedRoots: environment.protectedRoots)
            let safeTargets = discovery.targets.filter { target in
                guard target.isFilesystemPath else { return true }
                return guardian.isSafe(target.path, mustBeUnder: declaredRoot, home: environment.homeDirectory)
            }
            let rejectedTarget = discovery.targets.filter(\.isFilesystemPath).count != safeTargets.filter(\.isFilesystemPath).count
            let status: ReviewStatus
            let reason: String
            if rejectedTarget {
                status = .blocked; reason = "One or more targets failed path protection checks."
            } else if discovery.status == .available, CapabilityRegistry.denialReason(for: item.action, itemID: item.id) != nil {
                status = .unavailable; reason = CapabilityRegistry.quarantineReason
            } else {
                status = discovery.status; reason = discovery.reason
            }
            let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "No review explanation is available."
                : reason

            let measurablePaths = safeTargets.filter(\.isFilesystemPath).map(\.path)
            var estimatedBytes: Int64 = 0
            if !measurablePaths.isEmpty {
                let results = await sizeScanner.scan(paths: measurablePaths, protectedRoots: environment.protectedRoots)
                estimatedBytes = results.reduce(0) { $0 + $1.bytes }
            }

            plannedItems.append(PlannedItem(
                id: item.id,
                title: item.title,
                tier: item.tier,
                dangerNote: item.dangerNote,
                costNote: item.costNote,
                targets: safeTargets,
                estimatedBytes: estimatedBytes,
                action: item.action,
                declaredRoot: declaredRoot,
                review: ActionDescriptor(id: item.id, status: status, reason: normalizedReason, requiresPerRunOptIn: item.action.requiresPerRunOptIn)
            ))
        }

        return CleanPlan(tier: tier, plannedItems: plannedItems)
    }

    /// Internal denial-only compatibility for quarantine regression tests.
    /// This entry can never become an effect route, including after adapter acceptance.
    internal func execute(plan: CleanPlan, environment: CleanEnvironment) async -> RunReport {
        let results = plan.plannedItems.map {
            ItemResult(id: $0.id, title: $0.title, freedBytes: 0, succeeded: false,
                       message: CapabilityRegistry.quarantineReason)
        }
        return RunReport(tier: plan.tier, results: results, startedAt: Date(), finishedAt: Date(),
                         freeSpaceBeforeBytes: 0, freeSpaceAfterBytes: 0,
                         disposition: .unavailableSelection, coordinatorMeasurementsAvailable: false)
    }
}
