import Foundation
import Darwin

/// Staged read-only migration. No live writer, policy publication, or bootstrap exists in A.1.
public actor SettingsStore {
    private let url: URL
    private var recoveryReadOnly = false
    public init(url: URL) { self.url = url }
    public func load() -> SettingsLoadResult {
        do {
            let result: SettingsLoadResult
            if let bytes = try SettingsReader.read(url) {
                result = try SettingsDecoding.load(bytes)
            } else {
                result = SettingsLoadResult(disposition: .newDefaults,
                    envelope: SettingsEnvelope(schemaVersion: 2, revision: 0,
                        config: TidyConfig(schemaVersion: 2)), recoveryReason: nil)
            }
            recoveryReadOnly = false
            return result
        } catch {
            recoveryReadOnly = true
            let reason: SettingsRecoveryReason
            switch error {
            case SettingsDecoding.Failure.unsupportedSchema(let version): reason = .unsupportedSchema(version)
            case SettingsDecoding.Failure.oversized: reason = .oversized
            case SettingsReader.Failure.unsafeLocation: reason = .unsafeLocation
            case SettingsReader.Failure.unavailable: reason = .unavailable
            default: reason = .malformed
            }
            return SettingsLoadResult(disposition: .recoveryReadOnly, envelope: nil, recoveryReason: reason)
        }
    }
    public func update(expectedRevision: UInt64, change: SettingsChange) throws -> SettingsEnvelope {
        throw recoveryReadOnly ? SettingsStoreError.readOnlyRecovery : SettingsStoreError.unavailable
    }
    public func previewRollback() throws -> SettingsRollbackPreview {
        throw recoveryReadOnly ? SettingsStoreError.readOnlyRecovery : SettingsStoreError.unavailable
    }
    public func rollback(expectedRevision: UInt64, preview: SettingsRollbackPreview) throws -> SettingsEnvelope {
        throw recoveryReadOnly ? SettingsStoreError.readOnlyRecovery : SettingsStoreError.unavailable
    }
}

/// Descriptor-relative, nonblocking read. Every opened regular-file FD is validated before read.
private enum SettingsReader {
    enum Failure: Error { case unavailable, unsafeLocation }

    static func read(_ url: URL) throws -> Data? {
        guard url.isFileURL, !url.path.utf8.contains(0), url.path.hasPrefix("/") else {
            throw Failure.unsafeLocation
        }
        let components = url.path.split(separator: "/").map(String.init)
        guard components.count > 1, !components.contains("."), !components.contains(".."),
              let name = components.last else { throw Failure.unsafeLocation }
        let directory = try openDirectory(Array(components.dropLast()))
        defer { close(directory) }
        // Auxiliary files are not repaired, read, or created by this staged reader.
        var hasAuxiliary = false
        for auxiliary in ["config.lock", "config.backup.json"] {
            if let fd = try openRegular(directory: directory, name: auxiliary) {
                hasAuxiliary = true
                close(fd)
            }
        }
        guard let fd = try openRegular(directory: directory, name: name) else {
            guard !hasAuxiliary else { throw Failure.unavailable }
            return nil
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw Failure.unavailable }
        guard info.st_size >= 0, info.st_size <= SettingsDecoding.byteLimit else {
            throw SettingsDecoding.Failure.oversized
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            // Read one extra byte at the limit to detect growth, never an unbounded stream.
            let capacity = min(buffer.count, SettingsDecoding.byteLimit + 1 - data.count)
            let count = Darwin.read(fd, &buffer, capacity)
            if count < 0 {
                if errno == EINTR { continue }
                throw Failure.unavailable
            }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= SettingsDecoding.byteLimit else { throw SettingsDecoding.Failure.oversized }
        }
    }

    private static func openRegular(directory: Int32, name: String) throws -> Int32? {
        let fd = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw errno == ELOOP ? Failure.unsafeLocation : Failure.unavailable
        }
        do {
            var info = stat()
            guard fstat(fd, &info) == 0 else { throw Failure.unavailable }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
                  info.st_mode & 0o022 == 0 else { throw Failure.unsafeLocation }
            try requireLocal(fd)
            return fd
        } catch { close(fd); throw error }
    }

    private static func openDirectory(_ components: [String]) throws -> Int32 {
        var fd = open("/", O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unavailable }
        do {
            for (index, component) in components.enumerated() {
                let next = openat(fd, component, O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else {
                    throw errno == ELOOP || errno == ENOTDIR ? Failure.unsafeLocation : Failure.unavailable
                }
                close(fd); fd = next
                var info = stat()
                guard fstat(fd, &info) == 0 else { throw Failure.unavailable }
                let final = index == components.count - 1
                let trustedOwner = info.st_uid == geteuid() || (!final && info.st_uid == 0)
                // Root-owned sticky temporary ancestors are allowed, not writable settings directories.
                let stickyAncestor = !final && info.st_uid == 0 && info.st_mode & S_ISVTX != 0
                guard info.st_mode & S_IFMT == S_IFDIR, trustedOwner,
                      info.st_mode & 0o022 == 0 || stickyAncestor else { throw Failure.unsafeLocation }
                try requireLocal(fd)
            }
            return fd
        } catch { close(fd); throw error }
    }

    private static func requireLocal(_ fd: Int32) throws {
        var info = statfs()
        guard fstatfs(fd, &info) == 0 else { throw Failure.unavailable }
        guard info.f_flags & UInt32(MNT_LOCAL) != 0 else { throw Failure.unsafeLocation }
    }
}
