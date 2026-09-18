import Darwin
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

@Suite("Optional completed-run history")
struct OptionalRunHistoryTests {
    private func report(finishedAt: Date, titleBytes: Int = 1) -> RunReport {
        RunReport(tier: .safe,
            results: [ItemResult(id: UUID().uuidString,
                title: String(repeating: "x", count: titleBytes), freedBytes: 1,
                succeeded: true)],
            startedAt: finishedAt.addingTimeInterval(-1), finishedAt: finishedAt,
            freeSpaceBeforeBytes: 10, freeSpaceAfterBytes: 11)
    }

    @Test("history off removes optional reports without touching mandatory recovery bytes")
    func historyOffIsIndependentOfRecovery() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OptionalHistory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let history = root.appendingPathComponent("runs.jsonl")
        let store = try OptionalRunHistoryStore(directory: root)
        let recovery = root.appendingPathComponent("execution.pending")
        let witness = Data("unresolved-recovery-witness".utf8)
        try witness.write(to: recovery)
        _ = try await store.record(report(finishedAt: Date()),
            policy: .init(enabled: true, retentionDays: 30, maxMiB: 1), acknowledgedRevision: 1, now: Date())

        let outcome = try await store.reconcile(
            policy: .init(enabled: false, retentionDays: 30, maxMiB: 1), acknowledgedRevision: 2, now: Date())
        #expect(outcome == .disabled)
        #expect(!FileManager.default.fileExists(atPath: history.path))
        #expect(try Data(contentsOf: recovery) == witness)
    }

    @Test("stale history work cannot override newer off or on revisions")
    func staleHistoryWorkPreservesLatestPolicy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OptionalHistory-Revisions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let store = try OptionalRunHistoryStore(directory: root)
        let enabled = OptionalRunHistoryPolicy(enabled: true, retentionDays: 30, maxMiB: 1)
        let disabled = OptionalRunHistoryPolicy(enabled: false, retentionDays: 30, maxMiB: 1)
        let now = Date()
        _ = try await store.reconcile(policy: disabled, acknowledgedRevision: 2)
        #expect(try await store.record(report(finishedAt: now), policy: enabled,
            acknowledgedRevision: 1) == .stalePolicy)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("runs.jsonl").path))
        _ = try await store.record(report(finishedAt: now), policy: enabled,
            acknowledgedRevision: 3)
        let before = try Data(contentsOf: root.appendingPathComponent("runs.jsonl"))
        #expect(try await store.reconcile(policy: disabled,
            acknowledgedRevision: 2) == .stalePolicy)
        #expect(try Data(contentsOf: root.appendingPathComponent("runs.jsonl")) == before)
        await #expect(throws: OptionalRunHistoryStore.Error.invalidPolicy) {
            _ = try await store.reconcile(policy: disabled, acknowledgedRevision: 3)
        }
        #expect(try Data(contentsOf: root.appendingPathComponent("runs.jsonl")) == before)
    }

    @Test("age and byte limits independently retain only eligible newest reports")
    func ageAndByteLimitsAreIndependent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OptionalHistory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let url = root.appendingPathComponent("runs.jsonl")
        let store = try OptionalRunHistoryStore(directory: root)
        let now = Date(timeIntervalSince1970: 4_000_000)
        let policy = OptionalRunHistoryPolicy(enabled: true, retentionDays: 30, maxMiB: 1)
        _ = try await store.record(
            report(finishedAt: now.addingTimeInterval(-31 * 86_400)),
            policy: policy, acknowledgedRevision: 1, now: now.addingTimeInterval(-31 * 86_400))
        _ = try await store.record(report(finishedAt: now, titleBytes: 700_000),
            policy: policy, acknowledgedRevision: 1, now: now)
        _ = try await store.record(
            report(finishedAt: now.addingTimeInterval(1), titleBytes: 700_000),
            policy: policy, acknowledgedRevision: 1, now: now.addingTimeInterval(1))

        let retained = try await store.read(policy: policy)
        #expect(retained.count == 1)
        #expect(retained[0].finishedAt == now.addingTimeInterval(1))
        #expect(try Data(contentsOf: url).count <= 1_048_576)
    }

    @Test("malformed optional history is preserved instead of reported as a successful rewrite")
    func malformedHistoryPreservesBytes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OptionalHistory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let url = root.appendingPathComponent("runs.jsonl")
        let store = try OptionalRunHistoryStore(directory: root)
        let bytes = Data("{malformed\n".utf8)
        try bytes.write(to: url)
        await #expect(throws: OptionalRunHistoryStore.Error.malformed) {
            _ = try await store.record(report(finishedAt: Date()),
                policy: .init(enabled: true, retentionDays: 30, maxMiB: 1), acknowledgedRevision: 1, now: Date())
        }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test("symlink FIFO directory and oversized history are rejected without touching witnesses")
    func unsafeStorageIsRejectedWithoutMutation() async throws {
        let policy = OptionalRunHistoryPolicy(enabled: false, retentionDays: 30, maxMiB: 1)
        for kind in ["symlink", "fifo", "directory", "oversized"] {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("OptionalHistory-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            let history = root.appendingPathComponent("runs.jsonl")
            let witness = root.appendingPathComponent("recovery.witness")
            let witnessBytes = Data("mandatory-recovery".utf8)
            try witnessBytes.write(to: witness)
            switch kind {
            case "symlink":
                try FileManager.default.createSymbolicLink(at: history,
                    withDestinationURL: witness)
            case "fifo":
                #expect(mkfifo(history.path, 0o600) == 0)
            case "directory":
                try FileManager.default.createDirectory(at: history,
                    withIntermediateDirectories: false)
            default:
                try Data(repeating: 0x61, count: 1_048_577).write(to: history)
            }
            let store = try OptionalRunHistoryStore(directory: root)
            do {
                _ = try await store.reconcile(policy: policy, acknowledgedRevision: 1, now: Date())
                Issue.record("unsafe \(kind) history was accepted")
            } catch let error as OptionalRunHistoryStore.Error {
                #expect(error == (kind == "oversized" ? .oversized : .unsafeStorage))
            }
            #expect(try Data(contentsOf: witness) == witnessBytes)
            if kind == "symlink" {
                #expect(try FileManager.default.destinationOfSymbolicLink(
                    atPath: history.path) == witness.path)
            } else {
                #expect(FileManager.default.fileExists(atPath: history.path))
            }
        }
    }
}
