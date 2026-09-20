import Foundation

public struct AppleSimulatorInventory: Equatable, Sendable {
    public let udid: UUID
    public let runtimeID: String
    public let name: String
    public let state: String
    public let isAvailable: Bool
}

public enum AppleSimulatorOperation: Equatable, Sendable {
    case shutdown
    case delete
}

public struct AppleDeveloperAdapter: ToolAdapter {
    public static let adapterID = "apple.developer"
    public static let contractVersion = "simctl-json-v1"
    static let ecosystemID = "apple"

    public init() {}

    public static func parseSimctlDevices(_ data: Data) -> [AppleSimulatorInventory]? {
        guard let root = BoundedAdapterData.jsonObject(data) as? [String: Any],
              Set(root.keys) == ["devices"],
              let devices = root["devices"] as? [String: Any],
              devices.count <= 256 else { return nil }
        var result: [AppleSimulatorInventory] = []
        for runtime in devices.keys.sorted() {
            guard runtime.utf8.count <= 4_096,
                  let rows = devices[runtime] as? [[String: Any]], rows.count <= 1_000 else {
                return nil
            }
            for row in rows {
                guard let rawID = row["udid"] as? String,
                      let id = UUID(uuidString: rawID),
                      let name = row["name"] as? String, name.utf8.count <= 4_096,
                      let state = row["state"] as? String, state.utf8.count <= 128,
                      let available = row["isAvailable"] as? Bool else { return nil }
                result.append(.init(udid: id, runtimeID: runtime, name: name,
                                    state: state, isAvailable: available))
            }
        }
        return result.sorted { $0.udid.uuidString < $1.udid.uuidString }
    }

    public static func effectSpec(for simulator: AppleSimulatorInventory,
                                  operation: AppleSimulatorOperation) -> ToolEffectSpec {
        let verb: String
        let completion: ToolEffectCompletionProbe
        switch operation {
        case .shutdown:
            verb = "shutdown"
            completion = .simulatorStateByUDID
        case .delete:
            verb = "delete"
            completion = .simulatorAbsentByUDID
        }
        let reason = simulator.state == "Shutdown" || operation == .shutdown
            ? "Typed simctl mutation dispatch is not registered in the compiled capability registry."
            : "Simulator must be revalidated as Shutdown before exact deletion."
        return ToolEffectSpec(adapterID: adapterID, adapterVersion: contractVersion,
            resourceIDs: [simulator.udid.uuidString],
            exactArgv: ["simctl", verb, simulator.udid.uuidString],
            preflight: .exactSimulatorIdentityAndState,
            completionProbe: completion, unavailable: reason)
    }

    public static func inventoryRecords(fromSimctlData data: Data, scopeID: String,
                                        observedAt: Date = Date()) -> [InventoryRecord]? {
        guard let devices = parseSimctlDevices(data) else { return nil }
        return devices.map { device in
            InventoryRecord(id: "simulator-" + device.udid.uuidString.lowercased(),
                adapterID: adapterID, adapterVersion: contractVersion,
                resource: .simulator(udid: device.udid, runtimeID: device.runtimeID),
                ownerIDs: [], scopeID: scopeID, kind: "apple-simulator",
                capability: .inventoryOnly, allocatedBytes: nil, confidence: .exact,
                activity: device.state == "Booted" ? .running : .unknown,
                observedAt: observedAt,
                reason: "Exact simctl device identity; state=\(device.state), "
                    + "available=\(device.isAvailable). Deletion dispatch remains unavailable.")
        }
    }

    func inventory(context: ToolAdapterContext) throws -> [DeveloperInventoryEntry] {
        let relative = [
            "Library/Developer/Xcode/DerivedData",
            "Library/Developer/Xcode/Archives",
            "Library/Developer/Xcode/iOS DeviceSupport",
            "Library/Developer/CoreSimulator/Devices",
            "Library/Caches/org.swift.swiftpm",
            ".cocoapods"
        ]
        return relative.compactMap { name in
            guard let path = context.knownHomePath(name) else { return nil }
            return context.entry(adapterID: Self.adapterID,
                adapterVersion: Self.contractVersion, path: path,
                kind: "apple:\(name)", disposition: .reportOnly,
                reason: "Bounded local Apple developer inventory; producer ownership is unknown.")
        }
    }
}
