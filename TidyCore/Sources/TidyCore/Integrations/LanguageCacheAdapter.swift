import Foundation

public struct LanguageCacheAdapter: ToolAdapter {
    public static let adapterID = "language.caches"
    public static let contractVersion = "filesystem-v1"
    static let ecosystemID = "languages"

    public init() {}

    func inventory(context: ToolAdapterContext) throws -> [DeveloperInventoryEntry] {
        var result: [DeveloperInventoryEntry] = []
        for project in context.projects.records {
            let names: [(String, String, DeveloperResourceDisposition, String)] = [
                ("target", "cargo-target", .reportOnly,
                 "Cargo target ownership and custom target-dir overrides are unknown."),
                (".venv", "python-virtual-environment", .reportOnly,
                 "Virtual environments may contain local data and are permanently inventory-only."),
                ("venv", "python-virtual-environment", .reportOnly,
                 "Virtual environments may contain local data and are permanently inventory-only."),
                (".conda", "conda-environment", .reportOnly,
                 "Conda environments are permanently inventory-only."),
                ("vendor/bundle", "bundler-local", .reportOnly,
                 "Bundler local paths may contain project data and are inventory-only.")
            ]
            for (name, kind, disposition, reason) in names {
                guard let path = AdapterPaths.child(name, of: project, context: context),
                      let entry = context.entry(adapterID: Self.adapterID,
                        adapterVersion: Self.contractVersion, path: path, kind: kind,
                        disposition: disposition, reason: reason) else { continue }
                result.append(entry)
            }
        }
        for relative in [".cargo/registry/cache", ".cargo/git/db", ".cache/pip",
                         ".cache/uv", "go/pkg/mod", ".bundle/cache"] {
            guard let path = context.knownHomePath(relative),
                  let entry = context.entry(adapterID: Self.adapterID,
                    adapterVersion: Self.contractVersion, path: path,
                    kind: "language-shared-cache", disposition: .reportOnly,
                    reason: "Shared consumers and owner activity are unknown; broad cleanup is unavailable.")
            else { continue }
            result.append(entry)
        }
        return result
    }
}
