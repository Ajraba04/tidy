import Foundation

/// APFS container free space — the figure that actually reflects what a
/// snapshot delete or a big cleanup will reclaim, since `df` on the boot
/// volume can under-report until purgeable space and snapshots are
/// accounted for.
public struct ContainerSpaceInfo: Sendable, Equatable {
    public let totalBytes: Int64
    public let freeBytes: Int64

    public static func current(volumePath: String = "/") async -> ContainerSpaceInfo? {
        guard let diskutilPath = ToolLocator.locate("diskutil") else { return nil }
        guard let output = try? await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: diskutilPath),
            arguments: ["info", "-plist", volumePath]
        ), output.succeeded, let data = output.standardOutput.data(using: .utf8) else {
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let free = plist["APFSContainerFree"] as? Int,
              let total = plist["APFSContainerSize"] as? Int
        else {
            return nil
        }

        return ContainerSpaceInfo(totalBytes: Int64(total), freeBytes: Int64(free))
    }
}
