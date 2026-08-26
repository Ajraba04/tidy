import Foundation
import Darwin

struct JournalDirectoryIdentity: Equatable, Sendable { let device: UInt64; let inode: UInt64 }
struct JournalScanLimits: Equatable, Sendable {
    static let production = JournalScanLimits()
    let maximumDirectoryEntries: Int
    let maximumJournalEntries: Int
    private init() { maximumDirectoryEntries = 16_384; maximumJournalEntries = 4_096 }
    init(reducingDirectoryEntriesTo: Int, reducingJournalEntriesTo: Int) throws {
        guard (4...16_384).contains(reducingDirectoryEntriesTo),
              (1...min(4_096, reducingDirectoryEntriesTo)).contains(reducingJournalEntriesTo) else {
            throw JournalError.capacity
        }
        maximumDirectoryEntries = reducingDirectoryEntriesTo
        maximumJournalEntries = reducingJournalEntriesTo
    }
}
struct JournalStorageEntry: Equatable, Sendable {
    let name: String
    let directory: JournalDirectoryIdentity
    let device: UInt64
    let inode: UInt64
    let byteCount: Int
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    var modifiedAt: Date { Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1e9) }
}
protocol JournalStorage: Sendable {
    func read(name: String) throws -> Data
    func replace(name: String, bytes: Data) throws
    func directoryIdentity() throws -> JournalDirectoryIdentity
    func journalEntries() throws -> [JournalStorageEntry]
    func removeJournal(_ entry: JournalStorageEntry) throws
}
final class DurableJournalStorage: JournalStorage, @unchecked Sendable {
    let scanLimits: JournalScanLimits
    private let directoryFD: Int32
    private let path: String
    private let io: any JournalPOSIXIO
    init(directory: URL, io: any JournalPOSIXIO = DarwinJournalIO(), scanLimits: JournalScanLimits = .production) throws {
        self.scanLimits = scanLimits
        self.path = directory.path
        self.io = io
        let fd = try JournalFiles.openDirectory(directory.path)
        do { try JournalFiles.validate(fd, directory: true) }
        catch { close(fd); throw error }
        directoryFD = fd
    }
    deinit { close(directoryFD) }
    func read(name: String) throws -> Data {
        _ = try directoryIdentity()
        return try JournalFiles.read(directoryFD, name: name)
    }
    func replace(name: String, bytes: Data) throws {
        _ = try directoryIdentity()
        do {
            try JournalFilePublication.replace(directoryFD: directoryFD, name: name, bytes: bytes,
                                               io: io, scanLimits: scanLimits)
        } catch let error as JournalError { throw error }
        catch { throw JournalError.unavailable }
    }
    func directoryIdentity() throws -> JournalDirectoryIdentity {
        try JournalFiles.validate(directoryFD, directory: true)
        let named = try JournalFiles.openDirectory(path)
        defer { close(named) }
        let identity = try JournalFiles.identity(directoryFD)
        guard try JournalFiles.identity(named) == identity else { throw JournalError.unavailable }
        return identity
    }
    func journalEntries() throws -> [JournalStorageEntry] {
        let directory = try directoryIdentity()
        let scan = try JournalDirectoryScan.read(directoryFD: directoryFD, limits: scanLimits)
        guard !scan.containsPendingStage else { throw JournalError.unavailable }
        return try scan.journalNames.map { try entry(name: $0, directory: directory) }
    }
    private func entry(name: String, directory: JournalDirectoryIdentity) throws -> JournalStorageEntry {
        let fd = try JournalFiles.openLeaf(directoryFD, name: name)
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= 0 else { throw JournalError.unavailable }
        guard info.st_size <= JournalFiles.maximumBytes else { throw JournalError.capacity }
        return JournalStorageEntry(name: name, directory: directory,
            device: UInt64(info.st_dev), inode: UInt64(info.st_ino), byteCount: Int(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec))
    }
    func removeJournal(_ entry: JournalStorageEntry) throws {
        let directory = try directoryIdentity()
        guard try JournalFiles.runID(entry.name) != nil, directory == entry.directory,
              try self.entry(name: entry.name, directory: directory) == entry else { throw JournalError.unavailable }
        guard unlinkat(directoryFD, entry.name, 0) == 0 else { throw JournalError.unavailable }
        do { try io.syncDirectory(fd: directoryFD) }
        catch { throw JournalError.unavailable }
    }
}

struct JournalDirectoryScan {
    let entryCount: Int
    let journalNames: [String]
    let containsStableLock: Bool
    let containsPendingStage: Bool
    static func read(directoryFD: Int32, limits: JournalScanLimits) throws -> Self {
        let fd = openat(directoryFD, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw JournalError.unavailable }
        guard let directory = fdopendir(fd) else { close(fd); throw JournalError.unavailable }
        defer { closedir(directory) }
        var count = 0, names: [String] = [], lock = false, pending = false
        while true {
            errno = 0
            guard let item = readdir(directory) else {
                guard errno == 0 else { throw JournalError.unavailable }
                break
            }
            let name = withUnsafePointer(to: &item.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(validatingCString: $0) }
            }
            guard let name else { throw JournalError.unavailable }
            if name == "." || name == ".." { continue }
            count += 1
            guard count <= limits.maximumDirectoryEntries else { throw JournalError.capacity }
            lock = lock || name == "mutation.lock"
            pending = pending || name.hasPrefix(".pending-")
            if try JournalFiles.runID(name) != nil {
                guard names.count < limits.maximumJournalEntries else { throw JournalError.capacity }
                names.append(name)
            }
        }
        return Self(entryCount: count, journalNames: names, containsStableLock: lock, containsPendingStage: pending)
    }
}

enum JournalFiles {
    static let maximumBytes = 1_048_576
    static func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.utf8.contains(0) else {
            throw JournalError.unavailable
        }
    }
    static func runID(_ name: String) throws -> UUID? {
        guard name.hasPrefix("run-") || name.hasSuffix(".journal") else { return nil }
        guard name.utf8.count == 48, name.hasPrefix("run-"), name.hasSuffix(".journal"),
              let id = UUID(uuidString: String(name.dropFirst(4).dropLast(8))),
              name == "run-" + id.uuidString + ".journal" else { throw JournalError.corrupt }
        return id
    }
    static func identity(_ fd: Int32) throws -> JournalDirectoryIdentity {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw JournalError.unavailable }
        return JournalDirectoryIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }
    static func validate(_ fd: Int32, directory: Bool) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              info.st_mode & 0o777 == (directory ? 0o700 : 0o600),
              directory || info.st_nlink == 1 else { throw JournalError.unavailable }
    }
    static func openDirectory(_ path: String) throws -> Int32 {
        let components = path.split(separator: "/").map(String.init)
        guard path.hasPrefix("/"), !path.utf8.contains(0), !components.isEmpty,
              !components.contains("."), !components.contains("..") else { throw JournalError.unavailable }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw JournalError.unavailable }
        for component in components {
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw JournalError.unavailable }
            fd = next
        }
        return fd
    }
    static func validateNamed(_ fd: Int32, directoryFD: Int32, name: String) throws {
        try validate(fd, directory: false)
        var named = stat(), opened = stat()
        guard fstatat(directoryFD, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              fstat(fd, &opened) == 0, named.st_mode & S_IFMT == S_IFREG,
              named.st_dev == opened.st_dev, named.st_ino == opened.st_ino else { throw JournalError.unavailable }
    }
    static func openLeaf(_ directoryFD: Int32, name: String) throws -> Int32 {
        try validateName(name)
        let fd = openat(directoryFD, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw errno == ENOENT ? JournalError.notFound : .unavailable }
        do { try validateNamed(fd, directoryFD: directoryFD, name: name) }
        catch { close(fd); throw error }
        return fd
    }
    static func read(_ directoryFD: Int32, name: String) throws -> Data {
        // openLeaf rejects every special node before the first read, including FIFOs.
        let fd = try openLeaf(directoryFD, name: name)
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= 0 else { throw JournalError.unavailable }
        guard info.st_size <= maximumBytes else { throw JournalError.capacity }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, min(buffer.count, maximumBytes - bytes.count + 1))
            if count < 0 {
                if errno == EINTR { continue }
                throw JournalError.unavailable
            }
            if count == 0 { break }
            guard count <= maximumBytes - bytes.count else { throw JournalError.capacity }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        try validateNamed(fd, directoryFD: directoryFD, name: name)
        return bytes
    }
}
