import Darwin
import Foundation
import TidyCore
import UserNotifications

enum NotificationBrokerError: Error {
    case unsafeStateStorage
    case stateUnavailable
    case permissionDenied
    case suppressed(NotificationSuppression)
}

@MainActor
final class NotificationBroker: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private let storage: NotificationStateStorage
    private let onNavigate: @MainActor (AssistanceNavigation) -> Void
    private var state: NotificationDedupState
    private var stateAvailable: Bool

    init(center: UNUserNotificationCenter = .current(), stateURL: URL,
         onNavigate: @escaping @MainActor (AssistanceNavigation) -> Void) {
        self.center = center
        storage = NotificationStateStorage(url: stateURL)
        self.onNavigate = onNavigate
        if let loaded = try? storage.load() {
            state = loaded
            stateAvailable = true
        } else {
            state = NotificationDedupState()
            stateAvailable = !FileManager.default.fileExists(atPath: stateURL.path)
        }
        super.init()
        center.delegate = self
    }

    /// This is the only authorization-request entry point. Call it directly
    /// from an explicit user button; delivery and refresh never invoke it.
    func requestAuthorizationFromExplicitUserAction() async -> NotificationPermission {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return .denied
        }
        return await permission()
    }

    func permission() async -> NotificationPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func deliver(event: AssistanceNotificationEvent,
                 navigation: AssistanceNavigation,
                 eligible: Bool,
                 configuration: NotificationConfiguration,
                 bootID: UUID,
                 nowMonotonicNanoseconds: UInt64,
                 nowWallDate: Date = Date(),
                 calendar: Calendar = .current,
                 title: String,
                 body: String) async throws {
        guard stateAvailable else { throw NotificationBrokerError.stateUnavailable }
        let livePermission = await permission()
        guard livePermission == .authorized else { throw NotificationBrokerError.permissionDenied }
        guard configuration.enabled else {
            throw NotificationBrokerError.suppressed(.disabled)
        }
        var candidate = state
        let decision = candidate.decide(event: event, navigation: navigation,
            eligible: eligible, configuration: configuration,
            permission: livePermission, bootID: bootID,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds,
            nowWallDate: nowWallDate, calendar: calendar)
        guard case .deliver = decision else {
            if case .suppress(let reason) = decision {
                throw NotificationBrokerError.suppressed(reason)
            }
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["tidy-navigation": Self.encode(navigation)]
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        do {
            try storage.save(candidate)
            state = candidate
        } catch {
            stateAvailable = false
            throw NotificationBrokerError.stateUnavailable
        }
        guard configuration.enabled else {
            throw NotificationBrokerError.suppressed(.disabled)
        }
        try await center.add(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["tidy-navigation"] as? String
        if let raw, let navigation = Self.decode(raw) {
            Task { @MainActor [weak self] in self?.onNavigate(navigation) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private nonisolated static func encode(_ navigation: AssistanceNavigation) -> String {
        switch navigation {
        case .headroomReview: return "headroom"
        case .budgetReview(let id, let volumeID):
            return "budget|\(id.rawValue)|\(volumeID.uuidString)"
        }
    }

    private nonisolated static func decode(_ raw: String) -> AssistanceNavigation? {
        if raw == "headroom" { return .headroomReview }
        let fields = raw.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0] == "budget",
              let id = BudgetID(rawValue: String(fields[1])),
              let volume = UUID(uuidString: String(fields[2])) else { return nil }
        return .budgetReview(id, volumeID: volume)
    }
}

private struct NotificationStateStorage {
    private static let limit = 32 * 1_024
    let url: URL

    func load() throws -> NotificationDedupState {
        guard let (directory, name) = try openParent() else {
            return NotificationDedupState()
        }
        defer { close(directory) }
        let fd = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return NotificationDedupState() }
            throw NotificationBrokerError.stateUnavailable
        }
        defer { close(fd) }
        try validate(fd: fd, directory: directory, name: name)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= 0, info.st_size <= Self.limit else {
            throw NotificationBrokerError.stateUnavailable
        }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = Darwin.read(fd, &buffer,
                min(buffer.count, Self.limit + 1 - bytes.count))
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw NotificationBrokerError.stateUnavailable }
            if count == 0 { break }
            guard bytes.count + count <= Self.limit else {
                throw NotificationBrokerError.stateUnavailable
            }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        try validate(fd: fd, directory: directory, name: name)
        return try NotificationDedupState.decode(bytes)
    }

    func save(_ state: NotificationDedupState) throws {
        let bytes = try state.encoded()
        guard bytes.count <= Self.limit, let (directory, name) = try openParent() else {
            throw NotificationBrokerError.stateUnavailable
        }
        defer { close(directory) }
        let temporary = ".notification-state-" + UUID().uuidString
        let fd = openat(directory, temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw NotificationBrokerError.stateUnavailable }
        var published = false
        defer {
            close(fd)
            if !published { _ = unlinkat(directory, temporary, 0) }
        }
        guard fchmod(fd, 0o600) == 0 else { throw NotificationBrokerError.stateUnavailable }
        try clearExtendedACL(fd)
        try validate(fd: fd, directory: directory, name: temporary)
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw NotificationBrokerError.stateUnavailable }
                offset += count
            }
        }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0,
              renameat(directory, temporary, directory, name) == 0 else {
            throw NotificationBrokerError.stateUnavailable
        }
        published = true
        try validate(fd: fd, directory: directory, name: name)
        guard fsync(directory) == 0 else { throw NotificationBrokerError.stateUnavailable }
    }

    private func openParent() throws -> (Int32, String)? {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.utf8.contains(0),
              url.lastPathComponent == "notification-dedup-v1.json" else {
            throw NotificationBrokerError.unsafeStateStorage
        }
        let parent = url.deletingLastPathComponent().standardizedFileURL
        let fd = open(parent.path,
            O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw NotificationBrokerError.unsafeStateStorage
        }
        var info = stat(), filesystem = statfs()
        guard fstat(fd, &info) == 0, fstatfs(fd, &filesystem) == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0,
              filesystem.f_flags & UInt32(MNT_LOCAL) != 0,
              try extendedACLTags(fd).allSatisfy({ $0 == ACL_EXTENDED_DENY }) else {
            close(fd)
            throw NotificationBrokerError.unsafeStateStorage
        }
        return (fd, url.lastPathComponent)
    }

    private func validate(fd: Int32, directory: Int32, name: String) throws {
        var opened = stat(), named = stat(), filesystem = statfs()
        guard fstat(fd, &opened) == 0, fstatfs(fd, &filesystem) == 0,
              opened.st_mode & S_IFMT == S_IFREG, opened.st_uid == geteuid(),
              opened.st_mode & 0o777 == 0o600, opened.st_nlink == 1,
              filesystem.f_flags & UInt32(MNT_LOCAL) != 0,
              fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_dev == opened.st_dev, named.st_ino == opened.st_ino,
              try extendedACLTags(fd).isEmpty else {
            throw NotificationBrokerError.unsafeStateStorage
        }
    }

    private func clearExtendedACL(_ fd: Int32) throws {
        guard let acl = acl_init(0) else { throw NotificationBrokerError.stateUnavailable }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0,
              acl_set_fd_np(fd, acl, ACL_TYPE_EXTENDED) == 0,
              try extendedACLTags(fd).isEmpty else {
            throw NotificationBrokerError.stateUnavailable
        }
    }

    private func extendedACLTags(_ fd: Int32) throws -> [acl_tag_t] {
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT {
                var info = stat()
                guard fstat(fd, &info) == 0, info.st_nlink > 0 else {
                    throw NotificationBrokerError.unsafeStateStorage
                }
                return []
            }
            throw NotificationBrokerError.unsafeStateStorage
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw NotificationBrokerError.unsafeStateStorage }
        var result: [acl_tag_t] = [], selector = ACL_FIRST_ENTRY
        while true {
            var entry: acl_entry_t?
            errno = 0
            let status = acl_get_entry(acl, Int32(selector.rawValue), &entry)
            if status == -1, errno == EINVAL { break }
            guard status == 0, let entry, result.count < Int(ACL_MAX_ENTRIES) else {
                throw NotificationBrokerError.unsafeStateStorage
            }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0 else {
                throw NotificationBrokerError.unsafeStateStorage
            }
            result.append(tag)
            selector = ACL_NEXT_ENTRY
        }
        return result
    }
}
