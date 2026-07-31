/// A single filesystem location a `CleanItem` resolved for the current
/// machine, paired with the label shown in plan and result screens.
public struct TargetPath: Sendable, Hashable {
    public let path: String
    public let label: String

    public init(path: String, label: String? = nil) {
        self.path = path
        self.label = label ?? path
    }
}
