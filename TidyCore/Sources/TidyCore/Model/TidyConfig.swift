import Foundation

/// One user-saved selection of catalog item IDs for the Custom mode.
public struct CustomPreset: Sendable, Codable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let itemIDs: Set<String>

    public init(name: String, itemIDs: Set<String>) {
        self.name = name
        self.itemIDs = itemIDs
    }
}

/// Everything the app persists across launches, versioned so a future
/// schema change can migrate rather than break. Every collection here
/// ships empty: nothing defaults to any one person's machine.
public struct TidyConfig: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var hasCompletedOnboarding: Bool
    public var keepCookieDomains: [String]
    public var simulatorsApprovedForDeletion: [String]
    public var gitRoots: [String]
    public var staleNodeModulesThresholdDays: Int
    public var transcriptAgeThresholdDays: Int
    public var appsApprovedForQuit: [String]
    public var allowRestartToReclaimSwap: Bool
    public var presets: [CustomPreset]

    public init(
        schemaVersion: Int = TidyConfig.currentSchemaVersion,
        hasCompletedOnboarding: Bool = false,
        keepCookieDomains: [String] = [],
        simulatorsApprovedForDeletion: [String] = [],
        gitRoots: [String] = [],
        staleNodeModulesThresholdDays: Int = 60,
        transcriptAgeThresholdDays: Int = 45,
        appsApprovedForQuit: [String] = [],
        allowRestartToReclaimSwap: Bool = false,
        presets: [CustomPreset] = []
    ) {
        self.schemaVersion = schemaVersion
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.keepCookieDomains = keepCookieDomains
        self.simulatorsApprovedForDeletion = simulatorsApprovedForDeletion
        self.gitRoots = gitRoots
        self.staleNodeModulesThresholdDays = staleNodeModulesThresholdDays
        self.transcriptAgeThresholdDays = transcriptAgeThresholdDays
        self.appsApprovedForQuit = appsApprovedForQuit
        self.allowRestartToReclaimSwap = allowRestartToReclaimSwap
        self.presets = presets
    }

    public func makeEnvironment(homeDirectory: String = NSHomeDirectory()) -> CleanEnvironment {
        CleanEnvironment(
            homeDirectory: homeDirectory,
            detectedTools: ToolchainDetector.detect(homeDirectory: homeDirectory),
            gitRoots: gitRoots,
            protectedRoots: CleanEnvironment.defaultProtectedRoots(homeDirectory: homeDirectory),
            keepCookieDomains: keepCookieDomains,
            simulatorsApprovedForDeletion: simulatorsApprovedForDeletion,
            staleNodeModulesThresholdDays: staleNodeModulesThresholdDays,
            transcriptAgeThresholdDays: transcriptAgeThresholdDays,
            appsApprovedForQuit: appsApprovedForQuit,
            allowRestartToReclaimSwap: allowRestartToReclaimSwap
        )
    }
}
