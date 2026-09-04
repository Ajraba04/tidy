import Foundation
import Darwin

/// One installation-wide, fail-closed ledger. No reconciliation/reset API exists here.
final class MutationAdmissionStore {
    private struct Bootstrap: Codable { let schema: Int; let storeID: UUID; let state: String }
    private struct Envelope: Codable { let schema: Int; let storeID: UUID; var unfinished: [PendingEffectIntent] }
    private let directoryFD: Int32
    private let directoryPath: String
    private let lockFD: Int32
    private var held = false
    private var failed = false
    private let io: any JournalPOSIXIO

    let scanLimits: JournalScanLimits
    init(directory: URL, io: any JournalPOSIXIO = DarwinJournalIO(), scanLimits: JournalScanLimits = .production) throws {
        self.scanLimits = scanLimits
        self.io = io
        directoryPath = directory.path
        let dir = try Self.openDirectory(directory.path, create: true)
        do { try Self.validate(dir, directory: true) } catch { close(dir); throw error }
        directoryFD = dir
        let scan: JournalDirectoryScan
        do { scan = try JournalDirectoryScan.read(directoryFD: dir, limits: scanLimits) }
        catch { close(dir); throw ConfirmationError.storageUnavailable }
        var created = false
        var fd: Int32 = -1
        if scan.entryCount == 0 {
            fd = openat(dir, "mutation.lock", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            created = fd >= 0
        }
        if fd < 0 {
            fd = openat(dir, "mutation.lock", O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else { close(dir); throw ConfirmationError.storageUnavailable }
        do { try Self.validate(fd, directory: false) } catch { close(fd); close(dir); throw error }
        lockFD = fd
        if created {
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                failed = true
                return
            }
            held = true
            do {
                let bootstrapScan = try JournalDirectoryScan.read(directoryFD: dir, limits: scanLimits)
                guard bootstrapScan.entryCount == 1, bootstrapScan.containsStableLock else {
                    throw ConfirmationError.storageUnavailable
                }
                let id = UUID()
                try publish(Bootstrap(schema: 1, storeID: id, state: "initializing"), name: "bootstrap.json")
                try publish(Envelope(schema: 1, storeID: id, unfinished: []), name: "unfinished-effects.json")
                try publish(Bootstrap(schema: 1, storeID: id, state: "initialized"), name: "bootstrap.json")
            } catch { failed = true }
            release()
        }
    }

    deinit { release(); close(lockFD); close(directoryFD) }

    func acquire() -> MutationAdmission {
        if held { return readAdmissionWhileLocked() }
        guard !failed else { return .storageUnavailable }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            return errno == EWOULDBLOCK ? .busy : .storageUnavailable
        }
        held = true
        return readAdmissionWhileLocked()
    }

    func release() {
        if held { _ = flock(lockFD, LOCK_UN); held = false }
    }

    func readAdmissionWhileLocked() -> MutationAdmission {
        guard held, !failed else { return .storageUnavailable }
        do {
            try validateStableLock()
            let ledger = try readLedger()
            return ledger.unfinished.isEmpty ? .ready : .uncertainAndPossiblyRunning
        } catch { return .storageUnavailable }
    }

    func requireJournalLock() throws {
        guard held, !failed else { throw JournalError.unavailable }
        do {
            try validateStableLock()
            _ = try readLedger()
        } catch {
            failed = true
            throw JournalError.unavailable
        }
    }

    func latchJournalStorageFailure() { failed = true }
    func journalDirectoryIdentityWhileLocked() throws -> JournalDirectoryIdentity {
        try requireJournalLock()
        return try JournalFiles.identity(directoryFD)
    }
    func unfinishedIntentsWhileLocked() throws -> [PendingEffectIntent] {
        try requireJournalLock()
        return try readLedger().unfinished
    }
    func persistIntentWhileLocked(_ intent: PendingEffectIntent, update: IntentPersistence = .append) throws {
        try requireJournalLock()
        var ledger = try readLedger()
        switch update {
        case .append:
            guard !ledger.unfinished.contains(where: { $0.operationID == intent.operationID }),
                  Self.validChildTuple(intent, allowAbsent: true) else { throw JournalError.invalidTransition }
            ledger.unfinished.append(intent)
        case .capturedChild:
            guard ledger.unfinished.filter({ $0.operationID == intent.operationID }).count == 1,
                  let index = ledger.unfinished.firstIndex(where: {
                $0.operationID == intent.operationID && $0.runID == intent.runID
            }) else { throw JournalError.invalidTransition }
            let prior = ledger.unfinished[index]
            guard Self.validChildTuple(intent, allowAbsent: false),
                  prior.adapterID == intent.adapterID, prior.bootID == intent.bootID,
                  prior.executablePath == intent.executablePath,
                  prior.executableDevice == intent.executableDevice, prior.executableInode == intent.executableInode,
                  prior.phase == intent.phase else { throw JournalError.invalidTransition }
            if prior == intent { return }
            guard prior.childPID == nil, prior.childStartSeconds == nil,
                  prior.childStartMicroseconds == nil else { throw JournalError.invalidTransition }
            ledger.unfinished[index] = intent
        }
        let bytes = try JSONEncoder().encode(ledger)
        guard bytes.count <= JournalFiles.maximumBytes else { throw JournalError.capacity }
        do {
            try JournalFilePublication.replace(directoryFD: directoryFD, name: "unfinished-effects.json",
                bytes: bytes, io: io, scanLimits: scanLimits)
        } catch JournalError.capacity { throw JournalError.capacity }
        catch {
            failed = true
            throw ConfirmationError.storageUnavailable
        }
    }

    private static func validChildTuple(_ intent: PendingEffectIntent, allowAbsent: Bool) -> Bool {
        if intent.childPID == nil && intent.childStartSeconds == nil && intent.childStartMicroseconds == nil {
            return allowAbsent
        }
        guard let pid = intent.childPID, let seconds = intent.childStartSeconds,
              let micros = intent.childStartMicroseconds else { return false }
        return pid > 0 && seconds >= 0 && (0..<1_000_000).contains(micros)
    }

    private func validateStableLock() throws {
        let scan = try JournalDirectoryScan.read(directoryFD: directoryFD, limits: scanLimits)
        guard !scan.containsPendingStage else { throw ConfirmationError.storageUnavailable }
        try Self.validate(directoryFD, directory: true)
        try Self.validate(lockFD, directory: false)
        let namedFD = try Self.openDirectory(directoryPath, create: false)
        defer { close(namedFD) }
        var namedDirectory = stat(); var openedDirectory = stat()
        guard fstat(namedFD, &namedDirectory) == 0, fstat(directoryFD, &openedDirectory) == 0,
              namedDirectory.st_mode & S_IFMT == S_IFDIR,
              namedDirectory.st_dev == openedDirectory.st_dev,
              namedDirectory.st_ino == openedDirectory.st_ino else { throw ConfirmationError.storageUnavailable }
        var current = stat(); var opened = stat()
        guard fstatat(directoryFD, "mutation.lock", &current, AT_SYMLINK_NOFOLLOW) == 0,
              fstat(lockFD, &opened) == 0,
              current.st_dev == opened.st_dev, current.st_ino == opened.st_ino,
              current.st_mode & S_IFMT == S_IFREG else { throw ConfirmationError.storageUnavailable }
    }

    private static func validate(_ fd: Int32, directory: Bool) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              info.st_mode & 0o777 == (directory ? 0o700 : 0o600),
              directory || info.st_nlink == 1 else { throw ConfirmationError.storageUnavailable }
    }

    /// Component-wise open prevents an ancestor symlink from redirecting bootstrap writes.
    private static func openDirectory(_ path: String, create: Bool) throws -> Int32 {
        let components = path.split(separator: "/").map(String.init)
        guard path.hasPrefix("/"), !path.utf8.contains(0), !components.isEmpty,
              !components.contains("."), !components.contains("..") else {
            throw ConfirmationError.storageUnavailable
        }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ConfirmationError.storageUnavailable }
        for component in components {
            var next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT, create {
                guard mkdirat(fd, component, 0o700) == 0 || errno == EEXIST else {
                    close(fd); throw ConfirmationError.storageUnavailable
                }
                guard fsync(fd) == 0 else { close(fd); throw ConfirmationError.storageUnavailable }
                next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            close(fd)
            guard next >= 0 else { throw ConfirmationError.storageUnavailable }
            fd = next
        }
        return fd
    }

    private func read<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        try JSONDecoder().decode(type, from: JournalFiles.read(directoryFD, name: name))
    }

    private func readLedger() throws -> Envelope {
        let marker = try read(Bootstrap.self, name: "bootstrap.json")
        let ledger = try read(Envelope.self, name: "unfinished-effects.json")
        guard marker.schema == 1, marker.state == "initialized",
              ledger.schema == 1, ledger.storeID == marker.storeID else { throw ConfirmationError.storageUnavailable }
        return ledger
    }

    private func publish<T: Encodable>(_ value: T, name: String) throws {
        let bytes = try JSONEncoder().encode(value)
        try JournalFilePublication.replace(directoryFD: directoryFD, name: name, bytes: bytes,
                                           io: io, scanLimits: scanLimits)
    }
}
struct PendingEffectIntent: Codable, Equatable, Sendable {
    let runID: UUID
    let operationID: UUID
    let adapterID: String
    let bootID: UUID
    let executablePath: String
    let executableDevice: UInt64
    let executableInode: UInt64
    let childPID: Int32?
    let childStartSeconds: Int64?
    let childStartMicroseconds: Int32?
    let phase: SubmissionPhase
}
enum SubmissionPhase: String, Codable, Sendable {
    case prepared, submitted, uncertainAndPossiblyRunning
}

enum IntentPersistence: Sendable { case append, capturedChild }
