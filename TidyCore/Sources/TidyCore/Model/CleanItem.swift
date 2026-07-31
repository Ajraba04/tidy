/// A single catalog row: everything the shell script did with one `nuke`
/// call, one package-manager `cache clean`, or one bespoke block, expressed
/// as data instead of a script section.
public struct CleanItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let tier: Tier
    /// The declared root every target this item resolves must fall under.
    /// `PathGuard` enforces this before any deletion.
    public let declaredRoot: @Sendable (Environment) -> String?
    /// Hides this item when the relevant toolchain is not installed.
    public let requires: ToolchainID?
    /// Shown when this item is on by default but has a real consequence
    /// (e.g. "Next build recompiles everything").
    public let dangerNote: String?
    /// Shown for opt-in, deep-tier items (e.g. "~9 G re-download on next
    /// build").
    public let costNote: String?
    /// Resolves this item's targets on the current machine. May glob, may
    /// return zero targets if nothing is present. Read-only: locating a
    /// target never deletes anything.
    public let locate: @Sendable (Environment) -> [TargetPath]
    public let action: CleanAction

    public init(
        id: String,
        title: String,
        tier: Tier,
        requires: ToolchainID? = nil,
        dangerNote: String? = nil,
        costNote: String? = nil,
        declaredRoot: @escaping @Sendable (Environment) -> String?,
        locate: @escaping @Sendable (Environment) -> [TargetPath],
        action: CleanAction
    ) {
        self.id = id
        self.title = title
        self.tier = tier
        self.requires = requires
        self.dangerNote = dangerNote
        self.costNote = costNote
        self.declaredRoot = declaredRoot
        self.locate = locate
        self.action = action
    }

    public func isRelevant(in environment: Environment) -> Bool {
        guard let requires else { return true }
        return environment.hasTool(requires)
    }
}
