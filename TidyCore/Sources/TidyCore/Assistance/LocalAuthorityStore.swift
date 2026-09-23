import CryptoKit
import Darwin
import Foundation

public enum LocalAuthorityError: Error, Equatable, Sendable {
    case unsafeLocation
    case storageUnavailable
    case storageBusy
    case corruptLedger
    case capacityExceeded
    case invalidScope
    case unknownReview
    case wrongOwner
    case expiredReview
    case revokedReview
}

public struct LocalInstallationIdentity: Hashable, Codable, Sendable {
    public let canonicalDirectoryPath: String
    public let volumeDevice: UInt64
    public let directoryInode: UInt64
    public let ownerUID: UInt32

    internal init(canonicalDirectoryPath: String, volumeDevice: UInt64,
                  directoryInode: UInt64, ownerUID: UInt32) {
        self.canonicalDirectoryPath = canonicalDirectoryPath
        self.volumeDevice = volumeDevice
        self.directoryInode = directoryInode
        self.ownerUID = ownerUID
    }

    public static func verify(directory: URL) throws -> Self {
        let (fd, canonical) = try LocalAuthorityFiles.openVerifiedDirectory(directory)
        defer { close(fd) }
        let info = try LocalAuthorityFiles.statInfo(fd)
        return Self(canonicalDirectoryPath: canonical, volumeDevice: UInt64(info.st_dev),
                    directoryInode: UInt64(info.st_ino), ownerUID: UInt32(info.st_uid))
    }
}

public struct LocalRootApproval: Hashable, Codable, Sendable {
    public let canonicalPath: String
    public let volumeID: UUID
    public let device: UInt64
    public let inode: UInt64

    public static func verify(directory: URL) throws -> Self {
        guard directory.isFileURL, directory.path.hasPrefix("/"),
              directory.path.utf8.count <= 4_096, !directory.path.utf8.contains(0) else {
            throw LocalAuthorityError.invalidScope
        }
        let canonical = directory.resolvingSymlinksInPath().standardizedFileURL
        let fd = open(canonical.path, O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw LocalAuthorityError.unsafeLocation }
        defer { close(fd) }
        var info = stat(), filesystem = statfs()
        guard fstat(fd, &info) == 0, fstatfs(fd, &filesystem) == 0,
              info.st_mode & S_IFMT == S_IFDIR, filesystem.f_flags & UInt32(MNT_LOCAL) != 0 else {
            throw LocalAuthorityError.unsafeLocation
        }
        let values = try canonical.resourceValues(forKeys: [.volumeUUIDStringKey])
        guard let raw = values.volumeUUIDString, let volumeID = UUID(uuidString: raw) else {
            throw LocalAuthorityError.unsafeLocation
        }
        return Self(canonicalPath: canonical.path, volumeID: volumeID,
                    device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    public static func verifyExternalVolumeRoot(directory: URL) throws -> Self {
        let approval = try verify(directory: directory)
        let canonical = URL(fileURLWithPath: approval.canonicalPath,
                            isDirectory: true).standardizedFileURL
        let values = try canonical.resourceValues(forKeys: [.volumeURLKey])
        guard let volumeURL = values.volume,
              volumeURL.resolvingSymlinksInPath().standardizedFileURL.path
                == canonical.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw LocalAuthorityError.invalidScope
        }
        return approval
    }
}

public struct LocalExecutableApproval: Hashable, Codable, Sendable {
    public let canonicalPath: String
    public let device: UInt64
    public let inode: UInt64

    public static func verify(executable: URL) throws -> Self {
        guard executable.isFileURL, executable.path.hasPrefix("/"),
              executable.path.utf8.count <= 4_096, !executable.path.utf8.contains(0) else {
            throw LocalAuthorityError.invalidScope
        }
        let canonical = executable.resolvingSymlinksInPath().standardizedFileURL
        let fd = open(canonical.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw LocalAuthorityError.unsafeLocation }
        defer { close(fd) }
        var info = stat(), filesystem = statfs()
        guard fstat(fd, &info) == 0, fstatfs(fd, &filesystem) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              (info.st_uid == 0 || info.st_uid == geteuid()),
              info.st_mode & 0o022 == 0, info.st_nlink == 1,
              info.st_mode & 0o111 != 0,
              filesystem.f_flags & UInt32(MNT_LOCAL) != 0 else {
            throw LocalAuthorityError.unsafeLocation
        }
        return Self(canonicalPath: canonical.path, device: UInt64(info.st_dev),
                    inode: UInt64(info.st_ino))
    }
}

public struct LocalSocketApproval: Hashable, Codable, Sendable {
    public let canonicalPath: String
    public let device: UInt64
    public let inode: UInt64
    public let ownerUID: UInt32

    public static func verify(socket: URL) throws -> Self {
        guard socket.isFileURL, socket.path.hasPrefix("/"),
              socket.path.utf8.count <= 4_096, !socket.path.utf8.contains(0) else {
            throw LocalAuthorityError.invalidScope
        }
        let leaf = socket.lastPathComponent
        guard !leaf.isEmpty, leaf != ".", leaf != "..", !leaf.contains("/"),
              leaf.utf8.count <= Int(NAME_MAX) else {
            throw LocalAuthorityError.invalidScope
        }
        let parentInput = socket.deletingLastPathComponent()
        guard let resolved = realpath(parentInput.path, nil) else {
            throw LocalAuthorityError.unsafeLocation
        }
        defer { free(resolved) }
        let parentPath = String(cString: resolved)
        let parentFD = open(parentPath,
            O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { throw LocalAuthorityError.unsafeLocation }
        defer { close(parentFD) }
        var info = stat(), filesystem = statfs()
        guard fstatat(parentFD, leaf, &info, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_mode & S_IFMT == S_IFSOCK,
              info.st_uid == 0 || info.st_uid == geteuid(),
              fstatfs(parentFD, &filesystem) == 0,
              filesystem.f_flags & UInt32(MNT_LOCAL) != 0 else {
            throw LocalAuthorityError.unsafeLocation
        }
        let canonical = URL(fileURLWithPath: parentPath, isDirectory: true)
            .appendingPathComponent(leaf, isDirectory: false).standardizedFileURL.path
        return Self(canonicalPath: canonical, device: UInt64(info.st_dev),
                    inode: UInt64(info.st_ino), ownerUID: UInt32(info.st_uid))
    }
}

/// The exhaustive set of authority which can be persisted. Adding a new case
/// requires a source change and migration; imported settings never decode into
/// this ledger.
public enum LocalAuthorityScope: Hashable, Codable, Sendable {
    case backgroundSignals
    case notifications
    case launchAtLogin
    case rescueApplication(RescueApplicationApproval)
    case maintenanceNotifyOnly(MaintenanceGrant)
    case maintenanceCaches(MaintenanceGrant)
    case localRoot(LocalRootApproval)
    case externalVolume(LocalRootApproval)
    case localExecutable(LocalExecutableApproval)
    case localSocket(LocalSocketApproval)
}

public struct LocalAuthorityOwner: Hashable, Sendable {
    fileprivate let value: UUID
    public init() { value = UUID() }
}

public struct LocalAuthorityReviewToken: Hashable, Sendable {
    fileprivate let value: UUID
    fileprivate let generation: UInt64
    fileprivate init(value: UUID, generation: UInt64) {
        self.value = value
        self.generation = generation
    }
}

final class LocalAuthorityEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64
    private var active: Bool

    init(revision: UInt64, active: Bool = true) {
        self.revision = revision
        self.active = active
    }

    func isCurrent(_ capturedRevision: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active && revision == capturedRevision
    }

    func invalidate() {
        lock.lock(); active = false; lock.unlock()
    }

    func publish(revision: UInt64) {
        lock.lock()
        self.revision = revision
        active = true
        lock.unlock()
    }
}

public struct LocalAuthoritySnapshot: Equatable, Sendable {
    public let revision: UInt64
    public let installation: LocalInstallationIdentity
    public let scopes: Set<LocalAuthorityScope>
    public let staleScopes: Set<LocalAuthorityScope>
    public let recordedScopes: Set<LocalAuthorityScope>
    private let epoch: LocalAuthorityEpoch

    internal init(revision: UInt64, installation: LocalInstallationIdentity,
                  scopes: Set<LocalAuthorityScope>,
                  staleScopes: Set<LocalAuthorityScope> = [],
                  epoch: LocalAuthorityEpoch? = nil) {
        self.revision = revision
        self.installation = installation
        self.scopes = scopes
        self.staleScopes = staleScopes
        self.recordedScopes = scopes.union(staleScopes)
        self.epoch = epoch ?? LocalAuthorityEpoch(revision: revision)
    }

    public var isCurrent: Bool { epoch.isCurrent(revision) }

    public func permits(_ scope: LocalAuthorityScope) -> Bool {
        isCurrent && scopes.contains(scope)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.revision == rhs.revision && lhs.installation == rhs.installation
            && lhs.scopes == rhs.scopes && lhs.staleScopes == rhs.staleScopes
            && lhs.isCurrent == rhs.isCurrent
    }
}

public actor LocalAuthorityStore {
    private struct Grant: Codable, Hashable, Sendable {
        let scope: LocalAuthorityScope
        let generation: UInt64
    }
    private struct Ledger: Codable, Sendable {
        let schemaVersion: UInt32
        let installation: LocalInstallationIdentity
        var revision: UInt64
        var generations: [String: UInt64]
        var grants: [Grant]
    }
    private struct Pending: Sendable {
        let scope: LocalAuthorityScope
        let owner: UUID
        let deadlineNanoseconds: UInt64
        let generation: UInt64
    }

    private static let ledgerName = "local-authority-v1.json"
    private static let lockName = "local-authority.lock"
    private static let maximumBytes = 128 * 1_024
    private static let maximumGrants = 256
    private static let maximumPendingReviews = 64
    private static let maximumSubscribers = 32

    private let directoryFD: Int32
    private let lockFD: Int32
    private let epoch: LocalAuthorityEpoch
    private var ledger: Ledger
    private var pending: [UUID: Pending] = [:]
    private var subscribers: [UUID: AsyncStream<LocalAuthoritySnapshot?>.Continuation] = [:]
    private var failed = false

    public init(directory: URL, installation: LocalInstallationIdentity) throws {
        let (openedDirectoryFD, canonical) = try LocalAuthorityFiles.openVerifiedDirectory(directory)
        guard canonical == installation.canonicalDirectoryPath else {
            close(openedDirectoryFD)
            throw LocalAuthorityError.unsafeLocation
        }
        let info = try LocalAuthorityFiles.statInfo(openedDirectoryFD)
        guard UInt64(info.st_dev) == installation.volumeDevice,
              UInt64(info.st_ino) == installation.directoryInode,
              UInt32(info.st_uid) == installation.ownerUID else {
            close(openedDirectoryFD)
            throw LocalAuthorityError.unsafeLocation
        }
        var openedLockFD: Int32 = -1
        do {
            openedLockFD = try LocalAuthorityFiles.openOrCreatePrivateFile(
                directoryFD: openedDirectoryFD, name: Self.lockName)
            guard flock(openedLockFD, LOCK_EX | LOCK_NB) == 0 else {
                let code = errno
                throw code == EWOULDBLOCK ? LocalAuthorityError.storageBusy : .storageUnavailable
            }
            try LocalAuthorityFiles.requireNoUnfinishedTransaction(
                directoryFD: openedDirectoryFD)
            let loaded: Ledger
            if let bytes = try LocalAuthorityFiles.readPrivateFile(
                directoryFD: openedDirectoryFD, name: Self.ledgerName, limit: Self.maximumBytes) {
                let strict = try StrictJSON.parse(bytes)
                let decoded = try JSONDecoder().decode(Ledger.self, from: bytes)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                let roundTrip = try StrictJSON.parse(encoder.encode(decoded))
                guard try StrictJSON.canonicalData(strict) == StrictJSON.canonicalData(roundTrip) else {
                    throw LocalAuthorityError.corruptLedger
                }
                try Self.validate(decoded, installation: installation)
                loaded = decoded
            } else {
                let empty = Ledger(schemaVersion: 1, installation: installation,
                    revision: 0, generations: [:], grants: [])
                try Self.publish(empty, directoryFD: openedDirectoryFD)
                loaded = empty
            }
            self.directoryFD = openedDirectoryFD
            self.lockFD = openedLockFD
            self.ledger = loaded
            self.epoch = LocalAuthorityEpoch(revision: loaded.revision)
        } catch {
            if openedLockFD >= 0 {
                _ = flock(openedLockFD, LOCK_UN)
                close(openedLockFD)
            }
            close(openedDirectoryFD)
            throw error
        }
    }

    deinit {
        epoch.invalidate()
        for continuation in subscribers.values { continuation.finish() }
        _ = flock(lockFD, LOCK_UN)
        close(lockFD)
        close(directoryFD)
    }

    public func beginReview(scope: LocalAuthorityScope, owner: LocalAuthorityOwner,
                            nowMonotonicNanoseconds: UInt64,
                            validityNanoseconds: UInt64 = 300_000_000_000) throws
        -> LocalAuthorityReviewToken {
        try requireHealthy()
        try Self.validateScope(scope, revalidateIdentity: true)
        pending = pending.filter { $0.value.deadlineNanoseconds >= nowMonotonicNanoseconds }
        guard pending.count < Self.maximumPendingReviews else {
            throw LocalAuthorityError.capacityExceeded
        }
        guard validityNanoseconds > 0, validityNanoseconds <= 600_000_000_000 else {
            throw LocalAuthorityError.expiredReview
        }
        let (deadline, overflow) = nowMonotonicNanoseconds.addingReportingOverflow(validityNanoseconds)
        guard !overflow else { throw LocalAuthorityError.expiredReview }
        let key = try Self.key(scope)
        let generation = ledger.generations[key, default: 0]
        let token = LocalAuthorityReviewToken(value: UUID(), generation: generation)
        pending[token.value] = Pending(scope: scope, owner: owner.value,
            deadlineNanoseconds: deadline, generation: generation)
        return token
    }

    public func cancel(_ token: LocalAuthorityReviewToken,
                       owner: LocalAuthorityOwner) throws {
        try requireHealthy()
        guard let review = pending[token.value], review.generation == token.generation else {
            throw LocalAuthorityError.unknownReview
        }
        guard review.owner == owner.value else { throw LocalAuthorityError.wrongOwner }
        pending[token.value] = nil
    }

    @discardableResult
    public func confirm(_ token: LocalAuthorityReviewToken, owner: LocalAuthorityOwner,
                        nowMonotonicNanoseconds: UInt64) throws -> LocalAuthoritySnapshot {
        try requireHealthy()
        guard let review = pending[token.value], review.generation == token.generation else {
            throw LocalAuthorityError.unknownReview
        }
        guard review.owner == owner.value else { throw LocalAuthorityError.wrongOwner }
        guard nowMonotonicNanoseconds <= review.deadlineNanoseconds else {
            pending[token.value] = nil
            throw LocalAuthorityError.expiredReview
        }
        let key = try Self.key(review.scope)
        guard ledger.generations[key, default: 0] == review.generation else {
            pending[token.value] = nil
            throw LocalAuthorityError.revokedReview
        }
        try Self.validateScope(review.scope, revalidateIdentity: true)
        var candidate = ledger
        candidate.revision = try Self.increment(candidate.revision)
        candidate.grants.removeAll { $0.scope == review.scope }
        guard candidate.grants.count < Self.maximumGrants else {
            throw LocalAuthorityError.capacityExceeded
        }
        candidate.grants.append(Grant(scope: review.scope, generation: review.generation))
        try persist(candidate)
        pending[token.value] = nil
        return snapshotUnchecked()
    }

    @discardableResult
    public func revoke(_ scope: LocalAuthorityScope) throws -> LocalAuthoritySnapshot {
        try requireHealthy()
        try Self.validateScope(scope, revalidateIdentity: false)
        let key = try Self.key(scope)
        var candidate = ledger
        candidate.revision = try Self.increment(candidate.revision)
        candidate.generations[key] = try Self.increment(candidate.generations[key, default: 0])
        candidate.grants.removeAll { $0.scope == scope }
        pending = pending.filter { $0.value.scope != scope }
        try persist(candidate)
        return snapshotUnchecked()
    }

    @discardableResult
    public func revokeAll() throws -> LocalAuthoritySnapshot {
        try requireHealthy()
        var candidate = ledger
        candidate.revision = try Self.increment(candidate.revision)
        for grant in candidate.grants {
            let key = try Self.key(grant.scope)
            candidate.generations[key] = try Self.increment(candidate.generations[key, default: 0])
        }
        candidate.grants = []
        pending = [:]
        try persist(candidate)
        return snapshotUnchecked()
    }

    public func snapshot() throws -> LocalAuthoritySnapshot {
        try requireHealthy()
        return snapshotUnchecked()
    }

    /// Event-driven authority changes with one buffered newest value per
    /// subscriber. Nil revokes runtime use before durable publication starts.
    public func updates() -> AsyncStream<LocalAuthoritySnapshot?> {
        let subscriberID = UUID()
        let pair = AsyncStream<LocalAuthoritySnapshot?>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        guard subscribers.count < Self.maximumSubscribers, !failed else {
            pair.continuation.yield(nil)
            pair.continuation.finish()
            return pair.stream
        }
        subscribers[subscriberID] = pair.continuation
        pair.continuation.yield(snapshotUnchecked())
        pair.continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeSubscriber(subscriberID) }
        }
        return pair.stream
    }

    private func snapshotUnchecked() -> LocalAuthoritySnapshot {
        let all = Set(ledger.grants.map(\.scope))
        let current = Set(all.filter(Self.isCurrent))
        return LocalAuthoritySnapshot(revision: ledger.revision,
            installation: ledger.installation, scopes: current,
            staleScopes: all.subtracting(current), epoch: epoch)
    }

    private func persist(_ candidate: Ledger) throws {
        // Revoke the runtime capability before attempting durable publication.
        // Failure remains fail-closed; success publishes only the new revision.
        epoch.invalidate()
        publishUpdate(nil)
        do {
            try Self.validate(candidate, installation: ledger.installation)
            try Self.publish(candidate, directoryFD: directoryFD)
            ledger = candidate
            epoch.publish(revision: candidate.revision)
            publishUpdate(snapshotUnchecked())
        } catch {
            failed = true
            throw error
        }
    }

    private func requireHealthy() throws {
        guard !failed else {
            epoch.invalidate()
            publishUpdate(nil)
            throw LocalAuthorityError.storageUnavailable
        }
        do {
            let info = try LocalAuthorityFiles.statInfo(directoryFD)
            guard UInt64(info.st_dev) == ledger.installation.volumeDevice,
                  UInt64(info.st_ino) == ledger.installation.directoryInode,
                  UInt32(info.st_uid) == ledger.installation.ownerUID else {
                throw LocalAuthorityError.storageUnavailable
            }
        } catch {
            failed = true
            epoch.invalidate()
            publishUpdate(nil)
            throw LocalAuthorityError.storageUnavailable
        }
    }

    private func publishUpdate(_ snapshot: LocalAuthoritySnapshot?) {
        for continuation in subscribers.values { continuation.yield(snapshot) }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private static func publish(_ ledger: Ledger, directoryFD: Int32) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(ledger)
        guard bytes.count <= maximumBytes else { throw LocalAuthorityError.capacityExceeded }
        try LocalAuthorityFiles.atomicReplace(directoryFD: directoryFD, name: ledgerName,
                                              bytes: bytes, limit: maximumBytes)
    }

    private static func validate(_ ledger: Ledger,
                                 installation: LocalInstallationIdentity) throws {
        guard ledger.schemaVersion == 1, ledger.installation == installation,
              ledger.grants.count <= maximumGrants,
              ledger.generations.count <= maximumGrants * 2 else {
            throw LocalAuthorityError.corruptLedger
        }
        var scopes = Set<LocalAuthorityScope>()
        for grant in ledger.grants {
            try validateScope(grant.scope, revalidateIdentity: false)
            let key = try key(grant.scope)
            guard scopes.insert(grant.scope).inserted,
                  ledger.generations[key, default: 0] == grant.generation else {
                throw LocalAuthorityError.corruptLedger
            }
        }
        guard ledger.generations.keys.allSatisfy({ $0.utf8.count <= 12_000 }) else {
            throw LocalAuthorityError.corruptLedger
        }
    }

    private static func validateScope(_ scope: LocalAuthorityScope,
                                      revalidateIdentity: Bool) throws {
        switch scope {
        case .backgroundSignals, .notifications, .launchAtLogin:
            break
        case .rescueApplication(let approval):
            guard approval.bundleURL.path.utf8.count <= 4_096,
                  approval.bundleIdentifier.utf8.count <= 255,
                  approval.hasValidStoredShape,
                  (!revalidateIdentity || approval.isCurrent()) else {
                throw LocalAuthorityError.invalidScope
            }
        case .maintenanceNotifyOnly(let grant):
            guard grant.mode == .notifyOnly else { throw LocalAuthorityError.invalidScope }
            try grant.validate()
            try validateStored(grant.root)
            if revalidateIdentity { try validateCurrent(grant.root) }
        case .maintenanceCaches(let grant):
            guard grant.mode == .authorizedCaches else { throw LocalAuthorityError.invalidScope }
            try grant.validate()
            try validateStored(grant.root)
            if revalidateIdentity { try validateCurrent(grant.root) }
        case .localRoot(let root):
            guard root.canonicalPath.hasPrefix("/"), root.canonicalPath.utf8.count <= 4_096 else {
                throw LocalAuthorityError.invalidScope
            }
            try validateStored(root)
            if revalidateIdentity { try validateCurrent(root) }
        case .externalVolume(let root):
            try validateStored(root)
            if revalidateIdentity {
                guard try LocalRootApproval.verifyExternalVolumeRoot(
                    directory: URL(fileURLWithPath: root.canonicalPath,
                                   isDirectory: true)) == root else {
                    throw LocalAuthorityError.invalidScope
                }
            }
        case .localExecutable(let executable):
            guard executable.canonicalPath.hasPrefix("/"),
                  executable.canonicalPath.utf8.count <= 4_096,
                  executable.device > 0, executable.inode > 0,
                  URL(fileURLWithPath: executable.canonicalPath)
                    .standardizedFileURL.path == executable.canonicalPath else {
                throw LocalAuthorityError.invalidScope
            }
            if revalidateIdentity {
                guard try LocalExecutableApproval.verify(
                    executable: URL(fileURLWithPath: executable.canonicalPath)) == executable else {
                    throw LocalAuthorityError.invalidScope
                }
            }
        case .localSocket(let socket):
            guard socket.canonicalPath.hasPrefix("/"),
                  socket.canonicalPath.utf8.count <= 4_096,
                  socket.device > 0, socket.inode > 0,
                  URL(fileURLWithPath: socket.canonicalPath)
                    .standardizedFileURL.path == socket.canonicalPath else {
                throw LocalAuthorityError.invalidScope
            }
            if revalidateIdentity {
                guard try LocalSocketApproval.verify(
                    socket: URL(fileURLWithPath: socket.canonicalPath)) == socket else {
                    throw LocalAuthorityError.invalidScope
                }
            }
        }
        _ = try key(scope)
    }

    private static func key(_ scope: LocalAuthorityScope) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(scope)
        guard bytes.count <= 8_192 else { throw LocalAuthorityError.invalidScope }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func validateCurrent(_ root: LocalRootApproval) throws {
        guard try LocalRootApproval.verify(
            directory: URL(fileURLWithPath: root.canonicalPath, isDirectory: true)) == root else {
            throw LocalAuthorityError.invalidScope
        }
    }

    private static func validateStored(_ root: LocalRootApproval) throws {
        guard root.canonicalPath.hasPrefix("/"), root.canonicalPath.utf8.count <= 4_096,
              root.device > 0, root.inode > 0,
              URL(fileURLWithPath: root.canonicalPath, isDirectory: true)
                .standardizedFileURL.path == root.canonicalPath else {
            throw LocalAuthorityError.invalidScope
        }
    }

    private static func isCurrent(_ scope: LocalAuthorityScope) -> Bool {
        (try? validateScope(scope, revalidateIdentity: true)) != nil
    }

    private static func increment(_ value: UInt64) throws -> UInt64 {
        let (next, overflow) = value.addingReportingOverflow(1)
        guard !overflow else { throw LocalAuthorityError.capacityExceeded }
        return next
    }
}

private enum LocalAuthorityFiles {
    private static let transactionName = ".authority-transaction"

    static func openVerifiedDirectory(_ url: URL) throws -> (Int32, String) {
        guard url.isFileURL, url.path.hasPrefix("/"), url.path.utf8.count <= 4_096,
              !url.path.utf8.contains(0) else { throw LocalAuthorityError.unsafeLocation }
        guard let resolved = realpath(url.path, nil) else { throw LocalAuthorityError.unsafeLocation }
        defer { free(resolved) }
        let canonical = String(cString: resolved)
        let fd = open(canonical, O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw LocalAuthorityError.unsafeLocation }
        do {
            let info = try statInfo(fd)
            var filesystem = statfs()
            guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
                  info.st_mode & 0o777 == 0o700, fstatfs(fd, &filesystem) == 0,
                  filesystem.f_flags & UInt32(MNT_LOCAL) != 0,
                  try extendedACLTags(fd).allSatisfy({ $0 == ACL_EXTENDED_DENY }) else {
                throw LocalAuthorityError.unsafeLocation
            }
            return (fd, canonical)
        } catch { close(fd); throw error }
    }

    static func statInfo(_ fd: Int32) throws -> stat {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw LocalAuthorityError.storageUnavailable }
        return info
    }

    static func openOrCreatePrivateFile(directoryFD: Int32, name: String) throws -> Int32 {
        var fd = openat(directoryFD, name, O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0, errno == ENOENT {
            fd = openat(directoryFD, name,
                O_RDWR | O_CREAT | O_EXCL | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw LocalAuthorityError.storageUnavailable }
            guard fchmod(fd, 0o600) == 0 else { close(fd); throw LocalAuthorityError.storageUnavailable }
            try clearExtendedACL(fd)
            guard fsync(directoryFD) == 0 else { close(fd); throw LocalAuthorityError.storageUnavailable }
        }
        guard fd >= 0 else { throw LocalAuthorityError.storageUnavailable }
        do { try validatePrivateFile(fd, directoryFD: directoryFD, name: name) }
        catch { close(fd); throw error }
        return fd
    }

    static func readPrivateFile(directoryFD: Int32, name: String, limit: Int) throws -> Data? {
        let fd = openat(directoryFD, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw LocalAuthorityError.storageUnavailable
        }
        defer { close(fd) }
        try validatePrivateFile(fd, directoryFD: directoryFD, name: name)
        let info = try statInfo(fd)
        guard info.st_size >= 0, info.st_size <= limit else {
            throw LocalAuthorityError.capacityExceeded
        }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let room = min(buffer.count, limit + 1 - result.count)
            let count = Darwin.read(fd, &buffer, room)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw LocalAuthorityError.storageUnavailable }
            if count == 0 { break }
            guard result.count + count <= limit else { throw LocalAuthorityError.capacityExceeded }
            result.append(contentsOf: buffer.prefix(count))
        }
        try validatePrivateFile(fd, directoryFD: directoryFD, name: name)
        return result
    }

    static func atomicReplace(directoryFD: Int32, name: String, bytes: Data,
                              limit: Int) throws {
        guard bytes.count <= limit else { throw LocalAuthorityError.capacityExceeded }
        let transactionFD = openat(directoryFD, transactionName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard transactionFD >= 0 else { throw LocalAuthorityError.storageUnavailable }
        defer { close(transactionFD) }
        guard fchmod(transactionFD, 0o600) == 0 else {
            throw LocalAuthorityError.storageUnavailable
        }
        try clearExtendedACL(transactionFD)
        try validatePrivateFile(transactionFD, directoryFD: directoryFD,
                                name: transactionName)
        guard fsync(transactionFD) == 0, fsync(directoryFD) == 0 else {
            throw LocalAuthorityError.storageUnavailable
        }
        let temporary = ".authority-pending-" + UUID().uuidString
        let fd = openat(directoryFD, temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw LocalAuthorityError.storageUnavailable }
        var published = false
        defer {
            close(fd)
            if !published { _ = unlinkat(directoryFD, temporary, 0) }
        }
        guard fchmod(fd, 0o600) == 0 else { throw LocalAuthorityError.storageUnavailable }
        try clearExtendedACL(fd)
        try validatePrivateFile(fd, directoryFD: directoryFD, name: temporary)
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw LocalAuthorityError.storageUnavailable }
                offset += count
            }
        }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0 else {
            throw LocalAuthorityError.storageUnavailable
        }
        try validatePrivateFile(fd, directoryFD: directoryFD, name: temporary)
        guard renameat(directoryFD, temporary, directoryFD, name) == 0 else {
            throw LocalAuthorityError.storageUnavailable
        }
        published = true
        try validatePrivateFile(fd, directoryFD: directoryFD, name: name)
        guard fsync(directoryFD) == 0,
              unlinkat(directoryFD, transactionName, 0) == 0,
              fsync(directoryFD) == 0 else { throw LocalAuthorityError.storageUnavailable }
    }

    static func requireNoUnfinishedTransaction(directoryFD: Int32) throws {
        var info = stat()
        if fstatat(directoryFD, transactionName, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            throw LocalAuthorityError.storageUnavailable
        }
        guard errno == ENOENT else { throw LocalAuthorityError.storageUnavailable }
    }

    private static func validatePrivateFile(_ fd: Int32, directoryFD: Int32,
                                            name: String) throws {
        let info = try statInfo(fd)
        var named = stat(), filesystem = statfs()
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
              info.st_mode & 0o777 == 0o600, info.st_nlink == 1,
              fstatfs(fd, &filesystem) == 0,
              filesystem.f_flags & UInt32(MNT_LOCAL) != 0,
              fstatat(directoryFD, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_dev == info.st_dev, named.st_ino == info.st_ino,
              try extendedACLTags(fd).isEmpty else {
            throw LocalAuthorityError.unsafeLocation
        }
    }

    private static func clearExtendedACL(_ fd: Int32) throws {
        guard let acl = acl_init(0) else { throw LocalAuthorityError.storageUnavailable }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0,
              acl_set_fd_np(fd, acl, ACL_TYPE_EXTENDED) == 0,
              try extendedACLTags(fd).isEmpty else {
            throw LocalAuthorityError.storageUnavailable
        }
    }

    private static func extendedACLTags(_ fd: Int32) throws -> [acl_tag_t] {
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT {
                let info = try statInfo(fd)
                guard info.st_nlink > 0 else { throw LocalAuthorityError.unsafeLocation }
                return []
            }
            throw LocalAuthorityError.storageUnavailable
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw LocalAuthorityError.storageUnavailable }
        var result: [acl_tag_t] = [], selector = ACL_FIRST_ENTRY
        while true {
            var entry: acl_entry_t?
            errno = 0
            let status = acl_get_entry(acl, Int32(selector.rawValue), &entry)
            if status == -1, errno == EINVAL { break }
            guard status == 0, let entry, result.count < Int(ACL_MAX_ENTRIES) else {
                throw LocalAuthorityError.storageUnavailable
            }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0 else {
                throw LocalAuthorityError.storageUnavailable
            }
            result.append(tag)
            selector = ACL_NEXT_ENTRY
        }
        return result
    }
}
