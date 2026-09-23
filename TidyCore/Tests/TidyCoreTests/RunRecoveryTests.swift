import Darwin
import Foundation
import Testing
@testable import TidyCore

private enum IOFault: CaseIterable, Equatable, Sendable {
    case shortWriteThenENOSPC, fileSync, renameBefore, renameAfter, directorySync
}
private final class FaultIO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let lock = NSLock()
    private var armed: IOFault?
    private var failFollowingWrite = false
    private var shortOnly = false
    private var trace: [String] = []
    fileprivate func arm(_ fault: IOFault) { lock.lock(); armed = fault; trace = []; lock.unlock() }
    func armShortWriteOnly() { lock.lock(); shortOnly = true; trace = []; lock.unlock() }
    func calls() -> [String] { lock.lock(); defer { lock.unlock() }; return trace }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        lock.lock()
        trace.append("write")
        if failFollowingWrite {
            failFollowingWrite = false; lock.unlock(); throw POSIXError(.ENOSPC)
        }
        let short = shortOnly || armed == .shortWriteThenENOSPC
        if armed == .shortWriteThenENOSPC { armed = nil; failFollowingWrite = true }
        shortOnly = false
        lock.unlock()
        if short {
            // A real one-byte write to the actual production-created staging FD.
            return try base.write(fd: fd, bytes: Data(bytes[offset..<(offset + 1)]), offset: 0)
        }
        return try base.write(fd: fd, bytes: bytes, offset: offset)
    }
    func syncFile(fd: Int32) throws {
        lock.lock(); trace.append("fileSync")
        let fail = armed == .fileSync; if fail { armed = nil }; lock.unlock()
        if fail { throw POSIXError(.EIO) }
        try base.syncFile(fd: fd)
    }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        lock.lock(); trace.append("rename")
        let before = armed == .renameBefore, after = armed == .renameAfter
        if before || after { armed = nil }; lock.unlock()
        if before { throw POSIXError(.EIO) }
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
        if after { throw POSIXError(.EIO) } // bytes really published; caller receives ambiguity
    }
    func syncDirectory(fd: Int32) throws {
        lock.lock(); trace.append("directorySync")
        let fail = armed == .directorySync; if fail { armed = nil }; lock.unlock()
        if fail { throw POSIXError(.EIO) }
        try base.syncDirectory(fd: fd)
    }
}
private struct AdmissionEnvelope: Decodable {
    let schema: Int
    let storeID: UUID
    let unfinished: [PendingEffectIntent]
}
private func envelope(_ root: URL) throws -> AdmissionEnvelope {
    try JSONDecoder().decode(AdmissionEnvelope.self,
        from: Data(contentsOf: root.appendingPathComponent("unfinished-effects.json")))
}
private func intent(_ run: UUID, operation: UUID = UUID(), pid: Int32? = nil,
                    path: String = "/untrusted/not-executed") -> PendingEffectIntent {
    PendingEffectIntent(runID: run, operationID: operation, adapterID: "unknown-untrusted-record",
        bootID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        executablePath: path, executableDevice: 1, executableInode: 1,
        childPID: pid, childStartSeconds: pid == nil ? nil : 100,
        childStartMicroseconds: pid == nil ? nil : 1, phase: .prepared)
}
private func journalScratch(_ body: (URL) throws -> Void) throws {
    // Canonicalize only this known existing temporary base before the UUID
    // allocation. Foundation resolvingSymlinksInPath can retain /var/folders
    // under its /var ancestor symlink; production no-follow rules stay strict.
    guard let canonical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { free(canonical) }
    let root = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
        .appendingPathComponent("tidy-t04-journal-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                           attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}
private func event(_ run: UUID, _ seq: UInt64, _ phase: JournalPhase,
                   operation: UUID? = nil) -> JournalEvent {
    JournalEvent(runID: run, sequence: seq, phase: phase,
                 operationID: operation, status: nil, reason: nil)
}
@Suite struct RunRecoveryTests {
    @Test func transitionAndRoundTrip() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            let run = UUID()
            #expect(throws: JournalError.invalidTransition) {
                try journal.append(event(run, 1, .confirmed))
            }
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            #expect(throws: JournalError.invalidTransition) {
                try journal.append(event(run, 2, .confirmed))
            }
            let reopened = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            #expect(try reopened.events(runID: run).map(\.phase) == [.planned, .confirmed])
        }
    }
    @Test(arguments: IOFault.allCases)
    fileprivate func actualPublicationFaultRetainsEvidenceAndBlocks(_ fault: IOFault) throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root, io: io))
            let run = UUID()
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let first = intent(run), second = intent(run)
            try journal.persistIntent(first)
            let ledger = root.appendingPathComponent("unfinished-effects.json")
            let prior = try Data(contentsOf: ledger)
            let priorStoreID = try envelope(root).storeID
            io.arm(fault)
            #expect(throws: (any Error).self) { try journal.persistIntent(second) }
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
            let observed = try envelope(root)
            #expect(observed.schema == 1 && observed.storeID == priorStoreID)
            #expect(observed.unfinished.contains(first))
            switch fault {
            case .renameAfter, .directorySync:
                #expect(observed.unfinished.contains(second))
                #expect(io.calls().contains("rename"))
            case .shortWriteThenENOSPC, .fileSync, .renameBefore:
                #expect(try Data(contentsOf: ledger) == prior)
                let staged = try FileManager.default.contentsOfDirectory(at: root,
                    includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".pending-") }
                #expect(!staged.isEmpty)
                if fault == .shortWriteThenENOSPC {
                    #expect(io.calls().filter { $0 == "write" }.count == 2)
                    #expect(try staged.contains { try Data(contentsOf: $0).count == 1 })
                } else {
                    let retained = try #require(staged.first)
                    let attempted = try JSONDecoder().decode(AdmissionEnvelope.self,
                        from: Data(contentsOf: retained))
                    #expect(attempted.unfinished.contains(first) && attempted.unfinished.contains(second))
                }
            }
            if fault == .fileSync { #expect(io.calls().contains("fileSync")) }
            if fault == .directorySync { #expect(io.calls().contains("directorySync")) }
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            let admission = reopened.acquire()
            #expect(admission == .storageUnavailable || admission == .uncertainAndPossiblyRunning)
            reopened.release()
            #expect(try envelope(root).unfinished.contains(first))
        }
    }
    @Test func positiveShortWriteRetriesWithoutTruncation() throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root, io: io))
            let run = UUID(), operation = intent(UUID())
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let expected = intent(run, operation: operation.operationID)
            io.armShortWriteOnly()
            try journal.persistIntent(expected)
            #expect(io.calls().filter { $0 == "write" }.count >= 2)
            #expect(try envelope(root).unfinished == [expected])
        }
    }
    @Test func capacityAndSequenceOverflowDoNotPublish() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID(), first = intent(UUID())
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(intent(run, operation: first.operationID))
            let before = try Data(contentsOf: root.appendingPathComponent("unfinished-effects.json"))
            #expect(throws: JournalError.capacity) {
                try journal.persistIntent(intent(run, path: "/" + String(repeating: "x", count: 1_048_576)))
            }
            #expect(try Data(contentsOf: root.appendingPathComponent("unfinished-effects.json")) == before)
            let tooLarge = JournalEvent(runID: run, sequence: 3, phase: .started,
                operationID: first.operationID, status: nil, reason: String(repeating: "x", count: 65_536))
            #expect(throws: JournalError.capacity) { try journal.append(tooLarge) }
            #expect(try journal.events(runID: run).count == 2)
            #expect(throws: JournalError.capacity) { _ = try JournalSequence.next(after: UInt64.max) }
            #expect(try JournalSequence.next(after: 2) == 3)
            #expect(store.readAdmissionWhileLocked() != .ready)
        }
    }
    @Test func childUpdatePreservesOtherUnresolvedOperation() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            let run = UUID()
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let first = intent(run), second = intent(run)
            try journal.persistIntent(first)
            try journal.persistIntent(second)
            let captured = intent(run, operation: first.operationID, pid: 123)
            try journal.recordChild(captured) // untrusted record simulation, no PID signal/probe
            let items = try envelope(root).unfinished
            #expect(items.count == 2 && items.contains(captured) && items.contains(second))
            #expect(!items.contains(first))
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
            reopened.release()
        }
    }
    @Test func preparedWithoutPIDSurvivesHistoryPruningAndRelaunch() throws {
        try journalScratch { root in
            let run = UUID(), operation = UUID()
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let intent = PendingEffectIntent(runID: run, operationID: operation,
                adapterID: "unknown-untrusted-record", bootID: UUID(),
                executablePath: "/untrusted/not-executed", executableDevice: 1,
                executableInode: 1, childPID: nil, childStartSeconds: nil,
                childStartMicroseconds: nil, phase: .prepared)
            try journal.persistIntent(intent)
            #expect(throws: JournalError.invalidTransition) { try journal.finish(runID: run) }
            try journal.applyHistoryLimits(days: 1, bytes: 1_048_576, now: .distantFuture)
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
            reopened.release()
        }
    }
    @Test func corruptLedgerNeverBecomesEmpty() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            store.release()
            let ledger = root.appendingPathComponent("unfinished-effects.json")
            var bytes = try Data(contentsOf: ledger)
            bytes.append(contentsOf: [0xff, 0x00])
            try bytes.write(to: ledger)
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .storageUnavailable)
            reopened.release()
            #expect(try Data(contentsOf: ledger) == bytes)
        }
    }
    @Test func diagnosticCorruptTailIsPreservedAndDoesNotClearAdmission() throws {
        try journalScratch { root in
            let run = UUID()
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(intent(run))
            let file = root.appendingPathComponent("run-\(run.uuidString).journal")
            var bytes = try Data(contentsOf: file)
            try #require(!bytes.isEmpty)
            bytes.removeLast()
            try bytes.write(to: file)
            #expect(throws: JournalError.corrupt) { _ = try journal.events(runID: run) }
            #expect(try Data(contentsOf: file) == bytes)
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() != .ready)
            reopened.release()
            #expect(try Data(contentsOf: file) == bytes)
        }
    }
    @Test func diagnosticFIFOReaderRejectsPromptlyAndPreservesUnfinishedAdmission() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID(), unresolved = intent(run)
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(unresolved)
            let target = root.appendingPathComponent("run-\(run.uuidString).journal")
            let targetBytes = try Data(contentsOf: target)
            let backup = root.appendingPathComponent(".t04-fifo-original-\(UUID())")
            try FileManager.default.moveItem(at: target, to: backup)
            // Snapshot after the move, before the FIFO exists. This includes the
            // owned neutral backup and every other regular metadata byte.
            let movedNames = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
            var preservedBytes: [String: Data] = [:]
            for name in movedNames {
                preservedBytes[name] = try Data(contentsOf: root.appendingPathComponent(name))
            }
            #expect(mkfifo(target.path, 0o600) == 0)
            var before = stat()
            try #require(lstat(target.path, &before) == 0)
            try #require(before.st_mode & S_IFMT == S_IFIFO)
            let watchdog = try FIFOReadWatchdog(fifo: target)
            // No cancellation, task race, throwing check or scratch cleanup between
            // the actual proposed reader call and draining its owned watchdog.
            let received: JournalError?
            do { _ = try storage.read(name: target.lastPathComponent); received = nil }
            catch let error as JournalError { received = error }
            catch { received = nil }
            let watchdogFired = watchdog.finishAndDrain()

            #expect(received == .unavailable)
            #expect(!watchdogFired, "Journal reader needed FIFO rescue after five seconds")
            var after = stat()
            try #require(lstat(target.path, &after) == 0)
            #expect(after.st_mode & S_IFMT == S_IFIFO)
            #expect(after.st_dev == before.st_dev && after.st_ino == before.st_ino)
            #expect(after.st_mode == before.st_mode)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
                == (movedNames + [target.lastPathComponent]).sorted())
            #expect(try Data(contentsOf: backup) == targetBytes)
            for (name, bytes) in preservedBytes {
                #expect(try Data(contentsOf: root.appendingPathComponent(name)) == bytes)
            }
            #expect(try envelope(root).unfinished.contains(unresolved))
            #expect(store.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
        }
    }
}

private func journalName(_ run: UUID) -> String { "run-\(run.uuidString).journal" }

private func completeNoEffect(_ journal: RunJournal, run: UUID,
                              reason: String? = nil) throws {
    try journal.append(JournalEvent(runID: run, sequence: 1, phase: .planned,
        operationID: nil, status: nil, reason: reason))
    try journal.append(event(run, 2, .confirmed))
    try journal.finish(runID: run)
}

private func ownedSafetyBytes(_ root: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for name in ["mutation.lock", "bootstrap.json", "unfinished-effects.json"] {
        result[name] = try Data(contentsOf: root.appendingPathComponent(name))
    }
    return result
}

private func childRecord(_ base: PendingEffectIntent, pid: Int32?,
                         seconds: Int64?, micros: Int32?,
                         executablePath: String? = nil) -> PendingEffectIntent {
    PendingEffectIntent(runID: base.runID, operationID: base.operationID,
        adapterID: base.adapterID, bootID: base.bootID!,
        executablePath: executablePath ?? base.executablePath!,
        executableDevice: base.executableDevice!, executableInode: base.executableInode!,
        childPID: pid, childStartSeconds: seconds, childStartMicroseconds: micros,
        phase: base.phase)
}

extension RunRecoveryTests {
    @Test func capturedChildCannotChooseAmongDuplicatedPersistedOperations() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID(), pending = intent(run)
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(pending)
            let ledger = root.appendingPathComponent("unfinished-effects.json")
            var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: ledger)) as? [String: Any])
            let records = try #require(object["unfinished"] as? [[String: Any]])
            object["unfinished"] = records + records
            try JSONSerialization.data(withJSONObject: object).write(to: ledger)
            let original = try ownedSafetyBytes(root)
            #expect(throws: JournalError.invalidTransition) {
                try journal.recordChild(childRecord(pending, pid: 123, seconds: 100, micros: 1))
            }
            #expect(try ownedSafetyBytes(root) == original)
            #expect(try envelope(root).unfinished == [pending, pending])
            #expect(store.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
        }
    }

    @Test func everyJournalEntryRequiresTheBorrowedLock() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            let storage = try DurableJournalStorage(directory: root)
            #expect(throws: JournalError.unavailable) {
                _ = try RunJournal(store: store, storage: storage)
            }
            // Missing lock is a call precondition, not a persistence failure.
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID()
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let before = try ownedSafetyBytes(root)
            let diagnostic = try storage.read(name: journalName(run))
            store.release()
            #expect(throws: JournalError.unavailable) { try journal.append(event(run, 3, .finished)) }
            #expect(throws: JournalError.unavailable) { _ = try journal.events(runID: run) }
            #expect(throws: JournalError.unavailable) { try journal.persistIntent(intent(run)) }
            #expect(throws: JournalError.unavailable) { try journal.recordChild(intent(run, pid: 123)) }
            #expect(throws: JournalError.unavailable) { try journal.finish(runID: run) }
            #expect(throws: JournalError.unavailable) {
                try journal.applyHistoryLimits(days: 1, bytes: 1_048_576, now: .distantFuture)
            }
            #expect(try ownedSafetyBytes(root) == before)
            #expect(try storage.read(name: journalName(run)) == diagnostic)
            #expect(store.acquire() == .ready)
            store.release()
        }
    }

    @Test func diagnosticDirectoryMustMatchTheLockedStore() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let other = root.appendingPathComponent("other", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let storage = try DurableJournalStorage(directory: other)
            let before = try ownedSafetyBytes(root)
            #expect(throws: JournalError.unavailable) { _ = try RunJournal(store: store, storage: storage) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: other.path).isEmpty)
            #expect(try ownedSafetyBytes(root) == before)
        }
    }

    @Test func duplicateOperationAcrossRunsCannotReplaceOrAppend() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            let firstRun = UUID(), secondRun = UUID(), operation = UUID()
            for run in [firstRun, secondRun] {
                try journal.append(event(run, 1, .planned))
                try journal.append(event(run, 2, .confirmed))
            }
            let first = intent(firstRun, operation: operation)
            try journal.persistIntent(first)
            let before = try ownedSafetyBytes(root)
            #expect(throws: JournalError.invalidTransition) { try journal.persistIntent(first) }
            #expect(throws: JournalError.invalidTransition) {
                try journal.persistIntent(intent(secondRun, operation: operation))
            }
            #expect(throws: JournalError.invalidTransition) {
                try journal.recordChild(intent(secondRun, operation: operation, pid: 123))
            }
            #expect(try envelope(root).unfinished == [first])
            #expect(try ownedSafetyBytes(root) == before)
        }
    }

    @Test func childTupleMustBeCompleteAndCannotChangeIdentity() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            let run = UUID()
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let first = intent(run), sibling = intent(run)
            try journal.persistIntent(first)
            try journal.persistIntent(sibling)
            let before = try ownedSafetyBytes(root)
            let invalid = [
                childRecord(first, pid: 123, seconds: nil, micros: 1),
                childRecord(first, pid: nil, seconds: 100, micros: 1),
                childRecord(first, pid: 0, seconds: 100, micros: 1),
                childRecord(first, pid: 123, seconds: -1, micros: 1),
                childRecord(first, pid: 123, seconds: 100, micros: -1),
                childRecord(first, pid: 123, seconds: 100, micros: 1_000_000),
                childRecord(first, pid: 123, seconds: 100, micros: 1,
                            executablePath: "/untrusted/replacement-not-executed")
            ]
            for changed in invalid {
                #expect(throws: JournalError.invalidTransition) { try journal.recordChild(changed) }
                #expect(try ownedSafetyBytes(root) == before)
            }
            let captured = childRecord(first, pid: 123, seconds: 100, micros: 1)
            try journal.recordChild(captured)
            let capturedBytes = try ownedSafetyBytes(root)
            try journal.recordChild(captured) // Exact repeat performs no publication.
            #expect(try ownedSafetyBytes(root) == capturedBytes)
            #expect(throws: JournalError.invalidTransition) {
                try journal.recordChild(childRecord(first, pid: 124, seconds: 101, micros: 1))
            }
            #expect(try ownedSafetyBytes(root) == capturedBytes)
            #expect(try envelope(root).unfinished == [captured, sibling])
            #expect(store.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
        }
    }

    @Test func finishAllowsOnlyConfirmedNoEffectRunAndDoesNotPublishAdmission() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            let run = UUID()
            let before = try ownedSafetyBytes(root)
            #expect(throws: JournalError.invalidTransition) { try journal.finish(runID: run) }
            try journal.append(event(run, 1, .planned))
            #expect(throws: JournalError.invalidTransition) { try journal.finish(runID: run) }
            try journal.append(event(run, 2, .confirmed))
            try journal.finish(runID: run)
            #expect(try journal.events(runID: run).map(\.phase) == [.planned, .confirmed, .finished])
            #expect(try journal.events(runID: run).map(\.sequence) == [1, 2, 3])
            #expect(throws: JournalError.invalidTransition) { try journal.finish(runID: run) }
            #expect(throws: JournalError.invalidTransition) { try journal.append(event(run, 4, .planned)) }
            #expect(try ownedSafetyBytes(root) == before)
            #expect(store.readAdmissionWhileLocked() == .ready)
        }
    }

    @Test func diagnosticSucceededNeverSuppliesTerminalProof() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            let run = UUID(), pending = intent(run)
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(pending)
            try journal.append(event(run, 3, .started, operation: pending.operationID))
            try journal.append(JournalEvent(runID: run, sequence: 4, phase: .itemTerminal,
                operationID: pending.operationID, status: .succeeded, reason: "Untrusted observation only"))
            let before = try ownedSafetyBytes(root)
            #expect(throws: JournalError.invalidTransition) { try journal.finish(runID: run) }
            #expect(throws: JournalError.invalidTransition) { try journal.append(event(run, 5, .finished)) }
            #expect(try ownedSafetyBytes(root) == before)
            #expect(try envelope(root).unfinished == [pending])
            #expect(store.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
        }
    }

    @Test func onlyUnreferencedMissingJournalMeansNewRun() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID()
            #expect(throws: JournalError.notFound) { _ = try storage.read(name: journalName(run)) }
            #expect(try journal.events(runID: run).isEmpty)
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let pending = intent(run)
            try journal.persistIntent(pending)
            let target = root.appendingPathComponent(journalName(run))
            let backup = root.appendingPathComponent("neutral-original-\(UUID())")
            let original = try Data(contentsOf: target)
            try FileManager.default.moveItem(at: target, to: backup)
            #expect(throws: JournalError.corrupt) { _ = try journal.events(runID: run) }
            #expect(!FileManager.default.fileExists(atPath: target.path))
            #expect(try Data(contentsOf: backup) == original)
            #expect(try envelope(root).unfinished == [pending])
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
        }
    }

    @Test func existingZeroLengthDiagnosticIsNotNewRun() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID()
            try storage.replace(name: journalName(run), bytes: Data())
            #expect(throws: JournalError.corrupt) { _ = try journal.events(runID: run) }
            #expect(try storage.read(name: journalName(run)).isEmpty)
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
        }
    }

    @Test func frameHeaderAndRecordSequenceHaveExactWidths() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID()
            try journal.append(event(run, 1, .planned))
            let bytes = try storage.read(name: journalName(run))
            try #require(bytes.count > 52)
            #expect(Array(bytes.prefix(8)) == [0x54, 0x44, 0x59, 0x4a, 0, 1, 0, 0])
            let length = bytes[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            #expect(bytes.count == 8 + 4 + 8 + Int(length) + 32)
            #expect(Array(bytes[12..<20]) == [0, 0, 0, 0, 0, 0, 0, 1])
            #expect(try journal.events(runID: run) == [event(run, 1, .planned)])
        }
    }


    @Test func agePruningUsesFinishedMtimeAndLeavesFreshHistory() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID()
            try completeNoEffect(journal, run: run)
            let entry = try #require(try storage.journalEntries().first)
            #expect(try entry.directory == storage.directoryIdentity())
            #expect(try entry.byteCount == storage.read(name: entry.name).count)
            let before = try ownedSafetyBytes(root)
            try journal.applyHistoryLimits(days: 1, bytes: 2_097_152,
                now: entry.modifiedAt.addingTimeInterval(86_399))
            #expect(try storage.journalEntries().count == 1)
            try journal.applyHistoryLimits(days: 1, bytes: 2_097_152,
                now: entry.modifiedAt.addingTimeInterval(86_401))
            #expect(try storage.journalEntries().isEmpty)
            #expect(try ownedSafetyBytes(root) == before)
        }
    }


    @Test func retentionPreservesNonhistoryFilesAndRejectsStaleRemoval() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID()
            try completeNoEffect(journal, run: run)
            // Opaque bytes are a nonhistory preservation fixture, not a valid T03 manifest.
            let evidence = root.appendingPathComponent("manifest-fixture.bin")
            try Data("preserve nonhistory evidence".utf8).write(to: evidence)
            let evidenceBytes = try Data(contentsOf: evidence)
            let stale = try #require(try storage.journalEntries().first)
            let backup = root.appendingPathComponent("neutral-finished-backup-\(UUID())")
            try FileManager.default.moveItem(at: root.appendingPathComponent(stale.name), to: backup)
            let original = try Data(contentsOf: backup)
            try storage.replace(name: stale.name, bytes: original)
            #expect(throws: JournalError.unavailable) { try storage.removeJournal(stale) }
            #expect(try storage.read(name: stale.name) == original)
            try journal.applyHistoryLimits(days: 1, bytes: 1_048_576, now: .distantFuture)
            #expect(try storage.journalEntries().isEmpty)
            #expect(try Data(contentsOf: evidence) == evidenceBytes)
            #expect(try Data(contentsOf: backup) == original)
        }
    }

    @Test func corruptHistoryBlocksPruningBeforeAnyRemoval() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let good = UUID(), corrupt = UUID()
            try completeNoEffect(journal, run: good)
            try completeNoEffect(journal, run: corrupt)
            let goodBytes = try storage.read(name: journalName(good))
            var damaged = try storage.read(name: journalName(corrupt))
            damaged.removeLast()
            try storage.replace(name: journalName(corrupt), bytes: damaged)
            let safety = try ownedSafetyBytes(root)
            #expect(throws: JournalError.corrupt) {
                try journal.applyHistoryLimits(days: 1, bytes: 1_048_576, now: .distantFuture)
            }
            #expect(try storage.read(name: journalName(good)) == goodBytes)
            #expect(try storage.read(name: journalName(corrupt)) == damaged)
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
        }
    }

    @Test(arguments: ["futureSchema", "symlink"])
    func unknownOrUnsafeHistoryBlocksPruning(_ kind: String) throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let good = UUID(), bad = UUID()
            try completeNoEffect(journal, run: good)
            try completeNoEffect(journal, run: bad)
            let goodBytes = try storage.read(name: journalName(good))
            let target = root.appendingPathComponent(journalName(bad))
            let backup = root.appendingPathComponent("neutral-unsafe-original-\(UUID())")
            let original = try storage.read(name: journalName(bad))
            let expected: JournalError
            if kind == "futureSchema" {
                var future = original
                future[5] = 2 // Exact header schema field; rejected before payload interpretation.
                try storage.replace(name: journalName(bad), bytes: future)
                expected = .unsupportedSchema
            } else {
                try FileManager.default.moveItem(at: target, to: backup)
                try FileManager.default.createSymbolicLink(at: target, withDestinationURL: backup)
                expected = .unavailable
            }
            var before = stat()
            try #require(lstat(target.path, &before) == 0)
            let safety = try ownedSafetyBytes(root)
            #expect(throws: expected) {
                try journal.applyHistoryLimits(days: 1, bytes: 1_048_576, now: .distantFuture)
            }
            var after = stat()
            try #require(lstat(target.path, &after) == 0)
            #expect(before.st_dev == after.st_dev && before.st_ino == after.st_ino)
            #expect(before.st_mode == after.st_mode)
            #expect(try storage.read(name: journalName(good)) == goodBytes)
            if kind == "symlink" { #expect(try Data(contentsOf: backup) == original) }
            else {
                var future = original; future[5] = 2
                #expect(try storage.read(name: journalName(bad)) == future)
            }
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
        }
    }

    @Test func retentionDirectorySyncFailureLatchesWithoutChangingSafetyBytes() throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            try completeNoEffect(journal, run: UUID())
            let safety = try ownedSafetyBytes(root)
            io.arm(.directorySync)
            #expect(throws: JournalError.unavailable) {
                try journal.applyHistoryLimits(days: 1, bytes: 1_048_576, now: .distantFuture)
            }
            #expect(io.calls().contains("directorySync"))
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
            // A removed optional report need not reappear after sync ambiguity.
            // No cross-power-loss latch is asserted for a failed error flag.
        }
    }

    @Test(arguments: [0, 1_048_575, 52_428_801])
    func invalidHistoryByteLimitsDoNotChangeAnyFile(_ limit: Int) throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID()
            try completeNoEffect(journal, run: run)
            let before = try storage.read(name: journalName(run))
            let safety = try ownedSafetyBytes(root)
            #expect(throws: JournalError.capacity) {
                try journal.applyHistoryLimits(days: 1, bytes: limit, now: .distantFuture)
            }
            #expect(try storage.read(name: journalName(run)) == before)
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(store.readAdmissionWhileLocked() == .ready)
        }
    }
}

import CryptoKit

private enum WriteProgressFault: CaseIterable, Equatable, Sendable { case zero, overRemaining, interrupted }
private final class ProgressIO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let lock = NSLock()
    private var next: WriteProgressFault?
    private var count = 0
    func arm(_ fault: WriteProgressFault) {
        lock.lock(); next = fault; count = 0; lock.unlock()
    }
    func writeCalls() -> Int { lock.lock(); defer { lock.unlock() }; return count }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        lock.lock(); count += 1; let fault = next; next = nil; lock.unlock()
        switch fault {
        case .zero: return 0
        case .overRemaining: return bytes.count - offset + 1
        case .interrupted: throw POSIXError(.EINTR)
        case nil: return try base.write(fd: fd, bytes: bytes, offset: offset)
        }
    }
    func syncFile(fd: Int32) throws { try base.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
    }
    func syncDirectory(fd: Int32) throws { try base.syncDirectory(fd: fd) }
}

private func tinyRootBytes(_ root: URL) throws -> [String: Data] {
    // Test-only snapshots: callers create <=10 regular leaves, each <=1 MiB.
    let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
    try #require(names.count <= 10)
    var result: [String: Data] = [:]
    for name in names {
        let bytes = try Data(contentsOf: root.appendingPathComponent(name))
        try #require(bytes.count <= 1_048_576)
        result[name] = bytes
    }
    return result
}

private let fixtureJournalHeader = Data([0x54, 0x44, 0x59, 0x4a, 0, 1, 0, 0])
private func fixtureU32(_ value: UInt32) -> Data {
    Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
}
private func fixtureU64(_ value: UInt64) -> Data {
    Data((0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
}
private func fixtureRecord(_ event: JournalEvent, prefix: UInt64? = nil) throws -> Data {
    let payload = try JSONEncoder().encode(event)
    try #require(payload.count <= 65_536)
    let body = fixtureU32(UInt32(payload.count)) + fixtureU64(prefix ?? event.sequence) + payload
    return body + Data(SHA256.hash(data: fixtureJournalHeader + body))
}

extension RunRecoveryTests {
    @Test(arguments: IOFault.allCases)
    fileprivate func firstIntentPublicationFaultNeverBecomesSuccessfulAdmission(_ fault: IOFault) throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root, io: io))
            let run = UUID(), attempted = intent(run)
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let ledger = root.appendingPathComponent("unfinished-effects.json")
            let original = try Data(contentsOf: ledger)
            let originalID = try envelope(root).storeID
            io.arm(fault)
            #expect(throws: (any Error).self) { try journal.persistIntent(attempted) }
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
            let observed = try envelope(root)
            #expect(observed.schema == 1 && observed.storeID == originalID)
            let staged = try FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".pending-") }
            switch fault {
            case .renameAfter, .directorySync:
                #expect(observed.unfinished == [attempted])
                #expect(staged.isEmpty && io.calls().contains("rename"))
            case .shortWriteThenENOSPC, .fileSync, .renameBefore:
                #expect(observed.unfinished.isEmpty)
                #expect(try Data(contentsOf: ledger) == original)
                let stage = try #require(staged.first)
                let bytes = try Data(contentsOf: stage)
                if fault == .shortWriteThenENOSPC {
                    #expect(bytes.count == 1)
                    #expect(io.calls().filter { $0 == "write" }.count == 2)
                } else {
                    let pending = try JSONDecoder().decode(AdmissionEnvelope.self, from: bytes)
                    #expect(pending.unfinished == [attempted])
                }
            }
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            let admission = reopened.acquire()
            #expect(admission == .storageUnavailable || admission == .uncertainAndPossiblyRunning)
            reopened.release()
            // No effect API is called; errors cannot produce a start permit.
            // This is real-file injected failure, not physical power-loss proof.
        }
    }

    @Test(arguments: IOFault.allCases)
    fileprivate func diagnosticPublicationFaultPreservesMandatoryIntentAndBlocks(_ fault: IOFault) throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID(), pending = intent(run)
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(pending)
            let safety = try ownedSafetyBytes(root)
            let before = try storage.read(name: journalName(run))
            io.arm(fault)
            #expect(throws: JournalError.unavailable) {
                try journal.append(event(run, 3, .started, operation: pending.operationID))
            }
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
            #expect(try ownedSafetyBytes(root) == safety)
            let after = try storage.read(name: journalName(run))
            let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
            let stages = names.filter { $0.hasPrefix(".pending-") }
            switch fault {
            case .renameAfter, .directorySync:
                #expect(after != before && stages.isEmpty)
            case .shortWriteThenENOSPC, .fileSync, .renameBefore:
                #expect(after == before)
                let name = try #require(stages.first)
                let staged = try Data(contentsOf: root.appendingPathComponent(name))
                if fault == .shortWriteThenENOSPC { #expect(staged.count == 1) }
                else { #expect(staged.count > before.count) }
            }
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            let admission = reopened.acquire()
            defer { reopened.release() }
            switch fault {
            case .renameAfter, .directorySync:
                #expect(admission == .uncertainAndPossiblyRunning)
                let recovered = try RunJournal(store: reopened, storage: DurableJournalStorage(directory: root))
                #expect(try recovered.events(runID: run).map(\.phase) == [.planned, .confirmed, .started])
            default: #expect(admission == .storageUnavailable)
            }
            #expect(try ownedSafetyBytes(root) == safety)
        }
    }

    @Test(arguments: WriteProgressFault.allCases, ["intent", "diagnostic"])
    fileprivate func writeProgressIsCheckedAndEINTRRetries(_ fault: WriteProgressFault, _ destination: String) throws {
        try journalScratch { root in
            let io = ProgressIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID(), pending = intent(run)
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            if destination == "diagnostic" { try journal.persistIntent(pending) }
            let safety = try ownedSafetyBytes(root)
            let diagnostic = try storage.read(name: journalName(run))
            let publish = {
                if destination == "intent" { try journal.persistIntent(pending) }
                else { try journal.append(event(run, 3, .started, operation: pending.operationID)) }
            }
            io.arm(fault)
            if fault == .interrupted {
                try publish()
                #expect(io.writeCalls() >= 2)
                #expect(try envelope(root).unfinished == [pending])
                #expect(store.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
                if destination == "diagnostic" {
                    #expect(try journal.events(runID: run).count == 3)
                    #expect(try ownedSafetyBytes(root) == safety)
                } else { #expect(try storage.read(name: journalName(run)) == diagnostic) }
            } else {
                #expect(throws: (any Error).self) { try publish() }
                #expect(io.writeCalls() == 1)
                #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
                #expect(try ownedSafetyBytes(root) == safety)
                #expect(try storage.read(name: journalName(run)) == diagnostic)
                let stages = try FileManager.default.contentsOfDirectory(at: root,
                    includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".pending-") }
                let stage = try #require(stages.first)
                #expect(try Data(contentsOf: stage).isEmpty)
            }
        }
    }
}

private enum MalformedJournal: CaseIterable, Sendable {
    case checksum, sequenceGap, prefixPayloadMismatch, foreignRun
    case headerOnly, zeroLength, excessiveLength, truncatedPayload
}
private func writeOwnedFixture(_ root: URL, name: String, bytes: Data) throws {
    // Fixed-size helper for new test-owned regular leaves, never production publication.
    try #require(!name.contains("/") && name != "." && name != "..")
    let url = root.appendingPathComponent(name)
    try #require(!FileManager.default.fileExists(atPath: url.path))
    try #require(bytes.count <= 65_536)
    try #require(FileManager.default.createFile(atPath: url.path, contents: bytes,
                                                attributes: [.posixPermissions: 0o600]))
}

extension RunRecoveryTests {
    @Test(arguments: MalformedJournal.allCases)
    fileprivate func malformedFrameCannotBecomePartialSuccess(_ kind: MalformedJournal) throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID(), pending = intent(run)
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(pending)
            // Positive control proves the fixture encoder's valid framing is accepted.
            let first = try fixtureRecord(event(run, 1, .planned))
            let second = try fixtureRecord(event(run, 2, .confirmed))
            try storage.replace(name: journalName(run), bytes: fixtureJournalHeader + first + second)
            #expect(try journal.events(runID: run).map(\.phase) == [.planned, .confirmed])
            var damaged: Data
            let expected: JournalError
            switch kind {
            case .checksum:
                damaged = fixtureJournalHeader + first + second
                damaged[damaged.count - 1] ^= 1
                expected = .corrupt
            case .sequenceGap:
                // Every checksum is valid; decoded sequences skip 2.
                damaged = try fixtureJournalHeader + first + fixtureRecord(event(run, 3, .confirmed))
                expected = .corrupt
            case .prefixPayloadMismatch:
                // Recompute hash over prefix 3 and payload sequence 2.
                damaged = try fixtureJournalHeader + first + fixtureRecord(event(run, 2, .confirmed), prefix: 3)
                expected = .corrupt
            case .foreignRun:
                damaged = try fixtureJournalHeader + fixtureRecord(event(UUID(), 1, .planned))
                expected = .corrupt
            case .headerOnly:
                damaged = fixtureJournalHeader
                expected = .corrupt
            case .zeroLength:
                let body = fixtureU32(0) + fixtureU64(1)
                damaged = fixtureJournalHeader + body + Data(SHA256.hash(data: fixtureJournalHeader + body))
                expected = .corrupt
            case .excessiveLength:
                // Valid hash and all declared bytes exist: bound must win before JSON decoding.
                let body = fixtureU32(65_537) + fixtureU64(1) + Data(repeating: 0x20, count: 65_537)
                damaged = fixtureJournalHeader + body + Data(SHA256.hash(data: fixtureJournalHeader + body))
                expected = .capacity
            case .truncatedPayload:
                damaged = fixtureJournalHeader + fixtureU32(128) + fixtureU64(1) + Data([0x7b])
                expected = .corrupt
            }
            try storage.replace(name: journalName(run), bytes: damaged)
            let safety = try ownedSafetyBytes(root)
            #expect(throws: expected) { _ = try journal.events(runID: run) }
            #expect(try storage.read(name: journalName(run)) == damaged)
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(try envelope(root).unfinished == [pending])
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
        }
    }

    @Test func cumulativeSegmentCapRejectsBeforeIOAndAllowsSmallBookkeeping() throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID()
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let padding = String(repeating: "x", count: 60_000)
            var sequence: UInt64 = 3
            // Sixteen bounded frames: ~960 KiB, with nine total untrusted intents at most.
            for _ in 0..<8 {
                let pending = intent(run)
                try journal.persistIntent(pending)
                try journal.append(JournalEvent(runID: run, sequence: sequence, phase: .started,
                    operationID: pending.operationID, status: nil, reason: padding))
                try journal.append(JournalEvent(runID: run, sequence: sequence + 1, phase: .itemTerminal,
                    operationID: pending.operationID, status: .succeeded, reason: padding))
                sequence += 2
            }
            let last = intent(run)
            try journal.persistIntent(last)
            try journal.append(JournalEvent(runID: run, sequence: sequence, phase: .started,
                operationID: last.operationID, status: nil, reason: padding))
            let rejected = JournalEvent(runID: run, sequence: sequence + 1, phase: .itemTerminal,
                operationID: last.operationID, status: .uncertain, reason: padding)
            let before = try storage.read(name: journalName(run))
            let rejectedRecordLength = try fixtureRecord(rejected).count
            #expect(before.count <= 1_048_576)
            #expect(rejectedRecordLength < 65_536 + 44)
            #expect(before.count + rejectedRecordLength > 1_048_576)
            let safety = try ownedSafetyBytes(root)
            let trace = io.calls()
            #expect(throws: JournalError.capacity) { try journal.append(rejected) }
            #expect(io.calls() == trace)
            #expect(try storage.read(name: journalName(run)) == before)
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(store.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
            try journal.append(JournalEvent(runID: run, sequence: sequence + 1, phase: .itemTerminal,
                operationID: last.operationID, status: .uncertain, reason: "Retained uncertainty"))
            try journal.recordChild(childRecord(last, pid: 123, seconds: 100, micros: 1))
            #expect(try journal.events(runID: run).last?.sequence == sequence + 1)
            #expect(try envelope(root).unfinished.count == 9)
            #expect(try storage.read(name: journalName(run)).count <= 1_048_576)
        }
    }

    @Test func productionScanLimitsAreUsedAndCanOnlyBeReduced() throws {
        try journalScratch { root in
            #expect(JournalScanLimits.production.maximumDirectoryEntries == 16_384)
            #expect(JournalScanLimits.production.maximumJournalEntries == 4_096)
            let store = try MutationAdmissionStore(directory: root)
            let storage = try DurableJournalStorage(directory: root)
            #expect(store.scanLimits == .production && storage.scanLimits == .production)
            let valid = try JournalScanLimits(reducingDirectoryEntriesTo: 8, reducingJournalEntriesTo: 2)
            #expect(valid.maximumDirectoryEntries == 8 && valid.maximumJournalEntries == 2)
            for (directory, journal) in [(3, 1), (16_385, 1), (8, 0), (16_384, 4_097), (4, 5)] {
                #expect(throws: JournalError.capacity) {
                    _ = try JournalScanLimits(reducingDirectoryEntriesTo: directory,
                                              reducingJournalEntriesTo: journal)
                }
            }
            #expect(store.acquire() == .ready)
            store.release()
        }
    }

    @Test func exactDirectoryLimitIncludesUnrelatedNamesAndReservesStaging() throws {
        try journalScratch { root in
            let limits = try JournalScanLimits(reducingDirectoryEntriesTo: 8, reducingJournalEntriesTo: 2)
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io, scanLimits: limits)
            #expect(store.acquire() == .ready)
            let storage = try DurableJournalStorage(directory: root, io: io, scanLimits: limits)
            let journal = try RunJournal(store: store, storage: storage)
            // Three mandatory entries plus five unrelated files is exactly eight.
            for index in 0..<5 {
                try writeOwnedFixture(root, name: "unrelated-\(index)", bytes: Data([UInt8(index)]))
            }
            let exact = try tinyRootBytes(root)
            #expect(exact.count == 8)
            #expect(store.readAdmissionWhileLocked() == .ready)
            #expect(try storage.journalEntries().isEmpty)
            let trace = io.calls()
            #expect(throws: JournalError.capacity) { try journal.append(event(UUID(), 1, .planned)) }
            #expect(throws: JournalError.capacity) { try store.persistIntentWhileLocked(intent(UUID())) }
            #expect(io.calls() == trace)
            #expect(try tinyRootBytes(root) == exact) // No hidden ninth staging file.
            #expect(store.readAdmissionWhileLocked() == .ready)
            store.release()
            // Existing-store initialization and acquire both succeed at the exact limit.
            let reopened = try MutationAdmissionStore(directory: root, io: DarwinJournalIO(), scanLimits: limits)
            #expect(reopened.acquire() == .ready)
            reopened.release()
            try writeOwnedFixture(root, name: "unrelated-overflow", bytes: Data("preserve".utf8))
            let overflow = try tinyRootBytes(root)
            #expect(overflow.count == 9)
            #expect(store.acquire() == .storageUnavailable)
            store.release()
            #expect(throws: JournalError.capacity) { _ = try storage.journalEntries() }
            #expect(throws: ConfirmationError.storageUnavailable) {
                _ = try MutationAdmissionStore(directory: root, io: DarwinJournalIO(), scanLimits: limits)
            }
            #expect(try tinyRootBytes(root) == overflow)
        }
    }

    @Test func freshOversizedDirectoryCannotCreateBootstrapOrLock() throws {
        try journalScratch { root in
            let limits = try JournalScanLimits(reducingDirectoryEntriesTo: 8, reducingJournalEntriesTo: 2)
            for index in 0..<9 {
                try writeOwnedFixture(root, name: "preexisting-\(index)", bytes: Data([UInt8(index)]))
            }
            let before = try tinyRootBytes(root)
            #expect(throws: ConfirmationError.storageUnavailable) {
                _ = try MutationAdmissionStore(directory: root, io: DarwinJournalIO(), scanLimits: limits)
            }
            #expect(try tinyRootBytes(root) == before)
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("mutation.lock").path))
        }
    }

    @Test func pendingStageAtExactDirectoryLimitRemainsFailClosed() throws {
        try journalScratch { root in
            let limits = try JournalScanLimits(reducingDirectoryEntriesTo: 8, reducingJournalEntriesTo: 2)
            let store = try MutationAdmissionStore(directory: root, io: DarwinJournalIO(), scanLimits: limits)
            #expect(store.acquire() == .ready)
            store.release()
            for index in 0..<4 {
                try writeOwnedFixture(root, name: "unrelated-\(index)", bytes: Data([UInt8(index)]))
            }
            try writeOwnedFixture(root, name: ".pending-\(UUID().uuidString)", bytes: Data("incomplete".utf8))
            let before = try tinyRootBytes(root)
            #expect(before.count == 8)
            #expect(store.acquire() == .storageUnavailable)
            store.release()
            let reopened = try MutationAdmissionStore(directory: root, io: DarwinJournalIO(), scanLimits: limits)
            #expect(reopened.acquire() == .storageUnavailable)
            reopened.release()
            #expect(try tinyRootBytes(root) == before)
        }
    }

    @Test func journalEnumerationExactAndPlusOnePreserveEveryByte() throws {
        try journalScratch { root in
            // Store retains production scan limits; storage uses a stricter mechanical bound.
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let limits = try JournalScanLimits(reducingDirectoryEntriesTo: 8, reducingJournalEntriesTo: 2)
            let storage = try DurableJournalStorage(directory: root, io: DarwinJournalIO(), scanLimits: limits)
            let journal = try RunJournal(store: store, storage: storage)
            for _ in 0..<2 { try completeNoEffect(journal, run: UUID()) }
            #expect(try storage.journalEntries().count == 2)
            let before = try tinyRootBytes(root)
            #expect(throws: JournalError.capacity) { try journal.append(event(UUID(), 1, .planned)) }
            #expect(try tinyRootBytes(root) == before)
            #expect(store.readAdmissionWhileLocked() == .ready)
            // External fixture insertion, not permission to publish a third production journal.
            let extra = UUID()
            try writeOwnedFixture(root, name: journalName(extra),
                bytes: fixtureJournalHeader + fixtureRecord(event(extra, 1, .planned)))
            let overflow = try tinyRootBytes(root)
            #expect(throws: JournalError.capacity) { _ = try storage.journalEntries() }
            #expect(throws: JournalError.capacity) {
                // Default 10 MiB, no age expiry: independent of the disputed minimum policy.
                try journal.applyHistoryLimits(days: 30, bytes: 10_485_760, now: .distantPast)
            }
            #expect(try tinyRootBytes(root) == overflow)
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
        }
    }
}

private final class CompletionPruneIO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let lock = NSLock()
    private var remaining: Int?
    func failSecondDirectorySync() { lock.lock(); remaining = 2; lock.unlock() }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        try base.write(fd: fd, bytes: bytes, offset: offset)
    }
    func syncFile(fd: Int32) throws { try base.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
    }
    func syncDirectory(fd: Int32) throws {
        lock.lock()
        let fail: Bool
        if let value = remaining {
            remaining = value > 1 ? value - 1 : nil
            fail = value == 1
        } else { fail = false }
        lock.unlock()
        if fail { throw POSIXError(.EIO) }
        try base.syncDirectory(fd: fd)
    }
}

extension RunRecoveryTests {
    @Test func minimumOptionalBudgetPermitsFirstRunAndIntent() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            try journal.applyHistoryLimits(days: 30, bytes: 1_048_576, now: .distantPast)
            let run = UUID(), pending = intent(run)
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(pending)
            #expect(try journal.events(runID: run).map(\.phase) == [.planned, .confirmed])
            #expect(try envelope(root).unfinished == [pending])
            #expect(try storage.read(name: journalName(run)).count > 0)
            #expect(store.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
        }
    }

    @Test func minimumHistoryPreservesActiveBytesAndAllowsBookkeeping() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let active = UUID(), finished = UUID()
            try journal.append(event(active, 1, .planned))
            try journal.append(event(active, 2, .confirmed))
            let pending = intent(active)
            try journal.persistIntent(pending)
            try completeNoEffect(journal, run: finished)
            let safety = try ownedSafetyBytes(root)
            let diagnostic = try storage.read(name: journalName(active))
            try journal.applyHistoryLimits(days: 1, bytes: 1_048_576, now: .distantFuture)
            #expect(throws: JournalError.notFound) { _ = try storage.read(name: journalName(finished)) }
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(try storage.read(name: journalName(active)) == diagnostic)
            // An unfinished intent still blocks execution, not scratch diagnostic preparation.
            try journal.append(event(UUID(), 1, .planned))
            let captured = childRecord(pending, pid: 123, seconds: 100, micros: 1)
            try journal.recordChild(captured)
            try journal.append(event(active, 3, .started, operation: pending.operationID))
            try journal.append(JournalEvent(runID: active, sequence: 4, phase: .itemTerminal,
                operationID: pending.operationID, status: .uncertain, reason: "No proof"))
            #expect(throws: JournalError.invalidTransition) { try journal.finish(runID: active) }
            #expect(try envelope(root).unfinished == [captured])
            #expect(store.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
        }
    }

    @Test func eightActiveReservationsRejectNinthBeforeIOAndSurviveReopen() throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            try journal.applyHistoryLimits(days: 30, bytes: 1_048_576, now: .distantPast)
            let runs = (0..<8).map { _ in UUID() }
            for run in runs {
                try journal.append(event(run, 1, .planned))
                try journal.append(event(run, 2, .confirmed))
            }
            let safety = try ownedSafetyBytes(root)
            let entries = try storage.journalEntries()
            #expect(entries.count == 8)
            #expect(entries.reduce(0) { $0 + $1.byteCount } <= 8 * 1_048_576)
            let trace = io.calls()
            #expect(throws: JournalError.capacity) { try journal.append(event(UUID(), 1, .planned)) }
            #expect(io.calls() == trace)
            #expect(try storage.journalEntries().sorted { $0.name < $1.name }
                == entries.sorted { $0.name < $1.name })
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(store.readAdmissionWhileLocked() == .ready)
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .ready)
            defer { reopened.release() }
            let recovered = try RunJournal(store: reopened, storage: DurableJournalStorage(directory: root))
            #expect(throws: JournalError.capacity) { try recovered.append(event(UUID(), 1, .planned)) }
            // Finish is legal at the active bound and releases exactly one slot.
            try recovered.finish(runID: runs[0])
            try recovered.append(event(UUID(), 1, .planned))
            #expect(throws: JournalError.capacity) { try recovered.append(event(UUID(), 1, .planned)) }
            #expect(try ownedSafetyBytes(root) == safety)
        }
    }

    @Test func optionalBytePruningDoesNotChargeLedgerOrActiveReservation() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let active = UUID()
            try journal.append(event(active, 1, .planned))
            let activeBytes = try storage.read(name: journalName(active))
            for _ in 0..<20 {
                try completeNoEffect(journal, run: UUID(), reason: String(repeating: "x", count: 60_000))
            }
            let before = try storage.journalEntries().filter { $0.name != journalName(active) }.sorted {
                if $0.modifiedSeconds != $1.modifiedSeconds { return $0.modifiedSeconds < $1.modifiedSeconds }
                if $0.modifiedNanoseconds != $1.modifiedNanoseconds { return $0.modifiedNanoseconds < $1.modifiedNanoseconds }
                return $0.name.utf8.lexicographicallyPrecedes($1.name.utf8)
            }
            #expect(before.reduce(0) { $0 + $1.byteCount } > 1_048_576)
            let safety = try ownedSafetyBytes(root)
            try journal.applyHistoryLimits(days: 90, bytes: 1_048_576, now: .distantPast)
            let after = try storage.journalEntries().filter { $0.name != journalName(active) }
            try #require(!after.isEmpty && after.count < before.count)
            let remaining = after.reduce(0) { $0 + $1.byteCount }
            #expect(remaining <= 1_048_576)
            let lastRemoved = before[before.count - after.count - 1]
            #expect(remaining + lastRemoved.byteCount > 1_048_576)
            #expect(Set(after.map(\.name)) == Set(before.suffix(after.count).map(\.name)))
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(try storage.read(name: journalName(active)) == activeBytes)
        }
    }

    @Test func disabledHistoryPrunesOnlyCompletedAndStillPersistsSafety() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let old = UUID(), active = UUID()
            try completeNoEffect(journal, run: old)
            try journal.append(event(active, 1, .planned))
            try journal.append(event(active, 2, .confirmed))
            let pending = intent(active)
            try journal.persistIntent(pending)
            let safety = try ownedSafetyBytes(root)
            let diagnostic = try storage.read(name: journalName(active))
            try journal.applyHistoryLimits(enabled: false, days: 30, bytes: 1_048_576, now: .distantPast)
            #expect(throws: JournalError.notFound) { _ = try storage.read(name: journalName(old)) }
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(try storage.read(name: journalName(active)) == diagnostic)
            let noEffect = UUID()
            try completeNoEffect(journal, run: noEffect)
            #expect(throws: JournalError.notFound) { _ = try storage.read(name: journalName(noEffect)) }
            let captured = childRecord(pending, pid: 123, seconds: 100, micros: 1)
            try journal.recordChild(captured)
            #expect(try envelope(root).unfinished == [captured])
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
            defer { reopened.release() }
            let recovered = try RunJournal(store: reopened, storage: DurableJournalStorage(directory: root))
            try recovered.applyHistoryLimits(enabled: false, days: 30, bytes: 1_048_576, now: .distantFuture)
            #expect(try envelope(root).unfinished == [captured])
            #expect(try recovered.events(runID: active).map(\.phase) == [.planned, .confirmed])
        }
    }

    @Test(arguments: [0, 1_048_575, 52_428_801, Int.max])
    func disabledHistoryStillRejectsInvalidByteLimits(_ bytes: Int) throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID()
            try completeNoEffect(journal, run: run)
            let safety = try ownedSafetyBytes(root)
            let original = try storage.read(name: journalName(run))
            let trace = io.calls()
            #expect(throws: JournalError.capacity) {
                try journal.applyHistoryLimits(enabled: false, days: 30, bytes: bytes, now: .distantFuture)
            }
            #expect(io.calls() == trace)
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(try storage.read(name: journalName(run)) == original)
        }
    }

    @Test func finishAtOptionalCapAutomaticallyPrunesWithoutGrowingHistory() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            try journal.applyHistoryLimits(days: 90, bytes: 1_048_576, now: .distantPast)
            for _ in 0..<20 {
                try completeNoEffect(journal, run: UUID(), reason: String(repeating: "x", count: 60_000))
                #expect(try storage.journalEntries().reduce(0) { $0 + $1.byteCount } <= 1_048_576)
            }
            #expect(try storage.journalEntries().count < 20)
            #expect(store.readAdmissionWhileLocked() == .ready)
        }
    }

    @Test func finishedPublicationThenPruneSyncFailurePreservesSafetyAndLatches() throws {
        try journalScratch { root in
            let io = CompletionPruneIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            let active = UUID(), finished = UUID()
            for run in [active, finished] {
                try journal.append(event(run, 1, .planned))
                try journal.append(event(run, 2, .confirmed))
            }
            let pending = intent(active)
            try journal.persistIntent(pending)
            try journal.applyHistoryLimits(enabled: false, days: 30, bytes: 1_048_576, now: .distantPast)
            let safety = try ownedSafetyBytes(root)
            let diagnostic = try storage.read(name: journalName(active))
            io.failSecondDirectorySync() // First: durable finished rename; second: actual prune unlink.
            #expect(throws: JournalError.unavailable) { try journal.finish(runID: finished) }
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(try storage.read(name: journalName(active)) == diagnostic)
            // Retirement-marker durability failed before any delete, so the
            // validated finished journal remains available for a later retry.
            #expect(try !storage.read(name: journalName(finished)).isEmpty)
            #expect(throws: JournalError.unavailable) { try journal.append(event(UUID(), 1, .planned)) }
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
            defer { reopened.release() }
            #expect(try ownedSafetyBytes(root) == safety)
            // Injected sync failure is not physical crash/durability proof.
        }
    }

    @Test func observedOptionalOverageBlocksGrowthButNotExistingBookkeeping() throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            let active = UUID(), waiting = UUID()
            for run in [active, waiting] {
                try journal.append(event(run, 1, .planned))
                try journal.append(event(run, 2, .confirmed))
            }
            let pending = intent(active)
            try journal.persistIntent(pending)
            try journal.applyHistoryLimits(days: 90, bytes: 10_485_760, now: .distantPast)
            // Correctly framed owned fixtures model a recovered optional overage, not terminal proof.
            // 180 small segments exceed the default 10 MiB; one payload is retained at a time.
            for _ in 0..<180 {
                let run = UUID()
                let planned = JournalEvent(runID: run, sequence: 1, phase: .planned,
                    operationID: nil, status: nil, reason: String(repeating: "x", count: 60_000))
                let bytes = try fixtureJournalHeader + fixtureRecord(planned)
                    + fixtureRecord(event(run, 2, .confirmed)) + fixtureRecord(event(run, 3, .finished))
                try storage.replace(name: journalName(run), bytes: bytes)
            }
            let safety = try ownedSafetyBytes(root)
            let trace = io.calls()
            #expect(throws: JournalError.capacity) { try journal.append(event(UUID(), 1, .planned)) }
            #expect(throws: JournalError.capacity) { try journal.persistIntent(intent(waiting)) }
            #expect(throws: JournalError.capacity) { try journal.finish(runID: waiting) }
            #expect(io.calls() == trace)
            #expect(try ownedSafetyBytes(root) == safety)
            let captured = childRecord(pending, pid: 123, seconds: 100, micros: 1)
            try journal.recordChild(captured)
            try journal.append(event(active, 3, .started, operation: pending.operationID))
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
            defer { reopened.release() }
            let recoveredStorage = try DurableJournalStorage(directory: root)
            let recovered = try RunJournal(store: reopened, storage: recoveredStorage)
            #expect(throws: JournalError.capacity) { try recovered.append(event(UUID(), 1, .planned)) }
            #expect(throws: JournalError.capacity) { try recovered.persistIntent(intent(waiting)) }
            #expect(throws: JournalError.capacity) { try recovered.finish(runID: waiting) }
            // Reapply current setting on reopen; this explicitly reconciles optional overage.
            try recovered.applyHistoryLimits(days: 90, bytes: 10_485_760, now: .distantPast)
            try recovered.finish(runID: waiting)
            #expect(try envelope(root).unfinished == [captured])
            #expect(try recovered.events(runID: active).last?.phase == .started)
            let optional = try recoveredStorage.journalEntries().filter { $0.name != journalName(active) }
            #expect(optional.reduce(0) { $0 + $1.byteCount } <= 10_485_760)
        }
    }
}
