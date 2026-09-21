import Foundation

/// Applies retention before overlap selection; withheld newer artifacts cannot
/// accidentally become replacement work when a user removes an older item.
enum CandidateWorkingSet {
    private struct Group: Hashable { let owner: String; let catalog: String }

    static func protectedReasons(_ candidates: [CleanupCandidate], policy: EffectivePolicy, now: Date)
        -> [String: String] {
        var result: [String: String] = [:]
        let warmCount = Int(max(0, min(50, integer(policy, "cleanup.warmProjectCount") ?? 5)))
        var activity: [String: Date] = [:]
        for candidate in candidates {
            guard let date = candidate.lastActivityAt, date.timeIntervalSince1970.isFinite else { continue }
            for owner in candidate.record.ownerIDs {
                activity[owner] = max(activity[owner] ?? .distantPast, date)
            }
        }
        let warm = Set(activity.keys.sorted {
            if activity[$0] != activity[$1] { return activity[$0]! > activity[$1]! }
            return $0 < $1
        }.prefix(warmCount))
        var artifacts: [Group: [CleanupCandidate]] = [:]
        for candidate in candidates {
            if !candidate.record.ownerIDs.isDisjoint(with: warm) {
                result[candidate.record.id] = "Resource belongs to a project retained by the warm-project limit."
            }
            guard case .projectArtifact(let createdAt) = candidate.artifactRetention else { continue }
            guard retentionCount(policy, catalog: candidate.catalogID) > 0 else { continue }
            guard !candidate.record.ownerIDs.isEmpty else {
                result[candidate.record.id] = "Artifact ownership is unknown; recent-artifact retention cannot be established."
                continue
            }
            guard let createdAt, createdAt.timeIntervalSince1970.isFinite, createdAt <= now else {
                result[candidate.record.id] = "Artifact creation time is unknown or invalid; retained conservatively."
                continue
            }
            for owner in candidate.record.ownerIDs {
                artifacts[Group(owner: owner, catalog: candidate.catalogID), default: []].append(candidate)
            }
        }
        for (group, items) in artifacts {
            let count = retentionCount(policy, catalog: group.catalog)
            let sorted = items.sorted {
                guard case .projectArtifact(let left?) = $0.artifactRetention,
                      case .projectArtifact(let right?) = $1.artifactRetention else { return false }
                if left != right { return left > right }
                return $0.record.id < $1.record.id
            }
            var retained = Set<ResourceKey>()
            for candidate in sorted {
                let key = ResourceKey(candidate.record.resource)
                guard !retained.contains(key) else { continue }
                guard retained.count < count else { break }
                retained.insert(key)
                if result[candidate.record.id] == nil {
                    result[candidate.record.id] = "One of the newest artifacts retained for its mapped project."
                }
            }
        }
        let retainedKeys = Set(candidates.filter { result[$0.record.id] != nil }
            .map { ResourceKey($0.record.resource) })
        // Include every observed alias before indexing paths, so enclosing
        // actions cannot remove a retained inode through another name.
        let protected = ProtectedResources(candidates.filter {
            retainedKeys.contains(ResourceKey($0.record.resource))
        })
        for candidate in candidates where result[candidate.record.id] == nil {
            if protected.overlaps(candidate.record.resource) {
                result[candidate.record.id] = "This action overlaps a retained project resource or artifact."
            }
        }
        return result
    }

    private enum ResourceKey: Hashable {
        case file(UUID, UInt64, UInt64)
        case other(ResourceIdentity)
        init(_ resource: ResourceIdentity) {
            if case .filesystem(let file) = resource {
                self = .file(file.volumeID, file.device, file.inode)
            } else { self = .other(resource) }
        }
    }

    private struct ProtectedResources {
        let keys: Set<ResourceKey>
        let paths: [UUID: Set<String>]
        let ordered: [UUID: [String]]
        init(_ candidates: [CleanupCandidate]) {
            keys = Set(candidates.map { ResourceKey($0.record.resource) })
            var paths: [UUID: Set<String>] = [:]
            for candidate in candidates {
                if case .filesystem(let file) = candidate.record.resource {
                    paths[file.volumeID, default: []].insert(file.canonicalPath)
                }
            }
            self.paths = paths
            ordered = paths.mapValues { $0.sorted() }
        }
        func overlaps(_ resource: ResourceIdentity) -> Bool {
            if keys.contains(ResourceKey(resource)) { return true }
            guard case .filesystem(let file) = resource,
                  let volumePaths = paths[file.volumeID],
                  let sorted = ordered[file.volumeID] else { return false }
            var ancestor = file.canonicalPath
            while true {
                if volumePaths.contains(ancestor) { return true }
                guard ancestor != "/", let slash = ancestor.lastIndex(of: "/") else { break }
                ancestor = slash == ancestor.startIndex ? "/" : String(ancestor[..<slash])
            }
            let prefix = file.canonicalPath == "/" ? "/" : file.canonicalPath + "/"
            var lower = 0, upper = sorted.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if sorted[middle] < prefix { lower = middle + 1 } else { upper = middle }
            }
            return lower < sorted.count && sorted[lower].hasPrefix(prefix)
        }
    }

    private static func retentionCount(_ policy: EffectivePolicy, catalog: String) -> Int {
        Int(max(0, min(100, integer(policy, "item.\(catalog).retainRecentArtifacts")
            ?? integer(policy, "cleanup.retainRecentArtifacts") ?? 2)))
    }

    private static func integer(_ policy: EffectivePolicy, _ raw: String) -> Int64? {
        guard case .stored(.integer(let value))? = policy.fields[.init(rawValue: raw)]?.value else { return nil }
        return value
    }
}
