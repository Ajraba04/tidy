import Foundation

/// A simulator device, decoded from `xcrun simctl list devices -j` — JSON
/// via `Codable`, so the shell script's embedded python3 disappears.
public struct SimulatorDevice: Codable, Sendable, Identifiable, Hashable {
    public var id: String { udid }
    public let udid: String
    public let name: String
    public let state: String
    public let isAvailable: Bool
    public let deviceTypeIdentifier: String?
    public internal(set) var runtimeIdentifier: String = ""

    private enum CodingKeys: String, CodingKey {
        case udid, name, state, isAvailable, deviceTypeIdentifier
    }
}

/// A simulator runtime, decoded from `xcrun simctl list runtimes -j`.
public struct SimulatorRuntime: Codable, Sendable, Identifiable, Hashable {
    public var id: String { identifier }
    public let name: String
    public let identifier: String
    public let version: String?
    public let isAvailable: Bool?
}

private struct SimctlDeviceListResponse: Codable {
    let devices: [String: [SimulatorDevice]]
}

private struct SimctlRuntimeListResponse: Codable {
    let runtimes: [SimulatorRuntime]
}

/// Thin wrapper over `xcrun simctl`. Read-only listing lives here for both
/// Scan (idle runtimes) and the Deep tier's simulator keep-list (Phase 6).
public enum SimctlClient: Sendable {
    public static func listDevices() async -> [SimulatorDevice] {
        guard let xcrunPath = ToolLocator.locate("xcrun") else { return [] }
        guard let output = try? await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: xcrunPath),
            arguments: ["simctl", "list", "devices", "-j"]
        ), output.succeeded, let data = output.standardOutput.data(using: .utf8) else {
            return []
        }
        guard let response = try? JSONDecoder().decode(SimctlDeviceListResponse.self, from: data) else {
            return []
        }

        var devices: [SimulatorDevice] = []
        for (runtimeIdentifier, deviceList) in response.devices {
            for device in deviceList {
                var device = device
                device.runtimeIdentifier = runtimeIdentifier
                devices.append(device)
            }
        }
        return devices
    }

    public static func listRuntimes() async -> [SimulatorRuntime] {
        guard let xcrunPath = ToolLocator.locate("xcrun") else { return [] }
        guard let output = try? await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: xcrunPath),
            arguments: ["simctl", "list", "runtimes", "-j"]
        ), output.succeeded, let data = output.standardOutput.data(using: .utf8) else {
            return []
        }
        guard let response = try? JSONDecoder().decode(SimctlRuntimeListResponse.self, from: data) else {
            return []
        }
        return response.runtimes
    }

    /// Runtimes with zero devices — pure waste, per the script's section 9
    /// report.
    public static func idleRuntimes() async -> [SimulatorRuntime] {
        async let devices = listDevices()
        async let runtimes = listRuntimes()
        let usedRuntimeIDs = Set(await devices.map(\.runtimeIdentifier))
        return await runtimes.filter { !usedRuntimeIDs.contains($0.identifier) }
    }
}
