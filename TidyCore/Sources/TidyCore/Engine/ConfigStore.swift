import Foundation

/// Loads and saves `TidyConfig` as versioned JSON at
/// `~/Library/Application Support/Tidy/config.json`.
public enum ConfigStore: Sendable {
    public static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("Tidy", isDirectory: true).appendingPathComponent("config.json")
    }

    public static func load(from url: URL? = ConfigStore.defaultURL) -> TidyConfig {
        guard let url, let data = try? Data(contentsOf: url) else {
            return TidyConfig()
        }
        guard let config = try? JSONDecoder().decode(TidyConfig.self, from: data) else {
            return TidyConfig()
        }
        return config
    }

    public static func save(_ config: TidyConfig, to url: URL? = ConfigStore.defaultURL) {
        guard let url else { return }
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
