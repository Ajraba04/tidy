import CoreFoundation
import CryptoKit
import Foundation

public struct ManualSimulatorRuntime: Codable, Equatable, Sendable {
    public let identifier: String
    public let version: String
    public let build: String
    public let isAvailable: Bool
    public let supportedDeviceTypeIdentifiers: [String]

    func validate() throws {
        try ManualServiceValueBounds.string(identifier, maximum: 512)
        try ManualServiceValueBounds.string(version, maximum: 128)
        try ManualServiceValueBounds.string(build, maximum: 128)
        guard identifier.hasPrefix("com.apple.CoreSimulator.SimRuntime."),
              supportedDeviceTypeIdentifiers.count <= 256,
              Set(supportedDeviceTypeIdentifiers).count == supportedDeviceTypeIdentifiers.count,
              supportedDeviceTypeIdentifiers == supportedDeviceTypeIdentifiers.sorted() else {
            throw ManualServiceInventoryError.invalidIdentity
        }
        for type in supportedDeviceTypeIdentifiers {
            try ManualServiceValueBounds.string(type, maximum: 512)
            guard type.hasPrefix("com.apple.CoreSimulator.SimDeviceType.") else {
                throw ManualServiceInventoryError.invalidIdentity
            }
        }
    }
}

extension ManualSimulatorRuntime {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(identifier: try c.decode(String.self, forKey: .identifier),
            version: try c.decode(String.self, forKey: .version), build: try c.decode(String.self, forKey: .build),
            isAvailable: try c.decode(Bool.self, forKey: .isAvailable),
            supportedDeviceTypeIdentifiers: try c.decode([String].self, forKey: .supportedDeviceTypeIdentifiers))
        try validate()
    }
}

public struct ManualSimulatorPair: Codable, Equatable, Sendable {
    public let pairID: UUID
    public let watchUDID: UUID
    public let phoneUDID: UUID
}

public struct ManualSimulatorInventory: Codable, Equatable, Sendable {
    public let parserFormatVersion: UInt32
    public let deviceSet: LocalRootApproval
    public let devices: [ManualSimulatorObject]
    public let runtimes: [ManualSimulatorRuntime]
    public let pairs: [ManualSimulatorPair]

    func validate() throws {
        guard parserFormatVersion == 1, devices.count <= 4_096,
              runtimes.count <= 256, pairs.count <= 1_024 else { throw ManualServiceInventoryError.capacity }
        try ManualServiceValueBounds.root(deviceSet)
        guard Set(devices.map(\.udid)).count == devices.count,
              Set(runtimes.map(\.identifier)).count == runtimes.count,
              Set(pairs.map(\.pairID)).count == pairs.count else { throw ManualServiceInventoryError.duplicateIdentity }
        guard devices.map(\.udid.uuidString) == devices.map(\.udid.uuidString).sorted(),
              runtimes.map(\.identifier) == runtimes.map(\.identifier).sorted(),
              pairs.map(\.pairID.uuidString) == pairs.map(\.pairID.uuidString).sorted() else {
            throw ManualServiceInventoryError.invalidIdentity
        }
        let byRuntime = Dictionary(uniqueKeysWithValues: runtimes.map { ($0.identifier, $0) })
        for runtime in runtimes { try runtime.validate() }
        for device in devices {
            try device.validate()
            guard let runtime = byRuntime[device.runtimeIdentifier],
                  runtime.supportedDeviceTypeIdentifiers.contains(device.deviceTypeIdentifier) else {
                throw ManualServiceInventoryError.identityMismatch
            }
        }
        let byDevice = Dictionary(uniqueKeysWithValues: devices.map { ($0.udid, $0) })
        var paired: Set<UUID> = []
        for pair in pairs {
            guard pair.watchUDID != pair.phoneUDID,
                  let watch = byDevice[pair.watchUDID], let phone = byDevice[pair.phoneUDID],
                  watch.runtimeIdentifier.hasPrefix("com.apple.CoreSimulator.SimRuntime.watchOS-"),
                  watch.deviceTypeIdentifier.hasPrefix("com.apple.CoreSimulator.SimDeviceType.Apple-Watch"),
                  phone.runtimeIdentifier.hasPrefix("com.apple.CoreSimulator.SimRuntime.iOS-"),
                  phone.deviceTypeIdentifier.hasPrefix("com.apple.CoreSimulator.SimDeviceType.iPhone"),
                  paired.insert(pair.watchUDID).inserted, paired.insert(pair.phoneUDID).inserted else {
                throw ManualServiceInventoryError.identityMismatch
            }
        }
    }
}

extension ManualSimulatorInventory {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(parserFormatVersion: try c.decode(UInt32.self, forKey: .parserFormatVersion),
            deviceSet: try c.decode(LocalRootApproval.self, forKey: .deviceSet),
            devices: try c.decode([ManualSimulatorObject].self, forKey: .devices),
            runtimes: try c.decode([ManualSimulatorRuntime].self, forKey: .runtimes),
            pairs: try c.decode([ManualSimulatorPair].self, forKey: .pairs))
        try validate()
    }
}

/// Internal parsing never grants authority or performs producer discovery.
enum ManualProducerInventory {
    static func parseSimulator(devices: Data, runtimes: Data, pairs: Data,
                               deviceSet: LocalRootApproval) throws -> ManualSimulatorInventory {
        let deviceRoot = try object(devices), runtimeRoot = try object(runtimes), pairRoot = try object(pairs)
        guard Set(deviceRoot.keys) == ["devices"], Set(runtimeRoot.keys) == ["runtimes"],
              Set(pairRoot.keys) == ["pairs"],
              let groups = deviceRoot["devices"] as? [String: Any], groups.count <= 256,
              let runtimeRows = runtimeRoot["runtimes"] as? [[String: Any]], runtimeRows.count <= 256,
              let pairRows = pairRoot["pairs"] as? [String: Any], pairRows.count <= 1_024 else {
            throw ManualServiceInventoryError.malformed
        }
        var parsedDevices: [ManualSimulatorObject] = []
        for runtimeID in groups.keys.sorted() {
            guard let rows = groups[runtimeID] as? [[String: Any]], rows.count <= 1_000,
                  rows.count <= 4_096 - parsedDevices.count else { throw ManualServiceInventoryError.capacity }
            for row in rows {
                let stateString = try string(row, "state", maximum: 64)
                guard let state = ManualSimulatorState(rawValue: stateString) else { throw ManualServiceInventoryError.ineligibleState }
                parsedDevices.append(.init(udid: try uuid(row["udid"]), runtimeIdentifier: runtimeID,
                    deviceTypeIdentifier: try string(row, "deviceTypeIdentifier", maximum: 512),
                    name: try string(row, "name", maximum: 512), state: state,
                    isAvailable: try boolean(row, "isAvailable")))
            }
        }
        let parsedRuntimes = try runtimeRows.map { row -> ManualSimulatorRuntime in
            guard let types = row["supportedDeviceTypes"] as? [[String: Any]], types.count <= 256 else {
                throw ManualServiceInventoryError.malformed
            }
            return .init(identifier: try string(row, "identifier", maximum: 512),
                version: try string(row, "version", maximum: 128), build: try string(row, "buildversion", maximum: 128),
                isAvailable: try boolean(row, "isAvailable"),
                supportedDeviceTypeIdentifiers: try types.map { try string($0, "identifier", maximum: 512) }.sorted())
        }
        let parsedPairs = try pairRows.map { key, value -> ManualSimulatorPair in
            guard let row = value as? [String: Any], let watch = row["watch"] as? [String: Any],
                  let phone = row["phone"] as? [String: Any] else { throw ManualServiceInventoryError.malformed }
            return .init(pairID: try uuid(key), watchUDID: try uuid(watch["udid"]), phoneUDID: try uuid(phone["udid"]))
        }
        let result = ManualSimulatorInventory(parserFormatVersion: 1, deviceSet: deviceSet,
            devices: parsedDevices.sorted { $0.udid.uuidString < $1.udid.uuidString },
            runtimes: parsedRuntimes.sorted { $0.identifier < $1.identifier },
            pairs: parsedPairs.sorted { $0.pairID.uuidString < $1.pairID.uuidString })
        try result.validate()
        return result
    }

    static func shutdownCandidate(id: UUID, inventory: ManualSimulatorInventory,
                                  producer: AppleSimulatorProducerIdentity) throws -> ManualSimulatorObject {
        try inventory.validate(); try producer.validate()
        guard producer.isInspectedCandidateVersion else { throw ManualServiceInventoryError.unsupportedProducer }
        guard inventory.deviceSet == producer.deviceSet,
              let device = inventory.devices.first(where: { $0.udid == id }) else {
            throw ManualServiceInventoryError.identityMismatch
        }
        guard device.isAvailable, inventory.runtimes.first(where: { $0.identifier == device.runtimeIdentifier })?.isAvailable == true else {
            throw ManualServiceInventoryError.unavailableRuntime
        }
        guard !inventory.pairs.contains(where: { $0.watchUDID == id || $0.phoneUDID == id }) else {
            throw ManualServiceInventoryError.pairedSimulator
        }
        guard [.booted, .shutdown].contains(device.state) else { throw ManualServiceInventoryError.ineligibleState }
        return device
    }

    static func parseDockerProducer(version: Data, info: Data, socket: LocalSocketApproval,
                                    peerPID: Int32, peerUID: UInt32, peerBootID: UUID,
                                    peerStartSeconds: Int64, peerStartMicroseconds: Int32,
                                    peerExecutable: LocalExecutableApproval,
                                    providerIdentifier: String) throws -> DockerProducerIdentity {
        let v = try object(version), i = try object(info)
        let parsedVersion = ManualDockerVersion(engineVersion: try string(v, "Version", maximum: 128),
            apiVersion: try string(v, "ApiVersion", maximum: 16),
            minimumAPIVersion: try string(v, "MinAPIVersion", maximum: 16),
            operatingSystem: try string(v, "Os", maximum: 32), architecture: try string(v, "Arch", maximum: 32))
        let architecture = try string(i, "Architecture", maximum: 32)
        let expectedArchitecture = ["aarch64": "arm64", "x86_64": "amd64"][architecture] ?? architecture
        guard try string(i, "ServerVersion", maximum: 128) == parsedVersion.engineVersion,
              try string(i, "OSType", maximum: 32) == parsedVersion.operatingSystem,
              expectedArchitecture == parsedVersion.architecture else { throw ManualServiceInventoryError.identityMismatch }
        let result = DockerProducerIdentity(socket: socket, peerPID: peerPID, peerUID: peerUID,
            peerBootID: peerBootID, peerStartSeconds: peerStartSeconds,
            peerStartMicroseconds: peerStartMicroseconds,
            peerExecutable: peerExecutable, providerIdentifier: providerIdentifier,
            daemonID: try string(i, "ID", maximum: 128), version: parsedVersion)
        try result.validate()
        return result
    }

    static func parseDockerContainers(inspections: [Data], expectedIDs: [String]) throws -> [ManualDockerContainerObject] {
        guard inspections.count == expectedIDs.count, inspections.count <= 32,
              Set(expectedIDs).count == expectedIDs.count else { throw ManualServiceInventoryError.duplicateIdentity }
        return try zip(inspections, expectedIDs).map { try parseDockerContainer(inspect: $0.0, expectedID: $0.1) }
            .sorted { $0.id < $1.id }
    }

    static func parseDockerContainer(inspect: Data, expectedID: String) throws -> ManualDockerContainerObject {
        try ManualServiceValueBounds.containerID(expectedID)
        let row = try object(inspect)
        let id = try string(row, "Id", maximum: 64)
        try ManualServiceValueBounds.containerID(id)
        guard id == expectedID else { throw ManualServiceInventoryError.identityMismatch }
        guard let state = row["State"] as? [String: Any],
              try string(state, "Status", maximum: 32) == "exited",
              try !boolean(state, "Running"), try !boolean(state, "Paused"), try !boolean(state, "Restarting") else {
            throw ManualServiceInventoryError.ineligibleState
        }
        guard let mounts = row["Mounts"] as? [Any], mounts.isEmpty,
              let config = row["Config"] as? [String: Any], let host = row["HostConfig"] as? [String: Any],
              host["VolumeDriver"] as? String == "",
              try emptyDeclaration(config, "Volumes", dictionary: true),
              try emptyDeclaration(host, "Binds", dictionary: false),
              try emptyDeclaration(host, "VolumesFrom", dictionary: false),
              try emptyDeclaration(host, "Tmpfs", dictionary: true, required: false),
              try emptyDeclaration(host, "Mounts", dictionary: false, required: false) else {
            throw ManualServiceInventoryError.mountedContainer
        }
        let labels: [String: String]
        if config["Labels"] is NSNull { labels = [:] }
        else if let parsed = config["Labels"] as? [String: String], parsed.count <= 128 { labels = parsed }
        else { throw ManualServiceInventoryError.malformed }
        for (key, value) in labels {
            try ManualServiceValueBounds.string(key, maximum: 256)
            guard value.utf8.count <= 1_024, !value.utf8.contains(0) else { throw ManualServiceInventoryError.capacity }
            guard !ManualServiceValueBounds.isManagedLabel(key) else { throw ManualServiceInventoryError.managedContainer }
        }
        let configuration = try JSONSerialization.data(withJSONObject: ["Config": config, "HostConfig": host], options: [.sortedKeys])
        let result = ManualDockerContainerObject(id: id, name: try string(row, "Name", maximum: 512),
            created: try string(row, "Created", maximum: 128), imageID: try string(row, "Image", maximum: 71),
            writableLayerBytes: try optionalInteger(row, "SizeRw"),
            configurationDigest: Data(SHA256.hash(data: configuration)), labelKeys: labels.keys.sorted())
        try result.validate()
        return result
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let result = BoundedAdapterData.jsonObject(data) as? [String: Any],
              uniqueJSONKeys(data) else { throw ManualServiceInventoryError.malformed }
        return result
    }

    private static func string(_ row: [String: Any], _ key: String, maximum: Int) throws -> String {
        guard let value = row[key] as? String else { throw ManualServiceInventoryError.malformed }
        try ManualServiceValueBounds.string(value, maximum: maximum)
        return value
    }

    private static func boolean(_ row: [String: Any], _ key: String) throws -> Bool {
        guard let value = row[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw ManualServiceInventoryError.malformed
        }
        return value.boolValue
    }

    private static func uuid(_ value: Any?) throws -> UUID {
        guard let raw = value as? String, raw.utf8.count == 36, let id = UUID(uuidString: raw),
              id.uuidString.caseInsensitiveCompare(raw) == .orderedSame else { throw ManualServiceInventoryError.invalidIdentity }
        return id
    }

    private static func emptyDeclaration(_ row: [String: Any], _ key: String,
                                         dictionary: Bool, required: Bool = true) throws -> Bool {
        guard let value = row[key] else {
            if required { throw ManualServiceInventoryError.malformed }
            return true
        }
        if value is NSNull { return true }
        if dictionary { return (value as? [String: Any])?.isEmpty == true }
        return (value as? [Any])?.isEmpty == true
    }

    private static func optionalInteger(_ row: [String: Any], _ key: String) throws -> Int64? {
        guard let value = row[key] else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let integer = Int64(number.stringValue), integer >= 0 else { throw ManualServiceInventoryError.malformed }
        return integer
    }

    /// JSONSerialization overwrites duplicate object keys. Reject them before
    /// trusting identities, state or mount declarations; depth/bytes/UTF-8 and
    /// complete JSON grammar have already been bounded by BoundedAdapterData.
    private static func uniqueJSONKeys(_ data: Data) -> Bool {
        struct Frame { let object: Bool; var expectsKey: Bool; var keys: Set<String> = [] }
        let bytes = Array(data)
        var stack: [Frame] = [], index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 34 {
                let start = index
                index += 1
                var escaped = false
                while index < bytes.count {
                    if escaped { escaped = false }
                    else if bytes[index] == 92 { escaped = true }
                    else if bytes[index] == 34 { break }
                    index += 1
                }
                guard index < bytes.count else { return false }
                if let last = stack.indices.last, stack[last].object, stack[last].expectsKey {
                    let quoted = Data([91] + Array(bytes[start...index]) + [93])
                    guard let values = try? JSONSerialization.jsonObject(with: quoted) as? [String],
                          let key = values.first, stack[last].keys.insert(key).inserted else { return false }
                    stack[last].expectsKey = false
                }
            } else if byte == 123 { stack.append(Frame(object: true, expectsKey: true)) }
            else if byte == 91 { stack.append(Frame(object: false, expectsKey: false)) }
            else if byte == 125 || byte == 93 {
                guard !stack.isEmpty else { return false }; stack.removeLast()
            } else if byte == 44, let last = stack.indices.last, stack[last].object { stack[last].expectsKey = true }
            index += 1
        }
        return stack.isEmpty
    }
}
