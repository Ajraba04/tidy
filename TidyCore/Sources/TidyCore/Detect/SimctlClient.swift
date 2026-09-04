import Foundation

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

public enum SimctlClient: Sendable {
    public static func listDevices() async -> [SimulatorDevice] {
        guard let xcrunPath = await ToolLocator.locateAsync("xcrun") else { return [] }
        guard let output = try? await ProcessRunner.runSimctlDevices(
            xcrunURL: URL(fileURLWithPath: xcrunPath)
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
        guard let xcrunPath = await ToolLocator.locateAsync("xcrun") else { return [] }
        guard let output = try? await ProcessRunner.runSimctlRuntimes(
            xcrunURL: URL(fileURLWithPath: xcrunPath)
        ), output.succeeded, let data = output.standardOutput.data(using: .utf8) else {
            return []
        }
        guard let response = try? JSONDecoder().decode(SimctlRuntimeListResponse.self, from: data) else {
            return []
        }
        return response.runtimes
    }

    /// Runtimes with zero devices: pure waste, per the script's section 9
    /// report.
    public static func idleRuntimes() async -> [SimulatorRuntime] {
        async let devices = listDevices()
        async let runtimes = listRuntimes()
        let usedRuntimeIDs = Set(await devices.map(\.runtimeIdentifier))
        return await runtimes.filter { !usedRuntimeIDs.contains($0.identifier) }
    }

    /// Deferred synchronous catalog route. T08.4 owns converting the exact
    /// `CleanCatalog+Xcode` caller to async orchestration. Returning no
    /// evidence is fail-closed and does not hide a private process escape.
    @available(*, deprecated, message: "T08.4 must use async listDevices()")
    static func listDevicesSync() -> [SimulatorDevice] {
        []
    }
}
