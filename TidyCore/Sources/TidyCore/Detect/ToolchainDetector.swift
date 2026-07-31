import Foundation

/// Detects which developer tools and apps are present on this machine, so
/// catalog items requiring an absent tool can hide themselves.
public enum ToolchainDetector: Sendable {
    public static func detect(homeDirectory: String = NSHomeDirectory()) -> Set<ToolchainID> {
        let fm = FileManager.default
        func exists(_ path: String) -> Bool { fm.fileExists(atPath: path) }

        var found: Set<ToolchainID> = []

        if exists("/Applications/Xcode.app") || exists(homeDirectory + "/Library/Developer/Xcode") {
            found.insert(.xcode)
        }
        if ToolLocator.isAvailable("brew") { found.insert(.homebrew) }
        if ToolLocator.isAvailable("node") { found.insert(.node) }
        if ToolLocator.isAvailable("npm") { found.insert(.npm) }
        if ToolLocator.isAvailable("pnpm") { found.insert(.pnpm) }
        if ToolLocator.isAvailable("yarn") { found.insert(.yarn) }
        if ToolLocator.isAvailable("bun") { found.insert(.bun) }
        if ToolLocator.isAvailable("pod") { found.insert(.cocoapods) }
        if ToolLocator.isAvailable("pip3") { found.insert(.pip) }
        if ToolLocator.isAvailable("uv") { found.insert(.uv) }
        if ToolLocator.isAvailable("deno") { found.insert(.deno) }
        if ToolLocator.isAvailable("go") { found.insert(.go) }
        if ToolLocator.isAvailable("flutter") { found.insert(.flutter) }
        if ToolLocator.isAvailable("dart") { found.insert(.dart) }
        if ToolLocator.isAvailable("git") { found.insert(.git) }
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
