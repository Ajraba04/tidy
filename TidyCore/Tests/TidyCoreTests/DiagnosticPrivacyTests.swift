import Foundation
import Testing
@testable import TidyCore

@Suite("Diagnostic privacy")
struct DiagnosticPrivacyTests {
    private func withArtifactDirectory(_ body: (URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("Tidy-Diagnostic-Privacy-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        try body(directory)
    }

    @Test("every rendered artifact candidate excludes immutable sensitive classes even with cosmetic redaction off")
    func immutableExclusionsApplyToEveryArtifact() throws {
        let sentinels = [
            "credential-SENTINEL", "cookie-SENTINEL", "environment-SENTINEL",
            "argv-SENTINEL", "remote-SENTINEL", "/Users/personal-SENTINEL"
        ]
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 41,
            config: TidyConfig(schemaVersion: 2, gitRoots: [sentinels[5]]),
            preferences: .init(profiles: [SavedProfile(id: UUID(),
                name: "Safe profile label", values: .init())]))
        let artifacts = try DiagnosticExportRenderer.render(.init(settings: envelope,
            cosmeticRedactionEnabled: false, credentials: [sentinels[0]],
            cookies: [sentinels[1]], environment: ["TOKEN": sentinels[2]],
            argv: [sentinels[3]], remotes: [sentinels[4]],
            personalPaths: [sentinels[5]]))

        for bytes in [artifacts.primaryCandidate, artifacts.temporaryCandidate,
                      artifacts.backupCandidate] {
            let text = String(decoding: bytes, as: UTF8.self)
            for sentinel in sentinels { #expect(!text.contains(sentinel)) }
            let object = try #require(JSONSerialization.jsonObject(with: bytes)
                as? [String: Any])
            #expect((object["settingsRevision"] as? NSNumber)?.uint64Value == 41)
        }
    }

    @Test("primary temporary and backup renderer outputs remain private after disk materialization")
    func diskMaterializedArtifactCandidatesExcludeEveryForbiddenSentinel() throws {
        let sentinels = [
            "credential-DISK-SENTINEL", "cookie-DISK-SENTINEL",
            "environment-DISK-SENTINEL", "argv-DISK-SENTINEL",
            "remote-DISK-SENTINEL", "/Users/personal-DISK-SENTINEL"
        ]
        let settingsValue = "setting-value-DISK-SENTINEL"
        let profileName = "profile-name-DISK-SENTINEL"
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 73,
            config: TidyConfig(schemaVersion: 2, gitRoots: [sentinels[5]]),
            preferences: .init(global: .init(fields: [
                SettingID(rawValue: "ui.units"): .choice(settingsValue)
            ]), profiles: [SavedProfile(id: UUID(), name: profileName, values: .init())]))
        let rendered = try DiagnosticExportRenderer.render(.init(settings: envelope,
            cosmeticRedactionEnabled: false, credentials: [sentinels[0]],
            cookies: [sentinels[1]], environment: ["TOKEN": sentinels[2]],
            argv: [sentinels[3]], remotes: [sentinels[4]], personalPaths: [sentinels[5]]))

        try withArtifactDirectory { directory in
            let candidates = [
                ("tidy-diagnostic.json", rendered.primaryCandidate),
                (".tidy-diagnostic.json.temporary", rendered.temporaryCandidate),
                ("tidy-diagnostic.json.backup", rendered.backupCandidate)
            ]
            for (name, candidate) in candidates {
                let url = directory.appendingPathComponent(name)
                try candidate.write(to: url, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                      ofItemAtPath: url.path)
                let diskBytes = try Data(contentsOf: url)
                #expect(diskBytes == candidate)
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
                let text = String(decoding: diskBytes, as: UTF8.self)
                for forbidden in sentinels + [settingsValue, profileName] {
                    #expect(!text.contains(forbidden))
                }
            }
        }
    }

    @Test("diagnostic artifacts never serialize portable setting values or profile names")
    func valuesAndNamesAreStructurallyExcluded() throws {
        let secret = "profile-name-SENTINEL"
        let id = SettingID(rawValue: "future.fixture")
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 2,
            config: TidyConfig(schemaVersion: 2),
            preferences: .init(global: .init(fields: [id: .choice(secret)]),
                profiles: [SavedProfile(id: UUID(), name: secret, values: .init())]))
        let bytes = try DiagnosticExportRenderer.render(.init(settings: envelope,
            cosmeticRedactionEnabled: false)).primaryCandidate
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains(secret))
        let object = try #require(JSONSerialization.jsonObject(with: bytes)
            as? [String: Any])
        #expect((object["profileCount"] as? NSNumber)?.intValue == 1)
    }
}
