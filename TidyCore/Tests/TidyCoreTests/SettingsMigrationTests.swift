import Foundation
import Darwin
import Dispatch
import Testing
@testable import TidyCore

// Makes only the owned directory read-only after successful bootstrap sync.
private final class BootstrapDirectoryReadOnlyIO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let directory: URL
    private var changedMode = false
    init(directory: URL) { self.directory = directory }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        try base.write(fd: fd, bytes: bytes, offset: offset)
    }
    func syncFile(fd: Int32) throws { try base.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
    }
    func syncDirectory(fd: Int32) throws {
        try base.syncDirectory(fd: fd)
        guard !changedMode else { return }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &path) == 0,
              String(cString: path) == directory.path else { throw POSIXError(.EINVAL) }
        var marker = stat()
        guard fstatat(fd, "config.pending.json", &marker, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else { throw POSIXError(.EINVAL) }
        guard fchmod(fd, 0o500) == 0 else { throw POSIXError(.EACCES) }
        changedMode = true
    }
}

// Changes only the real, owned pending marker after a real P4 directory sync.
private final class MarkerByteChangeIO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private var configRenamed = false
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        try base.write(fd: fd, bytes: bytes, offset: offset)
    }
    func syncFile(fd: Int32) throws { try base.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
        if destination == "config.json" { configRenamed = true }
    }
    func syncDirectory(fd: Int32) throws {
        try base.syncDirectory(fd: fd)
        guard configRenamed else { return }
        configRenamed = false
        let marker = openat(fd, "config.pending.json", O_WRONLY | O_APPEND | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard marker >= 0 else { throw POSIXError(.EBADF) }
        defer { close(marker) }
        var info = stat()
        guard fstat(marker, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid() else { throw POSIXError(.EINVAL) }
        let changed = Data(" altered-marker".utf8)
        try JournalCheckedWrite.write(fd: marker, bytes: changed, io: base)
    }
}

extension SettingsPublicationTests {
    @Test(arguments: ["schema", "threshold", "profiles", "list", "string", "encodedBytes"])
    func wholePreferenceValidationPrecedesEvenDirectoryCreation(kind: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let directory = s.root.appendingPathComponent("new-settings", isDirectory: true)
        let url = directory.appendingPathComponent("config.json")
        let io = SettingsFaultIO(), store = SettingsStore(url: url, io: io)
        #expect(await store.load().disposition == .newDefaults)
        var invalid = TidyConfig(schemaVersion: 2)
        switch kind {
        case "schema": invalid.schemaVersion = 1
        case "threshold": invalid.staleNodeModulesThresholdDays = 6
        case "profiles": invalid.presets = Array(repeating: CustomPreset(name: "p", itemIDs: []), count: 51)
        case "list": invalid.appsApprovedForQuit = Array(repeating: "inert name", count: 1001)
        case "string": invalid.keepCookieDomains = [String(repeating: "x", count: 4097)]
        default: invalid.gitRoots = Array(repeating: String(repeating: "x", count: 4096), count: 256)
        }
        await expectStoreError(kind == "encodedBytes" ? .oversized : .invalidChange) {
            _ = try await store.update(expectedRevision: 0, change: .legacyPreferences(invalid))
        }
        #expect(io.trace().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path).isEmpty)
        #expect(await store.load().disposition == .newDefaults)
    }

    @Test func explicitFirstSaveCreatesOwnerOnlyDirectoryAndNoFakeBackup() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let directory = s.root.appendingPathComponent("new-settings", isDirectory: true)
        let url = directory.appendingPathComponent("config.json")
        let store = SettingsStore(url: url)
        #expect(await store.load().disposition == .newDefaults)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        var value = TidyConfig(schemaVersion: 2)
        value.presets = [CustomPreset(name: "Inert", itemIDs: ["unknown.id"])]
        let saved = try await store.update(expectedRevision: 0, change: .legacyPreferences(value))
        #expect(saved.revision == 1 && saved.config == value)
        #expect(try mode(directory) == 0o700)
        for name in ["config.json", "config.lock", "config.store.json"] {
            #expect(try mode(directory.appendingPathComponent(name)) == 0o600)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() ==
            ["config.json", "config.lock", "config.store.json"])
        #expect(await SettingsStore(url: url).load().envelope == saved)
    }

    @Test func bootstrapCompletionThenMarkerCreateFailureLatchesOriginalActor() async throws {
        guard geteuid() != 0 else { Issue.record("Requires ordinary unprivileged test user"); return }
        let s = try SettingsScratch(); defer { s.remove() }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: s.root.path) }
        let original = SettingsEnvelope(schemaVersion: 2, revision: 41, config: TidyConfig(schemaVersion: 2))
        let bytes = try JSONEncoder().encode(original); try s.seed(bytes)
        let store = SettingsStore(url: s.file, io: BootstrapDirectoryReadOnlyIO(directory: s.root))
        #expect(await store.load().envelope == original)
        await expectStoreError(.writeFailed) {
            _ = try await store.update(expectedRevision: 41, change: .transcriptAgeDays(60))
        }
        let failure = try #require(await store.lastPublicationFailure())
        #expect(failure.stage == "marker.create" && failure.errno == EACCES)
        #expect(try mode(s.root) == 0o500)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: s.root.path)
        let latched = await store.load()
        #expect(latched.disposition == .recoveryReadOnly && latched.envelope == nil)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.update(expectedRevision: 41, change: .transcriptAgeDays(90))
        }
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path).sorted() ==
            ["config.json", "config.lock", "config.store.json"])
        // Complete metadata over an unchanged standalone schema2 file is readable on
        // a fresh actor. It does not retroactively prove that the failed edit committed.
        let reopened = await SettingsStore(url: s.file).load()
        #expect(reopened.disposition == .loaded && reopened.envelope == original)
    }

    @Test func changedMarkerBytesCannotBeDeletedDuringFinalization() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture("v1-original"); try s.seed(original)
        let store = SettingsStore(url: s.file, io: MarkerByteChangeIO())
        _ = await store.load()
        await expectStoreError(.finalizationBlocked) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        let marker = s.root.appendingPathComponent("config.pending.json")
        let retained = try Data(contentsOf: marker)
        #expect(String(decoding: retained, as: UTF8.self).hasSuffix(" altered-marker"))
        #expect(try Data(contentsOf: s.backup) == original)
        #expect(await store.load().disposition == .recoveryReadOnly)
        #expect(await SettingsStore(url: s.file).load().disposition == .recoveryReadOnly)
        #expect(try Data(contentsOf: marker) == retained)
    }

    @Test func rejectedAdmissionDoesNotEraseLastActualPublicationFailure() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture("v1-original"); try s.seed(original)
        let store = SettingsStore(url: s.file); _ = await store.load()
        guard geteuid() != 0 else { Issue.record("Requires ordinary unprivileged test user"); return }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: s.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: s.root.path) }
        await expectStoreError(.writeFailed) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        let failure = try #require(await store.lastPublicationFailure())
        #expect(failure.stage == "bootstrap.lock.create" && failure.errno == EACCES)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: s.root.path)
        let future = try fixture("v999"); try s.seed(future)
        await expectStoreError(.changedExternally) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        #expect(await store.lastPublicationFailure() == failure)
        #expect(try Data(contentsOf: s.file) == future)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
    }
}

extension SettingsMigrationTests {
    @Test(arguments: ["v1-original", "v1-memory"])
    func bothHistoricalShapesPersistRoundTrip(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture(name); try s.seed(original)
        let store = SettingsStore(url: s.file)
        let result = await store.load()
        #expect(result.disposition == .migrated)
        let envelope = try #require(result.envelope)
        let c = envelope.config
        #expect(c.schemaVersion == 2 && c.hasCompletedOnboarding)
        #expect(c.gitRoots == ["/fixture/Developer", "/fixture/Other"])
        #expect(c.keepCookieDomains == ["example.invalid", "keep.invalid"])
        #expect(c.simulatorsApprovedForDeletion == ["Old simulator name"])
        #expect(c.staleNodeModulesThresholdDays == 90 && c.transcriptAgeThresholdDays == 120)
        #expect(c.presets == [CustomPreset(name: "Weekly", itemIDs: [
            "safe.tool.npm-cache-clean", "unknown.preset.id", "deep.simulator.erase-all"])])
        #expect(c.appsApprovedForQuit == (name == "v1-memory" ? ["Old application name"] : []))
        #expect(c.allowRestartToReclaimSwap == (name == "v1-memory"))
        #expect(try Data(contentsOf: s.file) == original) // load never writes
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        let saved = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(121))
        #expect(saved.revision == 1 && saved.config.transcriptAgeThresholdDays == 121)
        #expect(saved.config.gitRoots == c.gitRoots && saved.config.presets == c.presets)
        #expect(try Data(contentsOf: s.backup) == original)
        let reopened = await SettingsStore(url: s.file).load()
        #expect(reopened.disposition == .loaded && reopened.envelope == saved)
        #expect(try mode(s.root) == 0o700)
        #expect(try mode(s.file) == 0o600 && mode(s.backup) == 0o600)
    }

    @Test func realWriteFailureLeavesExistingConfigAndRevision() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        let store = SettingsStore(url: s.file); _ = await store.load()
        guard geteuid() != 0 else { Issue.record("Requires ordinary unprivileged test user"); return }
        // Real pre-publication EACCES in this exact disposable directory. Because
        // load is read-only and has not created config.lock, the first failure may
        // be stable-lock creation, not candidate-temp creation. Do not claim a
        // later write stage without observing that the real lock was established.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: s.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: s.root.path) }
        await expectStoreError(.writeFailed) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(await store.load().envelope?.revision == 0)
    }

    @Test func staleRevisionAndExternalReplacementCannotOverwrite() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let store = SettingsStore(url: s.file); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let first = try Data(contentsOf: s.file)
        await expectStoreError(.staleRevision) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        }
        #expect(try Data(contentsOf: s.file) == first)
        let future = try fixture("v999"); try s.seed(future)
        await expectStoreError(.changedExternally) {
            _ = try await store.update(expectedRevision: 1, change: .transcriptAgeDays(90))
        }
        #expect(try Data(contentsOf: s.file) == future)
    }

    @Test func invalidEditAndExplicitRollback() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-memory"); try s.seed(bytes)
        let store = SettingsStore(url: s.file); _ = await store.load()
        await expectStoreError(.invalidChange) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(366))
        }
        #expect(try Data(contentsOf: s.file) == bytes)
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let preview = try await store.previewRollback()
        let restored = try await store.rollback(expectedRevision: 1, preview: preview)
        #expect(restored.revision == 2 && restored.config.transcriptAgeThresholdDays == 120)
        #expect(restored.config.presets.first?.itemIDs.contains("unknown.preset.id") == true)
    }

    @Test func revisionOverflowNeverWrapsOrWrites() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try schema2(revision: UInt64.max); try s.seed(bytes)
        let store = SettingsStore(url: s.file); _ = await store.load()
        await expectStoreError(.revisionOverflow) {
            _ = try await store.update(expectedRevision: UInt64.max, change: .transcriptAgeDays(90))
        }
        #expect(try Data(contentsOf: s.file) == bytes)
    }

    @Test func ownedLegacy755DirectoryAnd644FileSaveOwnerOnlyCopies() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: s.file.path)
        let store = SettingsStore(url: s.file); let result = await store.load()
        #expect(result.disposition == .migrated && result.envelope != nil)
        #expect(try mode(s.root) == 0o755 && mode(s.file) == 0o644)
        #expect(try Data(contentsOf: s.file) == bytes)
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        #expect(try mode(s.root) == 0o755)
        #expect(try mode(s.file) == 0o600 && mode(s.backup) == 0o600)
        #expect(try Data(contentsOf: s.backup) == bytes)
    }

    @Test func replacingBackupAfterPreviewCannotRollbackDifferentValue() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let store = SettingsStore(url: s.file); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        let preview = try await store.previewRollback()
        let current = try Data(contentsOf: s.file)
        let replacement = try fixture("v1-memory")
        try replacement.write(to: s.backup, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: s.backup.path)
        await expectStoreError(.changedExternally) {
            _ = try await store.rollback(expectedRevision: 1, preview: preview)
        }
        #expect(try Data(contentsOf: s.file) == current)
        #expect(try Data(contentsOf: s.backup) == replacement)
    }

    @Test func recoveryCannotUsePreviouslyIssuedRollbackPreview() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let store = SettingsStore(url: s.file); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        let preview = try await store.previewRollback()
        let future = try schema2(extra: ["registryPreferences": ["unknown.key": true]])
        try s.seed(future)
        #expect(await store.load().disposition == .recoveryReadOnly)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.rollback(expectedRevision: 1, preview: preview)
        }
        #expect(try Data(contentsOf: s.file) == future)
    }
}

private enum SettingsIOFault: String, CaseIterable, Sendable {
    case bootstrapLockWrite, bootstrapLockSync, bootstrapStoreWrite, bootstrapStoreSync, bootstrapDirectorySync
    case markerSync, preparedDirectorySync, candidateShortWrite, candidateSync, backupSync
    case backupRenameBefore, backupRenameAfter, backupDirectorySync
    case configRenameBefore, configRenameAfter, configDirectorySync, markerRemoval
    static let bootstrap: [Self] = [.bootstrapLockWrite, .bootstrapLockSync,
        .bootstrapStoreWrite, .bootstrapStoreSync, .bootstrapDirectorySync]
    static let publication: [Self] = [.markerSync, .preparedDirectorySync, .candidateShortWrite,
        .candidateSync, .backupSync, .backupRenameBefore, .backupRenameAfter, .backupDirectorySync,
        .configRenameBefore, .configRenameAfter, .configDirectorySync, .markerRemoval]
    var failureStage: String {
        switch self {
        case .bootstrapLockWrite: "bootstrap.lock.write"
        case .bootstrapLockSync: "bootstrap.lock.syncFile"
        case .bootstrapStoreWrite: "bootstrap.store.write"
        case .bootstrapStoreSync: "bootstrap.store.syncFile"
        case .bootstrapDirectorySync: "bootstrap.syncDirectory"
        case .markerSync: "marker.syncFile"
        case .preparedDirectorySync: "prepared.syncDirectory"
        case .candidateShortWrite: "candidate.write"
        case .candidateSync: "candidate.syncFile"
        case .backupSync: "backup.syncFile"
        case .backupRenameBefore, .backupRenameAfter: "backup.replace"
        case .backupDirectorySync: "backup.syncDirectory"
        case .configRenameBefore, .configRenameAfter: "config.replace"
        case .configDirectorySync: "config.syncDirectory"
        case .markerRemoval: "finalize.marker.unlink"
        }
    }
    var expectedErrno: Int32 {
        switch self {
        case .backupRenameBefore, .configRenameBefore: ENOENT
        case .markerRemoval: EACCES
        default: EBADF
        }
    }
}
private enum FaultHarnessError: Error { case unexpectedSyscallSuccess }

private final class SettingsFaultIO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let lock = NSLock()
    private var fault: SettingsIOFault?
    private var publication = "prepared"
    private var failNextCandidateWrite = false
    private var events: [String] = []

    func arm(_ value: SettingsIOFault) {
        lock.lock(); defer { lock.unlock() }
        fault = value; publication = "prepared"; events = []; failNextCandidateWrite = false
    }
    func trace() -> [String] { lock.lock(); defer { lock.unlock() }; return events }
    private func record(_ value: String) { lock.lock(); events.append(value); lock.unlock() }
    private func consume(_ value: SettingsIOFault) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard fault == value else { return false }
        fault = nil; events.append("fault.consumed.\(value.rawValue)"); return true
    }
    private func name(_ fd: Int32) throws -> String {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &path) == 0 else { throw POSIXError(.EBADF) }
        return URL(fileURLWithPath: String(cString: path)).lastPathComponent
    }
    private func failingSyscall<T>(_ fault: SettingsIOFault, _ body: () throws -> T) throws -> T {
        do { _ = try body(); throw FaultHarnessError.unexpectedSyscallSuccess }
        catch let error as POSIXError {
            record("fault.errno.\(fault.rawValue).\(error.code.rawValue)")
            throw error
        }
    }
    private func fileStage(_ file: String) -> String {
        if file == "config.lock" { return "bootstrap.lock" }
        if file == "config.store.json" { return "bootstrap.store" }
        if file == "config.pending.json" { return "marker" }
        if file.hasPrefix(".config-candidate-") { return "candidate" }
        if file.hasPrefix(".config-backup-") { return "backup" }
        return "other"
    }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        let stage = fileStage(try name(fd)), candidate = stage == "candidate"
        record(stage + ".write.begin")
        if stage == "bootstrap.lock" && consume(.bootstrapLockWrite) {
            return try failingSyscall(.bootstrapLockWrite) { try base.write(fd: -1, bytes: bytes, offset: offset) }
        }
        if stage == "bootstrap.store" && consume(.bootstrapStoreWrite) {
            return try failingSyscall(.bootstrapStoreWrite) { try base.write(fd: -1, bytes: bytes, offset: offset) }
        }
        lock.lock()
        let fail = candidate && failNextCandidateWrite
        if fail { failNextCandidateWrite = false }
        lock.unlock()
        if fail {
            return try failingSyscall(.candidateShortWrite) { try base.write(fd: -1, bytes: bytes, offset: offset) }
        }
        if candidate && consume(.candidateShortWrite) {
            lock.lock(); failNextCandidateWrite = true; lock.unlock()
            let written = try base.write(fd: fd, bytes: Data(bytes.dropFirst(offset).prefix(1)), offset: 0)
            record("candidate.write.oneByte.\(written)")
            return written
        }
        let written = try base.write(fd: fd, bytes: bytes, offset: offset)
        record(stage + ".write.succeeded")
        return written
    }
    func syncFile(fd: Int32) throws {
        let stage = fileStage(try name(fd))
        record(stage + ".syncFile.begin")
        let wanted: SettingsIOFault?
        switch stage {
        case "bootstrap.lock": wanted = .bootstrapLockSync
        case "bootstrap.store": wanted = .bootstrapStoreSync
        case "marker": wanted = .markerSync
        case "candidate": wanted = .candidateSync
        case "backup": wanted = .backupSync
        default: wanted = nil
        }
        if let wanted, consume(wanted) {
            return try failingSyscall(wanted) { try base.syncFile(fd: -1) }
        }
        try base.syncFile(fd: fd)
        record(stage + ".syncFile.succeeded")
    }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        let stage: String?
        if destination == "config.backup.json" { stage = "backup" }
        else if destination == "config.json" { stage = "config" }
        else { stage = nil }
        if let stage {
            record(stage + ".replace.begin")
            lock.lock(); publication = stage; lock.unlock()
            let before: SettingsIOFault = stage == "backup" ? .backupRenameBefore : .configRenameBefore
            if consume(before) {
                return try failingSyscall(before) {
                    try base.replace(directoryFD: directoryFD,
                        temporary: ".config-guaranteed-absent-\(UUID().uuidString)", destination: destination)
                }
            }
        }
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
        if let stage {
            record(stage + ".renamed")
            let after: SettingsIOFault = stage == "backup" ? .backupRenameAfter : .configRenameAfter
            if consume(after) { return try failingSyscall(after) { try base.syncDirectory(fd: -1) } }
        }
    }
    func syncDirectory(fd: Int32) throws {
        lock.lock(); let published = publication; lock.unlock()
        var marker = stat()
        let pendingExists = fstatat(fd, "config.pending.json", &marker, AT_SYMLINK_NOFOLLOW) == 0
        let stage = pendingExists ? published : "bootstrap"
        let wanted: SettingsIOFault = stage == "config" ? .configDirectorySync :
            (stage == "backup" ? .backupDirectorySync :
                (stage == "bootstrap" ? .bootstrapDirectorySync : .preparedDirectorySync))
        record(stage + ".syncDirectory.begin")
        if consume(wanted) { return try failingSyscall(wanted) { try base.syncDirectory(fd: -1) } }
        try base.syncDirectory(fd: fd)
        record(stage + ".syncDirectory.succeeded")
        if stage == "config" {
            if consume(.markerRemoval) {
                guard fchmod(fd, 0o500) == 0 else { throw POSIXError(.EACCES) }
                record("markerRemoval.directoryMode500")
            }
        }
    }
}

private func expectExactFault(_ fault: SettingsIOFault, io: SettingsFaultIO,
                              store: SettingsStore) async throws {
    let calls = io.trace()
    #expect(calls.filter { $0.hasPrefix("fault.consumed.") } == ["fault.consumed.\(fault.rawValue)"])
    let failure = try #require(await store.lastPublicationFailure())
    #expect(failure.stage == fault.failureStage)
    #expect(failure.errno == fault.expectedErrno)
    let required: [String]
    let forbidden: [String]
    switch fault {
    case .bootstrapLockWrite:
        required = ["bootstrap.lock.write.begin"]
        forbidden = ["bootstrap.lock.syncFile", "bootstrap.store", "marker.", "candidate.", "backup.", "config."]
    case .bootstrapLockSync:
        required = ["bootstrap.lock.write.succeeded", "bootstrap.lock.syncFile.begin"]
        forbidden = ["bootstrap.store", "bootstrap.syncDirectory", "marker.", "candidate.", "backup.", "config."]
    case .bootstrapStoreWrite:
        required = ["bootstrap.lock.syncFile.succeeded", "bootstrap.store.write.begin"]
        forbidden = ["bootstrap.store.syncFile", "bootstrap.syncDirectory", "marker.", "candidate.", "backup.", "config."]
    case .bootstrapStoreSync:
        required = ["bootstrap.lock.syncFile.succeeded", "bootstrap.store.write.succeeded", "bootstrap.store.syncFile.begin"]
        forbidden = ["bootstrap.syncDirectory", "marker.", "candidate.", "backup.", "config."]
    case .bootstrapDirectorySync:
        required = ["bootstrap.lock.syncFile.succeeded", "bootstrap.store.syncFile.succeeded", "bootstrap.syncDirectory.begin"]
        forbidden = ["bootstrap.syncDirectory.succeeded", "marker.", "candidate.", "backup.", "config."]
    case .markerSync:
        required = ["marker.write.succeeded", "marker.syncFile.begin"]
        forbidden = ["prepared.syncDirectory", "candidate.", "backup.", "config."]
    case .preparedDirectorySync:
        required = ["marker.syncFile.succeeded", "prepared.syncDirectory.begin"]
        forbidden = ["prepared.syncDirectory.succeeded", "candidate.", "backup.", "config."]
    case .candidateShortWrite:
        required = ["prepared.syncDirectory.succeeded", "candidate.write.begin",
                    "fault.consumed.candidateShortWrite", "candidate.write.oneByte.1", "candidate.write.begin"]
        forbidden = ["candidate.syncFile", "backup.", "config."]
        #expect(calls.filter { $0 == "candidate.write.begin" }.count == 2)
    case .candidateSync:
        required = ["prepared.syncDirectory.succeeded", "candidate.write.succeeded", "candidate.syncFile.begin"]
        forbidden = ["candidate.syncFile.succeeded", "backup.", "config."]
    case .backupSync:
        required = ["candidate.syncFile.succeeded", "backup.write.succeeded", "backup.syncFile.begin"]
        forbidden = ["backup.syncFile.succeeded", "backup.replace", "backup.renamed", "config."]
    case .backupRenameBefore:
        required = ["backup.syncFile.succeeded", "backup.replace.begin"]
        forbidden = ["backup.renamed", "backup.syncDirectory", "config."]
    case .backupRenameAfter:
        required = ["backup.syncFile.succeeded", "backup.replace.begin", "backup.renamed"]
        forbidden = ["backup.syncDirectory", "config."]
    case .backupDirectorySync:
        required = ["backup.renamed", "backup.syncDirectory.begin"]
        forbidden = ["backup.syncDirectory.succeeded", "config."]
    case .configRenameBefore:
        required = ["backup.renamed", "backup.syncDirectory.succeeded", "config.replace.begin"]
        forbidden = ["config.renamed", "config.syncDirectory"]
    case .configRenameAfter:
        required = ["backup.syncDirectory.succeeded", "config.replace.begin", "config.renamed"]
        forbidden = ["config.syncDirectory"]
    case .configDirectorySync:
        required = ["backup.syncDirectory.succeeded", "config.renamed", "config.syncDirectory.begin"]
        forbidden = ["config.syncDirectory.succeeded", "markerRemoval."]
    case .markerRemoval:
        required = ["config.renamed", "config.syncDirectory.succeeded",
                    "fault.consumed.markerRemoval", "markerRemoval.directoryMode500"]
        forbidden = []
        #expect(calls.filter { $0 == "config.syncDirectory.begin" }.count == 1)
        #expect(calls.last == "markerRemoval.directoryMode500")
        #expect(calls.filter { $0.hasPrefix("fault.errno.") }.isEmpty)
    }
    var cursor = 0
    for event in required {
        guard let index = calls[cursor...].firstIndex(of: event) else {
            Issue.record("Missing ordered stage \(event) for \(fault.rawValue): \(calls)"); return
        }
        cursor = index + 1
    }
    for prefix in forbidden { #expect(!calls.contains { $0.hasPrefix(prefix) }) }
    if fault != .markerRemoval {
        let errorEvent = "fault.errno.\(fault.rawValue).\(fault.expectedErrno)"
        #expect(calls.filter { $0.hasPrefix("fault.errno.") } == [errorEvent])
        #expect(calls.last == errorEvent) // no later write/sync/rename after observed failure
    }
}

// Scheduling-only pause after a real lock-identity write while the production
// bootstrap still holds flock. It supplies neither data nor a success result.
private final class PausingBootstrapIO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let condition = NSCondition()
    private var entered = false, released = false, paused = false
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
    private func hasEntered() -> Bool { condition.lock(); defer { condition.unlock() }; return entered }
    func waitForEntry() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if hasEntered() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        let written = try base.write(fd: fd, bytes: bytes, offset: offset)
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &path) == 0 else { throw POSIXError(.EBADF) }
        guard URL(fileURLWithPath: String(cString: path)).lastPathComponent == "config.lock" else { return written }
        condition.lock(); defer { condition.unlock() }
        if paused { return written }; paused = true; entered = true; condition.broadcast()
        let deadline = Date().addingTimeInterval(5)
        while !released {
            guard condition.wait(until: deadline) else { throw POSIXError(.ETIMEDOUT) }
        }
        return written
    }
    func syncFile(fd: Int32) throws { try base.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
    }
    func syncDirectory(fd: Int32) throws { try base.syncDirectory(fd: fd) }
}

private struct HeldSettingsLockResult: Sendable {
    let acquired: Bool
    let watchdogFired: Bool
    let failureErrno: Int32?
}

// Only this dedicated Thread owns the FD: open/flock/unlock/close all occur
// there. Test continuations receive observations, never an FD to close/reuse.
private final class HeldSettingsLockThread: @unchecked Sendable {
    private let path: String
    private let state = NSLock()
    private var started = false, acquired = false, releaseRequested = false
    private var watchdogFired = false
    private var result: HeldSettingsLockResult?
    private var readyWaiters: [CheckedContinuation<Bool, Never>] = []
    private var joinWaiters: [CheckedContinuation<HeldSettingsLockResult, Never>] = []

    init(lockURL: URL) { path = lockURL.path }
    func start() {
        state.lock(); precondition(!started); started = true; state.unlock()
        Thread { [self] in run() }.start()
    }
    func release() { state.lock(); releaseRequested = true; state.unlock() }
    private func shouldRelease() -> Bool {
        state.lock(); defer { state.unlock() }; return releaseRequested
    }
    func waitUntilReady() async -> Bool {
        await withCheckedContinuation { continuation in
            state.lock()
            if acquired { state.unlock(); continuation.resume(returning: true) }
            else if result != nil { state.unlock(); continuation.resume(returning: false) }
            else { readyWaiters.append(continuation); state.unlock() }
        }
    }
    // Completion is published only after the owning Thread has unlocked and
    // closed its FD. There is no remaining filesystem work after this join.
    func join() async -> HeldSettingsLockResult {
        await withCheckedContinuation { continuation in
            state.lock()
            if let result { state.unlock(); continuation.resume(returning: result) }
            else { joinWaiters.append(continuation); state.unlock() }
        }
    }
    private func publishReady() {
        state.lock(); acquired = true
        let waiters = readyWaiters; readyWaiters = []; state.unlock()
        for waiter in waiters { waiter.resume(returning: true) }
    }
    private func finish(_ failure: Int32?) {
        state.lock()
        let completed = HeldSettingsLockResult(acquired: acquired,
            watchdogFired: watchdogFired, failureErrno: failure)
        result = completed
        let ready = readyWaiters, joined = joinWaiters
        readyWaiters = []; joinWaiters = []; state.unlock()
        for waiter in ready { waiter.resume(returning: false) }
        for waiter in joined { waiter.resume(returning: completed) }
    }
    private func run() {
        let fd = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { finish(errno); return }
        var failure: Int32?
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            failure = errno
        } else {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            publishReady()
            while !shouldRelease() {
                if ContinuousClock.now >= deadline {
                    state.lock(); watchdogFired = true; state.unlock()
                    break
                }
                // Relative short sleep; the deadline comparison is monotonic.
                // OS descheduling may delay it; no hard real-time claim.
                usleep(10_000)
            }
            if flock(fd, LOCK_UN) != 0 { failure = errno }
        }
        if close(fd) != 0, failure == nil { failure = errno }
        finish(failure) // last action, after all FD work on this same Thread
    }
}

// Bound this batch of synchronous storage/FIFO/pause fixtures without serializing
// the full test run or either contention test's independent actors and Thread.
@Suite("Settings publication", .serialized)
struct SettingsPublicationTests {
    @Test func invalidLegacyEditCannotBootstrapAndValidEditStillSucceeds() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture("v1-original"); try s.seed(original)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: s.file.path)
        let io = SettingsFaultIO(), store = SettingsStore(url: s.file, io: io)
        #expect(await store.load().disposition == .migrated)
        await expectStoreError(.invalidChange) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(366))
        }
        await expectStoreError(.staleRevision) {
            _ = try await store.update(expectedRevision: 9, change: .transcriptAgeDays(60))
        }
        #expect(io.trace().isEmpty)
        #expect(try Data(contentsOf: s.file) == original)
        #expect(try mode(s.root) == 0o755 && mode(s.file) == 0o644)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
        let fresh = SettingsStore(url: s.file)
        let loaded = await fresh.load()
        #expect(loaded.disposition == .migrated && loaded.envelope?.revision == 0)
        let saved = try await fresh.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        #expect(saved.revision == 1 && saved.config.transcriptAgeThresholdDays == 60)
        #expect(try Data(contentsOf: s.backup) == original)
        #expect(try mode(s.root) == 0o755 && mode(s.file) == 0o600 && mode(s.backup) == 0o600)
    }

    @Test(arguments: SettingsIOFault.bootstrap)
    fileprivate func bootstrapFaultNeverPublishesConfigAndPreservesReopenEvidence(fault: SettingsIOFault) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture("v1-original"); try s.seed(original)
        let io = SettingsFaultIO(), store = SettingsStore(url: s.file, io: io)
        #expect(await store.load().disposition == .migrated)
        io.arm(fault)
        await expectStoreError(.writeFailed) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        try await expectExactFault(fault, io: io, store: store)
        #expect(try Data(contentsOf: s.file) == original)
        #expect(try mode(s.root) == 0o700 && mode(s.file) == 0o600)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.pending.json").path))
        let names = try FileManager.default.contentsOfDirectory(atPath: s.root.path).sorted()
        var evidence: [String: Data] = [:]
        for name in names { evidence[name] = try Data(contentsOf: s.root.appendingPathComponent(name)) }
        #expect(names.contains("config.lock"))
        #expect(await store.load().disposition == .recoveryReadOnly)
        let fresh = SettingsStore(url: s.file)
        let reopened = await fresh.load()
        #expect(reopened.disposition == .recoveryReadOnly && reopened.envelope == nil)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await fresh.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path).sorted() == names)
        for (name, bytes) in evidence { #expect(try Data(contentsOf: s.root.appendingPathComponent(name)) == bytes) }
    }

    @Test func independentStoreCannotOverwriteNewerDiskRevision() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let a = SettingsStore(url: s.file), bIO = SettingsFaultIO()
        let b = SettingsStore(url: s.file, io: bIO)
        _ = await a.load(); _ = await b.load()
        _ = try await a.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let newest = try Data(contentsOf: s.file), backup = try Data(contentsOf: s.backup)
        await expectStoreError(.changedExternally) {
            _ = try await b.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        }
        #expect(bIO.trace().isEmpty)
        #expect(try Data(contentsOf: s.file) == newest && Data(contentsOf: s.backup) == backup)
        #expect(await b.load().envelope?.revision == 1)
        let second = try await b.update(expectedRevision: 1, change: .transcriptAgeDays(90))
        #expect(second.revision == 2 && second.config.transcriptAgeThresholdDays == 90)
    }

    @Test func independentHeldLockBlocksWithoutWritingThenExplicitRetrySucceeds() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let first = SettingsStore(url: s.file); _ = await first.load()
        _ = try await first.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let io = SettingsFaultIO(), second = SettingsStore(url: s.file, io: io)
        _ = await second.load()
        let lockURL = s.root.appendingPathComponent("config.lock")
        let holder = HeldSettingsLockThread(lockURL: lockURL)
        holder.start()
        do {
            let ready = await holder.waitUntilReady()
            if !ready {
                holder.release(); let joined = await holder.join()
                Issue.record("Dedicated lock holder failed to acquire: \(String(describing: joined.failureErrno))")
                return
            }
            let bytes = try Data(contentsOf: s.file)
            await expectStoreError(.unavailable) {
                _ = try await second.update(expectedRevision: 1, change: .transcriptAgeDays(90))
            }
            // A broken blocking flock cannot deadlock this test forever: the
            // independent Thread's watchdog releases its own lock, then the
            // unexpected update result and watchdog assertion both fail RED.
            holder.release()
            let joined = await holder.join()
            #expect(joined.acquired && joined.failureErrno == nil)
            #expect(!joined.watchdogFired)
            guard !joined.watchdogFired else { return } // no retry after defective blocking call
            #expect(try io.trace().isEmpty && Data(contentsOf: s.file) == bytes)
            // Holder FD is closed before this explicit retry.
            let saved = try await second.update(expectedRevision: 1, change: .transcriptAgeDays(90))
            #expect(saved.revision == 2)
        } catch {
            holder.release()
            let joined = await holder.join()
            #expect(!joined.watchdogFired && joined.failureErrno == nil)
            throw error
        }
    }

    @Test func independentBootstrapContenderCannotInitializeWinnersMetadata() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture("v1-original"); try s.seed(original)
        let pause = PausingBootstrapIO(), contenderIO = SettingsFaultIO()
        let winner = SettingsStore(url: s.file, io: pause)
        let contender = SettingsStore(url: s.file, io: contenderIO)
        _ = await winner.load(); _ = await contender.load()
        let task = Task { try await winner.update(expectedRevision: 0, change: .transcriptAgeDays(60)) }
        do {
            let entered = await pause.waitForEntry()
            if !entered {
                pause.release(); _ = await task.result
                Issue.record("Real bootstrap lock write was not reached within 2 seconds"); return
            }
            await expectStoreError(.unavailable) {
                _ = try await contender.update(expectedRevision: 0, change: .transcriptAgeDays(90))
            }
            #expect(contenderIO.trace().isEmpty)
            #expect(try Data(contentsOf: s.file) == original)
            #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.store.json").path))
            pause.release()
            let completed = await task.result
            let saved = try completed.get()
            #expect(saved.revision == 1 && saved.config.transcriptAgeThresholdDays == 60)
            await expectStoreError(.changedExternally) {
                _ = try await contender.update(expectedRevision: 0, change: .transcriptAgeDays(90))
            }
            #expect(await contender.load().envelope == saved)
        } catch {
            // Async-finally pattern: even a throwing Data read above must drain
            // the writer before the outer scratch-removal defer can execute.
            pause.release()
            _ = await task.result
            throw error
        }
    }

    @Test(arguments: SettingsIOFault.publication)
    fileprivate func faultsPreserveEvidenceAndBlockFreshStore(fault: SettingsIOFault) async throws {
        #expect(geteuid() != 0, "Requires ordinary unprivileged test user")
        guard geteuid() != 0 else { return }
        let s = try SettingsScratch(); defer { s.remove() }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: s.root.path) }
        try s.seed(try fixture("v1-original"))
        let io = SettingsFaultIO(), store = SettingsStore(url: s.file)
        _ = await store.load()
        // Bootstrap and one successful production transaction establish revision1.
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(61))
        let old = try Data(contentsOf: s.file), priorBackup = try Data(contentsOf: s.backup)
        let lockPath = s.root.appendingPathComponent("config.lock")
        let lockAttributes = try FileManager.default.attributesOfItem(atPath: lockPath.path)
        let lockInode = try #require(lockAttributes[.systemFileNumber] as? NSNumber)
        let failing = SettingsStore(url: s.file, io: io); _ = await failing.load()
        io.arm(fault)
        let expected: SettingsStoreError
        switch fault {
        case .configRenameBefore, .configRenameAfter, .configDirectorySync: expected = .durabilityUncertain
        case .markerRemoval: expected = .finalizationBlocked
        default: expected = .writeFailed
        }
        await expectStoreError(expected) {
            _ = try await failing.update(expectedRevision: 1, change: .transcriptAgeDays(92))
        }
        try await expectExactFault(fault, io: io, store: failing)
        let pending = s.root.appendingPathComponent("config.pending.json")
        #expect(FileManager.default.fileExists(atPath: pending.path))
        let observed = try Data(contentsOf: s.file)
        let calls = io.trace()
        switch fault {
        case .configRenameAfter, .configDirectorySync, .markerRemoval:
            #expect(calls.contains("config.renamed"))
            #expect(observed != old)
            let candidate = try JSONDecoder().decode(SettingsEnvelope.self, from: observed)
            #expect(candidate.revision == 2 && candidate.config.transcriptAgeThresholdDays == 92)
            #expect(try Data(contentsOf: s.backup) == old)
        default:
            #expect(observed == old)
            if calls.contains("backup.renamed") { #expect(try Data(contentsOf: s.backup) == old) }
            else { #expect(try Data(contentsOf: s.backup) == priorBackup) }
        }
        if fault == .configDirectorySync {
            #expect(calls.contains("fault.errno.configDirectorySync.\(EBADF)"))
            #expect(!calls.contains("config.syncDirectory.succeeded"))
        }
        if fault == .markerRemoval {
            #expect(calls.contains("config.syncDirectory.succeeded"))
            #expect(calls.contains("markerRemoval.directoryMode500"))
        }
        let latched = await failing.load()
        #expect(latched.disposition == .recoveryReadOnly && latched.envelope == nil)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await failing.update(expectedRevision: 1, change: .transcriptAgeDays(93))
        }
        await expectStoreError(.readOnlyRecovery) { _ = try await failing.previewRollback() }
        // Restore scratch permission solely for inspection; never remove the marker.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: s.root.path)
        let fresh = SettingsStore(url: s.file)
        let reopened = await fresh.load()
        #expect(reopened.disposition == .recoveryReadOnly && reopened.envelope == nil)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await fresh.update(expectedRevision: 1, change: .transcriptAgeDays(94))
        }
        #expect(try Data(contentsOf: s.file) == observed)
        #expect(FileManager.default.fileExists(atPath: pending.path))
        let after = try FileManager.default.attributesOfItem(atPath: lockPath.path)
        #expect(after[.systemFileNumber] as? NSNumber == lockInode)
        #expect(try mode(lockPath) == 0o600 && mode(pending) == 0o600)
    }

    @Test func firstSaveFailureNeverBecomesDefaultsOnRelaunch() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let io = SettingsFaultIO(), store = SettingsStore(url: s.file, io: io)
        #expect(await store.load().disposition == .newDefaults)
        io.arm(.configDirectorySync)
        await expectStoreError(.durabilityUncertain) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        let candidate = try JSONDecoder().decode(SettingsEnvelope.self, from: Data(contentsOf: s.file))
        #expect(candidate.revision == 1)
        #expect(io.trace().contains("config.renamed"))
        #expect(io.trace().contains("fault.consumed.configDirectorySync"))
        #expect(io.trace().contains("fault.errno.configDirectorySync.\(EBADF)"))
        #expect(io.trace().filter { $0.hasPrefix("fault.consumed.") } == ["fault.consumed.configDirectorySync"])
        #expect(io.trace().last == "fault.errno.configDirectorySync.\(EBADF)")
        #expect(!io.trace().contains("config.syncDirectory.succeeded"))
        let failure = try #require(await store.lastPublicationFailure())
        #expect(failure.stage == "config.syncDirectory" && failure.errno == EBADF)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
    }

    @Test func rollbackFailurePreservesPreRollbackBytesAndBlocksOldPreview() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let io = SettingsFaultIO(), store = SettingsStore(url: s.file, io: io)
        let original = try fixture("v1-memory"); try s.seed(original); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let beforeRollback = try Data(contentsOf: s.file)
        let preview = try await store.previewRollback()
        io.arm(.configDirectorySync)
        await expectStoreError(.durabilityUncertain) {
            _ = try await store.rollback(expectedRevision: 1, preview: preview)
        }
        try await expectExactFault(.configDirectorySync, io: io, store: store)
        #expect(try Data(contentsOf: s.backup) == beforeRollback)
        let candidate = try JSONDecoder().decode(SettingsEnvelope.self, from: Data(contentsOf: s.file))
        #expect(candidate.revision == 2 && candidate.config.transcriptAgeThresholdDays == 120)
        #expect(candidate.config.appsApprovedForQuit == ["Old application name"])
        #expect(candidate.config.presets.first?.itemIDs.contains("unknown.preset.id") == true)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.rollback(expectedRevision: 1, preview: preview)
        }
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
    }

    @Test func completedTransactionReopensButInitializedMissingFilesDoNotReset() async throws {
        for missing in ["config.json", "config.lock", "config.store.json"] {
            let s = try SettingsScratch(); defer { s.remove() }
            try s.seed(try fixture("v1-original"))
            let store = SettingsStore(url: s.file); _ = await store.load()
            let saved = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
            #expect(await SettingsStore(url: s.file).load().envelope == saved)
            #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.pending.json").path))
            let removed = s.root.appendingPathComponent(missing)
            try FileManager.default.removeItem(at: removed) // exact disposable initialized fixture
            let result = await SettingsStore(url: s.file).load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            #expect(!FileManager.default.fileExists(atPath: removed.path))
        }
    }

    @Test func unknownMetadataAndMarkerArePreservedWithoutAutomaticFinalization() async throws {
        for name in ["config.lock", "config.store.json", "config.pending.json"] {
            let s = try SettingsScratch(); defer { s.remove() }
            try s.seed(try fixture("v1-original"))
            let store = SettingsStore(url: s.file); _ = await store.load()
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
            let bytes = Data("{\"schema\":999,\"unknown\":true}".utf8)
            let target = s.root.appendingPathComponent(name)
            try bytes.write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            let result = await SettingsStore(url: s.file).load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            #expect(try Data(contentsOf: target) == bytes)
        }
    }

    @Test(arguments: [Data(), Data("{\"schema\":1,".utf8)])
    func partialMarkerBlocksEvenWhenConfigAndBackupAreValid(bytes: Data) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let store = SettingsStore(url: s.file); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let config = try Data(contentsOf: s.file), backup = try Data(contentsOf: s.backup)
        let pending = s.root.appendingPathComponent("config.pending.json")
        try bytes.write(to: pending)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pending.path)
        let fresh = SettingsStore(url: s.file)
        #expect(await fresh.load().disposition == .recoveryReadOnly)
        await expectStoreError(.readOnlyRecovery) { _ = try await fresh.previewRollback() }
        #expect(try Data(contentsOf: s.file) == config && Data(contentsOf: s.backup) == backup)
        #expect(try Data(contentsOf: pending) == bytes)
    }
}

extension SettingsPublicationTests {
    @Test(arguments: ["config.json", "config.backup.json", "config.lock", "config.store.json",
                      "config.pending.json", ".config-candidate-11111111-1111-1111-1111-111111111111",
                      ".config-backup-11111111-1111-1111-1111-111111111111"])
    func fifoInitializedSettingsAndArtifactsArePreserved(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        try s.seed(try fixture("v1-original"))
        let writer = SettingsStore(url: s.file); _ = await writer.load()
        _ = try await writer.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        let image = try SettingsFIFOImage(scratch: s, name: name)
        let store = SettingsStore(url: s.file)
        let loaded = try await withSettingsFIFORescue(image.fifo) { await store.load() }
        let result = try loaded.get()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        let edit = try await withSettingsFIFORescue(image.fifo) {
            try await store.update(expectedRevision: 1, change: .transcriptAgeDays(90))
        }
        expectFIFOStoreError(.readOnlyRecovery, result: edit)
        let preview = try await withSettingsFIFORescue(image.fifo) { try await store.previewRollback() }
        expectFIFOStoreError(.readOnlyRecovery, result: preview)
        try image.expectPreserved(in: s)
        if name != "config.lock" {
            let fd = open(s.root.appendingPathComponent("config.lock").path,
                          O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            try #require(fd >= 0)
            defer { close(fd) }
            let locked = flock(fd, LOCK_EX | LOCK_NB)
            #expect(locked == 0, "Read failure must release any transient settings lock")
            if locked == 0 { _ = flock(fd, LOCK_UN) }
        }
        // Keep objects alive: deinit must not provide the lock-release evidence.
        withExtendedLifetime((store, writer)) {}
    }
}


private func canonicalSettingsScratchBase() throws -> URL {
    var path = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath("/private/tmp", &path) != nil else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return URL(fileURLWithPath: String(cString: path), isDirectory: true)
}

private struct SettingsScratch {
    let root: URL
    var file: URL { root.appendingPathComponent("config.json") }
    var backup: URL { root.appendingPathComponent("config.backup.json") }
    init() throws {
        root = try canonicalSettingsScratchBase()
            .appendingPathComponent("T05-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
    }
    func seed(_ bytes: Data) throws {
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json",
                                             subdirectory: "Config"))
    return try Data(contentsOf: url)
}
private func expectStoreError(_ expected: SettingsStoreError,
                             _ body: () async throws -> Void) async {
    do { try await body(); Issue.record("Expected \(expected)") }
    catch let error as SettingsStoreError { #expect(error == expected) }
    catch { Issue.record("Unexpected error: \(error)") }
}
private func mode(_ url: URL) throws -> Int {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attrs[.posixPermissions] as? NSNumber).intValue & 0o777
}

@Suite("Settings migration")
struct SettingsMigrationTests {
    @Test func missingOnlyCreatesInMemoryDefaults() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .newDefaults)
        let value = try #require(result.envelope)
        #expect(value.schemaVersion == 2 && value.revision == 0)
        #expect(value.config.gitRoots.isEmpty && value.config.presets.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: s.file.path))
    }

    @Test(arguments: ["v1-original", "v1-memory"])
    func bothHistoricalShapes(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture(name); try s.seed(original)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .migrated && result.recoveryReason == nil)
        let envelope = try #require(result.envelope)
        #expect(envelope.schemaVersion == 2 && envelope.revision == 0)
        let c = envelope.config
        #expect(c.schemaVersion == 2 && c.hasCompletedOnboarding)
        #expect(c.gitRoots == ["/fixture/Developer", "/fixture/Other"])
        #expect(c.keepCookieDomains == ["example.invalid", "keep.invalid"])
        #expect(c.simulatorsApprovedForDeletion == ["Old simulator name"])
        #expect(c.staleNodeModulesThresholdDays == 90 && c.transcriptAgeThresholdDays == 120)
        #expect(c.presets == [CustomPreset(name: "Weekly", itemIDs: [
            "safe.tool.npm-cache-clean", "unknown.preset.id", "deep.simulator.erase-all"])])
        #expect(c.appsApprovedForQuit == (name == "v1-memory" ? ["Old application name"] : []))
        #expect(c.allowRestartToReclaimSwap == (name == "v1-memory"))
        #expect(try Data(contentsOf: s.file) == original)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
    }


    @Test(arguments: ["corrupt", "v999"])
    func recoveryPreservesBytes(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture(name); try s.seed(bytes)
        let store = SettingsStore(url: s.file); let result = await store.load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(result.recoveryReason == (name == "v999" ? .unsupportedSchema(999) : .malformed))
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        await expectStoreError(.readOnlyRecovery) { _ = try await store.previewRollback() }
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
    }

    @Test(arguments: [Data(), Data("{\"schemaVersion\":1,\"hasCompletedOnboarding\":false}".utf8),
                       Data("{\"schemaVersion\":1,\"schemaVersion\":2}".utf8),
                       Data(repeating: 0x20, count: 1_048_577), Data([0xff, 0xfe])])
    func existingInvalidIsNeverNewDefaults(bytes: Data) async throws {
        let s = try SettingsScratch(); defer { s.remove() }; try s.seed(bytes)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(try Data(contentsOf: s.file) == bytes)
    }

    @Test func symlinkDoesNotAuthorizeReadingOrReplacingDestination() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let target = s.root.appendingPathComponent("other.json")
        let bytes = try fixture("v1-original"); try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: s.file, withDestinationURL: target)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly)
        #expect(try Data(contentsOf: target) == bytes)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: s.file.path) == target.path)
    }
    @Test func oldReportsHaveUnavailableMemoryNotMeasuredZero() throws {
        let report = try JSONDecoder().decode(RunReport.self, from: fixture("old-report"))
        #expect(report.totalFreedBytes == 13)
        #expect(report.results[0].measuredReclaimedMemoryBytes == nil)
        #expect(report.measuredTotalReclaimedMemoryBytes == nil)
        let roundTrip = try JSONDecoder().decode(RunReport.self, from: JSONEncoder().encode(report))
        #expect(roundTrip.measuredTotalReclaimedMemoryBytes == nil)
        #expect(roundTrip.results[0].measuredReclaimedMemoryBytes == nil)
    }

    @Test func emptyHistoricalAndCoordinatorReportsHaveUnavailableMemoryNotMeasuredZero() throws {
        let historical = try JSONDecoder().decode(RunReport.self, from: Data(#"{"tier":"safe","results":[],"startedAt":0,"finishedAt":1,"freeSpaceBeforeBytes":0,"freeSpaceAfterBytes":0}"#.utf8))
        #expect(historical.measuredTotalReclaimedMemoryBytes == nil)
        let historicalRoundTrip = try JSONDecoder().decode(RunReport.self,
            from: JSONEncoder().encode(historical))
        #expect(historicalRoundTrip.measuredTotalReclaimedMemoryBytes == nil)
        for disposition in [RunDisposition.invalidToken, .noWork] {
            let report = RunReport(tier: .safe, results: [],
                startedAt: Date(timeIntervalSince1970: 100), finishedAt: Date(timeIntervalSince1970: 101),
                freeSpaceBeforeBytes: 0, freeSpaceAfterBytes: 0,
                disposition: disposition, coordinatorMeasurementsAvailable: false)
            #expect(report.measuredTotalReclaimedMemoryBytes == nil)
            let roundTrip = try JSONDecoder().decode(RunReport.self, from: JSONEncoder().encode(report))
            #expect(roundTrip.measuredTotalReclaimedMemoryBytes == nil)
            #expect(roundTrip.disposition == disposition)
        }
    }
}

extension SettingsMigrationTests {
    @Test(arguments: ["config.backup.json", "config.lock"])
    func missingConfigWithHistoricalAuxiliaryIsRecovery(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let auxiliary = s.root.appendingPathComponent(name)
        let bytes = name == "config.backup.json" ? try fixture("v1-original")
            : Data(#"{"schema":1,"storeID":"11111111-1111-1111-1111-111111111111"}"#.utf8)
        try bytes.write(to: auxiliary)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: auxiliary.path)
        let store = SettingsStore(url: s.file)
        let result = await store.load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(result.recoveryReason == .unavailable)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        #expect(try Data(contentsOf: auxiliary) == bytes && mode(auxiliary) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == [name])
    }

    @Test func directoryAndUnreadableExistingFilesNeverBecomeDefaults() async throws {
        let directory = try SettingsScratch(); defer { directory.remove() }
        try FileManager.default.createDirectory(at: directory.file, withIntermediateDirectories: false)
        let directoryResult = await SettingsStore(url: directory.file).load()
        #expect(directoryResult.disposition == .recoveryReadOnly && directoryResult.envelope == nil)
        #expect(directoryResult.recoveryReason == .unsafeLocation)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.file.path).isEmpty)
        guard geteuid() != 0 else { Issue.record("Requires ordinary unprivileged test user"); return }
        let unreadable = try SettingsScratch(); defer { unreadable.remove() }
        let bytes = try fixture("v1-original"); try unreadable.seed(bytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.file.path) }
        let result = await SettingsStore(url: unreadable.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(result.recoveryReason == .unavailable)
        #expect(try mode(unreadable.file) == 0)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.file.path)
        #expect(try Data(contentsOf: unreadable.file) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: unreadable.root.path) == ["config.json"])
    }

    @Test func validStateSavesButUnissuedPreviewAndRecoveryRejectRollback() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        let store = SettingsStore(url: s.file)
        let loaded = await store.load()
        let config = try #require(loaded.envelope).config
        // Internal construction is possible only under @testable; it grants no production write path.
        let preview = SettingsRollbackPreview(config: config, identity: UUID())
        await expectStoreError(.unavailable) { _ = try await store.previewRollback() }
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
        let saved = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        #expect(saved.revision == 1 && saved.config.transcriptAgeThresholdDays == 60)
        #expect(try Data(contentsOf: s.backup) == bytes)
        let current = try Data(contentsOf: s.file)
        await expectStoreError(.invalidChange) { _ = try await store.rollback(expectedRevision: 1, preview: preview) }
        #expect(try Data(contentsOf: s.file) == current)
        let corrupt = try fixture("corrupt"); try s.seed(corrupt)
        #expect(await store.load().disposition == .recoveryReadOnly)
        await expectStoreError(.readOnlyRecovery) { _ = try await store.rollback(expectedRevision: 0, preview: preview) }
        #expect(try Data(contentsOf: s.file) == corrupt)
    }

    @Test func strictBoundsAndTypesRejectOtherwiseValidSettings() async throws {
        let original = String(decoding: try fixture("v1-original"), as: UTF8.self)
        let invalid = [
            original.replacingOccurrences(of: "\"schemaVersion\":1", with: #""schemaVersion":1,"schema\u0056ersion":1"#),
            original.replacingOccurrences(of: "\"staleNodeModulesThresholdDays\":90", with: "\"staleNodeModulesThresholdDays\":9223372036854775808"),
            original.replacingOccurrences(of: "\"staleNodeModulesThresholdDays\":90", with: "\"staleNodeModulesThresholdDays\":true"),
            original.replacingOccurrences(of: "\"staleNodeModulesThresholdDays\":90", with: "\"staleNodeModulesThresholdDays\":90.5"),
            original.replacingOccurrences(of: "\"hasCompletedOnboarding\":true", with: "\"hasCompletedOnboarding\":1"),
            original.replacingOccurrences(of: "\"staleNodeModulesThresholdDays\":90", with: "\"staleNodeModulesThresholdDays\":6"),
            original.replacingOccurrences(of: "\"transcriptAgeThresholdDays\":120", with: "\"transcriptAgeThresholdDays\":366")
        ]
        var tooManyProfiles = try #require(JSONSerialization.jsonObject(with: fixture("v1-original")) as? [String: Any])
        tooManyProfiles["presets"] = Array(repeating: ["name": "Profile", "itemIDs": [String]()] as [String: Any], count: 51)
        for bytes in invalid.map({ Data($0.utf8) }) + [try JSONSerialization.data(withJSONObject: tooManyProfiles)] {
            let s = try SettingsScratch(); defer { s.remove() }; try s.seed(bytes)
            let result = await SettingsStore(url: s.file).load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            #expect(try Data(contentsOf: s.file) == bytes)
        }
    }

    @Test func exactCollectionStringAndByteBoundsRemainReadable() async throws {
        var object = try #require(JSONSerialization.jsonObject(with: fixture("v1-original")) as? [String: Any])
        object["gitRoots"] = Array(repeating: "/fixture/root", count: 1000)
        object["presets"] = Array(repeating: ["name": String(repeating: "x", count: 4096), "itemIDs": [String]()] as [String: Any], count: 50)
        var bytes = try JSONSerialization.data(withJSONObject: object)
        bytes.append(Data(repeating: 0x20, count: 1_048_576 - bytes.count))
        let s = try SettingsScratch(); defer { s.remove() }; try s.seed(bytes)
        #expect(await SettingsStore(url: s.file).load().disposition == .migrated)
        #expect(try Data(contentsOf: s.file) == bytes)
    }

    @Test func explicitZeroMixedUnknownAndOverflowMemoryStayTruthful() throws {
        func report(_ items: [ItemResult]) -> RunReport {
            RunReport(tier: .safe, results: items, startedAt: Date(), finishedAt: Date(),
                freeSpaceBeforeBytes: 0, freeSpaceAfterBytes: 0)
        }
        let zero = ItemResult(id: "zero", title: "Zero", freedBytes: 0, reclaimedMemoryBytes: 0, succeeded: true)
        let unknown = ItemResult(id: "unknown", title: "Unknown", freedBytes: 0, succeeded: true)
        #expect(zero.measuredReclaimedMemoryBytes == 0)
        #expect(unknown.measuredReclaimedMemoryBytes == nil)
        #expect(report([zero]).measuredTotalReclaimedMemoryBytes == 0)
        #expect(report([zero, unknown]).measuredTotalReclaimedMemoryBytes == nil)
        let largest = ItemResult(id: "large", title: "Large", freedBytes: 0, reclaimedMemoryBytes: .max, succeeded: true)
        #expect(report([largest, largest]).measuredTotalReclaimedMemoryBytes == nil)
        let encoded = try JSONEncoder().encode(report([zero, unknown]))
        let decoded = try JSONDecoder().decode(RunReport.self, from: encoded)
        #expect(decoded.results[0].measuredReclaimedMemoryBytes == 0)
        #expect(decoded.results[1].measuredReclaimedMemoryBytes == nil)
        #expect(decoded.measuredTotalReclaimedMemoryBytes == nil)
        let legacyExplicit = try JSONDecoder().decode(ItemResult.self,
            from: Data(#"{"id":"x","title":"X","freedBytes":0,"reclaimedMemoryBytes":0,"succeeded":true}"#.utf8))
        #expect(legacyExplicit.measuredReclaimedMemoryBytes == 0)
    }

    private func schema2(nestedVersion: Int = 2, revision: UInt64 = 0,
                         extra: [String: Any] = [:]) throws -> Data {
        var config = try #require(JSONSerialization.jsonObject(with: fixture("v1-original")) as? [String: Any])
        config["schemaVersion"] = nestedVersion
        config["appsApprovedForQuit"] = [String]()
        config["allowRestartToReclaimSwap"] = false
        var envelope: [String: Any] = ["schemaVersion": 2, "revision": NSNumber(value: revision), "config": config]
        for (key, value) in extra { envelope[key] = value }
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    @Test func knownSchema2LoadsNonzeroRevisionWithoutWriting() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try schema2(revision: 41); try s.seed(bytes)
        let expected = TidyConfig(schemaVersion: 2, hasCompletedOnboarding: true,
            keepCookieDomains: ["example.invalid", "keep.invalid"],
            simulatorsApprovedForDeletion: ["Old simulator name"],
            gitRoots: ["/fixture/Developer", "/fixture/Other"],
            staleNodeModulesThresholdDays: 90, transcriptAgeThresholdDays: 120,
            appsApprovedForQuit: [], allowRestartToReclaimSwap: false,
            presets: [CustomPreset(name: "Weekly", itemIDs: [
                "safe.tool.npm-cache-clean", "unknown.preset.id", "deep.simulator.erase-all"])])
        let store = SettingsStore(url: s.file)
        let result = await store.load()
        #expect(result.disposition == .loaded && result.recoveryReason == nil)
        let envelope = try #require(result.envelope)
        #expect(envelope.schemaVersion == 2 && envelope.revision == 41)
        #expect(envelope.config == expected)
        #expect(await store.load() == result)
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
    }

    @Test func unknownSchema2ExtensionAndNestedMismatchAreReadOnly() async throws {
        var nestedUnknown = try #require(JSONSerialization.jsonObject(with: schema2()) as? [String: Any])
        var config = try #require(nestedUnknown["config"] as? [String: Any])
        config["registryPreferences"] = ["feature.rescue": true]
        nestedUnknown["config"] = config
        var presetUnknown = try #require(JSONSerialization.jsonObject(with: schema2()) as? [String: Any])
        config.removeValue(forKey: "registryPreferences")
        config["presets"] = [["name": "Weekly", "itemIDs": ["unknown.preset.id"], "future": true] as [String: Any]]
        presetUnknown["config"] = config
        for bytes in [try schema2(extra: ["registryPreferences": ["feature.rescue": true]]),
                      try schema2(nestedVersion: 1),
                      try JSONSerialization.data(withJSONObject: nestedUnknown),
                      try JSONSerialization.data(withJSONObject: presetUnknown)] {
            let s = try SettingsScratch(); defer { s.remove() }; try s.seed(bytes)
            let store = SettingsStore(url: s.file); let result = await store.load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            await expectStoreError(.readOnlyRecovery) {
                _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
            }
            await expectStoreError(.readOnlyRecovery) { _ = try await store.previewRollback() }
            #expect(try Data(contentsOf: s.file) == bytes)
            #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        }
    }


    @Test func depthListAndStringBoundsRejectWithoutRewrite() async throws {
        var base = try #require(JSONSerialization.jsonObject(with: fixture("v1-original")) as? [String: Any])
        var largeList = base; largeList["gitRoots"] = Array(repeating: "/fixture/root", count: 1001)
        var longString = base; longString["gitRoots"] = [String(repeating: "x", count: 4097)]
        var nested: Any = "leaf"
        for _ in 0..<17 { nested = ["next": nested] }
        base["unknownNested"] = nested
        for object in [largeList, longString, base] {
            let s = try SettingsScratch(); defer { s.remove() }
            let bytes = try JSONSerialization.data(withJSONObject: object); try s.seed(bytes)
            let result = await SettingsStore(url: s.file).load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            #expect(try Data(contentsOf: s.file) == bytes)
        }
    }

    @Test func ownedLegacy755DirectoryAnd644FileMigrateWithoutSilentChmod() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: s.file.path)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .migrated && result.recoveryReason == nil)
        let envelope = try #require(result.envelope)
        #expect(envelope.schemaVersion == 2 && envelope.revision == 0)
        #expect(envelope.config.gitRoots == ["/fixture/Developer", "/fixture/Other"])
        #expect(try mode(s.root) == 0o755 && mode(s.file) == 0o644)
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
    }
    @Test(arguments: [true, false])
    func groupWritableLegacyLocationIsReadOnly(directory: Bool) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        let changed = directory ? s.root : s.file
        let permissions = directory ? 0o770 : 0o660
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: changed.path)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(try mode(changed) == permissions)
        #expect(try Data(contentsOf: s.file) == bytes)
    }

    @Test(arguments: ["config.lock", "config.backup.json"])
    func unsafeExistingAuxiliaryFilesAreNotRepaired(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        let auxiliary = s.root.appendingPathComponent(name)
        let sentinel = Data("preserve unsafe auxiliary".utf8)
        try sentinel.write(to: auxiliary)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: auxiliary.path)
        let store = SettingsStore(url: s.file)
        #expect(await store.load().disposition == .recoveryReadOnly)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        }
        #expect(try Data(contentsOf: auxiliary) == sentinel && mode(auxiliary) == 0o666)
        #expect(try Data(contentsOf: s.file) == bytes)
    }
}

private func withSettingsFIFORescue<Value>(
    _ fifo: URL, operation: () async throws -> Value
) async throws -> Result<Value, Error> {
    let watchdog = try FIFOReadWatchdog(fifo: fifo)
    let result: Result<Value, Error>
    do { result = .success(try await operation()) }
    catch { result = .failure(error) }
    let fired = watchdog.finishAndDrain() // before any assertion can throw/return
    #expect(!fired, "Settings I/O needed the FIFO rescue writer after five seconds")
    return result
}

private func expectFIFOStoreError<Value>(_ expected: SettingsStoreError,
                                         result: Result<Value, Error>) {
    switch result {
    case .success: Issue.record("Expected settings error \(expected)")
    case .failure(let error):
        guard let error = error as? SettingsStoreError else {
            Issue.record("Wrong settings error: \(error)"); return
        }
        #expect(error == expected)
    }
}

private struct SettingsFIFOImage {
    let fifo: URL
    let before: stat
    let names: [String]
    let regularBytes: [String: Data]
    let regularModes: [String: mode_t]
    let regularDevices: [String: dev_t]
    let regularInodes: [String: ino_t]
    let directoryMode: mode_t

    init(scratch: SettingsScratch, name: String) throws {
        fifo = scratch.root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: fifo.path) {
            // Only an exact existing disposable regular fixture is moved aside.
            let retained = scratch.root.appendingPathComponent("retained-original-" + name)
            try FileManager.default.moveItem(at: fifo, to: retained)
        }
        try #require(mkfifo(fifo.path, 0o600) == 0)
        var info = stat(), directory = stat()
        try #require(lstat(fifo.path, &info) == 0)
        try #require(info.st_mode & S_IFMT == S_IFIFO)
        try #require(info.st_mode & 0o777 == 0o600)
        try #require(lstat(scratch.root.path, &directory) == 0)
        before = info; directoryMode = directory.st_mode
        names = try FileManager.default.contentsOfDirectory(atPath: scratch.root.path).sorted()
        var bytes: [String: Data] = [:], modes: [String: mode_t] = [:]
        var devices: [String: dev_t] = [:], inodes: [String: ino_t] = [:]
        for other in names where other != name {
            let url = scratch.root.appendingPathComponent(other)
            var regular = stat()
            try #require(lstat(url.path, &regular) == 0 && regular.st_mode & S_IFMT == S_IFREG)
            bytes[other] = try Data(contentsOf: url)
            modes[other] = regular.st_mode
            devices[other] = regular.st_dev
            inodes[other] = regular.st_ino
        }
        regularBytes = bytes; regularModes = modes
        regularDevices = devices; regularInodes = inodes
    }
    func expectPreserved(in scratch: SettingsScratch) throws {
        var after = stat(), directory = stat()
        try #require(lstat(fifo.path, &after) == 0)
        #expect(after.st_mode & S_IFMT == S_IFIFO)
        #expect(after.st_dev == before.st_dev && after.st_ino == before.st_ino)
        #expect(after.st_mode == before.st_mode)
        try #require(lstat(scratch.root.path, &directory) == 0)
        #expect(directory.st_mode == directoryMode)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.root.path).sorted() == names)
        for (name, bytes) in regularBytes {
            let url = scratch.root.appendingPathComponent(name)
            var info = stat()
            try #require(lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG)
            #expect(try Data(contentsOf: url) == bytes)
            #expect(info.st_mode == regularModes[name])
            #expect(info.st_dev == regularDevices[name] && info.st_ino == regularInodes[name])
        }
    }
}

extension SettingsMigrationTests {
    @Test func fifoConfigReadRejectsPromptlyWithoutBootstrap() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture("v1-original"); try s.seed(original)
        let image = try SettingsFIFOImage(scratch: s, name: "config.json")
        let store = SettingsStore(url: s.file)
        let load = try await withSettingsFIFORescue(image.fifo) { await store.load() }
        let result = try load.get() // watchdog already drained
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        let edit = try await withSettingsFIFORescue(image.fifo) {
            try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        expectFIFOStoreError(.readOnlyRecovery, result: edit)
        try image.expectPreserved(in: s)
        #expect(try Data(contentsOf: s.root.appendingPathComponent("retained-original-config.json")) == original)
        #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.lock").path))
        #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.store.json").path))
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        withExtendedLifetime(store) {}
    }
}
