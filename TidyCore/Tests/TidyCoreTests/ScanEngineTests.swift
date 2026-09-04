import Foundation
import Testing
@testable import TidyCore

@Suite("ScanEngine")
struct ScanEngineTests {
    @Test("returns a structurally valid report without launching discovery or measurement")
    func producesUnmeasuredNoOpReport() async throws {
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

        let report = await ScanEngine.run(environment: environment)

        #expect(report.memoryStats.totalBytes > 0)
        #expect(report.detectedTools == environment.detectedTools)
        // Superseded by ScanEngine.start(environment:registry:sessions:session:): this legacy
        // overload launches no discovery or measurement, so nothing was ever walked.
        #expect(report.topLevelHomeRanking.isEmpty)
        #expect(report.libraryRanking.isEmpty)
        #expect(report.filesOver1GB.isEmpty)
    }
}
