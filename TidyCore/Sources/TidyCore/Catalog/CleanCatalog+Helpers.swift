import Foundation

extension CleanCatalog {
    /// A catalog item whose single target is a fixed path under the
    /// user's home directory (`~/Library/Caches/X`, `~/.npm/_cacache`, ...).
    /// Covers most of the shell script's plain `nuke`/`nuke_contents` calls.
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
            action: action
        )
    }

    /// A catalog item whose action is a package manager's own cache-clean
    /// subcommand rather than a path deletion. `estimateRelativePath`, when
    /// given, is measured for display only — the tool manages the actual
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
            action: .runTool(ToolCommand(tool, arguments))
        )
    }

    /// A catalog item whose targets are every entry under a directory
    /// matching a glob-like prefix (e.g. `~/.gradle/caches/build-cache-*`).
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
