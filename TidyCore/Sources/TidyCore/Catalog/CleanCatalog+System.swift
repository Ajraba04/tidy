import Foundation

extension CleanCatalog {
    static var system: CleanCategory {
        var items: [CleanItem] = []

        items.append(CleanItem(
            id: "deep.system.apfs-snapshots",
            title: "Delete APFS local snapshots",
            tier: .deep,
            dangerNote: "Needs an administrator password. Safe for your data: only discards Time Machine restore points, not files.",
            declaredRoot: { env in env.homeDirectory },
            locate: { _ in [] },
            action: .custom(.apfsSnapshots)
        ))

        items.append(fixedPathItem(
            id: "deep.system.claude-vm-bundles",
            title: "Claude Desktop vm_bundles",
            tier: .deep,
            costNote: "Re-downloads on next use",
            relativePath: "Library/Application Support/Claude/vm_bundles",
            declaredRootRelativePath: "Library/Application Support/Claude"
        ))

        items.append(fixedPathItem(
            id: "deep.system.claude-code-vm",
            title: "Claude Desktop claude-code-vm",
            tier: .deep,
            costNote: "Re-downloads on next use",
            relativePath: "Library/Application Support/Claude/claude-code-vm",
            declaredRootRelativePath: "Library/Application Support/Claude"
        ))

        return CleanCategory(id: "system", title: "System & VMs", items: items)
    }

    static func discoverLocalSnapshots(orchestration: CoreOrchestrationContext) async
      -> ActionDiscovery {
        do {
            let snapshots = try await orchestration.withCommand {
                guard let path = await ToolLocator.locateAsync("tmutil") else {
                    throw CoreOrchestrationError.schedulerUnavailable
                }
                let output = try await ProcessRunner.runLocalSnapshots(
                    tmutilURL: URL(fileURLWithPath: path), volumePath: "/")
                guard output.succeeded else { throw CoreOrchestrationError.schedulerUnavailable }
                let identifiers = output.standardOutput.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("com.apple.TimeMachine") }
                guard identifiers.count <= 64 else {
                    throw CoreOrchestrationError.invalidPolicySnapshot
                }
                return identifiers
            }
            guard !snapshots.isEmpty else {
                return ActionDiscovery(status: .noWork,
                    reason: "No APFS local snapshot was reported.", targets: [])
            }
            return ActionDiscovery(status: .available,
                reason: "The bounded snapshot command reported local restore points.",
                targets: [TargetPath(path: "apfs-snapshots", label: "APFS local snapshots",
                    isFilesystemPath: false)])
        } catch {
            return ActionDiscovery(status: .unavailable,
                reason: "The bounded snapshot command was unavailable or incomplete.", targets: [])
        }
    }
}
