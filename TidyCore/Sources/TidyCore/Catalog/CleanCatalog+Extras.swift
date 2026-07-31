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
            locate: { env in
                let fm = FileManager.default
                var targets: [TargetPath] = []
                for root in env.gitRoots {
                    guard let projects = try? fm.contentsOfDirectory(atPath: root) else { continue }
                    for project in projects {
                        let projectPath = root + "/" + project
                        var isDirectory: ObjCBool = false
                        guard fm.fileExists(atPath: projectPath, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                        for relativeOutput in Self.buildOutputSubpaths {
                            let outputPath = projectPath + "/" + relativeOutput
                            guard fm.fileExists(atPath: outputPath) else { continue }
                            targets.append(TargetPath(
                                path: outputPath,
                                label: "build output: \(PathDisplay.tilde(projectPath, homeDirectory: env.homeDirectory))/\(relativeOutput)"
                            ))
                        }
                    }
                }
                return targets
            },
            action: .deletePath
        ))

        items.append(CleanItem(
            id: "normal.extras.stale-node-modules",
            title: "Stale node_modules (untouched 60+ days)",
            tier: .normal,
            requires: .node,
            declaredRoot: { env in env.homeDirectory },
            locate: { env in
                StaleNodeModulesScanner.find(roots: env.gitRoots, olderThanDays: env.staleNodeModulesThresholdDays)
            },
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
}
