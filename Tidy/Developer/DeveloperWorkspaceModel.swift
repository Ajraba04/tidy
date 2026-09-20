import Foundation
import Observation
import TidyCore

struct DeveloperWorkspaceSnapshot: Sendable {
    let inventory: DeveloperInventorySnapshot
    let buildPrep: CandidateRanking
    let headroomPlan: HeadroomPlan?
    let headroomUnavailableReason: String?
    let measurement: SystemSnapshot
}

@Observable @MainActor
final class DeveloperWorkspaceModel {
    private(set) var snapshot: DeveloperWorkspaceSnapshot?
    private(set) var error: String?
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
            measurement: snapshot.measurement)
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
                measurement: measurement)
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
        return CleanupCandidate(record: entry.record, catalogID: entry.record.kind,
            cost: .low, lastActivityAt: nil,
            manualRisk: entry.disposition == .manualRisk, allocation: allocation)
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
