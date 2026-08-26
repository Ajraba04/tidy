public enum ReviewStatus: String, Codable, Sendable { case available, noWork, unavailable, blocked }

public struct ActionDescriptor: Sendable {
    public let id: String
    public let status: ReviewStatus
    public let reason: String
    public let requiresPerRunOptIn: Bool
    public init(id: String, status: ReviewStatus, reason: String, requiresPerRunOptIn: Bool) {
        self.id = id; self.status = status; self.reason = reason; self.requiresPerRunOptIn = requiresPerRunOptIn
    }
    public var isSelectable: Bool { status == .available }
}

public struct ActionDiscovery: Sendable {
    public let status: ReviewStatus
    public let reason: String
    public let targets: [TargetPath]
    public init(status: ReviewStatus, reason: String, targets: [TargetPath]) {
        self.status = status; self.reason = reason; self.targets = targets
    }
}
