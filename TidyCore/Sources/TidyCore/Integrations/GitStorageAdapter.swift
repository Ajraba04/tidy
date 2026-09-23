import Darwin
import Foundation

public struct GitStorageAdapter: ToolAdapter {
    public static let adapterID = "git.storage"
    public static let contractVersion = "metadata-v1"
    static let ecosystemID = "git"

    public init() {}

    func inventory(context: ToolAdapterContext) throws -> [DeveloperInventoryEntry] {
        var ownersByCommon: [FileResourceIdentity: Set<String>] = [:]
        for project in context.projects.records {
            guard let common = project.git?.commonDirectoryIdentity else { continue }
            ownersByCommon[common, default: []].insert(project.id)
        }
        var result: [DeveloperInventoryEntry] = []
        for (common, owners) in ownersByCommon {
            guard context.authorizes(common.canonicalPath) else { continue }
            let lockPath = common.canonicalPath + "/index.lock"
            var lockMetadata = stat()
            let lockPresent = lstat(lockPath, &lockMetadata) == 0
            let reason = lockPresent
                ? "Git lock is present and its owner is unknown; no maintenance or lock removal is permitted."
                : "Common Git storage is shared; hook/config effects and complete worktree owners are unknown."
            let id = InventoryFilesystem.stableID(adapterID: Self.adapterID, identity: common)
            let size = context.budget.measure(identity: common) {
                InventoryFilesystem.allocatedBytes(path: common.canonicalPath,
                    budget: context.budget, authorizes: { context.authorizes($0) })
            }
            let record = InventoryRecord(id: id, adapterID: Self.adapterID,
                adapterVersion: Self.contractVersion, resource: .filesystem(common),
                ownerIDs: owners, scopeID: context.scopeID,
                kind: "git-common-storage", capability: .inventoryOnly,
                allocatedBytes: size.bytes, confidence: size.complete ? .partial : .unknown,
                activity: .unknown, observedAt: context.now, reason: reason)
            result.append(.init(record: record, disposition: .reportOnly,
                                effectSpec: nil))
        }
        return result
    }
}
