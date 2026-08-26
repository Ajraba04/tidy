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

    init(directory: URL) throws {
        directoryPath = directory.path
        let dir = try Self.openDirectory(directory.path, create: true)
        do { try Self.validate(dir, directory: true) } catch { close(dir); throw error }
        directoryFD = dir
        let names: [String]
        do { names = try Self.names(in: dir) }
        catch { close(dir); throw ConfirmationError.storageUnavailable }
        var created = false
        var fd: Int32 = -1
        if names.isEmpty {
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
                guard try Self.names(in: dir) == ["mutation.lock"] else {
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

    func persistIntentWhileLocked(_ intent: PendingEffectIntent) throws {
        guard held, !failed else { throw ConfirmationError.storageUnavailable }
        do {
            try validateStableLock()
            var ledger = try readLedger()
            ledger.unfinished.append(intent)
            try publish(ledger, name: "unfinished-effects.json")
        } catch {
            failed = true
            throw ConfirmationError.storageUnavailable
        }
    }

    private func validateStableLock() throws {
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

    private static func names(in fd: Int32) throws -> [String] {
        // A distinct open-file description avoids sharing directory enumeration offsets.
        let duplicate = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard duplicate >= 0 else { throw ConfirmationError.storageUnavailable }
        guard let directory = fdopendir(duplicate) else {
            close(duplicate); throw ConfirmationError.storageUnavailable
        }
        defer { closedir(directory) }
        var result: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { result.append(name) }
            errno = 0
        }
        guard errno == 0 else { throw ConfirmationError.storageUnavailable }
        return result.sorted()
    }

    private func read<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        let fd = openat(directoryFD, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ConfirmationError.storageUnavailable }
        defer { close(fd) }
        try Self.validate(fd, directory: false)
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw ConfirmationError.storageUnavailable
            }
            if count == 0 { break }
            guard bytes.count + count <= 8 * 1024 * 1024 else { throw ConfirmationError.storageUnavailable }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        return try JSONDecoder().decode(type, from: bytes)
    }

    private func readLedger() throws -> Envelope {
        let marker = try read(Bootstrap.self, name: "bootstrap.json")
        let ledger = try read(Envelope.self, name: "unfinished-effects.json")
        guard marker.schema == 1, marker.state == "initialized",
              ledger.schema == 1, ledger.storeID == marker.storeID else { throw ConfirmationError.storageUnavailable }
        return ledger
    }

    private func publish<T: Encodable>(_ value: T, name: String) throws {
        let data = try JSONEncoder().encode(value)
        let temporary = ".pending-" + UUID().uuidString
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ConfirmationError.storageUnavailable }
        defer { close(fd); _ = unlinkat(directoryFD, temporary, 0) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ConfirmationError.storageUnavailable }
                offset += count
            }
        }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0,
              renameat(directoryFD, temporary, directoryFD, name) == 0,
              fsync(directoryFD) == 0 else { throw ConfirmationError.storageUnavailable }
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
