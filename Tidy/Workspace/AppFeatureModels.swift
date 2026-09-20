import Foundation
import Observation
import TidyCore

/// Shared across scenes so closing a window does not discard local consent or
/// start a second inventory/authority store when the window opens again.
@Observable @MainActor
final class AppFeatureModels {
    let developer: DeveloperWorkspaceModel
    let assistance: AssistanceModel
    @ObservationIgnored private weak var configStore: AppConfigStore?
    @ObservationIgnored nonisolated(unsafe) private var policyObserver: UUID?

    init(services: AppExecutionServices) {
        developer = DeveloperWorkspaceModel(services: services)
        assistance = AssistanceModel(services: services)
        configStore = services.configStore
        developer.onInventoryChange = { [weak assistance] inventory in
            guard let assistance else { return }
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
        policyObserver = services.configStore.observeAcknowledgedPolicy { [weak developer] _, _ in
            developer?.invalidate()
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
