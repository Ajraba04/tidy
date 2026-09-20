import Darwin
import Foundation

public enum WorkloadIdentityError: Error, Equatable, Sendable {
    case invalidProcess
    case invalidBundleURL
    case invalidBundleIdentifier
    case invalidExecutable
}

/// An exact, local application process instance. Display names are deliberately
/// absent: neither a name nor a PID is sufficient authority for rescue.
public struct WorkloadIdentity: Hashable, Codable, Sendable {
    public let bundleURL: URL
    public let bundleIdentifier: String
    public let bootID: UUID
    public let pid: Int32
    public let startedAtTicks: UInt64
    public let executablePath: String
    public let executableDevice: UInt64
    public let executableInode: UInt64

    public init(bundleURL: URL, bundleIdentifier: String, bootID: UUID,
                pid: Int32, startedAtTicks: UInt64, executablePath: String,
                executableDevice: UInt64, executableInode: UInt64) throws {
        guard pid > 0, startedAtTicks > 0,
              executableDevice > 0, executableInode > 0 else {
            throw WorkloadIdentityError.invalidProcess
        }
        let standardizedBundle = bundleURL.standardizedFileURL
        guard bundleURL.isFileURL, standardizedBundle.path.hasPrefix("/"),
              !standardizedBundle.path.utf8.contains(0),
              standardizedBundle.path.utf8.count <= 4_096 else {
            throw WorkloadIdentityError.invalidBundleURL
        }
        guard Self.validBundleIdentifier(bundleIdentifier) else {
            throw WorkloadIdentityError.invalidBundleIdentifier
        }
        guard executablePath.hasPrefix("/"), !executablePath.utf8.contains(0),
              executablePath.utf8.count <= 4_096 else {
            throw WorkloadIdentityError.invalidExecutable
        }
        self.bundleURL = standardizedBundle
        self.bundleIdentifier = bundleIdentifier
        self.bootID = bootID
        self.pid = pid
        self.startedAtTicks = startedAtTicks
        self.executablePath = URL(fileURLWithPath: executablePath).standardizedFileURL.path
        self.executableDevice = executableDevice
        self.executableInode = executableInode
    }

    /// Captures the existing descriptor-backed process identity seam and binds
    /// it to the app bundle identity observed by the AppKit layer.
    public static func capture(bundleURL: URL, bundleIdentifier: String,
                               pid: Int32) throws -> Self {
        let process = try ProcessIdentity.capture(pid: pid)
        guard process.startSeconds >= 0, process.startMicroseconds >= 0 else {
            throw WorkloadIdentityError.invalidProcess
        }
        let (seconds, secondsOverflow) = UInt64(process.startSeconds)
            .multipliedReportingOverflow(by: 1_000_000)
        let (ticks, ticksOverflow) = seconds.addingReportingOverflow(
            UInt64(process.startMicroseconds))
        guard !secondsOverflow, !ticksOverflow else {
            throw WorkloadIdentityError.invalidProcess
        }
        return try Self(bundleURL: bundleURL, bundleIdentifier: bundleIdentifier,
                        bootID: process.bootID, pid: pid, startedAtTicks: ticks,
                        executablePath: process.executablePath,
                        executableDevice: process.executableDevice,
                        executableInode: process.executableInode)
    }

    public func matchesCurrentProcess() -> Bool {
        (try? Self.capture(bundleURL: bundleURL, bundleIdentifier: bundleIdentifier,
                           pid: pid)) == self
    }

    private static func validBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 255,
              !value.hasPrefix("."), !value.hasSuffix("."), value.contains(".") else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-"
        }
    }
}

public struct RescueApplicationApproval: Hashable, Codable, Sendable {
    public let bundleURL: URL
    public let bundleIdentifier: String
    public let bundleDevice: UInt64
    public let bundleInode: UInt64

    public init(bundleURL: URL, bundleIdentifier: String) throws {
        let probe = try WorkloadIdentity(bundleURL: bundleURL,
            bundleIdentifier: bundleIdentifier, bootID: UUID(), pid: 1,
            startedAtTicks: 1,
            executablePath: bundleURL.appendingPathComponent("Contents/MacOS/application").path,
            executableDevice: 1, executableInode: 1)
        let fd = open(probe.bundleURL.path,
            O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw WorkloadIdentityError.invalidBundleURL }
        defer { close(fd) }
        var info = stat(), filesystem = statfs()
        guard fstat(fd, &info) == 0, fstatfs(fd, &filesystem) == 0,
              info.st_mode & S_IFMT == S_IFDIR,
              filesystem.f_flags & UInt32(MNT_LOCAL) != 0 else {
            throw WorkloadIdentityError.invalidBundleURL
        }
        self.bundleURL = probe.bundleURL
        self.bundleIdentifier = probe.bundleIdentifier
        bundleDevice = UInt64(info.st_dev)
        bundleInode = UInt64(info.st_ino)
    }

    internal init(bundleURL: URL, bundleIdentifier: String,
                  bundleDevice: UInt64, bundleInode: UInt64) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.bundleDevice = bundleDevice
        self.bundleInode = bundleInode
    }

    public func contains(_ workload: WorkloadIdentity) -> Bool {
        workload.bundleURL == bundleURL && workload.bundleIdentifier == bundleIdentifier
    }

    internal func isCurrent() -> Bool {
        guard let current = try? Self(bundleURL: bundleURL,
                                      bundleIdentifier: bundleIdentifier) else { return false }
        return current == self
    }

    internal var hasValidStoredShape: Bool {
        bundleDevice > 0 && bundleInode > 0 &&
        (try? WorkloadIdentity(bundleURL: bundleURL,
            bundleIdentifier: bundleIdentifier, bootID: UUID(), pid: 1, startedAtTicks: 1,
            executablePath: bundleURL.appendingPathComponent(
                "Contents/MacOS/application").path,
            executableDevice: 1, executableInode: 1)) != nil
    }
}
