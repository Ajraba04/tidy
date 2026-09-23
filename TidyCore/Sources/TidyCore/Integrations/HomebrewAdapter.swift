import Foundation

public struct HomebrewAdapter: ToolAdapter {
    public static let adapterID = "homebrew"
    public static let contractVersion = "filesystem-v1"
    static let ecosystemID = "homebrew"

    public init() {}

    func inventory(context: ToolAdapterContext) throws -> [DeveloperInventoryEntry] {
        let candidates = [
            context.environment.path("Library/Caches/Homebrew"),
            "/opt/homebrew/Cellar", "/usr/local/Cellar"
        ]
        return AdapterPaths.existing(candidates, context: context).compactMap { path in
            let cache = path.hasSuffix("/Library/Caches/Homebrew")
            return context.entry(adapterID: Self.adapterID,
                adapterVersion: Self.contractVersion, path: path,
                kind: cache ? "homebrew-download-cache" : "homebrew-installed-cellar",
                disposition: .reportOnly,
                reason: "Homebrew version, ownership, and exact cleanup effects are unavailable; broad brew cleanup is disabled.")
        }
    }
}
