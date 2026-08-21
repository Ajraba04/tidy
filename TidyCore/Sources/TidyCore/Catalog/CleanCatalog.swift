/// The declarative list of everything Tidy knows how to clean. Populated
/// incrementally: safe-tier rows, then normal-tier, then deep-tier, each
/// alongside the engine code that can act on them.
public enum CleanCatalog: Sendable {
    public static var categories: [CleanCategory] {
        [
            safeCaches,
            browsers,
            xcodeAndSimulators,
            gitCleanup,
            extras,
            android,
            dependencyCaches,
            system,
            memory
        ]
    }

    public static var allItems: [CleanItem] {
        categories.flatMap(\.items)
    }

    public static func items(in tier: Tier) -> [CleanItem] {
        allItems.filter { $0.tier == tier }
    }
}
