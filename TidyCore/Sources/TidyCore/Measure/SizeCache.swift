import Foundation

/// Persists measured directory sizes keyed by path and modification time, so
/// a size that has not changed since the last scan does not need re-walking.
public struct SizeCache: Sendable {
    struct Entry: Codable, Sendable {
        let bytes: Int64
        let modifiedAt: TimeInterval
    }

    private var entries: [String: Entry]
    public let fileURL: URL?

    public init(fileURL: URL? = SizeCache.defaultURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = [:]
        }
    }

    public static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("Tidy", isDirectory: true).appendingPathComponent("sizecache.json")
    }

    public func cachedBytes(forPath path: String, modifiedAt: TimeInterval) -> Int64? {
        guard let entry = entries[path], entry.modifiedAt == modifiedAt else { return nil }
        return entry.bytes
    }

    public mutating func store(bytes: Int64, forPath path: String, modifiedAt: TimeInterval) {
        entries[path] = Entry(bytes: bytes, modifiedAt: modifiedAt)
    }

    public func save() {
        guard let fileURL else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
