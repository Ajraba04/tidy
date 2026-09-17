import Foundation

public struct DiagnosticExportInput: Sendable {
    public let settings: SettingsEnvelope
    public let cosmeticRedactionEnabled: Bool
    public let credentials: [String]
    public let cookies: [String]
    public let environment: [String: String]
    public let argv: [String]
    public let remotes: [String]
    public let personalPaths: [String]

    public init(settings: SettingsEnvelope, cosmeticRedactionEnabled: Bool,
                credentials: [String] = [], cookies: [String] = [],
                environment: [String: String] = [:], argv: [String] = [],
                remotes: [String] = [], personalPaths: [String] = []) {
        self.settings = settings
        self.cosmeticRedactionEnabled = cosmeticRedactionEnabled
        self.credentials = credentials
        self.cookies = cookies
        self.environment = environment
        self.argv = argv
        self.remotes = remotes
        self.personalPaths = personalPaths
    }
}

public struct DiagnosticExportRenderings: Equatable, Sendable {
    public let primaryCandidate: Data
    public let temporaryCandidate: Data
    public let backupCandidate: Data
}

/// Produces metadata-only diagnostic bytes. Sensitive classes are absent
/// from the encoded payload by construction, so disabling cosmetic
/// redaction can never include credentials, cookies, environment, argv,
/// remotes, settings values, profile names, or personal path identities.
public enum DiagnosticExportRenderer {
    private struct Payload: Codable {
        let schemaVersion: Int
        let settingsRevision: UInt64
        let profileCount: Int
        let inertSettingCount: Int
        let cosmeticRedactionEnabled: Bool
        let immutablePrivacyExclusions: [String]
    }

    public static func render(_ input: DiagnosticExportInput) throws
        -> DiagnosticExportRenderings {
        let payload = Payload(schemaVersion: input.settings.schemaVersion,
            settingsRevision: input.settings.revision,
            profileCount: input.settings.preferences?.profiles.count ?? 0,
            inertSettingCount: input.settings.inertImports.count,
            cosmeticRedactionEnabled: input.cosmeticRedactionEnabled,
            immutablePrivacyExclusions: [
                "argv", "cookies", "credentials", "environment", "personalPathIdentity",
                "portableSettingValues", "profileNames", "remotes"
            ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        var bytes = try encoder.encode(payload)
        bytes.append(0x0A)
        return DiagnosticExportRenderings(primaryCandidate: bytes,
            temporaryCandidate: bytes, backupCandidate: bytes)
    }
}
