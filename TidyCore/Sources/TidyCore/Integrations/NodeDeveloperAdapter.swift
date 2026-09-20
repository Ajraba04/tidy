import Foundation

public struct NodeDeveloperAdapter: ToolAdapter {
    public static let adapterID = "node.developer"
    public static let contractVersion = "filesystem-v1"
    static let ecosystemID = "node"

    public init() {}

    func inventory(context: ToolAdapterContext) throws -> [DeveloperInventoryEntry] {
        var result: [DeveloperInventoryEntry] = []
        for project in context.projects.records where project.toolchains.contains(.node) {
            if let dependencies = AdapterPaths.child("node_modules", of: project,
                                                      context: context),
               let entry = context.entry(adapterID: Self.adapterID,
                    adapterVersion: Self.contractVersion, path: dependencies,
                    kind: "node-modules", disposition: .manualRisk,
                    reason: "Dependency tree may contain edited or generated local data; no clean state was inferred.") {
                result.append(entry)
            }
            for name in ["dist", "build", ".next", ".turbo"] {
                guard let path = AdapterPaths.child(name, of: project, context: context),
                      let identity = try? ResourcePreflight.captureFile(at: path) else { continue }
                let resourceID = InventoryFilesystem.stableID(
                    adapterID: Self.adapterID, identity: identity)
                let spec = ToolEffectSpec(adapterID: Self.adapterID,
                    adapterVersion: Self.contractVersion, resourceIDs: [resourceID],
                    preflight: .producerOwnershipAndQuiescence,
                    completionProbe: .reviewedLeavesRevalidated,
                    unavailable: "No producer ownership lease or registered filesystem effect exists for Node outputs.")
                if let entry = context.entry(adapterID: Self.adapterID,
                    adapterVersion: Self.contractVersion, path: path,
                    kind: "node-output:\(name)", disposition: .exactManualCandidate,
                    reason: "Regeneratable-looking output remains blocked pending producer proof.",
                    effectSpec: spec) {
                    result.append(entry)
                }
            }
        }
        for relative in [".npm/_cacache", ".cache/yarn", ".pnpm-store"] {
            guard let path = context.knownHomePath(relative),
                  let entry = context.entry(adapterID: Self.adapterID,
                    adapterVersion: Self.contractVersion, path: path,
                    kind: "node-shared-cache", disposition: .reportOnly,
                    reason: "Shared package-cache consumers are not completely mapped.")
            else { continue }
            result.append(entry)
        }
        return result
    }
}
