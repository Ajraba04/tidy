import Foundation
import Observation

@Observable @MainActor
public final class ExecutionPolicyBridge {
    public private(set) var updateGeneration = UUID()
    public private(set) var isExecutionEnabled = true
    public private(set) var policyUpdatePending = false
    public private(set) var persistenceError: String?
    private let coordinator: ExecutionCoordinator
    private let configURL: URL?
    private let homeDirectory: String
    private let detectedTools: Set<ToolchainID> // metadata only, no lazy getter/refresh
    private var generation = UUID() // UI update identity, never execution authority
    private var pending: Task<Void, Never>?

    public init(coordinator: ExecutionCoordinator, configURL: URL?,
                homeDirectory: String, detectedTools: Set<ToolchainID>) {
        self.coordinator = coordinator
        self.configURL = configURL
        self.homeDirectory = homeDirectory
        self.detectedTools = detectedTools
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
            policyUpdatePending = false
            persistenceError = "Settings could not be applied. Cleanup remains disabled."
            return Task {}
        }
        let environment = config.makePolicyEnvironment(homeDirectory: homeDirectory,
                                                       detectedTools: detectedTools)
        let previous = pending
        let task = Task { [self] in
            await previous?.value
            do {
                try ConfigStore.save(config, to: configURL)
                let commit = try await coordinator.commitPolicyUpdate(ticket, environment: environment)
                if generation == next {
                    policyUpdatePending = false
                    if case .applied(let revision) = commit,
                       coordinator.policyAdmission() == .ready(revision: revision) {
                        persistenceError = nil
                        isExecutionEnabled = true
                    } else {
                        isExecutionEnabled = false
                        persistenceError = "A newer settings update is pending. Cleanup remains disabled."
                    }
                }
            } catch {
                if generation == next {
                    policyUpdatePending = false
                    isExecutionEnabled = false
                    persistenceError = "Settings could not be saved. Cleanup remains disabled. Fix the settings storage location and save again."
                }
            }
        }
        pending = task
        return task
    }
}
