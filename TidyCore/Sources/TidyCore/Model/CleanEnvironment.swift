import Foundation

/// Everything a `CleanItem.locate` closure needs to resolve its targets on
/// this particular machine: where home is, what tools were detected, and the
/// user's own configuration. Ships with empty keep-lists and no roots:
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
    /// Simulator device names the user has explicitly opted into deleting.
    /// Deliberately an opt-*in* delete-approval list, not a keep-list: the
    /// shell script this app replaces used a keep-list with a few
    /// hardcoded personal device names, so an empty list meant "delete
    /// everything else," the wrong default for a stranger installing this
    /// app. Empty here means nothing is eligible for deletion. Matched by
    /// exact device name, not substring.
    public var simulatorsApprovedForDeletion: [String]
    public var staleNodeModulesThresholdDays: Int
    public var transcriptAgeThresholdDays: Int
    /// Application names the user has explicitly approved for quitting,
    /// an opt-in list like `simulatorsApprovedForDeletion`. Empty means
    /// nothing is eligible. Matched by exact name, not substring.
    public var appsApprovedForQuit: [String]
    /// Whether the restart-to-reclaim-swap item may appear at all. Off by
    /// default: rebooting the machine should never be reachable from a
    /// checkbox the user did not deliberately enable.
    public var allowRestartToReclaimSwap: Bool

    public init(
        homeDirectory: String = NSHomeDirectory(),
        detectedTools: Set<ToolchainID> = [],
        gitRoots: [String] = [],
        protectedRoots: [String] = CleanEnvironment.defaultProtectedRoots(homeDirectory: NSHomeDirectory()),
        keepCookieDomains: [String] = [],
        simulatorsApprovedForDeletion: [String] = [],
        staleNodeModulesThresholdDays: Int = 60,
        transcriptAgeThresholdDays: Int = 45,
        appsApprovedForQuit: [String] = [],
        allowRestartToReclaimSwap: Bool = false
    ) {
        self.homeDirectory = homeDirectory
        self.detectedTools = detectedTools
        self.gitRoots = gitRoots
        var seen = Set<String>()
        self.protectedRoots = (protectedRoots + Self.defaultProtectedRoots(homeDirectory: homeDirectory))
            .filter { seen.insert($0).inserted }
        self.keepCookieDomains = keepCookieDomains
        self.simulatorsApprovedForDeletion = simulatorsApprovedForDeletion
        self.staleNodeModulesThresholdDays = staleNodeModulesThresholdDays
        self.transcriptAgeThresholdDays = transcriptAgeThresholdDays
        self.appsApprovedForQuit = appsApprovedForQuit
        self.allowRestartToReclaimSwap = allowRestartToReclaimSwap
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
