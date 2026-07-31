extension CleanCatalog {
    /// Section 7b (APFS local snapshots) and the Claude Desktop VM bundle
    /// from section 6 — both Deep-tier, opt-in, with the largest
    /// individual costs in the whole catalog.
    static var system: CleanCategory {
        var items: [CleanItem] = []

        items.append(CleanItem(
            id: "deep.system.apfs-snapshots",
            title: "Delete APFS local snapshots",
            tier: .deep,
            dangerNote: "Needs an administrator password. Safe for your data — only discards Time Machine restore points, not files.",
            declaredRoot: { env in env.homeDirectory },
            locate: { env in
                // Snapshots aren't part of the filesystem tree SizeScanner
                // measures, so there's no byte estimate here — only
                // whether any exist. The executor re-lists and deletes
                // them together in one administrator-privileged call, so
                // exactly one prompt appears no matter how many there are.
                guard SnapshotLister.hasLocalSnapshotsSync() else { return [] }
                return [TargetPath(path: "apfs-snapshots", label: "APFS local snapshots", isFilesystemPath: false)]
            },
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
}
