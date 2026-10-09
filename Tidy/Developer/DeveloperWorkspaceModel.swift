import AppKit
import Darwin
import Foundation
import Observation
import TidyCore

struct BuildPrepVolumeSelection: Equatable {
    private(set) var selectedID: UUID?

    mutating func select(_ id: UUID) { selectedID = id }

    func resolvedID(homeVolumeID: UUID?, availableVolumeIDs: [UUID]) -> UUID? {
        guard let candidate = selectedID ?? homeVolumeID,
              availableVolumeIDs.contains(candidate) else { return nil }
        return candidate
    }
}

struct BuildPrepVolumeTarget: Identifiable, Sendable {
    enum Error: Swift.Error { case authorityChanged, identityChanged, measurementUnavailable }
    typealias DiskProbe = @Sendable (URL) async throws -> DiskStats

    let root: LocalRootApproval
    let scope: LocalAuthorityScope?
    var id: UUID { root.volumeID }
    var label: String { scope == nil ? "Home volume" : root.canonicalPath }

    static func options(home: URL, authority: LocalAuthoritySnapshot?) -> [Self] {
        var result: [Self] = []
        if let root = try? LocalRootApproval.verify(directory: home) {
            result.append(Self(root: root, scope: nil))
        }
        guard let authority, authority.isCurrent else { return result }
        let approved = authority.scopes.compactMap { scope -> Self? in
            switch scope {
            case .localRoot(let root), .externalVolume(let root):
                return Self(root: root, scope: scope)
            default: return nil
            }
        }.sorted { $0.root.canonicalPath < $1.root.canonicalPath }
        for target in approved where !result.contains(where: { $0.id == target.id }) {
            result.append(target)
        }
        return result
    }

    func measure(authority: LocalAuthoritySnapshot?, probe: DiskProbe) async throws -> DiskStats {
        try Task.checkCancellation()
        try validateAuthority(authority)
        let target = self
        try await Task.detached { try target.validateIdentity() }.value
        try Task.checkCancellation()
        try validateAuthority(authority)
        let disk = try await probe(URL(fileURLWithPath: root.canonicalPath))
        try Task.checkCancellation()
        try validateAuthority(authority)
        try await Task.detached { try target.validateIdentity() }.value
        try Task.checkCancellation()
        try validateAuthority(authority)
        guard disk.volumeIdentifier.flatMap(UUID.init(uuidString:)) == id,
              disk.totalBytes > 0, disk.availableBytes >= 0,
              disk.availableBytes <= disk.totalBytes else { throw Error.measurementUnavailable }
        return disk
    }

    private func validateAuthority(_ authority: LocalAuthoritySnapshot?) throws {
        if let scope, authority?.permits(scope) != true { throw Error.authorityChanged }
    }

    private func validateIdentity() throws {
        let url = URL(fileURLWithPath: root.canonicalPath)
        let current: LocalRootApproval
        if case .externalVolume? = scope {
            current = try LocalRootApproval.verifyExternalVolumeRoot(directory: url)
        } else {
            current = try LocalRootApproval.verify(directory: url)
        }
        guard current == root else { throw Error.identityChanged }
    }
}

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
    private(set) var isRefreshingBuildPrepCapacity = false
    private(set) var buildPrepVolumeOptions: [BuildPrepVolumeTarget] = []
    private(set) var buildPrepVolumeSelection = BuildPrepVolumeSelection()
    private(set) var buildPrepCapacityMessage: String?
    @ObservationIgnored var onInventoryChange:
        (@MainActor (DeveloperInventorySnapshot?) -> Void)?

    @ObservationIgnored private weak var services: AppExecutionServices?
    @ObservationIgnored private let ownerID = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var session: WorkSession?
    @ObservationIgnored private var deselectedBuildPrepIDs: Set<String> = []
    @ObservationIgnored private let diskProbe: BuildPrepVolumeTarget.DiskProbe
    @ObservationIgnored private var capacityTask: Task<Void, Never>?
    @ObservationIgnored private var capacityGeneration = UUID()

    init(services: AppExecutionServices,
         diskProbe: @escaping BuildPrepVolumeTarget.DiskProbe = { url in
             try await Task.detached { try LiveSystemProbe().diskStats(volumeURL: url) }.value
         }) {
        self.services = services
        self.diskProbe = diskProbe
    }

    var selectedBuildPrepVolumeID: UUID? {
        buildPrepVolumeSelection.selectedID ?? buildPrepVolumeOptions.first(where: { $0.scope == nil })?.id
    }

    func updateBuildPrepVolumeOptions(localAuthority: LocalAuthoritySnapshot?) {
        guard let services else { return }
        buildPrepVolumeOptions = BuildPrepVolumeTarget.options(home: services.paths.home,
            authority: localAuthority)
    }

    func selectBuildPrepVolume(_ id: UUID, localAuthority: LocalAuthoritySnapshot?) {
        guard !isScanning else { return }
        buildPrepVolumeSelection.select(id)
        deselectedBuildPrepIDs = []
        refreshBuildPrepCapacity(localAuthority: localAuthority)
    }

    func invalidateBuildPrepCapacity() {
        capacityTask?.cancel()
        capacityTask = nil
        capacityGeneration = UUID()
        isRefreshingBuildPrepCapacity = false
        buildPrepCapacityMessage = "Refresh capacity for the selected volume."
        if let snapshot {
            self.snapshot = DeveloperWorkspaceSnapshot(inventory: snapshot.inventory,
                buildPrep: snapshot.buildPrep, headroomPlan: nil,
                headroomUnavailableReason: buildPrepCapacityMessage,
                measurement: snapshot.measurement, policyRevision: snapshot.policyRevision)
        }
    }

    func refreshBuildPrepCapacity(localAuthority: LocalAuthoritySnapshot?) {
        guard !isScanning, let services else { return }
        invalidateBuildPrepCapacity()
        updateBuildPrepVolumeOptions(localAuthority: localAuthority)
        guard let captured = snapshot else {
            buildPrepCapacityMessage = "Refresh Inventory before preparing the selected volume."
            return
        }
        guard let target = selectedVolumeTarget() else {
            buildPrepCapacityMessage = "The selected volume is unavailable or no longer approved."
            return
        }
        let generation = capacityGeneration
        let probe = diskProbe
        isRefreshingBuildPrepCapacity = true
        capacityTask = Task { @MainActor [weak self, weak services] in
            guard let self, let services else { return }
            defer {
                if self.capacityGeneration == generation {
                    self.capacityTask = nil
                    self.isRefreshingBuildPrepCapacity = false
                }
            }
            do {
                guard services.configStore.acknowledgedEffectivePolicy?.allowedFeatures
                    .contains("buildPrep") == true,
                      !services.configStore.hasPendingSettingsWrites else {
                    throw BuildPrepVolumeTarget.Error.authorityChanged
                }
                let disk = try await target.measure(authority: localAuthority, probe: probe)
                try Task.checkCancellation()
                guard self.capacityGeneration == generation,
                      services.configStore.acknowledgedSettingsRevision == captured.policyRevision,
                      !services.configStore.hasPendingSettingsWrites,
                      let policy = services.configStore.acknowledgedPolicyForVolume(
                        identity: disk.volumeIdentifier, capacityBytes: disk.totalBytes) else {
                    throw BuildPrepVolumeTarget.Error.authorityChanged
                }
                let measurement = Self.replacingVolume(in: captured.measurement,
                    target: target, disk: disk)
                let planning = try Self.headroomPlan(ranking: captured.buildPrep, policy: policy,
                    policyRevision: captured.policyRevision, measurement: measurement,
                    volumeID: target.id, deselectedIDs: self.deselectedBuildPrepIDs)
                self.snapshot = DeveloperWorkspaceSnapshot(inventory: captured.inventory,
                    buildPrep: captured.buildPrep, headroomPlan: planning.plan,
                    headroomUnavailableReason: planning.unavailableReason,
                    measurement: measurement, policyRevision: captured.policyRevision)
                self.buildPrepCapacityMessage = nil
            } catch {
                guard self.capacityGeneration == generation else { return }
                self.buildPrepCapacityMessage = "Selected-volume capacity is unavailable. Refresh after checking its approval and identity."
            }
        }
    }

    private func selectedVolumeTarget() -> BuildPrepVolumeTarget? {
        let homeID = buildPrepVolumeOptions.first(where: { $0.scope == nil })?.id
        guard let id = buildPrepVolumeSelection.resolvedID(homeVolumeID: homeID,
            availableVolumeIDs: buildPrepVolumeOptions.map(\.id)) else { return nil }
        return buildPrepVolumeOptions.first { $0.id == id }
    }

    func scan(localAuthority: LocalAuthoritySnapshot?) {
        guard task == nil, let services else { return }
        invalidateBuildPrepCapacity()
        updateBuildPrepVolumeOptions(localAuthority: localAuthority)
        error = nil
        isScanning = true
        task = Task { @MainActor [weak self, weak services] in
            guard let self, let services else { return }
            await self.performScan(services: services, localAuthority: localAuthority)
        }
    }

    func cancel() {
        invalidateBuildPrepCapacity()
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
            var measurement = await services.systemMonitor.requestSnapshot()
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
            var planning: (plan: HeadroomPlan?, unavailableReason: String?) =
                (nil, "The selected volume is unavailable or no longer approved.")
            if scope.policy.allowedFeatures.contains("buildPrep"),
               let target = selectedVolumeTarget() {
                do {
                    let disk = try await target.measure(authority: localAuthority, probe: diskProbe)
                    try Task.checkCancellation()
                    guard services.configStore.acknowledgedSettingsRevision == scope.policyRevision,
                          !services.configStore.hasPendingSettingsWrites,
                          let measuredPolicy = services.configStore.acknowledgedPolicyForVolume(
                            identity: disk.volumeIdentifier, capacityBytes: disk.totalBytes) else {
                        throw CancellationError()
                    }
                    measurement = Self.replacingVolume(in: measurement, target: target, disk: disk)
                    planning = try Self.headroomPlan(ranking: ranking, policy: measuredPolicy,
                        policyRevision: scope.policyRevision, measurement: measurement,
                        volumeID: target.id, deselectedIDs: deselectedBuildPrepIDs)
                } catch is CancellationError { throw CancellationError() }
                catch {
                    planning = (nil, "Selected-volume capacity is unavailable. Check its approval and identity, then refresh capacity.")
                }
            } else if !scope.policy.allowedFeatures.contains("buildPrep") {
                planning = (nil, "Build Prep is disabled by the acknowledged policy.")
            }
            try Task.checkCancellation()
            guard services.configStore.acknowledgedSettingsRevision == scope.policyRevision,
                  localAuthority?.isCurrent != false else { throw CancellationError() }
            snapshot = DeveloperWorkspaceSnapshot(inventory: inventory,
                buildPrep: ranking, headroomPlan: planning.plan,
                headroomUnavailableReason: planning.unavailableReason,
                measurement: measurement, policyRevision: scope.policyRevision)
            onInventoryChange?(inventory)
            buildPrepCapacityMessage = nil
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
                                     volumeID: UUID,
                                     deselectedIDs: Set<String>) throws
        -> (plan: HeadroomPlan?, unavailableReason: String?) {
        guard policy.allowedFeatures.contains("buildPrep") else {
            return (nil, "Build Prep is disabled by the acknowledged policy.")
        }
        guard case .bytes(let target)? = policy.fields[
                SettingID(rawValue: "headroom.targetGiB")]?.value else {
            return (nil, "The headroom target is unavailable for the selected volume.")
        }
        guard let volume = measurement.volumes.first(where: {
                  $0.disk?.volumeIdentifier.flatMap(UUID.init(uuidString:)) == volumeID
              }),
              let disk = volume.disk,
              let rawVolumeID = disk.volumeIdentifier,
              UUID(uuidString: rawVolumeID) == volumeID else {
            return (nil, "Strict available capacity or stable volume identity is unavailable.")
        }
        let plan = try HeadroomPlanner.plan(ranking: ranking, volumeID: volumeID,
            strictAvailableBytes: disk.availableBytes, targetBytes: target,
            byteCap: policy.manualBatchBytes, itemCap: policy.manualBatchItems,
            policyRevision: policyRevision, deselectedIDs: deselectedIDs)
        return (plan, nil)
    }

    private static func replacingVolume(in measurement: SystemSnapshot,
                                        target: BuildPrepVolumeTarget, disk: DiskStats) -> SystemSnapshot {
        let volume = VolumeObservation(volumeIdentity: target.id.uuidString,
            displayPath: target.root.canonicalPath, disk: disk)
        return SystemSnapshot(observedAt: Date(), bootIdentity: measurement.bootIdentity,
            volumes: [volume], memory: nil,
            memoryUnavailableReason: "This explicit observation measures selected-volume capacity only.",
            swap: nil, swapUnavailableReason: "This explicit observation measures selected-volume capacity only.",
            pageOutRatePerSecond: nil, memoryPressureLevel: nil,
            thermalState: nil, isLowPowerModeEnabled: nil)
    }
}
