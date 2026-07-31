import Foundation

public struct RankedItem: Sendable, Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    public let bytes: Int64

    public init(path: String, bytes: Int64) {
        self.path = path
        self.bytes = bytes
    }
}

/// Read-only "largest remaining items" scans, ported from the shell
/// script's section 9: two separate top-level rankings (home, then
/// ~/Library) rather than one merged sort (mixing them would double-count
/// the same bytes and misrepresent them as independent), plus single files
/// over 1 GB.
public enum LargestItemsScanner: Sendable {
    /// Immediate children of `$HOME`, filtered the way the script's glob
    /// `$HOME/* $HOME/.[a-z]*` does: every visible entry, plus dot-entries
    /// whose second character is a lowercase letter (catches `.gradle`,
    /// `.npm`, `.cache`, ...) while skipping Apple's capitalized dot-entries
    /// (`.Trash`, `.DS_Store`, `.Spotlight-V100`, ...).
    public static func homeTopLevelEntries(homeDirectory: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: homeDirectory)) ?? []
        return names
            .filter(matchesHomeTopLevelPattern)
            .map { homeDirectory + "/" + $0 }
    }

    public static func libraryEntries(homeDirectory: String) -> [String] {
        let libraryPath = homeDirectory + "/Library"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: libraryPath)) ?? []
        return names.map { libraryPath + "/" + $0 }
    }

    static func matchesHomeTopLevelPattern(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        if first != "." { return true }
        guard let second = name.dropFirst().first else { return false }
        return second.isASCII && second.isLowercase && second.isLetter
    }

    /// Single files at or above `minimumBytes`, walking the whole home
    /// directory but never crossing onto another volume and never entering
    /// the protected iCloud roots.
    public static func filesAtLeast(
        _ minimumBytes: Int64,
        homeDirectory: String,
        protectedRoots: [String],
        limit: Int
    ) -> [RankedItem] {
        let fm = FileManager.default
        let canonicalHome = PathGuard.canonicalize(homeDirectory)
        let canonicalProtectedRoots = protectedRoots.map(PathGuard.canonicalize)
        let homeURL = URL(fileURLWithPath: canonicalHome)

        let rootVolumeID = try? homeURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier

        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .volumeIdentifierKey
        ]
        let keySet = Set(keys)
        guard let enumerator = fm.enumerator(at: homeURL, includingPropertiesForKeys: keys, options: []) else {
            return []
        }

        var results: [RankedItem] = []

        for case let fileURL as URL in enumerator {
            let path = fileURL.path

            if canonicalProtectedRoots.contains(where: { PathGuard.isEqualOrDescendant(path, of: $0) }) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: keySet) else { continue }

            if let childVolumeID = values.volumeIdentifier as AnyObject?,
               let rootVolumeID = rootVolumeID as AnyObject?,
               !childVolumeID.isEqual(rootVolumeID) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }

            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }

            let size = Int64(values.totalFileAllocatedSize ?? 0)
            if size >= minimumBytes {
                results.append(RankedItem(path: path, bytes: size))
            }
        }

        return Array(results.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }
}
