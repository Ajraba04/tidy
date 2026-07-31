import Foundation

/// Lists the user's own LaunchAgents — on a memory-constrained Mac, each one
/// is a background process running at every login.
public enum LaunchAgentsSurvey: Sendable {
    public static func userLaunchAgents(homeDirectory: String) -> [String] {
        let path = homeDirectory + "/Library/LaunchAgents"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return names.sorted()
    }
}
