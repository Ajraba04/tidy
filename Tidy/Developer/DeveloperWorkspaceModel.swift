import AppKit
import Darwin
import Foundation
import Observation
import TidyCore

struct DeveloperWorkspaceSnapshot: Sendable {
    let inventory: DeveloperInventorySnapshot
    let buildPrep: CandidateRanking
    let headroomPlan: HeadroomPlan?
    let headroomUnavailableReason: String?
    let measurement: SystemSnapshot
    let policyRevision: UInt64
}

@Observable @MainActor
final class DeveloperWorkspaceModel {
    private(set) var snapshot: DeveloperWorkspaceSnapshot?
    private(set) var error: String?
    private(set) var projectActionMessage: String?
    private(set) var isScanning = false
    @ObservationIgnored var onInventoryChange:
        (@MainActor (DeveloperInventorySnapshot?) -> Void)?

    @ObservationIgnored private weak var services: AppExecutionServices?
    @ObservationIgnored private let ownerID = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var session: WorkSession?
    @ObservationIgnored private var deselectedBuildPrepIDs: Set<String> = []

    init(services: AppExecutionServices) {
        self.services = services
    }

    func scan(localAuthority: LocalAuthoritySnapshot?) {
        guard task == nil, let services else { return }
        error = nil
        isScanning = true
        task = Task { @MainActor [weak self, weak services] in
            guard let self, let services else { return }
            await self.performScan(services: services, localAuthority: localAuthority)
        }
    }

    func cancel() {
        task?.cancel()
        if let services, let session {
            Task { await services.explicitSessions.cancel(session: session) }
        }
    }

    func invalidate() {
        cancel()
        snapshot = nil
        error = nil
        deselectedBuildPrepIDs = []
        onInventoryChange?(nil)
    }

    func removeFromBuildPrep(_ id: String) {
        guard let snapshot, let plan = snapshot.headroomPlan else { return }
        deselectedBuildPrepIDs.insert(id)
        self.snapshot = DeveloperWorkspaceSnapshot(inventory: snapshot.inventory,
            buildPrep: snapshot.buildPrep,
            headroomPlan: HeadroomPlanner.removingSelection([id], from: plan),
            headroomUnavailableReason: snapshot.headroomUnavailableReason,
            measurement: snapshot.measurement,
            policyRevision: snapshot.policyRevision)
    }

    var projectControlsEnabled: Bool {
        services?.configStore.acknowledgedEffectivePolicy?
            .allowedFeatures.contains("projects") == true
    }

    var projectSettingsWritePending: Bool {
        services?.configStore.hasPendingSettingsWrites == true
    }

    var canEditProjectSettings: Bool {
        projectControlsEnabled && !projectSettingsWritePending
    }

    var globalPinnedProjectIDs: Set<String> {
        guard let store = services?.configStore else { return [] }
        return Self.storedStrings(store.preferences.global, Self.pinnedProjectsID)
    }

    var profilePinnedProjectIDs: Set<String> {
        guard let store = services?.configStore,
              let active = store.activeProfileID,
              let profile = store.preferences.profiles.first(where: { $0.id == active })
        else { return [] }
        return Self.storedStrings(profile.values, Self.pinnedProjectsID)
    }

    var profileOnlyPinnedProjectIDs: Set<String> {
        profilePinnedProjectIDs.subtracting(globalPinnedProjectIDs)
    }

    var globalCurrentProjectID: String? {
        guard let store = services?.configStore else { return nil }
        return Self.storedChoice(store.preferences.global, Self.currentProjectID)
    }

    var effectiveCurrentProjectID: String? {
        guard let policy = services?.configStore.effectivePolicy else { return nil }
        return Self.choice(policy, Self.currentProjectID.rawValue)
    }

    var activeProfileCurrentProjectID: String? {
        guard let store = services?.configStore,
              let active = store.activeProfileID,
              let profile = store.preferences.profiles.first(where: { $0.id == active })
        else { return nil }
        return Self.storedChoice(profile.values, Self.currentProjectID)
    }

    var activeProfileOverridesCurrentProject: Bool {
        guard let store = services?.configStore,
              let active = store.activeProfileID,
              let profile = store.preferences.profiles.first(where: { $0.id == active })
        else { return false }
        return profile.values.fields[Self.currentProjectID] != nil
    }

    func projectDisplayName(_ id: String) -> String {
        guard let path = snapshot?.inventory.projects.records
            .first(where: { $0.id == id })?.canonicalRoot else { return id }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    func isGloballyPinned(_ id: String) -> Bool {
        globalPinnedProjectIDs.contains(id)
    }

    func isProfilePinned(_ id: String) -> Bool {
        profilePinnedProjectIDs.contains(id)
    }

    func pinGlobally(_ id: String) {
        guard snapshot?.inventory.projects.records.contains(where: { $0.id == id }) == true else {
            projectActionMessage = "Refresh Inventory before pinning a project."
            return
        }
        var pins = globalPinnedProjectIDs
        pins.insert(id)
        submitProjectSetting(Self.pinnedProjectsID, value: .strings(pins.sorted()),
            savedMessage: "Global project pin saved.")
    }

    func unpinGlobally(_ id: String) {
        var pins = globalPinnedProjectIDs
        guard pins.remove(id) != nil else {
            projectActionMessage = isProfilePinned(id)
                ? "This project is pinned by the active profile."
                : "This project has no global pin."
            return
        }
        submitProjectSetting(Self.pinnedProjectsID, value: .strings(pins.sorted()),
            savedMessage: isProfilePinned(id)
                ? "Global pin removed; the active profile still protects this project."
                : "Global project pin removed.")
    }

    func setGlobalCurrentProject(_ id: String) {
        guard snapshot?.inventory.projects.records.contains(where: { $0.id == id }) == true else {
            projectActionMessage = "Refresh Inventory before selecting a current project."
            return
        }
        submitProjectSetting(Self.currentProjectID, value: .choice(id),
            savedMessage: "Global current project saved.")
    }

    func clearGlobalCurrentProject() {
        guard globalCurrentProjectID != nil else {
            projectActionMessage = "No global current project is selected."
            return
        }
        submitProjectSetting(Self.currentProjectID, value: .null,
            savedMessage: activeProfileCurrentProjectID == nil
                ? "Global current project cleared."
                : "Global current project cleared; the active profile still selects a current project.")
    }

    func revealProject(_ id: String) {
        guard let project = snapshot?.inventory.projects.records.first(where: { $0.id == id }) else {
            projectActionMessage = "That project is no longer in the current inventory."
            return
        }
        reveal(project.rootIdentity)
    }

    func revealInventoryEntry(_ id: String) {
        guard let record = snapshot?.inventory.entries
            .first(where: { $0.record.id == id })?.record else {
            projectActionMessage = "That resource is no longer in the current inventory."
            return
        }
        guard case .filesystem(let identity) = record.resource else {
            projectActionMessage = "This resource has no local filesystem location to reveal."
            return
        }
        reveal(identity)
    }

    private func performScan(services: AppExecutionServices,
                             localAuthority: LocalAuthoritySnapshot?) async {
        var openedSession: WorkSession?
        let monitorLease = MonitorLease()
        var monitorLeaseAcquired = false
        do {
            await services.explicitSessions.awaitInitialInstall()
            let scope = try services.authorizeProjectScope(ownerID: ownerID,
                localAuthority: localAuthority)
            guard let environment = services.configStore.acknowledgedPolicyEnvironment(
                homeDirectory: services.paths.home.path) else {
                throw ScanAvailabilityError.policyNotInstalled
            }
            let session = try await services.explicitSessions.beginSession(
                requirements: try SchedulerRequirements(features: [.projects]))
            openedSession = session
            self.session = session
            await services.systemMonitor.acquireExplicitWorkLease(monitorLease)
            monitorLeaseAcquired = true
            let measurement = await services.systemMonitor.requestSnapshot()
            let request = Self.inventoryRequest(localAuthority)
            let scanOwnerID = ownerID
            let pins = Self.strings(scope.policy, "scope.pinnedProjects")
            let current = Self.choice(scope.policy, "scope.currentProject")
            let inventory = try await services.explicitSessions.withPermit(
                session: session) { probe in
                    try await DeveloperInventoryService.scan(scope: scope,
                        ownerID: scanOwnerID, environment: environment,
                        pinnedProjectIDs: pins, currentProjectID: current,
                        request: request,
                        checkpoint: { try await probe.checkCancellation() })
                }
            try Task.checkCancellation()
            guard services.configStore.acknowledgedSettingsRevision == scope.policyRevision,
                  localAuthority?.isCurrent != false else {
                throw CancellationError()
            }
            let candidates = inventory.entries.map(Self.candidate)
            let ranking = try CandidateRanker.rank(candidates, policy: scope.policy,
                pinnedOwnerIDs: pins, currentOwnerID: current)
            let disk = measurement.volumes.first?.disk
            let measuredPolicy = services.configStore.acknowledgedPolicyForVolume(
                identity: disk?.volumeIdentifier, capacityBytes: disk?.totalBytes) ?? scope.policy
            let planning = try Self.headroomPlan(ranking: ranking, policy: measuredPolicy,
                policyRevision: scope.policyRevision, measurement: measurement,
                deselectedIDs: deselectedBuildPrepIDs)
            snapshot = DeveloperWorkspaceSnapshot(inventory: inventory,
                buildPrep: ranking, headroomPlan: planning.plan,
                headroomUnavailableReason: planning.unavailableReason,
                measurement: measurement, policyRevision: scope.policyRevision)
            onInventoryChange?(inventory)
            error = nil
        } catch is CancellationError {
            error = "Inventory scan cancelled."
        } catch {
            self.error = "Developer inventory is unavailable: \(error.localizedDescription)"
        }
        if let openedSession {
            await services.explicitSessions.finish(session: openedSession)
        }
        if monitorLeaseAcquired {
            await services.systemMonitor.releaseExplicitWorkLease(monitorLease)
        }
        session = nil
        task = nil
        isScanning = false
    }

    private static func inventoryRequest(_ authority: LocalAuthoritySnapshot?)
        -> DeveloperInventoryRequest {
        guard let authority, authority.isCurrent else { return .none }
        let executables = authority.scopes.compactMap { scope -> LocalExecutableApproval? in
            guard case .localExecutable(let value) = scope else { return nil }
            return value
        }
        let sockets = authority.scopes.compactMap { scope -> LocalSocketApproval? in
            guard case .localSocket(let value) = scope else { return nil }
            return value
        }
        let xcrun = executables.first { $0.canonicalPath == "/usr/bin/xcrun" }
        let docker = executables.first {
            URL(fileURLWithPath: $0.canonicalPath).lastPathComponent == "docker"
        }
        let apple = xcrun.flatMap { AppleReadApproval(authority: authority, executable: $0) }
        let dockerRead: DockerReadApproval?
        if let docker, let socket = sockets.first {
            dockerRead = DockerReadApproval(authority: authority, executable: docker,
                endpoint: "unix://" + socket.canonicalPath, socket: socket)
        } else {
            dockerRead = nil
        }
        return DeveloperInventoryRequest(apple: apple, docker: dockerRead)
    }

    private static func candidate(_ entry: DeveloperInventoryEntry) -> CleanupCandidate {
        let allocation: AllocationKnowledge
        if entry.record.allocatedBytes == nil {
            allocation = entry.record.reason.contains("shared")
                ? .shared("Shared allocation is not additive.") : .unknown
        } else {
            allocation = .exclusiveEstimate
        }
        let retention: ArtifactRetention = entry.record.kind.hasPrefix("node-output:")
            || entry.record.kind.hasPrefix("android-project-")
            ? .projectArtifact(createdAt: nil) : .notArtifact
        return CleanupCandidate(record: entry.record, catalogID: entry.record.kind,
            cost: .low, lastActivityAt: nil,
            manualRisk: entry.disposition == .manualRisk, allocation: allocation,
            artifactRetention: retention)
    }

    private static let pinnedProjectsID = SettingID(rawValue: "scope.pinnedProjects")
    private static let currentProjectID = SettingID(rawValue: "scope.currentProject")

    private static func storedStrings(_ values: PolicyValues, _ id: SettingID) -> Set<String> {
        guard case .strings(let result)? = values.fields[id] else { return [] }
        return Set(result)
    }

    private static func storedChoice(_ values: PolicyValues, _ id: SettingID) -> String? {
        guard case .choice(let result)? = values.fields[id] else { return nil }
        return result
    }

    private func submitProjectSetting(_ id: SettingID, value: SettingValue,
                                      savedMessage: String) {
        guard let store = services?.configStore else {
            projectActionMessage = "Project settings are unavailable."
            return
        }
        guard projectControlsEnabled else {
            projectActionMessage = "Project inventory is disabled by the acknowledged policy."
            return
        }
        guard !store.hasPendingSettingsWrites else {
            projectActionMessage = "Wait for the pending settings change to finish."
            return
        }
        switch store.setGlobalPreference(id, to: value) {
        case .rejected(_, let reason):
            projectActionMessage = "The settings change was rejected: \(Self.rejectionText(reason))."
        case .accepted(_, let completion):
            projectActionMessage = "Saving project settings…"
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch await completion.value {
                case .saved:
                    self.projectActionMessage = savedMessage
                case .conflict:
                    self.projectActionMessage = "Project settings changed elsewhere. Try again."
                case .invalid:
                    self.projectActionMessage = "The project setting is no longer valid."
                case .failed:
                    self.projectActionMessage = "Project settings could not be saved."
                }
            }
        }
    }

    private static func rejectionText(_ rejection: SettingsSubmissionRejection) -> String {
        switch rejection {
        case .invalid: return "invalid value"
        case .unsupportedAuthority: return "unsupported settings authority"
        case .queueFull: return "settings queue is full"
        case .unavailable: return "settings persistence is unavailable"
        }
    }

    private func reveal(_ identity: FileResourceIdentity) {
        guard let services, let snapshot else {
            projectActionMessage = "Refresh Inventory before revealing this item."
            return
        }
        let store = services.configStore
        guard !store.hasPendingSettingsWrites,
              store.acknowledgedSettingsRevision == snapshot.policyRevision else {
            projectActionMessage = "Settings changed. Refresh Inventory before revealing this item."
            return
        }
        do {
            guard let environment = store.acknowledgedPolicyEnvironment(
                homeDirectory: services.paths.home.path) else {
                projectActionMessage = "The acknowledged project scope is unavailable."
                return
            }
            let scope = try services.authorizeProjectScope(ownerID: ownerID,
                localAuthority: store.localAuthoritySnapshot)
            guard scope.policyRevision == snapshot.policyRevision else {
                // Consume the issued grant even when the inventory revision is stale.
                try scope.consumeForPresentation(resource: .filesystem(identity),
                    ownerID: ownerID, environment: environment)
                projectActionMessage = "Settings changed. Refresh Inventory before revealing this item."
                return
            }
            try scope.consumeForPresentation(resource: .filesystem(identity),
                ownerID: ownerID, environment: environment)
            guard
                  Self.isCurrent(identity) else {
                projectActionMessage = "The item or its approved scope changed. Refresh Inventory first."
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([
                URL(fileURLWithPath: identity.canonicalPath)
            ])
            projectActionMessage = nil
        } catch {
            projectActionMessage = "The approved project scope is no longer current. Refresh Inventory first."
        }
    }

    private static func isCurrent(_ expected: FileResourceIdentity) -> Bool {
        let path = expected.canonicalPath
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty, !components.contains("."), !components.contains("..") else {
            return false
        }
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        var parentIndex = 0
        for component in components.dropLast() {
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0,
                  parentIndex < expected.parentChain.count,
                  nodeMatches(metadata, expected.parentChain[parentIndex]) else { return false }
            parentIndex += 1
            let next = openat(descriptor, component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { return false }
            Darwin.close(descriptor)
            descriptor = next
        }
        var parent = stat()
        guard fstat(descriptor, &parent) == 0,
              parentIndex < expected.parentChain.count,
              nodeMatches(parent, expected.parentChain[parentIndex]) else { return false }
        parentIndex += 1
        guard parentIndex == expected.parentChain.count,
              let leaf = components.last else { return false }

        var namespaceMetadata = stat()
        guard fstatat(descriptor, leaf, &namespaceMetadata, AT_SYMLINK_NOFOLLOW) == 0,
              [S_IFREG, S_IFDIR].contains(namespaceMetadata.st_mode & S_IFMT) else { return false }
        let leafDescriptor = openat(descriptor, leaf,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard leafDescriptor >= 0 else { return false }
        defer { Darwin.close(leafDescriptor) }
        var opened = stat()
        var volume = statfs()
        guard fstat(leafDescriptor, &opened) == 0,
              opened.st_dev == namespaceMetadata.st_dev,
              opened.st_ino == namespaceMetadata.st_ino,
              fstatfs(leafDescriptor, &volume) == 0,
              volume.f_flags & UInt32(MNT_LOCAL) != 0,
              volumeUUID(leafDescriptor) == expected.volumeID else { return false }
        var final = stat()
        guard fstatat(descriptor, leaf, &final, AT_SYMLINK_NOFOLLOW) == 0,
              final.st_dev == opened.st_dev, final.st_ino == opened.st_ino,
              final.st_mode == opened.st_mode, final.st_size == opened.st_size,
              final.st_mtimespec.tv_sec == opened.st_mtimespec.tv_sec,
              final.st_mtimespec.tv_nsec == opened.st_mtimespec.tv_nsec else { return false }
        return expected.device == UInt64(UInt32(bitPattern: opened.st_dev))
            && expected.inode == UInt64(opened.st_ino)
            && expected.generation == UInt64(opened.st_gen)
            && expected.mode == UInt32(opened.st_mode)
            && expected.size == opened.st_size
            && expected.modifiedSeconds == Int64(opened.st_mtimespec.tv_sec)
            && expected.modifiedNanoseconds == Int64(opened.st_mtimespec.tv_nsec)
    }

    private static func nodeMatches(_ metadata: stat, _ expected: FileNodeIdentity) -> Bool {
        expected.device == UInt64(UInt32(bitPattern: metadata.st_dev))
            && expected.inode == UInt64(metadata.st_ino)
            && expected.generation == UInt64(metadata.st_gen)
            && expected.mode == UInt32(metadata.st_mode)
    }

    private static func volumeUUID(_ descriptor: Int32) -> UUID? {
        struct VolumeAttributes {
            var length: UInt32 = 0
            var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        }
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_UUID)
        var result = VolumeAttributes()
        guard fgetattrlist(descriptor, &attributes, &result,
                          MemoryLayout<VolumeAttributes>.size, 0) == 0,
              result.length == MemoryLayout<VolumeAttributes>.size,
              withUnsafeBytes(of: result.uuid, { $0.contains { $0 != 0 } }) else { return nil }
        return UUID(uuid: result.uuid)
    }

    private static func strings(_ policy: EffectivePolicy, _ rawID: String) -> Set<String> {
        guard case .stored(.strings(let values))? =
                policy.fields[SettingID(rawValue: rawID)]?.value else { return [] }
        return Set(values)
    }

    private static func choice(_ policy: EffectivePolicy, _ rawID: String) -> String? {
        guard case .stored(.choice(let value))? =
                policy.fields[SettingID(rawValue: rawID)]?.value else { return nil }
        return value
    }

    private static func headroomPlan(ranking: CandidateRanking, policy: EffectivePolicy,
                                     policyRevision: UInt64,
                                     measurement: SystemSnapshot,
                                     deselectedIDs: Set<String>) throws
        -> (plan: HeadroomPlan?, unavailableReason: String?) {
        guard policy.allowedFeatures.contains("buildPrep") else {
            return (nil, "Build Prep is disabled by the acknowledged policy.")
        }
        guard case .bytes(let target)? = policy.fields[
                SettingID(rawValue: "headroom.targetGiB")]?.value else {
            return (nil, "The headroom target is unavailable for the selected volume.")
        }
        guard let volume = measurement.volumes.first,
              let disk = volume.disk,
              let rawVolumeID = disk.volumeIdentifier,
              let volumeID = UUID(uuidString: rawVolumeID) else {
            return (nil, "Strict available capacity or stable volume identity is unavailable.")
        }
        let plan = try HeadroomPlanner.plan(ranking: ranking, volumeID: volumeID,
            strictAvailableBytes: disk.availableBytes, targetBytes: target,
            byteCap: policy.manualBatchBytes, itemCap: policy.manualBatchItems,
            policyRevision: policyRevision, deselectedIDs: deselectedIDs)
        return (plan, nil)
    }
}
