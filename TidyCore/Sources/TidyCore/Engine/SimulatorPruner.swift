import Foundation

/// Simulator device deletion, gated on an opt-in approval list rather than
/// the shell script's keep-list: see `CleanEnvironment.simulatorsApprovedForDeletion`.
/// With nothing approved, this never deletes anything, which is the
/// shipped default.
public enum SimulatorPruner: Sendable {
    /// Devices eligible for deletion: present on this machine, and their
    /// name exactly matches an entry the user explicitly approved. Pure
    /// and synchronous: takes the device list rather than fetching it, so
    /// it's testable with fabricated devices and never touches `simctl`.
    public static func devicesEligibleForDeletion(
        allDevices: [SimulatorDevice],
        approvedForDeletion: [String]
    ) -> [SimulatorDevice] {
        guard !approvedForDeletion.isEmpty else { return [] }
        let approvedSet = Set(approvedForDeletion)
        return allDevices.filter { approvedSet.contains($0.name) }
    }

    /// Shuts the device down first (delete can fail on a booted device),
    /// then deletes it. Returns whether the delete itself succeeded.
    public static func deleteDevice(udid: String) async -> Bool {
        guard let xcrunPath = ToolLocator.locate("xcrun") else { return false }
        let xcrun = URL(fileURLWithPath: xcrunPath)
        _ = try? await ProcessRunner.run(executableURL: xcrun, arguments: ["simctl", "shutdown", udid])
        let result = try? await ProcessRunner.run(executableURL: xcrun, arguments: ["simctl", "delete", udid])
        return result?.succeeded ?? false
    }
}
