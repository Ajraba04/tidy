import Foundation

extension CleanCatalog {
    static var extras: CleanCategory {
        var items: [CleanItem] = []

        items.append(fixedPathItem(
            id: "normal.trash.empty",
            title: "Empty Trash",
            tier: .normal,
            dangerNote: "Permanent. There is no second bin behind this one",
            relativePath: ".Trash",
            declaredRootRelativePath: ".Trash",
            action: .deleteContents
        ))

        items.append(CleanItem(
            id: "normal.extras.build-outputs",
            title: "Build output directories in your project roots",
            tier: .normal,
            declaredRoot: { env in env.homeDirectory },
            locate: { _ in [] },
            action: .deletePath
        ))

        items.append(CleanItem(
            id: "normal.extras.stale-node-modules",
            title: "Stale node_modules (untouched 60+ days)",
            tier: .normal,
            requires: .node,
            declaredRoot: { env in env.homeDirectory },
            locate: { _ in [] },
            action: .deletePath
        ))

        items.append(CleanItem(
            id: "normal.extras.old-transcripts",
            title: "Old Claude Code session transcripts (memory/ is never touched)",
            tier: .normal,
            declaredRoot: { env in env.homeDirectory + "/.claude/projects" },
            locate: { env in
                TranscriptPruneScanner.findOldTranscripts(
                    claudeProjectsDirectory: env.homeDirectory + "/.claude/projects",
                    olderThanDays: env.transcriptAgeThresholdDays
                )
            },
            action: .deletePath
        ))

        return CleanCategory(id: "extras", title: "Projects & Trash", items: items)
    }

    static let buildOutputSubpaths = [
        "build", ".next", "dist", ".dart_tool", ".expo",
        "android/build", "android/app/build", "ios/Pods", "ios/build",
        ".gradle", "target", "out"
    ]

    static func discoverBuildOutputs(environment: CleanEnvironment,
                                     orchestration: CoreOrchestrationContext) async
      -> ActionDiscovery {
        guard environment.gitRoots.count <= 64 else {
            return unavailableBoundedCatalogDiscovery()
        }
        let expected = Set(buildOutputSubpaths)
        var targets: [TargetPath] = []
        for root in environment.gitRoots {
            let limits = orchestration.traversalLimits.replacing(maxDepth: 4, topN: 0)
            let traversal = BoundedTraversal(sessions: orchestration.sessions, limits: limits)
            let result = await traversal.start(root: root, session: orchestration.session,
                sessionID: orchestration.sessionID, generation: orchestration.generation,
                options: TraversalOptions(recordSelection: .all))
            var reasons = result.coverage.reasons
            reasons.remove(.missing)
            guard result.cursor == nil, reasons.isEmpty else {
                await traversal.invalidate(sessionID: orchestration.sessionID)
                return unavailableBoundedCatalogDiscovery()
            }
            let projectDirectories = Set(result.records.filter {
                $0.depth == 1 && $0.kind == .directory
            }.map(\.relativePath))
            for record in result.records {
                let components = record.relativePath.split(separator: "/").map(String.init)
                guard components.count >= 2, projectDirectories.contains(components[0]) else {
                    continue
                }
                let output = components.dropFirst().joined(separator: "/")
                guard expected.contains(output) else { continue }
                let projectPath = PathGuard.canonicalize(root) + "/" + components[0]
                let display = PathDisplay.tilde(projectPath,
                    homeDirectory: environment.homeDirectory)
                targets.append(TargetPath(path: record.path,
                    label: "build output: \(display)/\(output)"))
            }
            if targets.count > orchestration.traversalLimits.resultRecords {
                return unavailableBoundedCatalogDiscovery()
            }
        }
        let unique = Dictionary(targets.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in
            first
        }).values.sorted { $0.path < $1.path }
        return unique.isEmpty
            ? ActionDiscovery(status: .noWork, reason: "No matching path exists.", targets: [])
            : ActionDiscovery(status: .available,
                reason: "Bounded project discovery found build output paths.",
                targets: unique)
    }

    static func discoverStaleNodeModules(environment: CleanEnvironment,
                                         orchestration: CoreOrchestrationContext) async
      -> ActionDiscovery {
        guard environment.gitRoots.count <= 64 else {
            return unavailableBoundedCatalogDiscovery()
        }
        var targets: [TargetPath] = []
        for root in environment.gitRoots {
            guard let page = await StaleNodeModulesScanner.findBounded(root: root,
                olderThanDays: environment.staleNodeModulesThresholdDays,
                sessions: orchestration.sessions, session: orchestration.session,
                sessionID: orchestration.sessionID, generation: orchestration.generation,
                limits: orchestration.traversalLimits) else { continue }
            var reasons = page.result.coverage.reasons
            reasons.remove(.missing)
            guard page.result.cursor == nil, reasons.isEmpty else {
                await page.traversal.invalidate(sessionID: orchestration.sessionID)
                return unavailableBoundedCatalogDiscovery()
            }
            targets.append(contentsOf: page.result.records.map {
                TargetPath(path: $0.path, label: $0.path)
            })
            if targets.count > orchestration.traversalLimits.resultRecords {
                return unavailableBoundedCatalogDiscovery()
            }
        }
        let unique = Dictionary(targets.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in
            first
        }).values.sorted { $0.path < $1.path }
        return unique.isEmpty
            ? ActionDiscovery(status: .noWork, reason: "No stale node_modules path exists.",
                targets: [])
            : ActionDiscovery(status: .available,
                reason: "Bounded project discovery found stale node_modules paths.",
                targets: unique)
    }

    private static func unavailableBoundedCatalogDiscovery() -> ActionDiscovery {
        ActionDiscovery(status: .unavailable,
            reason: "The bounded discovery was incomplete; no truncated target set was presented.",
            targets: [])
    }
}
