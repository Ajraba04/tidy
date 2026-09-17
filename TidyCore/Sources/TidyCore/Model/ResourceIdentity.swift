import Foundation
public enum ResourceIdentity: Hashable, Sendable {
    case filesystem(FileResourceIdentity)
    case simulator(udid: UUID, runtimeID: String)
    case snapshot(volumeID: UUID, exactSnapshotID: String)
}
public struct FileResourceIdentity: Hashable, Sendable {
    public let volumeID: UUID
    public let device: UInt64
    public let inode: UInt64
    public let generation: UInt64?
    public let canonicalPath: String
    public let mode: UInt32
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let parentChain: [FileNodeIdentity]
    public let manifest: ReviewedManifestIdentity?
}
public struct FileNodeIdentity: Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let generation: UInt64?
    public let mode: UInt32
}
public struct ReviewedManifestIdentity: Hashable, Sendable {
    public let schemaVersion: UInt32
    public let digest: Data
    public let protectionDigest: Data
    public let batchIDs: [UUID]
    public let nodeCount: Int
    public let encodedBytes: Int
}
