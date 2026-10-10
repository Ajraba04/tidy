import Foundation
import Observation
import TidyCore

/// Shared across scenes so closing a window does not discard local consent or
/// start a second inventory/authority store when the window opens again.
@Observable @MainActor
final class AppFeatureModels {
    let developer: DeveloperWorkspaceModel
    let assistance: AssistanceModel
    let manualServices: ManualServiceReviewModel
    @ObservationIgnored private weak var configStore: AppConfigStore?
    @ObservationIgnored nonisolated(unsafe) private var policyObserver: UUID?

    init(services: AppExecutionServices) {
        let developer = DeveloperWorkspaceModel(services: services)
        let assistance = AssistanceModel(services: services)
        self.developer = developer
        self.assistance = assistance
        manualServices = ManualServiceReviewModel(facadeProvider: { [weak services, weak assistance] in
            guard let services, let authority = assistance?.authority else { return nil }
            return services.policyBridge.manualServices(authority: authority)
        }, candidateReader: { [weak services, weak assistance, weak developer] in
            guard let services, let authority = assistance?.authority,
                  let deviceSet = developer?.selectedManualDeviceSet else {
                throw ManualServiceReviewError.authorityDenied
            }
            let snapshot = try await authority.snapshot()
            return try await services.readManualSimulatorCandidates(deviceSet: deviceSet, authority: snapshot)
        }, executionStarter: { [weak services] facade, review in
            guard let services else { throw ManualServiceReviewError.policyUnavailable }
            return try services.startManualServiceExecution(facade: facade, review: review)
        }, executionOwnerAvailable: { [weak services, weak assistance] in
            guard let services, assistance?.authority != nil else { return false }
            return services.canStartManualServiceExecution
        })
        configStore = services.configStore
        developer.onInventoryChange = { [weak assistance, weak configStore = services.configStore] inventory in
            guard let assistance else { return }
            assistance.installMaintenanceInventory(inventory,
                sourcePolicyRevision: configStore?.acknowledgedSettingsRevision ?? 0)
            guard let inventory else {
                assistance.clearBudgetMeasurements()
                return
            }
            let volumes = Set(inventory.records.compactMap { record -> UUID? in
                if case .filesystem(let file) = record.resource { return file.volumeID }
                return nil
            })
            assistance.installBudgetInventory(Dictionary(uniqueKeysWithValues: volumes.map { volume in
                (volume, InventoryBudgetProjection.measurements(inventory, volumeID: volume))
            }))
        }
        policyObserver = services.configStore.observeAcknowledgedPolicy { [weak developer, weak manualServices] _, _ in
            developer?.invalidate()
            manualServices?.invalidateCandidates()
        }
    }

    deinit {
        let token = policyObserver
        let store = configStore
        Task { @MainActor in
            if let token { store?.removeAcknowledgedPolicyObserver(token) }
        }
    }
}
