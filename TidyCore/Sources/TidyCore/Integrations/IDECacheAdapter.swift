import Foundation

public struct IDECacheAdapter: ToolAdapter {
    public static let adapterID = "ide.caches"
    public static let contractVersion = "allowlist-v1"
    static let ecosystemID = "ides"

    public init() {}

    func inventory(context: ToolAdapterContext) throws -> [DeveloperInventoryEntry] {
        let candidates = [
            "Library/Application Support/Code/Cache",
            "Library/Application Support/Code/CachedData",
            "Library/Caches/JetBrains",
            "Library/Caches/com.microsoft.VSCode"
        ]
        return candidates.compactMap { relative in
            guard !relative.contains("workspaceStorage"), !relative.contains("extensions"),
                  let path = context.knownHomePath(relative) else { return nil }
            return context.entry(adapterID: Self.adapterID,
                adapterVersion: Self.contractVersion, path: path,
                kind: "ide-cache", disposition: .reportOnly,
                reason: "IDE owner/version/closed-state evidence is unavailable; workspace state and extensions are excluded.")
        }
    }
}
