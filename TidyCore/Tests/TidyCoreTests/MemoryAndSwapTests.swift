import Foundation
import Testing
@testable import TidyCore

/// Memory and swap actions are the only catalog items that can interrupt
/// the user rather than delete a file, so what's pinned here is mostly
/// about them staying opt-in and staying honest about which resource they
/// moved. Nothing in this suite purges memory, quits an application, or
/// restarts anything: the side-effecting calls are covered by asserting
/// they are unreachable without explicit approval.
@Suite("Memory and swap")
struct MemoryAndSwapTests {

    private var environment: CleanEnvironment {
        CleanEnvironment(homeDirectory: NSHomeDirectory(), detectedTools: Set(ToolchainID.allCases))
    }

    @Test("every memory item is deep tier, so none is ever on by default")
    func memoryItemsAreDeepTier() {
        let items = CleanCatalog.memory.items
        #expect(!items.isEmpty)
        for item in items {
            #expect(item.tier == .deep, "\(item.id) is not deep tier")
        }
    }

    @Test("memory targets are opaque identifiers, never filesystem paths")
    func memoryTargetsAreNotPaths() {
        var env = environment
        env.appsApprovedForQuit = ["Some App"]
        env.allowRestartToReclaimSwap = true

        for item in CleanCatalog.memory.items {
            for target in item.locate(env) {
                #expect(!target.isFilesystemPath, "\(item.id) produced a filesystem target")
            }
        }
    }

    @Test("the restart action is unreachable until it is explicitly enabled")
    func restartRequiresOptIn() throws {
        let item = try #require(CleanCatalog.memory.items.first { $0.id == "deep.memory.restart-for-swap" })

        var off = environment
        off.allowRestartToReclaimSwap = false
        #expect(item.locate(off).isEmpty)

        var on = environment
        on.allowRestartToReclaimSwap = true
        #expect(item.locate(on).count == 1)
    }

    @Test("quitting applications is limited to the approved list, and empty means none")
    func quitRespectsApprovalList() throws {
        let item = try #require(CleanCatalog.memory.items.first { $0.id == "deep.memory.quit-approved-apps" })

        var none = environment
        none.appsApprovedForQuit = []
        #expect(item.locate(none).isEmpty)

        var some = environment
        some.appsApprovedForQuit = ["Xcode", "Google Chrome"]
        #expect(item.locate(some).map(\.path) == ["Xcode", "Google Chrome"])
    }

    @Test("a memory outcome never contributes to the disk freed figure")
    func memoryNeverCountsAsDiskBytes() {
        let result = ItemResult(
            id: "deep.memory.purge-inactive",
            title: "Purge inactive memory",
            freedBytes: 0,
            reclaimedMemoryBytes: 3_000_000_000,
            succeeded: true
        )
        let report = RunReport(
            tier: .deep,
            results: [result],
            startedAt: Date(),
            finishedAt: Date(),
            freeSpaceBeforeBytes: 1_000,
            freeSpaceAfterBytes: 1_000
        )

        #expect(report.totalFreedBytes == 0)
        #expect(report.totalReclaimedMemoryBytes == 3_000_000_000)
    }

    @Test("a freed estimate that the disk did not confirm is flagged for reconciling")
    func flagsUnreconciledFreedFigure() {
        func report(freed: Int64, delta: Int64) -> RunReport {
            RunReport(
                tier: .normal,
                results: [ItemResult(id: "x", title: "x", freedBytes: freed, succeeded: true)],
                startedAt: Date(),
                finishedAt: Date(),
                freeSpaceBeforeBytes: 0,
                freeSpaceAfterBytes: delta
            )
        }

        #expect(report(freed: 8_000_000_000, delta: 1_000_000_000).freedFigureNeedsReconciling)
        #expect(!report(freed: 8_000_000_000, delta: 7_900_000_000).freedFigureNeedsReconciling)
        #expect(!report(freed: 0, delta: 0).freedFigureNeedsReconciling)
    }

    // MARK: - RestartReclaimSurvey

    @Test("classifies VM files into separately labelled components")
    func classifiesVMFiles() {
        #expect(RestartReclaimSurvey.label(forFileNamed: "swapfile0") == "Swap files")
        #expect(RestartReclaimSurvey.label(forFileNamed: "swapfile12") == "Swap files")
        #expect(RestartReclaimSurvey.label(forFileNamed: "sleepimage") == "Sleep image")
        #expect(RestartReclaimSurvey.label(forFileNamed: "kernelcore") == "Kernel core reservation")
        #expect(RestartReclaimSurvey.label(forFileNamed: "something-else") == "Other VM files")
    }

    @Test("groups and sums VM files from a synthetic directory")
    func surveysSyntheticVMDirectory() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("VMSurvey-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        try Data(repeating: 0, count: 30_000).write(to: scratch.appendingPathComponent("swapfile0"))
        try Data(repeating: 0, count: 30_000).write(to: scratch.appendingPathComponent("swapfile1"))
        try Data(repeating: 0, count: 10_000).write(to: scratch.appendingPathComponent("sleepimage"))

        let survey = RestartReclaimSurvey.current(directories: [scratch.path])

        #expect(survey.totalBytes == 70_000)
        let swap = survey.components.first { $0.label == "Swap files" }
        #expect(swap?.bytes == 60_000)
        #expect(swap?.fileCount == 2)
        #expect(survey.components.first?.label == "Swap files", "components should be ordered largest first")
    }

    @Test("reports nothing rather than failing when the VM directories are unreadable")
    func surveyHandlesMissingDirectories() {
        let survey = RestartReclaimSurvey.current(directories: ["/nonexistent/vm/\(UUID().uuidString)"])
        #expect(survey.isEmpty)
        #expect(survey.totalBytes == 0)
    }

    /// The real machine's VM directories: this must never throw or hang,
    /// whatever the kernel currently has open there.
    @Test("surveys the real VM directories without crashing")
    func surveysRealVMDirectories() {
        let survey = RestartReclaimSurvey.current()
        #expect(survey.totalBytes >= 0)
        #expect(survey.pagedOutBytes >= 0)
    }
}
