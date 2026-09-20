import Foundation

public struct DataDirectoryAdapter: ToolAdapter {
    public static let adapterID = "data.directories"
    public static let contractVersion = "markers-v1"
    static let ecosystemID = "data"

    public init() {}

    func inventory(context: ToolAdapterContext) throws -> [DeveloperInventoryEntry] {
        var candidates: [(String, String)] = []
        for project in context.projects.records {
            for (name, kind) in [
                ("postgres", "database-directory"), ("data", "data-directory"),
                ("vm", "virtual-machine-directory"), ("VMs", "virtual-machine-directory")
            ] {
                if let path = AdapterPaths.child(name, of: project, context: context) {
                    candidates.append((path, kind))
                }
            }
        }
        for relative in ["Library/Application Support/Postgres",
                         "Library/Application Support/UTM",
                         "Parallels", "Virtual Machines.localized"] {
            if let path = context.knownHomePath(relative) {
                candidates.append((path, relative.contains("Postgres")
                    ? "database-directory" : "virtual-machine-directory"))
            }
        }
        return candidates.compactMap { path, kind in
            context.entry(adapterID: Self.adapterID,
                adapterVersion: Self.contractVersion, path: path, kind: kind,
                disposition: .reportOnly,
                reason: "Database and virtual-machine data are permanent inventory-only resources.")
        }
    }
}
