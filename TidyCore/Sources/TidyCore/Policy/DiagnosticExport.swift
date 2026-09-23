import Darwin
import Foundation

public struct DiagnosticExportInput: Sendable {
    public let settings: SettingsEnvelope
    public let cosmeticRedactionEnabled: Bool
    public let credentials: [String]
    public let cookies: [String]
    public let environment: [String: String]
    public let argv: [String]
    public let remotes: [String]
    public let personalPaths: [String]

    public init(settings: SettingsEnvelope, cosmeticRedactionEnabled: Bool,
                credentials: [String] = [], cookies: [String] = [],
                environment: [String: String] = [:], argv: [String] = [],
                remotes: [String] = [], personalPaths: [String] = []) {
        self.settings = settings
        self.cosmeticRedactionEnabled = cosmeticRedactionEnabled
        self.credentials = credentials
        self.cookies = cookies
        self.environment = environment
        self.argv = argv
        self.remotes = remotes
        self.personalPaths = personalPaths
    }
}

public struct DiagnosticExportRenderings: Equatable, Sendable {
    public let primaryCandidate: Data
    public let temporaryCandidate: Data
    public let backupCandidate: Data
}

/// Produces metadata-only diagnostic bytes. Sensitive classes are absent
/// from the encoded payload by construction, so disabling cosmetic
/// redaction can never include credentials, cookies, environment, argv,
/// remotes, settings values, profile names, or personal path identities.
public enum DiagnosticExportRenderer {
    private struct Payload: Codable {
        let schemaVersion: Int
        let settingsRevision: UInt64
        let profileCount: Int
        let inertSettingCount: Int
        let cosmeticRedactionEnabled: Bool
        let immutablePrivacyExclusions: [String]
    }

    public static func render(_ input: DiagnosticExportInput) throws
        -> DiagnosticExportRenderings {
        let payload = Payload(schemaVersion: input.settings.schemaVersion,
            settingsRevision: input.settings.revision,
            profileCount: input.settings.preferences?.profiles.count ?? 0,
            inertSettingCount: input.settings.inertImports.count,
            cosmeticRedactionEnabled: input.cosmeticRedactionEnabled,
            immutablePrivacyExclusions: [
                "argv", "cookies", "credentials", "environment", "personalPathIdentity",
                "portableSettingValues", "profileNames", "remotes"
            ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        var bytes = try encoder.encode(payload)
        bytes.append(0x0A)
        return DiagnosticExportRenderings(primaryCandidate: bytes,
            temporaryCandidate: bytes, backupCandidate: bytes)
    }
}

public struct DiagnosticExportReceipt: Equatable, Sendable {
    public let bytesWritten: Int
}

public enum DiagnosticExportWriteStage: String, Equatable, Sendable {
    case rendering
    case destinationValidation
    case parentOpen
    case parentValidation
    case stagingCreate
    case stagingValidation
    case stagingWrite
    case stagingSync
    case publication
    case parentSync
}

public enum DiagnosticExportWriteError: Error, Equatable, Sendable {
    case failure(stage: DiagnosticExportWriteStage, code: Int32)
    case publicationUncertain(code: Int32)
}

enum DiagnosticExportWriterFault: Equatable, Sendable {
    case beforePublication(code: Int32)
    case afterPublication(code: Int32)
}

/// Publishes one new owner-only diagnostic file. Existing destination nodes are
/// never opened, replaced, backed up, or removed.
public enum DiagnosticExportWriter {
    private static let maximumPayloadBytes = 64 * 1024
    private static let stagingPrefix = ".tidy-diagnostic-"
    private static let stagingSuffix = ".staging"

    public static func write(_ input: DiagnosticExportInput, to destination: URL) throws
        -> DiagnosticExportReceipt {
        try write(input, to: destination, fault: nil)
    }

    static func write(_ input: DiagnosticExportInput, to destination: URL,
                      injecting fault: DiagnosticExportWriterFault) throws
        -> DiagnosticExportReceipt {
        try write(input, to: destination, fault: fault)
    }

    private static func write(_ input: DiagnosticExportInput, to destination: URL,
                              fault: DiagnosticExportWriterFault?) throws
        -> DiagnosticExportReceipt {
        let target = try validatedDestination(destination)
        let bytes: Data
        do {
            bytes = try DiagnosticExportRenderer.render(input).primaryCandidate
        } catch {
            throw failure(.rendering, EIO)
        }
        guard !bytes.isEmpty, bytes.count <= maximumPayloadBytes else {
            throw failure(.rendering, bytes.isEmpty ? EINVAL : EFBIG)
        }

        let directory = Darwin.open(target.parent.path,
            O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw failure(.parentOpen, errno) }
        defer { Darwin.close(directory) }
        try validateParent(directory)

        let stagingName = stagingPrefix + UUID().uuidString + stagingSuffix
        let descriptor = openat(directory, stagingName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw failure(.stagingCreate, errno) }
        defer { Darwin.close(descriptor) }

        var created = stat()
        guard fstat(descriptor, &created) == 0 else {
            throw failure(.stagingValidation, errno)
        }
        var removeStaging = true
        defer {
            if removeStaging {
                removeExactStaging(directory: directory, name: stagingName, identity: created)
            }
        }

        guard fchmod(descriptor, 0o600) == 0 else {
            throw failure(.stagingValidation, errno)
        }
        try clearExtendedACL(descriptor)
        try validateStaging(descriptor, directory: directory, name: stagingName,
                            expected: created, expectedSize: 0)
        try writeAll(bytes, to: descriptor)
        try validateStaging(descriptor, directory: directory, name: stagingName,
                            expected: created, expectedSize: bytes.count)
        guard fsync(descriptor) == 0 else { throw failure(.stagingSync, errno) }
        try validateStaging(descriptor, directory: directory, name: stagingName,
                            expected: created, expectedSize: bytes.count)

        if case .beforePublication(let code)? = fault {
            throw failure(.publication, code)
        }
        guard renameatx_np(directory, stagingName, directory, target.name,
                           UInt32(RENAME_EXCL)) == 0 else {
            throw failure(.publication, errno)
        }
        removeStaging = false
        try validatePublished(descriptor: descriptor, directory: directory, name: target.name,
                              expected: created, expectedSize: bytes.count)

        if case .afterPublication(let code)? = fault {
            throw DiagnosticExportWriteError.publicationUncertain(code: normalized(code))
        }
        guard fsync(directory) == 0 else {
            throw DiagnosticExportWriteError.publicationUncertain(code: normalized(errno))
        }
        return DiagnosticExportReceipt(bytesWritten: bytes.count)
    }

    private static func validatedDestination(_ destination: URL) throws
        -> (parent: URL, name: String) {
        guard destination.isFileURL, !destination.hasDirectoryPath,
              destination.path.hasPrefix("/"), !destination.path.utf8.contains(0) else {
            throw failure(.destinationValidation, EINVAL)
        }
        let value = destination.standardizedFileURL
        let name = value.lastPathComponent
        let parent = value.deletingLastPathComponent()
        guard !name.isEmpty, name != ".", name != "..", !name.utf8.contains(0),
              name.utf8.count <= Int(NAME_MAX), parent.path != value.path,
              parent.path.hasPrefix("/") else {
            throw failure(.destinationValidation, EINVAL)
        }
        return (parent, name)
    }

    private static func validateParent(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw failure(.parentValidation, errno)
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
              info.st_mode & 0o022 == 0 else {
            throw failure(.parentValidation, EPERM)
        }
        let tags: [acl_tag_t]
        do { tags = try extendedACLTags(descriptor) }
        catch let error as POSIXError {
            throw failure(.parentValidation, error.code.rawValue)
        }
        guard tags.allSatisfy({ $0 == ACL_EXTENDED_DENY }) else {
            throw failure(.parentValidation, EPERM)
        }
    }

    private static func validateStaging(_ descriptor: Int32, directory: Int32, name: String,
                                        expected: stat, expectedSize: Int) throws {
        var opened = stat()
        guard fstat(descriptor, &opened) == 0 else {
            throw failure(.stagingValidation, errno)
        }
        guard opened.st_dev == expected.st_dev, opened.st_ino == expected.st_ino,
              opened.st_mode & S_IFMT == S_IFREG, opened.st_uid == geteuid(),
              opened.st_mode & 0o777 == 0o600, opened.st_nlink == 1,
              opened.st_size == off_t(expectedSize) else {
            throw failure(.stagingValidation, EPERM)
        }
        var named = stat()
        guard fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw failure(.stagingValidation, errno)
        }
        guard named.st_dev == opened.st_dev, named.st_ino == opened.st_ino,
              named.st_mode & S_IFMT == S_IFREG else {
            throw failure(.stagingValidation, ESTALE)
        }
        do {
            guard try extendedACLTags(descriptor).isEmpty else {
                throw failure(.stagingValidation, EPERM)
            }
        } catch let error as POSIXError {
            throw failure(.stagingValidation, error.code.rawValue)
        }
    }

    private static func writeAll(_ bytes: Data, to descriptor: Int32) throws {
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset),
                                         raw.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw failure(.stagingWrite, errno) }
                offset += count
            }
        }
    }

    private static func validatePublished(descriptor: Int32, directory: Int32, name: String,
                                          expected: stat, expectedSize: Int) throws {
        var named = stat()
        guard fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw DiagnosticExportWriteError.publicationUncertain(code: normalized(errno))
        }
        guard named.st_dev == expected.st_dev, named.st_ino == expected.st_ino,
              named.st_mode & S_IFMT == S_IFREG, named.st_uid == geteuid(),
              named.st_mode & 0o777 == 0o600, named.st_nlink == 1,
              named.st_size == off_t(expectedSize) else {
            throw DiagnosticExportWriteError.publicationUncertain(code: ESTALE)
        }
        do {
            guard try extendedACLTags(descriptor).isEmpty else {
                throw DiagnosticExportWriteError.publicationUncertain(code: EPERM)
            }
        } catch let error as POSIXError {
            throw DiagnosticExportWriteError.publicationUncertain(
                code: normalized(error.code.rawValue))
        }
    }

    private static func clearExtendedACL(_ descriptor: Int32) throws {
        guard let empty = acl_init(0) else {
            throw failure(.stagingValidation, errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(empty)) }
        guard acl_valid(empty) == 0 else {
            throw failure(.stagingValidation, errno)
        }
        guard acl_set_fd_np(descriptor, empty, ACL_TYPE_EXTENDED) == 0 else {
            throw failure(.stagingValidation, errno)
        }
        do {
            guard try extendedACLTags(descriptor).isEmpty else {
                throw failure(.stagingValidation, EPERM)
            }
        } catch let error as POSIXError {
            throw failure(.stagingValidation, error.code.rawValue)
        }
    }

    private static func extendedACLTags(_ descriptor: Int32) throws -> [acl_tag_t] {
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            let code = errno
            // Darwin reports an absent extended ACL with ENOENT. Confirm the
            // descriptor still identifies a linked object before accepting it.
            if code == ENOENT {
                var info = stat()
                guard fstat(descriptor, &info) == 0 else { throw posixError() }
                guard info.st_nlink > 0 else { throw POSIXError(.ESTALE) }
                return []
            }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw posixError() }

        var tags: [acl_tag_t] = []
        var selector = ACL_FIRST_ENTRY
        while true {
            var entry: acl_entry_t?
            errno = 0
            let status = acl_get_entry(acl, Int32(selector.rawValue), &entry)
            if status == -1, errno == EINVAL { break }
            guard status == 0, let entry else { throw posixError() }
            guard tags.count < Int(ACL_MAX_ENTRIES) else {
                throw POSIXError(.E2BIG)
            }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0 else { throw posixError() }
            tags.append(tag)
            selector = ACL_NEXT_ENTRY
        }
        return tags
    }

    private static func removeExactStaging(directory: Int32, name: String, identity: stat) {
        var named = stat()
        guard fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_dev == identity.st_dev, named.st_ino == identity.st_ino,
              named.st_mode & S_IFMT == S_IFREG, named.st_uid == geteuid() else { return }
        guard unlinkat(directory, name, 0) == 0 else { return }
        _ = fsync(directory)
    }

    private static func normalized(_ code: Int32) -> Int32 { code == 0 ? EIO : code }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: normalized(errno)) ?? .EIO)
    }

    private static func failure(_ stage: DiagnosticExportWriteStage, _ code: Int32)
        -> DiagnosticExportWriteError {
        .failure(stage: stage, code: normalized(code))
    }
}
