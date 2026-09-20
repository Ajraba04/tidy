import Foundation

public struct AndroidAVDInventory: Equatable, Sendable {
    public let id: String
    public let displayName: String?
    public let declaredPath: String?
    public let runtimeInstanceToken: String?
}

public struct AndroidDeveloperAdapter: ToolAdapter {
    public static let adapterID = "android.developer"
    public static let contractVersion = "avd-ini-v1"
    static let ecosystemID = "android"

    public init() {}

    public static func parseAVDINI(_ data: Data) -> AndroidAVDInventory? {
        guard let text = BoundedAdapterData.utf8(data) else { return nil }
        var fields: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else { return nil }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            guard !key.isEmpty, key.utf8.count <= 128, value.utf8.count <= 4_096,
                  fields.updateValue(value, forKey: key) == nil else { return nil }
        }
        guard let id = fields["avd.ini.displayname"] ?? fields["target"], !id.isEmpty else {
            return nil
        }
        return AndroidAVDInventory(id: id, displayName: fields["avd.ini.displayname"],
            declaredPath: fields["path"], runtimeInstanceToken: fields["runtime.instanceToken"])
    }

    func inventory(context: ToolAdapterContext) throws -> [DeveloperInventoryEntry] {
        var result: [DeveloperInventoryEntry] = []
        for project in context.projects.records where project.toolchains.contains(.gradle) {
            for name in ["build", ".gradle"] {
                guard let path = AdapterPaths.child(name, of: project, context: context),
                      let entry = context.entry(adapterID: Self.adapterID,
                        adapterVersion: Self.contractVersion, path: path,
                        kind: "android-project-\(name)", disposition: .reportOnly,
                        reason: "Project-local Gradle data; active version and producer state are unknown.")
                else { continue }
                result.append(entry)
            }
        }
        for relative in [".android/avd", ".gradle/caches", "Library/Android/sdk"] {
            guard let path = context.knownHomePath(relative),
                  let entry = context.entry(adapterID: Self.adapterID,
                    adapterVersion: Self.contractVersion, path: path,
                    kind: "android:\(relative)", disposition: .reportOnly,
                    reason: "SDK, AVD, and global Gradle data are inventory-only without a supported runtime identity protocol.")
            else { continue }
            result.append(entry)
        }
        return result
    }
}
