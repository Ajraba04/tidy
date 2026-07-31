import Foundation

/// Everything a `CleanItem.locate` closure needs to resolve its targets on
/// this particular machine: where home is, what tools were detected, and the
/// user's own configuration. Ships with empty keep-lists and no roots —
/// nothing here defaults to any one person's machine.
///
/// Named `CleanEnvironment`, not `Environment`: the app layer imports both
/// TidyCore and SwiftUI, and `Environment` would collide with SwiftUI's own
/// `@Environment` property wrapper type in every file that does.
public struct CleanEnvironment: Sendable {
    public var homeDirectory: String
    public var detectedTools: Set<ToolchainID>
    public var gitRoots: [String]
    public var protectedRoots: [String]
    public var keepCookieDomains: [String]
    public var keepSimulatorNames: [String]
    public var staleNodeModulesThresholdDays: Int
    public var transcriptAgeThresholdDays: Int

    public init(
        homeDirectory: String = NSHomeDirectory(),
        detectedTools: Set<ToolchainID> = [],
        gitRoots: [String] = [],
        protectedRoots: [String] = CleanEnvironment.defaultProtectedRoots(homeDirectory: NSHomeDirectory()),
        keepCookieDomains: [String] = [],
        keepSimulatorNames: [String] = [],
        staleNodeModulesThresholdDays: Int = 60,
        transcriptAgeThresholdDays: Int = 45
    ) {
        self.homeDirectory = homeDirectory
        self.detectedTools = detectedTools
        self.gitRoots = gitRoots
        self.protectedRoots = protectedRoots
        self.keepCookieDomains = keepCookieDomains
        self.keepSimulatorNames = keepSimulatorNames
        self.staleNodeModulesThresholdDays = staleNodeModulesThresholdDays
        self.transcriptAgeThresholdDays = transcriptAgeThresholdDays
    }

    /// iCloud is not local scratch space and is never walked into, by
    /// default and unconditionally.
    public static func defaultProtectedRoots(homeDirectory: String) -> [String] {
        [
            homeDirectory + "/Library/CloudStorage",
            homeDirectory + "/Library/Mobile Documents"
        ]
    }

    public func hasTool(_ tool: ToolchainID) -> Bool {
        detectedTools.contains(tool)
    }

    public func path(_ components: String) -> String {
        homeDirectory + "/" + components
    }
}
