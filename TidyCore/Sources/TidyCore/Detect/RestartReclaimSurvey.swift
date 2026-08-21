import Foundation

/// Measures the space macOS is holding in swap and VM files: the one
/// category of disk usage that no cleaner can release, because the kernel
/// only lets go of it at boot.
///
/// This is reported, never acted on. There is deliberately no `CleanItem`,
/// no `TargetPath`, and no path from here into a `CleanPlan`: these files
/// belong to the kernel, and the honest thing to tell a user is what is
/// holding the space and that restarting is what returns it.
///
/// `/System/Volumes/VM` and `/private/var/vm` sit on two different volumes
/// (verified by differing `st_dev`), so summing both is correct rather than
/// double-counting a firmlinked pair.
public struct RestartReclaimSurvey: Sendable, Equatable {
    public struct Component: Sendable, Equatable, Identifiable {
        public var id: String { label }
        public let label: String
        public let bytes: Int64
        public let fileCount: Int

        public init(label: String, bytes: Int64, fileCount: Int) {
            self.label = label
            self.bytes = bytes
            self.fileCount = fileCount
        }
    }

    public let components: [Component]
    /// `vm.swapusage.used`: how much is currently paged out. Context only,
    /// and deliberately not the reclaim figure -- this is the part that has
    /// to come back into memory, not the part a restart hands back.
    public let pagedOutBytes: Int64

    public init(components: [Component], pagedOutBytes: Int64) {
        self.components = components
        self.pagedOutBytes = pagedOutBytes
    }

    public var totalBytes: Int64 {
        components.reduce(0) { $0 + $1.bytes }
    }

    public var isEmpty: Bool { components.isEmpty }

    public static let vmDirectories = ["/System/Volumes/VM", "/private/var/vm"]

    public static func current(directories: [String] = vmDirectories) -> RestartReclaimSurvey {
        let fm = FileManager.default
        var buckets: [String: (bytes: Int64, count: Int)] = [:]

        for directory in directories {
            guard let names = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            for name in names {
                let path = directory + "/" + name
                guard let attributes = try? fm.attributesOfItem(atPath: path),
                      (attributes[.type] as? FileAttributeType) == .typeRegular,
                      let size = attributes[.size] as? NSNumber else { continue }

                let label = self.label(forFileNamed: name)
                var bucket = buckets[label] ?? (0, 0)
                bucket.bytes += size.int64Value
                bucket.count += 1
                buckets[label] = bucket
            }
        }

        let components = buckets
            .map { Component(label: $0.key, bytes: $0.value.bytes, fileCount: $0.value.count) }
            .sorted { $0.bytes > $1.bytes }

        return RestartReclaimSurvey(
            components: components,
            pagedOutBytes: SwapStats.current()?.usedBytes ?? 0
        )
    }

    /// Reported as separate lines rather than one figure: a sleep image is
    /// hibernation state and a kernel core reservation is neither swap nor
    /// hibernation, and a restart does not treat the three identically.
    static func label(forFileNamed name: String) -> String {
        if name.hasPrefix("swapfile") { return "Swap files" }
        if name.hasPrefix("sleepimage") { return "Sleep image" }
        if name.hasPrefix("kernelcore") { return "Kernel core reservation" }
        return "Other VM files"
    }
}
