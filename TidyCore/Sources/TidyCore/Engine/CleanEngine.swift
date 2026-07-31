import Foundation

/// The result of a custom action running against one target.
public struct CustomActionOutcome: Sendable {
    public let freedBytes: Int64
    public let succeeded: Bool
    public let message: String?

    public init(freedBytes: Int64, succeeded: Bool, message: String? = nil) {
        self.freedBytes = freedBytes
        self.succeeded = succeeded
        self.message = message
    }
}

/// A `CustomOperationID`'s real implementation, registered with the engine
/// so bespoke logic (Chrome cookies, simulator pruning, git gc, APFS
/// snapshots — Phases 5 and 6) never has to live inside the engine itself.
public typealias CustomActionExecutor = @Sendable (TargetPath, CleanEnvironment) async -> CustomActionOutcome

/// Enumerates catalog items into a confirmable plan, then executes exactly
/// that plan. There is no other path to deletion: every mode, including a
/// pure dry-run preview, produces a `CleanPlan` first.
public actor CleanEngine {
    private let sizeScanner: SizeScanner
    private var customExecutors: [CustomOperationID: CustomActionExecutor] = [:]

    public init(sizeScanner: SizeScanner) {
        self.sizeScanner = sizeScanner
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
    /// Tiers are cumulative — matching the shell script, where sections 1–3
    /// and most of 5–7 run on every invocation and only a handful of
    /// flags are opt-in — so a Normal plan includes Safe items too, and a
    /// Deep plan includes Safe and Normal. `Tier` is `Comparable` in
    /// exactly this order for that reason.
    public func makePlan(items: [CleanItem], tier: Tier, environment: CleanEnvironment) async -> CleanPlan {
        let relevantItems = items.filter { $0.tier <= tier && $0.isRelevant(in: environment) }

        var plannedItems: [PlannedItem] = []
        plannedItems.reserveCapacity(relevantItems.count)

        for item in relevantItems {
            let declaredRoot = item.declaredRoot(environment)
            let rawTargets = item.locate(environment)

            let guardian = PathGuard(protectedRoots: environment.protectedRoots)
            let safeTargets = rawTargets.filter { target in
                guard target.isFilesystemPath else { return true }
                return guardian.isSafe(target.path, mustBeUnder: declaredRoot, home: environment.homeDirectory)
            }

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
                action: item.action
            ))
        }

        return CleanPlan(tier: tier, plannedItems: plannedItems)
    }

    /// Executes exactly the plan handed to it. Every target is re-validated
    /// against `PathGuard` immediately before deletion — defense in depth
    /// against however much time has passed since the plan was made.
    public func execute(plan: CleanPlan, environment: CleanEnvironment) async -> RunReport {
        let startedAt = Date()
        let freeBefore = (try? DiskStats.current().availableForImportantUsageBytes) ?? 0
        let guardian = PathGuard(protectedRoots: environment.protectedRoots)

        var results: [ItemResult] = []
        results.reserveCapacity(plan.plannedItems.count)

        // Every planned item runs, not just ones with non-empty targets:
        // a `.runTool` action (e.g. "npm cache clean --force") has no
        // target path by design — it is the tool's own job to know what to
        // clean — so filtering on `targets.isEmpty` would silently skip it.
        for item in plan.plannedItems {
            let result = await executeItem(item, guardian: guardian, environment: environment)
            results.append(result)
        }

        let freeAfter = (try? DiskStats.current().availableForImportantUsageBytes) ?? freeBefore

        return RunReport(
            tier: plan.tier,
            results: results,
            startedAt: startedAt,
            finishedAt: Date(),
            freeSpaceBeforeBytes: freeBefore,
            freeSpaceAfterBytes: freeAfter
        )
    }

    private func executeItem(
        _ item: PlannedItem,
        guardian: PathGuard,
        environment: CleanEnvironment
    ) async -> ItemResult {
        switch item.action {
        case .deletePath:
            return await deleteTargets(item, guardian: guardian, environment: environment, keepDirectory: false)

        case .deleteContents:
            return await deleteTargets(item, guardian: guardian, environment: environment, keepDirectory: true)

        case .runTool(let command):
            guard let executablePath = ToolLocator.locate(command.tool.executableName) else {
                return ItemResult(id: item.id, title: item.title, freedBytes: 0, succeeded: false, message: "\(command.tool.executableName) not found")
            }
            let succeeded = await ProcessRunner.runDiscardingOutput(
                executableURL: URL(fileURLWithPath: executablePath),
                arguments: command.arguments
            )
            return ItemResult(id: item.id, title: item.title, freedBytes: item.estimatedBytes, succeeded: succeeded, message: succeeded ? nil : "command failed")

        case .custom(let operationID):
            guard let executor = customExecutors[operationID] else {
                return ItemResult(id: item.id, title: item.title, freedBytes: 0, succeeded: false, message: "\(operationID.rawValue) has no registered handler")
            }
            var freed: Int64 = 0
            var succeeded = true
            var messages: [String] = []
            for target in item.targets {
                // Same defense-in-depth re-validation as deleteTargets,
                // for the custom actions whose targets are real paths
                // (Chrome profiles, git repos) rather than an opaque
                // identifier like a simulator UDID.
                if target.isFilesystemPath {
                    do {
                        try guardian.validate(target.path, home: environment.homeDirectory)
                    } catch {
                        succeeded = false
                        messages.append("\(target.path): \(error)")
                        continue
                    }
                }
                let outcome = await executor(target, environment)
                freed += outcome.freedBytes
                succeeded = succeeded && outcome.succeeded
                if let message = outcome.message { messages.append(message) }
            }
            return ItemResult(id: item.id, title: item.title, freedBytes: freed, succeeded: succeeded, message: messages.isEmpty ? nil : messages.joined(separator: "; "))
        }
    }

    private func deleteTargets(
        _ item: PlannedItem,
        guardian: PathGuard,
        environment: CleanEnvironment,
        keepDirectory: Bool
    ) async -> ItemResult {
        var freed: Int64 = 0
        var failures: [String] = []

        for target in item.targets {
            do {
                try guardian.validate(target.path, home: environment.homeDirectory)
            } catch {
                failures.append("\(target.path): \(error)")
                continue
            }

            let measured = await sizeScanner.scan(paths: [target.path], protectedRoots: environment.protectedRoots)
            let bytes = measured.first?.bytes ?? 0

            do {
                if keepDirectory {
                    try emptyDirectory(at: target.path)
                } else {
                    try FileManager.default.removeItem(atPath: target.path)
                }
                freed += bytes
            } catch {
                failures.append("\(target.path): \(error.localizedDescription)")
            }
        }

        return ItemResult(
            id: item.id,
            title: item.title,
            freedBytes: freed,
            succeeded: failures.isEmpty,
            message: failures.isEmpty ? nil : failures.joined(separator: "; ")
        )
    }

    private func emptyDirectory(at path: String) throws {
        let fm = FileManager.default
        let children = try fm.contentsOfDirectory(atPath: path)
        for child in children {
            try? fm.removeItem(atPath: path + "/" + child)
        }
    }
}
