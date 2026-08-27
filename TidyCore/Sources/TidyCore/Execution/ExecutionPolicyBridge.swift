import Foundation
import Observation

@Observable @MainActor
public final class ExecutionPolicyBridge {
    public private(set) var updateGeneration = UUID()
    public private(set) var isExecutionEnabled: Bool
    public private(set) var policyUpdatePending = false
    public private(set) var persistenceError: String?
    public private(set) var durableSettingsRevision: UInt64?
    internal private(set) var pendingSnapshotCount = 0
    internal private(set) var pendingSnapshotBytes = 0

    private let coordinator: ExecutionCoordinator
    private let settings: SettingsStore
    private let homeDirectory: String
    private let detectedTools: Set<ToolchainID>
    private var generation = UUID()
    private var lastSuccessfullyPersistedRevision: UInt64?
    private var pendingTail: Task<Void, Never>?
    private var pendingTailID: UUID?

    private static let maximumPendingSnapshots = 32
    private static let maximumPendingBytes = 32 * 1_048_576
    private static let saveFailure = "Settings could not be saved. Cleanup remains disabled. Fix the settings storage location and save again."
    private static let overflowFailure = "Settings changes are pending; wait and save again."

    public init(coordinator: ExecutionCoordinator, settings: SettingsStore,
                loaded: SettingsLoadResult, homeDirectory: String,
                detectedTools: Set<ToolchainID>) {
        self.coordinator = coordinator
        self.settings = settings
        self.homeDirectory = homeDirectory
        self.detectedTools = detectedTools
        let revision = loaded.envelope?.revision
        self.lastSuccessfullyPersistedRevision = revision
        self.durableSettingsRevision = revision
        self.isExecutionEnabled = revision != nil && loaded.disposition != .recoveryReadOnly

        if !isExecutionEnabled {
            self.persistenceError = "Settings are read-only. Cleanup remains disabled."
            do { _ = try coordinator.beginPolicyUpdate() }
            catch { self.persistenceError = "Settings could not be applied. Cleanup remains disabled." }
        }
    }

    @discardableResult
    public func submit(config: TidyConfig) -> Task<Void, Never> {
        isExecutionEnabled = false
        policyUpdatePending = true
        persistenceError = nil
        let next = UUID()
        generation = next
        updateGeneration = next

        let ticket: PolicyUpdateTicket
        do { ticket = try coordinator.beginPolicyUpdate() }
        catch {
            policyUpdatePending = pendingSnapshotCount > 0
            persistenceError = "Settings could not be applied. Cleanup remains disabled."
            return pendingTail ?? Task {}
        }

        let snapshotBytes: Int
        do {
            snapshotBytes = try SettingsDecoding.encode(SettingsEnvelope(
                schemaVersion: 2, revision: UInt64.max, config: config)).count
        } catch {
            policyUpdatePending = pendingSnapshotCount > 0
            persistenceError = Self.saveFailure
            return pendingTail ?? Task {}
        }

        guard pendingSnapshotCount < Self.maximumPendingSnapshots,
              pendingSnapshotBytes <= Self.maximumPendingBytes - snapshotBytes else {
            policyUpdatePending = pendingSnapshotCount > 0
            persistenceError = Self.overflowFailure
            return pendingTail ?? Task {}
        }

        pendingSnapshotCount += 1
        pendingSnapshotBytes += snapshotBytes
        let previous = pendingTail
        let tailID = UUID()
        pendingTailID = tailID
        let task = Task { @MainActor [self] in
            await previous?.value
            do {
                guard let expectedRevision = lastSuccessfullyPersistedRevision else {
                    throw SettingsStoreError.readOnlyRecovery
                }
                let saved = try await settings.update(expectedRevision: expectedRevision,
                    change: .legacyPreferences(config))
                lastSuccessfullyPersistedRevision = saved.revision
                durableSettingsRevision = saved.revision
                let environment = saved.config.makePolicyEnvironment(
                    homeDirectory: homeDirectory, detectedTools: detectedTools)
                let commit = try await coordinator.commitPolicyUpdate(ticket, environment: environment)
                if generation == next {
                    if case .applied(let revision) = commit,
                       coordinator.policyAdmission() == .ready(revision: revision) {
                        persistenceError = nil
                        isExecutionEnabled = true
                    } else {
                        persistenceError = "A newer settings update is pending. Cleanup remains disabled."
                        isExecutionEnabled = false
                    }
                }
            } catch {
                if generation == next {
                    persistenceError = Self.saveFailure
                    isExecutionEnabled = false
                }
            }

            pendingSnapshotCount -= 1
            pendingSnapshotBytes -= snapshotBytes
            policyUpdatePending = pendingSnapshotCount > 0
            if pendingTailID == tailID {
                pendingTail = nil
                pendingTailID = nil
            }
        }
        pendingTail = task
        return task
    }

    public func drain() async {
        while let tail = pendingTail {
            await tail.value
        }
    }
}
