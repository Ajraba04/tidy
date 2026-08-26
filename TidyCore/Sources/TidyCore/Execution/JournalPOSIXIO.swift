import Foundation
import Darwin

protocol JournalPOSIXIO: Sendable {
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int
    func syncFile(fd: Int32) throws
    func replace(directoryFD: Int32, temporary: String, destination: String) throws
    func syncDirectory(fd: Int32) throws
}
struct DarwinJournalIO: JournalPOSIXIO {
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        guard offset >= 0, offset < bytes.count else { throw JournalError.unavailable }
        let count = bytes.withUnsafeBytes {
            Darwin.write(fd, $0.baseAddress!.advanced(by: offset), bytes.count - offset)
        }
        guard count >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return count
    }
    func syncFile(fd: Int32) throws {
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        guard renameat(directoryFD, temporary, directoryFD, destination) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
    func syncDirectory(fd: Int32) throws {
        guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

/// The sole publication algorithm for mandatory and diagnostic bytes.
enum JournalFilePublication {
    static func replace(directoryFD: Int32, name: String, bytes: Data,
                        io: any JournalPOSIXIO, scanLimits: JournalScanLimits) throws {
        try JournalFiles.validateName(name)
        guard bytes.count <= JournalFiles.maximumBytes else { throw JournalError.capacity }
        try JournalFiles.validate(directoryFD, directory: true)
        let scan = try JournalDirectoryScan.read(directoryFD: directoryFD, limits: scanLimits)
        guard !scan.containsPendingStage else { throw JournalError.unavailable }
        guard scan.entryCount < scanLimits.maximumDirectoryEntries else { throw JournalError.capacity }
        if try JournalFiles.runID(name) != nil, !scan.journalNames.contains(name),
           scan.journalNames.count >= scanLimits.maximumJournalEntries { throw JournalError.capacity }
        var existing = stat()
        if fstatat(directoryFD, name, &existing, AT_SYMLINK_NOFOLLOW) == 0 {
            let old = try JournalFiles.openLeaf(directoryFD, name: name)
            close(old)
        } else if errno != ENOENT { throw JournalError.unavailable }
        let temporary = ".pending-" + UUID().uuidString
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw JournalError.unavailable }
        // Failed stages deliberately survive. A successful rename consumes its name.
        defer { close(fd) }
        try JournalFiles.validateNamed(fd, directoryFD: directoryFD, name: temporary)
        var offset = 0
        while offset < bytes.count {
            let count: Int
            do { count = try io.write(fd: fd, bytes: bytes, offset: offset) }
            catch let error as POSIXError where error.code == .EINTR { continue }
            guard count > 0, count <= bytes.count - offset else { throw JournalError.unavailable }
            offset += count
        }
        try JournalFiles.validateNamed(fd, directoryFD: directoryFD, name: temporary)
        try io.syncFile(fd: fd)
        try JournalFiles.validateNamed(fd, directoryFD: directoryFD, name: temporary)
        try io.replace(directoryFD: directoryFD, temporary: temporary, destination: name)
        try JournalFiles.validateNamed(fd, directoryFD: directoryFD, name: name)
        try io.syncDirectory(fd: directoryFD)
    }
}
