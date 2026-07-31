import Testing
@testable import TidyCore

@Suite("ToolLocator")
struct ToolLocatorTests {

    @Test("finds a tool that is guaranteed to exist on every Mac")
    func findsGuaranteedTool() {
        let path = ToolLocator.locate("ls")
        #expect(path == "/bin/ls")
        #expect(ToolLocator.isAvailable("ls"))
    }

    @Test("resolves git through xcrun --find")
    func resolvesGitThroughXcrun() {
        // Every Mac with Xcode or the Command Line Tools installed can
        // resolve git this way; this machine has Xcode installed.
        let path = ToolLocator.locate("git")
        #expect(path != nil)
        if let path {
            #expect(path.hasSuffix("/git"))
        }
    }

    @Test("returns nil for a tool that does not exist anywhere in the search path")
    func returnsNilForUnknownTool() {
        #expect(ToolLocator.locate("this-tool-does-not-exist-anywhere-xyz") == nil)
        #expect(!ToolLocator.isAvailable("this-tool-does-not-exist-anywhere-xyz"))
    }

    @Test("only searches the fixed directories, never an arbitrary PATH")
    func onlySearchesFixedDirectories() {
        #expect(ToolLocator.fixedSearchDirectories == [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ])
    }
}
