import Foundation
import Testing
@testable import TidyCore

@Suite("RunLog")
struct RunLogTests {
    private func makeReport(freed: Int64) -> RunReport {
        RunReport(
            tier: .safe,
            results: [ItemResult(id: "x", title: "X", freedBytes: freed, succeeded: true)],
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_010),
            freeSpaceBeforeBytes: 1_000,
            freeSpaceAfterBytes: 1_000 + freed
        )
    }

    @Test("appends one JSON line per call and reads them all back")
    func appendsAndReadsBack() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RunLogTests-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        RunLog.append(makeReport(freed: 100), to: url)
        RunLog.append(makeReport(freed: 200), to: url)

        let reports = RunLog.readAll(from: url)
        #expect(reports.count == 2)
        #expect(reports.map(\.totalFreedBytes) == [100, 200])
    }

    @Test("creates the containing directory if it does not exist yet")
    func createsContainingDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RunLogTests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("runs.jsonl")
        defer { try? FileManager.default.removeItem(at: dir) }

        RunLog.append(makeReport(freed: 50), to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("readAll returns an empty array when the file does not exist")
    func readAllReturnsEmptyForMissingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RunLogTests-missing-\(UUID().uuidString).jsonl")
        #expect(RunLog.readAll(from: url).isEmpty)
    }
}
