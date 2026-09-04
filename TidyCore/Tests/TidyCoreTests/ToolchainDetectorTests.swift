import Foundation
import Testing
@testable import TidyCore

@Suite("ToolchainDetector")
struct ToolchainDetectorTests {
    @Test("detects Xcode and git on any Mac with Xcode or the Command Line Tools installed")
    func detectsXcodeAndGit() async {
        let found = await ToolchainDetector.detectAsync()
        #expect(found.contains(.xcode))
        #expect(found.contains(.git))
    }

    @Test("home-directory-dependent tools are absent under a bogus home, CLI-resolved tools are not")
    func homeDependentToolsAbsentUnderBogusHome() async {
        let found = await ToolchainDetector.detectAsync(
            homeDirectory: "/nonexistent-home-\(UUID().uuidString)")
        #expect(!found.contains(.gradle))
        #expect(!found.contains(.android))
        #expect(!found.contains(.chrome))
        // git resolves via xcrun --find, independent of homeDirectory.
        #expect(found.contains(.git))
    }
}
