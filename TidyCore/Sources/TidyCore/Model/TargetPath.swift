/// A single location or identifier a `CleanItem` resolved for the current
/// machine, paired with the label shown in plan and result screens.
public struct TargetPath: Sendable, Hashable {
    public let path: String
    public let label: String
    /// When true (the default), `path` is a real filesystem path and
    /// `CleanEngine` runs it through `PathGuard` both when building the
    /// plan and again immediately before acting on it. A few custom
    /// actions key off something else (a simulator UDID, a fixed marker
    /// string) and set this to false so that opaque identifier is never
    /// mistaken for a path to validate (or, worse, rejected because it
    /// happens to collide with a guarded case like the home directory).
    public let isFilesystemPath: Bool

    public init(path: String, label: String? = nil, isFilesystemPath: Bool = true) {
        self.path = path
        self.label = label ?? path
        self.isFilesystemPath = isFilesystemPath
    }
}
