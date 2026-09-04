import Darwin
import Foundation

struct ProcessInstanceIdentity: Codable, Equatable, Sendable {
    let bootID: UUID
    let pid: Int32
    let startSeconds: Int64
    let startMicroseconds: Int32
    let executablePath: String
    let executableDevice: UInt64
    let executableInode: UInt64
}

/// Instance observations only. These are not accepted-adapter/signature proof.
enum ProcessIdentity {
    // sys/proc_info.h defines PROC_PIDPATHINFO_MAXSIZE as (4 * MAXPATHLEN),
    // a compound C macro that Swift does not import.
    private static let pathCapacity = 4 * Int(MAXPATHLEN)
    private static func bsdInfo(pid: Int32) throws -> proc_bsdinfo {
        guard pid > 0 else { throw POSIXError(.EINVAL) }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_pid == UInt32(pid) else { throw POSIXError(.ESRCH) }
        return info
    }

    static func capture(pid: Int32) throws -> ProcessInstanceIdentity {
        var boot = [CChar](repeating: 0, count: 128)
        var length = boot.count
        guard sysctlbyname("kern.bootsessionuuid", &boot, &length, nil, 0) == 0,
              length > 0, length <= boot.count,
              let bootID = UUID(uuidString: String(cString: boot)) else { throw POSIXError(.EIO) }
        let before = try bsdInfo(pid: pid)
        var pathBuffer = [CChar](repeating: 0, count: pathCapacity)
        guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else {
            throw POSIXError(.ESRCH)
        }
        let path = String(cString: pathBuffer)
        guard path.hasPrefix("/") else { throw POSIXError(.EINVAL) }
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        var metadata = stat(), named = stat()
        guard fstat(fd, &metadata) == 0, lstat(path, &named) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              named.st_dev == metadata.st_dev, named.st_ino == metadata.st_ino,
              named.st_mode & S_IFMT == S_IFREG else { throw POSIXError(.ESTALE) }
        let after = try bsdInfo(pid: pid)
        var afterPath = [CChar](repeating: 0, count: pathCapacity)
        guard before.pbi_start_tvsec == after.pbi_start_tvsec,
              before.pbi_start_tvusec == after.pbi_start_tvusec,
              proc_pidpath(pid, &afterPath, UInt32(afterPath.count)) > 0,
              String(cString: afterPath) == path,
              let seconds = Int64(exactly: before.pbi_start_tvsec),
              let microseconds = Int32(exactly: before.pbi_start_tvusec),
              (0..<1_000_000).contains(microseconds) else { throw POSIXError(.ESTALE) }
        return ProcessInstanceIdentity(bootID: bootID, pid: pid, startSeconds: seconds,
            startMicroseconds: microseconds, executablePath: path,
            executableDevice: UInt64(metadata.st_dev), executableInode: UInt64(metadata.st_ino))
    }

    static func matches(_ expected: ProcessInstanceIdentity) -> Bool {
        (try? capture(pid: expected.pid)) == expected
    }

    static func parentPID(of expected: ProcessInstanceIdentity) throws -> Int32 {
        guard matches(expected) else { throw POSIXError(.ESTALE) }
        let info = try bsdInfo(pid: expected.pid)
        guard matches(expected), let parent = Int32(exactly: info.pbi_ppid) else {
            throw POSIXError(.ESTALE)
        }
        return parent
    }
}
