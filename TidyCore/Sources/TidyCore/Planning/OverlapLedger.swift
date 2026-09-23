import Foundation

/// Conservative accounting: selecting a covering action excludes overlapping
/// actions rather than pretending an indivisible action can be partially run.
struct OverlapLedger {
    private var resources = Set<ResourceIdentity>()
    private var files: [FileResourceIdentity] = []
    private var nodes = Set<String>()

    mutating func reserve(_ candidate: CleanupCandidate) -> Bool {
        guard candidate.allocation == .exclusiveEstimate else { return false }
        let resource = candidate.record.resource
        guard !resources.contains(resource) else { return false }
        if case .filesystem(let file) = resource {
            let node = "\(file.volumeID):\(file.device):\(file.inode):\(String(describing: file.generation))"
            guard !nodes.contains(node), !files.contains(where: { other in
                other.volumeID == file.volumeID && (
                    PathGuard.isEqualOrDescendant(file.canonicalPath, of: other.canonicalPath)
                    || PathGuard.isEqualOrDescendant(other.canonicalPath, of: file.canonicalPath))
            }) else { return false }
            nodes.insert(node); files.append(file)
        }
        resources.insert(resource)
        return true
    }
}
