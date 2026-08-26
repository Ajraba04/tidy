import Foundation

extension CleanCatalog {
    static func fixedPathItem(
        id: String,
        title: String,
        tier: Tier,
        requires: ToolchainID? = nil,
        dangerNote: String? = nil,
        costNote: String? = nil,
        relativePath: String,
        declaredRootRelativePath: String,
        action: CleanAction = .deletePath
    ) -> CleanItem {
        CleanItem(
            id: id,
            title: title,
            tier: tier,
            requires: requires,
            dangerNote: dangerNote,
            costNote: costNote,
            declaredRoot: { env in env.homeDirectory + "/" + declaredRootRelativePath },
            locate: { env in
                let path = env.homeDirectory + "/" + relativePath
                guard FileManager.default.fileExists(atPath: path) else { return [] }
                return [TargetPath(path: path, label: "~/" + relativePath)]
            },
            action: action,
            discover: { env in
                let path = env.homeDirectory + "/" + relativePath
                do {
                    _ = try FileManager.default.attributesOfItem(atPath: path)
                    return ActionDiscovery(status: .available, reason: "Path found; execution requires an accepted contract.", targets: [TargetPath(path: path, label: "~/" + relativePath)])
                } catch let error as NSError where error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError {
                    return ActionDiscovery(status: .noWork, reason: "No matching path exists.", targets: [])
                } catch {
                    return ActionDiscovery(status: .unavailable, reason: "The path could not be inspected.", targets: [])
                }
            }
        )
    }

    /// A catalog item whose action is a package manager's own cache-clean
    /// subcommand rather than a path deletion. `estimateRelativePath`, when
    /// given, is measured for display only: the tool manages the actual
    /// deletion.
    static func toolRunItem(
        id: String,
        title: String,
        tier: Tier,
        requires: ToolchainID,
        tool: ToolID,
        arguments: [String],
        estimateRelativePath: String? = nil
    ) -> CleanItem {
        CleanItem(
            id: id,
            title: title,
            tier: tier,
            requires: requires,
            declaredRoot: { env in
                if let estimateRelativePath {
                    return env.homeDirectory + "/" + estimateRelativePath
                }
                return env.homeDirectory
            },
            locate: { env in
                guard let estimateRelativePath else { return [] }
                let path = env.homeDirectory + "/" + estimateRelativePath
                guard FileManager.default.fileExists(atPath: path) else { return [] }
                return [TargetPath(path: path, label: title)]
            },
            action: .runTool(ToolCommand(tool, arguments)),
            discover: { env in
                let targets: [TargetPath]
                if let estimateRelativePath {
                    let path = env.homeDirectory + "/" + estimateRelativePath
                    targets = FileManager.default.fileExists(atPath: path) ? [TargetPath(path: path, label: title)] : []
                } else {
                    targets = []
                }
                return ActionDiscovery(status: .available, reason: "Tool action requires an accepted exact-scope contract.", targets: targets)
            }
        )
    }

    static func globPrefixItem(
        id: String,
        title: String,
        tier: Tier,
        requires: ToolchainID? = nil,
        directoryRelativePath: String,
        prefixes: [String],
        declaredRootRelativePath: String
    ) -> CleanItem {
        CleanItem(
            id: id,
            title: title,
            tier: tier,
            requires: requires,
            declaredRoot: { env in env.homeDirectory + "/" + declaredRootRelativePath },
            locate: { env in
                let directory = env.homeDirectory + "/" + directoryRelativePath
                guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
                return entries
                    .filter { name in prefixes.contains { name.hasPrefix($0) } }
                    .map { name in
                        TargetPath(path: directory + "/" + name, label: "~/" + directoryRelativePath + "/" + name)
                    }
            },
            action: .deletePath
        )
    }
}
