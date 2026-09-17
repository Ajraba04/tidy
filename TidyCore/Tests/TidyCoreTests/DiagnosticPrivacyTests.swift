import Foundation
import Testing
@testable import TidyCore

@Suite("Diagnostic privacy")
struct DiagnosticPrivacyTests {
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
