import Foundation
import Testing
@testable import TidyCore

@Suite("ScanEngine")
struct ScanEngineTests {
    @Test("produces a complete report end to end without crashing or deleting anything")
    func producesCompleteReport() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("Library"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let environment = CleanEnvironment(
            homeDirectory: scratch.path,
            detectedTools: ToolchainDetector.detect(),
            gitRoots: [scratch.path],
            protectedRoots: []
        )

        let report = await ScanEngine.run(environment: environment, sizeScanner: SizeScanner(cache: SizeCache(fileURL: nil)))

        #expect(report.memoryStats.totalBytes > 0)
        #expect(report.detectedTools == environment.detectedTools)
        // The scratch home has one entry ("Library"); confirm it was actually measured.
        #expect(report.topLevelHomeRanking.contains { $0.path.hasSuffix("/Library") })
    }
}
