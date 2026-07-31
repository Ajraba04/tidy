import Foundation
import Testing
@testable import TidyCore

@Suite("LaunchAgentsSurvey")
struct LaunchAgentsSurveyTests {

    @Test("lists plist files sorted by name")
    func listsPlistFilesSorted() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchAgentsSurveyTests-\(UUID().uuidString)", isDirectory: true)
        let launchAgents = scratch.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        for name in ["com.zzz.agent.plist", "com.aaa.agent.plist"] {
            try Data().write(to: launchAgents.appendingPathComponent(name))
        }

        let result = LaunchAgentsSurvey.userLaunchAgents(homeDirectory: scratch.path)
        #expect(result == ["com.aaa.agent.plist", "com.zzz.agent.plist"])
    }

    @Test("returns an empty list when there is no LaunchAgents directory")
    func returnsEmptyWhenMissing() {
        let result = LaunchAgentsSurvey.userLaunchAgents(homeDirectory: "/nonexistent-\(UUID().uuidString)")
        #expect(result.isEmpty)
    }
}
