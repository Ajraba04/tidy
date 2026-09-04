import Foundation
import Darwin
import CryptoKit

struct SettingsFileIdentity: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let owner: uid_t
    init(_ info: stat) {
        device = info.st_dev; inode = info.st_ino; mode = info.st_mode; owner = info.st_uid
    }
}

struct SettingsFileImage: Equatable, Sendable {
    let identity: SettingsFileIdentity
    let bytes: Data
    var digest: String { SettingsFiles.digest(bytes) }
}

struct SettingsDiskImage: Equatable, Sendable {
    let directory: SettingsFileIdentity?
    let config: SettingsFileImage?
    let backup: SettingsFileImage?
    let lock: SettingsFileImage?
    let metadata: SettingsFileImage?

    func loaded() throws -> SettingsLoadResult {
        if lock != nil || metadata != nil {
            guard let lock, let metadata,
                  try SettingsDecoding.storeIdentity(lock.bytes) == SettingsDecoding.storeIdentity(metadata.bytes),
                  let config else { throw SettingsFiles.Failure.unavailable }
            let result = try SettingsDecoding.load(config.bytes)
            guard result.disposition == .loaded else { throw SettingsFiles.Failure.unavailable }
            return result
        }
        if let config { return try SettingsDecoding.load(config.bytes) }
        guard backup == nil else { throw SettingsFiles.Failure.unavailable }
        return SettingsLoadResult(disposition: .newDefaults,
            envelope: SettingsEnvelope(schemaVersion: 2, revision: 0, config: TidyConfig(schemaVersion: 2)),
            recoveryReason: nil)
    }
}

/// Settings-specific bounded descriptor I/O; no process or policy authority.
enum SettingsFiles {
    enum Failure: Error { case unavailable, unsafeLocation, busy }
    static let pending = "config.pending.json"
    static let lockName = "config.lock"
    static let metadataName = "config.store.json"
    static let backupName = "config.backup.json"

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func components(_ url: URL) throws -> [String] {
        guard url.isFileURL, !url.path.utf8.contains(0), url.path.hasPrefix("/") else {
            throw Failure.unsafeLocation
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count > 1, parts.last == "config.json",
              !parts.contains("."), !parts.contains("..") else { throw Failure.unsafeLocation }
        return Array(parts.dropLast())
    }

    static func requireLocal(_ fd: Int32) throws {
        var info = statfs()
        guard fstatfs(fd, &info) == 0 else { throw Failure.unavailable }
        guard info.f_flags & UInt32(MNT_LOCAL) != 0 else { throw Failure.unsafeLocation }
    }

    static func identity(_ fd: Int32) throws -> SettingsFileIdentity {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw Failure.unavailable }
        return SettingsFileIdentity(info)
    }

    static func directory(_ url: URL, create: Bool = false) throws -> Int32? {
        let parts = try components(url)
        var fd = open("/", O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unavailable }
        do {
            for (index, part) in parts.enumerated() {
                var next = openat(fd, part, O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0, errno == ENOENT {
                    guard create else { close(fd); return nil }
                    guard mkdirat(fd, part, 0o700) == 0 else { throw posixError() }
                    next = openat(fd, part, O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else {
                    throw errno == ELOOP || errno == ENOTDIR ? Failure.unsafeLocation : Failure.unavailable
                }
                close(fd); fd = next
                let info = try identity(fd)
                let final = index == parts.count - 1
                let stickyAncestor = !final && info.owner == 0 && info.mode & S_ISVTX != 0
                guard info.mode & S_IFMT == S_IFDIR,
                      info.owner == geteuid() || (!final && info.owner == 0),
                      info.mode & 0o022 == 0 || stickyAncestor else { throw Failure.unsafeLocation }
                try requireLocal(fd)
            }
            return fd
        } catch { close(fd); throw error }
    }

    static func validateRegular(_ fd: Int32, ownerOnly: Bool = false) throws -> SettingsFileIdentity {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw Failure.unavailable }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
              info.st_mode & 0o022 == 0, info.st_nlink == 1,
              !ownerOnly || info.st_mode & 0o777 == 0o600 else { throw Failure.unsafeLocation }
        try requireLocal(fd)
        return SettingsFileIdentity(info)
    }

    static func openRegular(_ directory: Int32, name: String, writable: Bool = false,
                            ownerOnly: Bool = false) throws -> Int32? {
        let flags = (writable ? O_RDWR : O_RDONLY) | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        let fd = openat(directory, name, flags)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw errno == ELOOP ? Failure.unsafeLocation : Failure.unavailable
        }
        do {
            _ = try validateRegular(fd, ownerOnly: ownerOnly)
            return fd
        } catch { close(fd); throw error }
    }

    static func requireNamed(_ fd: Int32, directory: Int32, name: String) throws {
        let held = try validateRegular(fd)
        var named = stat()
        guard fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              SettingsFileIdentity(named) == held else { throw SettingsStoreError.changedExternally }
    }

    static func read(_ directory: Int32, name: String, limit: Int = SettingsDecoding.byteLimit,
                     ownerOnly: Bool = false) throws -> SettingsFileImage? {
        guard let fd = try openRegular(directory, name: name, ownerOnly: ownerOnly) else { return nil }
        defer { close(fd) }
        let before = try validateRegular(fd, ownerOnly: ownerOnly)
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw Failure.unavailable }
        guard info.st_size >= 0, info.st_size <= limit else { throw SettingsDecoding.Failure.oversized }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let capacity = min(buffer.count, limit + 1 - data.count)
            let count = Darwin.read(fd, &buffer, capacity)
            if count < 0 {
                if errno == EINTR { continue }
                throw Failure.unavailable
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= limit else { throw SettingsDecoding.Failure.oversized }
        }
        try requireNamed(fd, directory: directory, name: name)
        guard try identity(fd) == before else { throw SettingsStoreError.changedExternally }
        return SettingsFileImage(identity: before, bytes: data)
    }

    static func requireNoRemnants(_ fd: Int32) throws {
        // Independent directory stream, with explicit count/name-byte budgets.
        let scanFD = openat(fd, ".", O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard scanFD >= 0 else { throw Failure.unavailable }
        guard let stream = fdopendir(scanFD) else { close(scanFD); throw Failure.unavailable }
        defer { closedir(stream) }
        var count = 0, bytes = 0
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw Failure.unavailable }
                return
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            count += 1; bytes += name.utf8.count
            guard count <= 4096, bytes <= SettingsDecoding.byteLimit else { throw Failure.unavailable }
            // Presence alone blocks; never open a possible FIFO staging remnant.
            guard name != pending, !name.hasPrefix(".config-candidate-"),
                  !name.hasPrefix(".config-backup-") else { throw Failure.unavailable }
        }
    }

    static func image(_ fd: Int32) throws -> SettingsDiskImage {
        try requireNoRemnants(fd)
        return SettingsDiskImage(directory: try identity(fd),
            config: try read(fd, name: "config.json"), backup: try read(fd, name: backupName),
            lock: try read(fd, name: lockName, limit: 1024, ownerOnly: true),
            metadata: try read(fd, name: metadataName, limit: 1024, ownerOnly: true))
    }

    static func lock(_ fd: Int32) throws {
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { throw Failure.busy }
            throw Failure.unavailable
        }
    }

    static func load(_ url: URL) throws -> SettingsDiskImage {
        guard let directory = try directory(url) else {
            return SettingsDiskImage(directory: nil, config: nil, backup: nil, lock: nil, metadata: nil)
        }
        defer { close(directory) }
        let lockFD = try openRegular(directory, name: lockName, writable: true, ownerOnly: true)
        defer { if let lockFD { _ = flock(lockFD, LOCK_UN); close(lockFD) } }
        if let lockFD {
            try lock(lockFD)
            try requireNamed(lockFD, directory: directory, name: lockName)
        }
        let result = try image(directory)
        if let lockFD {
            guard result.lock?.identity == (try identity(lockFD)) else { throw Failure.unavailable }
        } else if result.lock != nil { throw Failure.busy }
        return result
    }

    static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}

/// One synchronous actor-owned transaction. A marker is retained on every failure after P1.
final class SettingsPublication {
    private let url: URL
    private let io: any JournalPOSIXIO
    private(set) var recoveryRequired = false
    private(set) var failure: SettingsPublicationFailure?
    private var stage = "admission"
    private var configRenameAttempted = false
    private var configSynchronized = false

    init(url: URL, io: any JournalPOSIXIO) { self.url = url; self.io = io }

    private func boundary<T>(_ stage: String, _ operation: () throws -> T) throws -> T {
        self.stage = stage
        return try operation()
    }

    private func create(_ directory: Int32, name: String) throws -> Int32 {
        let fd = openat(directory, name, O_RDWR | O_CREAT | O_EXCL | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SettingsFiles.posixError() }
        recoveryRequired = true
        do {
            _ = try SettingsFiles.validateRegular(fd, ownerOnly: true)
            try SettingsFiles.requireNamed(fd, directory: directory, name: name)
            return fd
        } catch { close(fd); throw error }
    }

    private func writeAndSync(_ fd: Int32, directory: Int32, name: String, bytes: Data,
                              stage: String) throws -> SettingsFileImage {
        try boundary(stage + ".write") { try JournalCheckedWrite.write(fd: fd, bytes: bytes, io: io) }
        try SettingsFiles.requireNamed(fd, directory: directory, name: name)
        try boundary(stage + ".syncFile") { try io.syncFile(fd: fd) }
        try SettingsFiles.requireNamed(fd, directory: directory, name: name)
        return SettingsFileImage(identity: try SettingsFiles.identity(fd), bytes: bytes)
    }

    private func recheckParent(_ directory: Int32, expected: SettingsFileIdentity?) throws {
        guard let reopened = try SettingsFiles.directory(url) else { throw SettingsStoreError.changedExternally }
        defer { close(reopened) }
        let held = try SettingsFiles.identity(directory)
        guard try SettingsFiles.identity(reopened) == held,
              expected == nil || (expected?.device == held.device && expected?.inode == held.inode) else {
            throw SettingsStoreError.changedExternally
        }
    }

    private func recheck(_ current: SettingsDiskImage, expected: SettingsDiskImage) throws {
        guard current.config == expected.config, current.backup == expected.backup,
              expected.lock == nil || current.lock == expected.lock,
              expected.metadata == nil || current.metadata == expected.metadata else {
            throw SettingsStoreError.changedExternally
        }
    }

    func publish(expected: SettingsDiskImage, envelope: SettingsEnvelope,
                 bytes: Data) throws -> SettingsDiskImage {
        do { return try transaction(expected: expected, envelope: envelope, bytes: bytes) }
        catch {
            if let posix = error as? POSIXError {
                failure = SettingsPublicationFailure(stage: stage, errno: posix.code.rawValue)
            }
            if configSynchronized { throw SettingsStoreError.finalizationBlocked }
            if configRenameAttempted { throw SettingsStoreError.durabilityUncertain }
            if recoveryRequired { throw SettingsStoreError.writeFailed }
            if let typed = error as? SettingsStoreError { throw typed }
            if case SettingsFiles.Failure.busy = error { throw SettingsStoreError.unavailable }
            if case SettingsFiles.Failure.unsafeLocation = error { throw SettingsStoreError.unsafeLocation }
            if stage != "admission" { throw SettingsStoreError.writeFailed }
            throw SettingsStoreError.readOnlyRecovery
        }
    }

    private func transaction(expected: SettingsDiskImage, envelope: SettingsEnvelope,
                             bytes: Data) throws -> SettingsDiskImage {
        let directory = try boundary("directory.open") {
            guard let fd = try SettingsFiles.directory(url, create: true) else { throw SettingsFiles.Failure.unavailable }
            return fd
        }
        defer { close(directory) }
        stage = "admission"
        try recheckParent(directory, expected: expected.directory)
        var lockFD = try SettingsFiles.openRegular(directory, name: SettingsFiles.lockName, writable: true, ownerOnly: true)
        var bootstrap = false
        if lockFD == nil {
            let before = try SettingsFiles.image(directory)
            try recheck(before, expected: expected)
            guard before.lock == nil, before.metadata == nil else { throw SettingsStoreError.readOnlyRecovery }
            do {
                lockFD = try boundary("bootstrap.lock.create") { try create(directory, name: SettingsFiles.lockName) }
                bootstrap = true
            } catch let error as POSIXError where error.code == .EEXIST {
                lockFD = try SettingsFiles.openRegular(directory, name: SettingsFiles.lockName, writable: true, ownerOnly: true)
            }
        }
        guard let lockFD else { throw SettingsStoreError.unavailable }
        defer { _ = flock(lockFD, LOCK_UN); close(lockFD) }
        try SettingsFiles.lock(lockFD)
        stage = "admission"
        try SettingsFiles.requireNamed(lockFD, directory: directory, name: SettingsFiles.lockName)
        var current = try SettingsFiles.image(directory)
        try recheckParent(directory, expected: expected.directory)
        try recheck(current, expected: expected)
        if !bootstrap {
            _ = try current.loaded()
            guard current.lock?.identity == (try SettingsFiles.identity(lockFD)),
                  current.metadata != nil else { throw SettingsStoreError.readOnlyRecovery }
        }

        let storeID: UUID
        if bootstrap {
            guard current.metadata == nil else { throw SettingsStoreError.readOnlyRecovery }
            storeID = UUID()
            let identityBytes = Data("{\"schema\":1,\"storeID\":\"\(storeID.uuidString)\"}".utf8)
            let lockImage = try writeAndSync(lockFD, directory: directory, name: SettingsFiles.lockName,
                bytes: identityBytes, stage: "bootstrap.lock")
            let metadataFD = try boundary("bootstrap.store.create") { try create(directory, name: SettingsFiles.metadataName) }
            defer { close(metadataFD) }
            let metadata = try writeAndSync(metadataFD, directory: directory, name: SettingsFiles.metadataName,
                bytes: identityBytes, stage: "bootstrap.store")
            try boundary("bootstrap.syncDirectory") { try io.syncDirectory(fd: directory) }
            try recheckParent(directory, expected: expected.directory)
            let after = try SettingsFiles.image(directory)
            try recheck(after, expected: expected)
            guard after.lock == lockImage, after.metadata == metadata else { throw SettingsStoreError.changedExternally }
            current = after
            // The creating actor stays conservative until the complete edit commits,
            // even if bootstrap itself succeeded but P0/marker creation later fails.
        } else {
            storeID = try SettingsDecoding.storeIdentity(current.lock!.bytes)
        }

        // P0 is still under the same stable lock. Nothing below suspends.
        try recheckParent(directory, expected: expected.directory)
        let rechecked = try SettingsFiles.image(directory)
        guard rechecked == current else { throw SettingsStoreError.changedExternally }
        let transactionID = UUID().uuidString
        let candidateName = ".config-candidate-" + transactionID
        let backupName = ".config-backup-" + transactionID
        let marker: [String: Any] = ["schema": 1, "storeID": storeID.uuidString,
            "transactionID": transactionID, "oldRevision": NSNumber(value: envelope.revision - 1),
            "newRevision": NSNumber(value: envelope.revision),
            "oldConfigSHA256": current.config.map { $0.digest as Any } ?? NSNull(),
            "candidateSHA256": SettingsFiles.digest(bytes),
            "candidateName": candidateName, "backupName": backupName]
        let markerBytes = try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
        guard markerBytes.count <= 4096 else { throw SettingsStoreError.oversized }
        let markerFD = try boundary("marker.create") { try create(directory, name: SettingsFiles.pending) }
        defer { close(markerFD) }
        let markerImage = try writeAndSync(markerFD, directory: directory, name: SettingsFiles.pending,
                             bytes: markerBytes, stage: "marker")
        try boundary("prepared.syncDirectory") { try io.syncDirectory(fd: directory) }

        let candidateFD = try boundary("candidate.create") { try create(directory, name: candidateName) }
        defer { close(candidateFD) }
        let candidate = try writeAndSync(candidateFD, directory: directory, name: candidateName,
                                         bytes: bytes, stage: "candidate")
        var backup = current.backup
        if let old = current.config {
            let backupFD = try boundary("backup.create") { try create(directory, name: backupName) }
            defer { close(backupFD) }
            backup = try writeAndSync(backupFD, directory: directory, name: backupName,
                                      bytes: old.bytes, stage: "backup")
            try recheckParent(directory, expected: expected.directory)
            guard try SettingsFiles.read(directory, name: SettingsFiles.backupName) == current.backup else {
                throw SettingsStoreError.changedExternally
            }
            try SettingsFiles.requireNamed(backupFD, directory: directory, name: backupName)
            try boundary("backup.replace") {
                try io.replace(directoryFD: directory, temporary: backupName, destination: SettingsFiles.backupName)
            }
            try SettingsFiles.requireNamed(backupFD, directory: directory, name: SettingsFiles.backupName)
            try boundary("backup.syncDirectory") { try io.syncDirectory(fd: directory) }
        }
        try recheckParent(directory, expected: expected.directory)
        guard try SettingsFiles.read(directory, name: "config.json") == current.config else {
            throw SettingsStoreError.changedExternally
        }
        try SettingsFiles.requireNamed(candidateFD, directory: directory, name: candidateName)
        try SettingsFiles.requireNamed(lockFD, directory: directory, name: SettingsFiles.lockName)
        configRenameAttempted = true
        try boundary("config.replace") {
            try io.replace(directoryFD: directory, temporary: candidateName, destination: "config.json")
        }
        try SettingsFiles.requireNamed(candidateFD, directory: directory, name: "config.json")
        try boundary("config.syncDirectory") { try io.syncDirectory(fd: directory) }
        configSynchronized = true

        // Both staging names were consumed by their successful renames. Never unlink
        // ENOENT, glob other artifacts, or remove a same-name replacement.
        for consumed in current.config == nil ? [candidateName] : [candidateName, backupName] {
            var info = stat()
            let found = fstatat(directory, consumed, &info, AT_SYMLINK_NOFOLLOW)
            guard found < 0, errno == ENOENT else { throw SettingsStoreError.changedExternally }
        }
        try SettingsFiles.requireNamed(markerFD, directory: directory, name: SettingsFiles.pending)
        guard try SettingsFiles.read(directory, name: SettingsFiles.pending, limit: 4096, ownerOnly: true) == markerImage else {
            throw SettingsStoreError.changedExternally
        }
        let completed = SettingsDiskImage(directory: current.directory, config: candidate, backup: backup,
                                           lock: current.lock, metadata: current.metadata)
        try boundary("finalize.marker.unlink") {
            guard unlinkat(directory, SettingsFiles.pending, 0) == 0 else { throw SettingsFiles.posixError() }
        }
        // No required I/O after the final unlink; P4 already synchronized config+backup.
        recoveryRequired = false
        return completed
    }
}
