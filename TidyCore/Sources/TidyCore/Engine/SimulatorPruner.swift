import Foundation

/// Simulator deletion is quarantined. The pure eligibility projection remains
/// available for read-only discovery, but no current caller can delete a
/// simulator through this type.
public enum SimulatorPruner: Sendable {
    /// Pure eligibility projection for read-only discovery. It takes a
    /// supplied device list and never contacts `simctl`.
    public static func devicesEligibleForDeletion(
        allDevices: [SimulatorDevice],
        approvedForDeletion: [String]
    ) -> [SimulatorDevice] {
        guard !approvedForDeletion.isEmpty else { return [] }
        let approvedSet = Set(approvedForDeletion)
        return allDevices.filter { approvedSet.contains($0.name) }
    }

    /// Legacy simulator-deletion entry point. It is fixed-denied before any
    /// command transport call and always returns `false`.
    public static func deleteDevice(udid: String, commandRunner: any CleanupCommandRunning = SystemCleanupCommandRunner()) async -> Bool {
        if CapabilityRegistry.denialReason(for: .custom(.simulatorPrune), itemID: "deep.simulator.delete-approved") != nil {
            return false
        }
        return false
    }
}
