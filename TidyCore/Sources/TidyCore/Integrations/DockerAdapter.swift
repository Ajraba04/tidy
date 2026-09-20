import Foundation

public enum DockerObjectKind: String, Equatable, Sendable {
    case image, container, volume, buildCache
}

public struct DockerObjectInventory: Equatable, Sendable {
    public let id: String
    public let kind: DockerObjectKind
    public let state: String?
    public let referenceCount: Int?
    public let hasWritableData: Bool?
}

public struct DockerAdapter: ToolAdapter {
    public static let adapterID = "docker.local"
    public static let contractVersion = "fixture-json-v1"
    static let ecosystemID = "docker"

    public init() {}

    public static func parseObjectList(_ data: Data) -> [DockerObjectInventory]? {
        guard let rows = BoundedAdapterData.jsonObject(data) as? [[String: Any]],
              rows.count <= 10_000 else { return nil }
        var result: [DockerObjectInventory] = []
        for row in rows {
            guard let rawID = (row["id"] ?? row["ID"]) as? String else { return nil }
            let id = rawID.hasPrefix("sha256:") ? String(rawID.dropFirst(7)) : rawID
            guard id.utf8.count <= 128,
                  let rawKind = row["kind"] as? String,
                  let kind = DockerObjectKind(rawValue: rawKind) else { return nil }
            result.append(DockerObjectInventory(id: id, kind: kind,
                state: (row["state"] ?? row["State"]) as? String,
                referenceCount: (row["referenceCount"] as? NSNumber)?.intValue,
                hasWritableData: row["hasWritableData"] as? Bool))
        }
        return result
    }

    public static func inventoryEntries(objects: [DockerObjectInventory],
                                        approval: DockerReadApproval,
                                        scopeID: String,
                                        observedAt: Date = Date()) -> [DeveloperInventoryEntry] {
        objects.map { object in
            let running = object.kind == .container && object.state?.lowercased() == "running"
            let record = InventoryRecord(id: "docker-\(object.kind.rawValue)-\(object.id)",
                adapterID: adapterID, adapterVersion: contractVersion,
                resource: .localService(adapterID: adapterID,
                    exactObjectID: "\(object.kind.rawValue):\(object.id)",
                    endpoint: approval.socket), ownerIDs: [], scopeID: scopeID,
                kind: "docker-\(object.kind.rawValue)", capability: .inventoryOnly,
                allocatedBytes: nil, confidence: .partial,
                activity: running ? .running : .unknown, observedAt: observedAt,
                reason: "Exact daemon object identity; references, allocation, or terminal proof may be incomplete.")
            let effect = effectSpec(object: object, endpoint: approval.endpoint,
                                    endpointIdentity: approval.socket)
            return DeveloperInventoryEntry(record: record,
                disposition: effect == nil ? .reportOnly : .exactManualCandidate,
                effectSpec: effect)
        }
    }

    public static func effectSpec(object: DockerObjectInventory,
                                  endpoint: String,
                                  endpointIdentity: LocalSocketApproval? = nil,
                                  acknowledgedContainerDataLoss: Bool = false)
        -> ToolEffectSpec? {
        guard object.id.count == 64,
              object.id.allSatisfy({ $0.isHexDigit }),
              LocalEndpointGuard.permitsLocalEndpointSyntax(endpoint),
              let endpointIdentity,
              "unix://" + endpointIdentity.canonicalPath == endpoint else { return nil }
        let noun: String
        switch object.kind {
        case .image:
            guard object.referenceCount == 0 else { return nil }
            noun = "image"
        case .container:
            guard object.state == "stopped",
                  object.hasWritableData != true || acknowledgedContainerDataLoss else { return nil }
            noun = "container"
        case .volume, .buildCache:
            return nil
        }
        return ToolEffectSpec(adapterID: adapterID, adapterVersion: contractVersion,
            resourceIDs: [object.id],
            exactArgv: ["--host", endpoint, noun, "rm", object.id],
            endpointIdentity: endpointIdentity,
            preflight: .exactDockerIdentityStateAndReferences,
            completionProbe: .dockerObjectAbsentByID,
            unavailable: "Docker mutation dispatch and terminal proof are not registered; no daemon call is permitted.")
    }

    func inventory(context: ToolAdapterContext) throws -> [DeveloperInventoryEntry] {
        let candidates = [
            context.environment.path(".colima"),
            context.environment.path("Library/Containers/com.docker.docker/Data/vms")
        ]
        return AdapterPaths.existing(candidates, context: context).compactMap { path in
            context.entry(adapterID: Self.adapterID, adapterVersion: Self.contractVersion,
                path: path, kind: path.contains("colima") ? "docker-vm" : "docker-data",
                disposition: .reportOnly,
                reason: "Local Docker/VM storage inventory only; daemon endpoint authority was not supplied.")
        }
    }
}
