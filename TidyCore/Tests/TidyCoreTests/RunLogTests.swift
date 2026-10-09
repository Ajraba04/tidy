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
    @Test("Opt-out clears optional history without touching recovery files")
    func optOutClearsHistory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("runs.jsonl")
        RunLog.append(makeReport(freed: 50), to: url)
        let recovery = dir.appendingPathComponent("unfinished-effects.json")
        try Data("preserve".utf8).write(to: recovery)
        try RunLog.update(at: url, policy: .init(enabled: false))
        #expect(RunLog.readAll(from: url).isEmpty)
        #expect(try Data(contentsOf: recovery) == Data("preserve".utf8))
    }

    @Test("Retention removes old records and strips leaf paths and diagnostic messages")
    func retentionAndRedaction() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let old = makeReport(freed: 50)
        RunLog.append(old, to: url)
        try RunLog.update(at: url, policy: .init(days: 1), now: old.finishedAt.addingTimeInterval(2 * 86_400))
        #expect(RunLog.readAll(from: url).isEmpty)
        let now = Date()
        let privateReport = RunReport(tier: .safe,
            results: [ItemResult(id: "fixture", title: "Fixture", freedBytes: 0, succeeded: false,
                message: "private/project/file", targetOutcomes: nil)],
            startedAt: now, finishedAt: now, freeSpaceBeforeBytes: 0, freeSpaceAfterBytes: 0)
        try RunLog.update(privateReport, at: url, policy: .init(), now: now)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("private/project/file") == false)
    }

}
