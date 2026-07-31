/// A named grouping of catalog items for display (e.g. "Developer tool
/// caches", "Browsers", "Xcode & Simulators").
public struct CleanCategory: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let items: [CleanItem]

    public init(id: String, title: String, items: [CleanItem]) {
        self.id = id
        self.title = title
        self.items = items
    }

    public func items(in tier: Tier) -> [CleanItem] {
        items.filter { $0.tier == tier }
    }

    public func relevantItems(in environment: CleanEnvironment) -> [CleanItem] {
        items.filter { $0.isRelevant(in: environment) }
    }
}
