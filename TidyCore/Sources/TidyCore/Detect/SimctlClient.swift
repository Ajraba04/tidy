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

    /// Runtimes with zero devices: pure waste, per the script's section 9
    /// report.
    public static func idleRuntimes() async -> [SimulatorRuntime] {
        async let devices = listDevices()
        async let runtimes = listRuntimes()
        let usedRuntimeIDs = Set(await devices.map(\.runtimeIdentifier))
        return await runtimes.filter { !usedRuntimeIDs.contains($0.identifier) }
    }

    /// A synchronous device listing for use inside `CleanItem.locate`
    /// closures, which cannot be `async`. `simctl list devices -j` can
    /// produce more output than fits in one pipe buffer (many runtimes ×
    /// many devices), so unlike the other synchronous helpers in this
    /// package, this drains stdout incrementally *while* the process runs
    /// rather than waiting for exit first: a wait-then-read sequence could
    /// let the buffer fill up and block the child. stderr is discarded
    /// outright so it can never block either.
    static func listDevicesSync() -> [SimulatorDevice] {
        guard let xcrunPath = ToolLocator.locate("xcrun") else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrunPath)
        process.arguments = ["simctl", "list", "devices", "-j"]
        process.environment = ProcessRunner.minimalEnvironment

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        var data = Data()
        let handle = outPipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let response = try? JSONDecoder().decode(SimctlDeviceListResponse.self, from: data)
        else {
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
}
