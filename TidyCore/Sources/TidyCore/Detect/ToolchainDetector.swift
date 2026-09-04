import Foundation

/// Detects which developer tools and apps are present on this machine, so
/// catalog items requiring an absent tool can hide themselves.
public enum ToolchainDetector: Sendable {
    private static let commandTools: [(String, ToolchainID)] = [
        ("brew", .homebrew), ("node", .node), ("npm", .npm), ("pnpm", .pnpm),
        ("yarn", .yarn), ("bun", .bun), ("pod", .cocoapods), ("pip3", .pip),
        ("uv", .uv), ("deno", .deno), ("go", .go), ("flutter", .flutter),
        ("dart", .dart), ("git", .git)
    ]

    /// Compatibility path for synchronous app/catalog owners. It performs
    /// fixed filesystem checks only and never launches discovery work. T08.5
    /// owns moving the onboarding caller to `detectAsync`.
    public static func detect(homeDirectory: String = NSHomeDirectory()) -> Set<ToolchainID> {
        var found = localTools(homeDirectory: homeDirectory)
        for (name, tool) in commandTools where ToolLocator.isAvailable(name) {
            found.insert(tool)
        }
        return found
    }

    /// Full onboarding discovery. Xcode-owned fallbacks flow through the
    /// declared, bounded ProcessRunner route and never block a cooperative
    /// thread on a process wait.
    public static func detectAsync(homeDirectory: String = NSHomeDirectory()) async -> Set<ToolchainID> {
        var found = localTools(homeDirectory: homeDirectory)
        for (name, tool) in commandTools where await ToolLocator.isAvailableAsync(name) {
            found.insert(tool)
        }
        return found
    }

    private static func localTools(homeDirectory: String) -> Set<ToolchainID> {
        let fm = FileManager.default
        func exists(_ path: String) -> Bool { fm.fileExists(atPath: path) }

        var found: Set<ToolchainID> = []

        if exists("/Applications/Xcode.app") || exists(homeDirectory + "/Library/Developer/Xcode") {
            found.insert(.xcode)
        }
        if exists(homeDirectory + "/.gradle") { found.insert(.gradle) }
        if exists(homeDirectory + "/Library/Android/sdk") { found.insert(.android) }
        if exists(homeDirectory + "/Library/Application Support/Google/Chrome") { found.insert(.chrome) }
        if exists(homeDirectory + "/Library/Containers/com.apple.Safari") { found.insert(.safari) }
        if exists(homeDirectory + "/Library/Application Support/JetBrains")
            || exists(homeDirectory + "/Library/Caches/JetBrains") {
            found.insert(.jetbrains)
        }
        if exists(homeDirectory + "/Library/Caches/ms-playwright") { found.insert(.playwright) }

        return found
    }
}
