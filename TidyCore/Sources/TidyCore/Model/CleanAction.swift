/// A resolvable command-line tool a `CleanAction.runTool` case can invoke.
/// `ToolLocator` resolves the identifier to an absolute path; if it cannot,
/// the item renders as "not found" rather than falling back to a shell.
public enum ToolID: String, Codable, Sendable, CaseIterable {
    case npm
    case brew
    case pod
    case uv
    case pnpm
    case deno
    case pip3
    case flutter
    case go
    case qlmanage
    case xcrun
    case git
    case tmutil
    case diskutil
    case osascript

    public var executableName: String { rawValue }
}

public struct ToolCommand: Sendable {
    public let tool: ToolID
    public let arguments: [String]

    public init(_ tool: ToolID, _ arguments: [String] = []) {
        self.tool = tool
        self.arguments = arguments
    }
}

/// A cleanup operation with logic too specific to express as a plain path
/// delete, implemented in `Engine` and `Browsers`, never inline in the
/// catalog. Simple path-based items (Trash, build outputs, stale
/// node_modules, old transcripts) don't need a case here: they use
/// `deletePath`/`deleteContents` instead.
public enum CustomOperationID: String, Codable, Sendable, CaseIterable {
    case chromeCookies
    case simulatorPrune
    case gitRepoGC
    case gitReflogExpireAggressive
    case apfsSnapshots
    case purgeInactiveMemory
    case quitMemoryHog
    case restartToReclaimSwap
}

/// What a `CleanItem` does once its targets have been located and confirmed.
public enum CleanAction: Sendable {
    case deletePath
    /// Empties a directory's contents but keeps the directory itself.
    case deleteContents
    /// Runs a tool's own cache-clean subcommand so its index/DB stays
    /// consistent (e.g. `npm cache clean --force`).
    case runTool(ToolCommand)
    case custom(CustomOperationID)
    case unavailable(reason: String)

    public var requiresPerRunOptIn: Bool {
        switch self {
        case .custom(.purgeInactiveMemory), .custom(.restartToReclaimSwap): true
        default: false
        }
    }
}
