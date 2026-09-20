import CryptoKit
import Darwin
import Dispatch
import Foundation
import Observation
import TidyCore

@Observable @MainActor
final class AssistanceModel {
    typealias NotificationBrokerFactory = @MainActor (
        URL, @escaping @MainActor (AssistanceNavigation) -> Void
    ) -> NotificationBroker?

    @ObservationIgnored private weak var services: AppExecutionServices?
    @ObservationIgnored private let notificationBrokerFactory: NotificationBrokerFactory?
    private(set) var authority: LocalAuthorityStore?
    private(set) var authoritySnapshot: LocalAuthoritySnapshot?
    private(set) var notificationBroker: NotificationBroker?
    private(set) var latestSystemSnapshot: SystemSnapshot?
    private(set) var budgetInventory: [UUID: [BudgetMeasurement]] = [:]
    private(set) var budgetVolumeID: UUID?
    private(set) var requestedNavigation: AssistanceNavigation?
    private(set) var errorMessage: String?

    @ObservationIgnored private let sceneLease: MonitorSceneLeaseController
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var signalTask: Task<Void, Never>?
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var authorityGeneration: UInt64 = 0
    @ObservationIgnored private var pressureState = PressureNotificationState()
    @ObservationIgnored private var budgetEvaluations: [UUID: BudgetEvaluation] = [:]

    init(services: AppExecutionServices,
         notificationBrokerFactory: NotificationBrokerFactory? = {
             stateURL, onNavigate in
             NotificationBroker(stateURL: stateURL, onNavigate: onNavigate)
         }) {
        self.services = services
        self.notificationBrokerFactory = notificationBrokerFactory
        sceneLease = MonitorSceneLeaseController(monitor: services.systemMonitor)
        bootstrapTask = Task { @MainActor [weak self, weak services] in
            guard let services else { return }
            await self?.applyAuthority(nil, services: services)
            do {
                let base = services.paths.settings.deletingLastPathComponent()
                let directory = try AssistancePrivateDirectory.prepare(
                    parent: base, name: "authority")
                let installation = try LocalInstallationIdentity.verify(directory: directory)
                let store = try LocalAuthorityStore(directory: directory,
                                                    installation: installation)
                self?.authority = store
                let updates = await store.updates()
                for await snapshot in updates {
                    guard !Task.isCancelled, let self,
                          let services = self.services else { break }
                    await self.applyAuthority(snapshot, services: services)
                }
            } catch {
                self?.authority = nil
                self?.errorMessage = "Local authority is unavailable; consent remains denied: \(String(describing: error))"
            }
        }
    }

    deinit {
        bootstrapTask?.cancel()
        signalTask?.cancel()
        sceneLease.dispose()
    }

    var effectivePolicy: EffectivePolicy? {
        services?.configStore.acknowledgedEffectivePolicy
    }

    var policyRevision: UInt64 {
        services?.configStore.acknowledgedSettingsRevision ?? 0
    }

    var availableMemoryBytes: Int64? {
        guard let memory = latestSystemSnapshot?.memory,
              let used = memory.usedBytes, used >= 0,
              memory.totalBytes >= used else { return nil }
        return memory.totalBytes - used
    }

    var budgetMeasurements: [BudgetMeasurement] {
        guard let budgetVolumeID else { return [] }
        return budgetInventory[budgetVolumeID] ?? []
    }

    var budgetVolumeIDs: [UUID] {
        budgetInventory.keys.sorted { $0.uuidString < $1.uuidString }
    }

    func setVisible(_ isVisible: Bool) {
        visible = isVisible
        sceneLease.setVisible(isVisible, requestSnapshot: isVisible)
        reconcileSignalSubscription()
    }

    /// Called only from the visible assistance UI. Construction reads a
    /// bounded private state file and installs a delegate; it never requests
    /// notification permission.
    func prepareNotificationControls() {
        initializeNotificationBroker(reportErrors: true)
    }

    private func initializeNotificationBroker(reportErrors: Bool) {
        guard notificationBroker == nil, let services,
              let notificationBrokerFactory else {
            if reportErrors, notificationBroker == nil {
                errorMessage = "Notification controls are unavailable in this host."
            }
            return
        }
        do {
            let base = services.paths.settings.deletingLastPathComponent()
            let directory = try AssistancePrivateDirectory.prepare(
                parent: base, name: "assistance")
            let stateURL = directory.appendingPathComponent(
                "notification-dedup-v1.json", isDirectory: false)
            notificationBroker = notificationBrokerFactory(stateURL) {
                [weak self] navigation in self?.requestedNavigation = navigation
            }
            guard notificationBroker != nil else {
                if reportErrors {
                    errorMessage = "Notification controls are unavailable in this host."
                }
                return
            }
            reconcileSignalSubscription()
            considerBudgetNotifications()
        } catch {
            if reportErrors {
                errorMessage = "Notification state is unavailable; delivery remains disabled: \(String(describing: error))"
            }
        }
    }

    func consumeNavigation() { requestedNavigation = nil }

    func acceptAuthoritySnapshot(_ snapshot: LocalAuthoritySnapshot) {
        // The store stream is authoritative. This immediate presentation
        // update avoids UI lag while the same snapshot is queued there.
        guard snapshot.isCurrent else { return }
        authoritySnapshot = snapshot
    }

    /// Inventory adapters may feed only known, already measured allocations.
    /// This method performs no discovery and starts no work.
    func installBudgetMeasurements(_ measurements: [BudgetMeasurement],
                                   volumeID: UUID) {
        installBudgetInventory([volumeID: measurements])
        selectBudgetVolume(volumeID)
    }

    func installBudgetInventory(_ byVolume: [UUID: [BudgetMeasurement]]) {
        let maximumVolumes = 64
        let maximumPerVolume = BudgetID.allCases.count * 2
        let valid = byVolume.count <= maximumVolumes && byVolume.allSatisfy { volume, values in
            values.count <= maximumPerVolume
                && values.allSatisfy { $0.volumeID == volume }
        }
        guard valid else {
            clearBudgetMeasurements()
            errorMessage = "Budget inventory was rejected because its volume binding or count was invalid."
            return
        }
        budgetInventory = byVolume
        budgetEvaluations = budgetEvaluations.filter { byVolume[$0.key] != nil }
        if let selected = budgetVolumeID, byVolume[selected] != nil {
            budgetVolumeID = selected
        } else {
            budgetVolumeID = budgetVolumeIDs.first
        }
        considerBudgetNotifications()
    }

    func selectBudgetVolume(_ volumeID: UUID) {
        guard budgetInventory[volumeID] != nil else { return }
        budgetVolumeID = volumeID
    }

    func clearBudgetMeasurements() {
        budgetInventory = [:]
        budgetVolumeID = nil
        budgetEvaluations = [:]
    }

    private func applyAuthority(_ snapshot: LocalAuthoritySnapshot?,
                                services: AppExecutionServices) async {
        let (next, overflow) = authorityGeneration.addingReportingOverflow(1)
        guard !overflow else {
            authoritySnapshot = nil
            services.configStore.installLocalAuthority(nil)
            errorMessage = "Local authority generation overflowed; consent remains denied."
            return
        }
        authorityGeneration = next
        _ = await services.systemMonitor.applyLocalAuthority(snapshot,
                                                             generation: next)
        services.configStore.installLocalAuthority(snapshot)
        authoritySnapshot = snapshot?.isCurrent == true ? snapshot : nil
        if authoritySnapshot?.permits(.notifications) == true {
            // Restored consent may resume delivery, but broker construction
            // still never requests OS permission.
            initializeNotificationBroker(reportErrors: false)
        }
        reconcileSignalSubscription()
    }

    private func reconcileSignalSubscription() {
        let keepHidden = notificationBroker != nil
            && authoritySnapshot?.permits(.backgroundSignals) == true
            && authoritySnapshot?.permits(.notifications) == true
        if visible || keepHidden {
            startSignalSubscriptionIfNeeded()
        } else {
            signalTask?.cancel()
            signalTask = nil
        }
    }

    private func startSignalSubscriptionIfNeeded() {
        guard signalTask == nil, let monitor = services?.systemMonitor else { return }
        signalTask = Task { @MainActor [weak self] in
            let stream = await monitor.subscribe()
            for await snapshot in stream {
                guard let self, !Task.isCancelled else { break }
                latestSystemSnapshot = snapshot
                if budgetInventory.isEmpty {
                    budgetVolumeID = snapshot.volumes.first.flatMap {
                        UUID(uuidString: $0.volumeIdentity)
                    }
                }
                await considerPressureNotification(snapshot)
            }
        }
    }

    private func considerPressureNotification(_ snapshot: SystemSnapshot) async {
        guard let broker = notificationBroker, let policy = effectivePolicy,
              let authoritySnapshot else { return }
        if !visible && !authoritySnapshot.permits(.backgroundSignals) { return }
        let configuration = NotificationConfiguration.resolve(
            policy: policy, authority: authoritySnapshot)
        let condition: PressureNotificationCondition
        switch snapshot.memoryPressureLevel {
        case .warning, .critical: condition = .warning
        case .normal: condition = .normal
        case nil: condition = .unknown
        }
        let bootID = Self.notificationBootID(snapshot.bootIdentity)
        let eligible = pressureState.observe(condition, configuration: configuration,
            bootID: bootID, nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
        guard eligible else { return }
        do {
            try await broker.deliver(event: .pressure, navigation: .headroomReview,
                eligible: true, configuration: configuration, bootID: bootID,
                nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
                nowWallDate: snapshot.observedAt, title: "Memory pressure",
                body: "Memory pressure remains elevated. Open Tidy to review current headroom.")
        } catch NotificationBrokerError.suppressed(_) {
            // Quiet hours, cooldown, and revoked authority are expected denials.
        } catch NotificationBrokerError.permissionDenied {
            // Permission state is shown in the visible Budgets view.
        } catch {
            errorMessage = "Notification delivery failed: \(String(describing: error))"
        }
    }

    private func considerBudgetNotifications() {
        guard let broker = notificationBroker, let policy = effectivePolicy,
              let authoritySnapshot else { return }
        if !visible && !authoritySnapshot.permits(.backgroundSignals) { return }
        var newlyAlerting: [(BudgetID, UUID)] = []
        for volumeID in budgetInventory.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let prior = budgetEvaluations[volumeID]
            let next = BudgetEvaluator.evaluate(policy: policy, volumeID: volumeID,
                measurements: budgetInventory[volumeID] ?? [], previous: prior)
            budgetEvaluations[volumeID] = next
            for id in BudgetID.allCases where next.statuses[id]?.state == .alerting
                && prior?.statuses[id]?.alertLatched != true {
                newlyAlerting.append((id, volumeID))
            }
        }
        guard !newlyAlerting.isEmpty else { return }
        let configuration = NotificationConfiguration.resolve(
            policy: policy, authority: authoritySnapshot)
        let bootID = Self.notificationBootID(latestSystemSnapshot?.bootIdentity)
        Task { @MainActor [weak self] in
            guard let self else { return }
            for (id, volumeID) in newlyAlerting {
                do {
                    try await broker.deliver(event: .budget(id, volumeID: volumeID),
                        navigation: .budgetReview(id, volumeID: volumeID),
                        eligible: true, configuration: configuration, bootID: bootID,
                        nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
                        title: "Storage budget reached",
                        body: "\(id.rawValue) reached its configured budget. Open Tidy to review inventory.")
                } catch NotificationBrokerError.suppressed(_) {
                } catch NotificationBrokerError.permissionDenied {
                } catch {
                    errorMessage = "Budget notification failed: \(String(describing: error))"
                }
            }
        }
    }

    private static func notificationBootID(_ identity: BootIdentity?) -> UUID {
        let material = Data("tidy-boot:\(identity?.bootTime.bitPattern ?? 0)".utf8)
        var bytes = Array(SHA256.hash(data: material).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let tuple: uuid_t = (bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: tuple)
    }
}

private enum AssistancePrivateDirectory {
    static func prepare(parent: URL, name: String) throws -> URL {
        guard parent.isFileURL, parent.path.hasPrefix("/"),
              !parent.path.utf8.contains(0), ["authority", "assistance"].contains(name),
              let resolved = realpath(parent.path, nil) else {
            throw LocalAuthorityError.unsafeLocation
        }
        defer { free(resolved) }
        let parentPath = String(cString: resolved)
        let parentFD = open(parentPath,
            O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { throw LocalAuthorityError.unsafeLocation }
        defer { close(parentFD) }
        try validateParent(parentFD)

        var directoryFD = openat(parentFD, name,
            O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if directoryFD < 0, errno == ENOENT {
            guard mkdirat(parentFD, name, 0o700) == 0 else {
                throw LocalAuthorityError.storageUnavailable
            }
            directoryFD = openat(parentFD, name,
                O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directoryFD >= 0, fchmod(directoryFD, 0o700) == 0 else {
                if directoryFD >= 0 { close(directoryFD) }
                throw LocalAuthorityError.storageUnavailable
            }
            try clearExtendedACL(directoryFD)
            guard fsync(parentFD) == 0 else {
                close(directoryFD)
                throw LocalAuthorityError.storageUnavailable
            }
        }
        guard directoryFD >= 0 else { throw LocalAuthorityError.unsafeLocation }
        defer { close(directoryFD) }
        try validatePrivateDirectory(directoryFD)
        return URL(fileURLWithPath: parentPath, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private static func validateParent(_ fd: Int32) throws {
        var info = stat(), filesystem = statfs()
        guard fstat(fd, &info) == 0, fstatfs(fd, &filesystem) == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
              info.st_mode & 0o022 == 0,
              filesystem.f_flags & UInt32(MNT_LOCAL) != 0,
              try extendedACLTags(fd).allSatisfy({ $0 == ACL_EXTENDED_DENY }) else {
            throw LocalAuthorityError.unsafeLocation
        }
    }

    private static func validatePrivateDirectory(_ fd: Int32) throws {
        var info = stat(), filesystem = statfs()
        guard fstat(fd, &info) == 0, fstatfs(fd, &filesystem) == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
              info.st_mode & 0o777 == 0o700,
              filesystem.f_flags & UInt32(MNT_LOCAL) != 0,
              try extendedACLTags(fd).allSatisfy({ $0 == ACL_EXTENDED_DENY }) else {
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
                var info = stat()
                guard fstat(fd, &info) == 0, info.st_nlink > 0 else {
                    throw LocalAuthorityError.unsafeLocation
                }
                return []
            }
            throw LocalAuthorityError.unsafeLocation
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw LocalAuthorityError.unsafeLocation }
        var result: [acl_tag_t] = [], selector = ACL_FIRST_ENTRY
        while true {
            var entry: acl_entry_t?
            errno = 0
            let status = acl_get_entry(acl, Int32(selector.rawValue), &entry)
            if status == -1, errno == EINVAL { break }
            guard status == 0, let entry, result.count < Int(ACL_MAX_ENTRIES) else {
                throw LocalAuthorityError.unsafeLocation
            }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0 else {
                throw LocalAuthorityError.unsafeLocation
            }
            result.append(tag)
            selector = ACL_NEXT_ENTRY
        }
        return result
    }
}
