import Foundation
import Testing
@testable import TidyCore

@Suite("Settings workflow") struct SettingsWorkflowTests {
    let p = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let q = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let inactive = SettingID(rawValue: "cleanup.inactiveDays")
    let workers = SettingID(rawValue: "scan.requestedWorkers")
    let roots = SettingID(rawValue: "scope.projectRoots")
    func envelope(_ profile: SavedProfile? = nil, active: UUID? = nil,
                  global: PolicyValues = .init(), revision: UInt64 = 7,
                  projects: [String: PolicyValues] = [:]) -> SettingsEnvelope {
        SettingsEnvelope(schemaVersion: 2, revision: revision,
            config: TidyConfig(schemaVersion: 2),
            preferences: PolicyPreferences(global: global,
                profiles: profile.map { [$0] } ?? [], projects: projects),
            activeProfileID: active)
    }

    @Test func lifecycleExactDeltas() throws {
        let base = envelope(global: .init(fields: [inactive: .integer(60)]))
        let create = try SettingsWorkflow.previewProfile(.create(id: p, name: " Build ",
            values: .init(fields: [workers: .integer(2)])), current: base)
        #expect(create.kind == .create && create.after?.name == "Build")
        #expect(create.delta.profiles == [.insert(create.after!)])
        #expect(!create.delta.touchesActiveProfile && create.activeProfileAfter == nil)
        #expect(create.fieldChanges.map(\.id) == [workers])
        let current = envelope(create.after, global: .init(fields: [inactive: .integer(60)]))
        let replacement = PolicyValues(fields: [workers: .integer(4)])
        let untouched = SavedProfile(id: q, name: "Other", values: .init())
        let direct = try SessionProfiles.update(id: p, values: replacement,
            inherited: current.preferences!.global, in: [untouched, create.after!])
        #expect(direct == [untouched,
            SavedProfile(id: p, name: "Build", values: replacement)])
        let update = try SettingsWorkflow.previewProfile(.update(id: p, values: replacement),
                                                           current: current)
        #expect(update.kind == .update && update.before == create.after)
        #expect(update.after == direct[1] && update.activeProfileAfter == nil)
        #expect(update.delta.profiles == [.update(id: p, base: create.after!, edited: direct[1])])
        #expect(update.fieldChanges.map(\.id) == [workers])
        #expect(update.fieldChanges.first?.oldValue == .integer(2))
        #expect(update.fieldChanges.first?.newValue == .integer(4))
        let factory = try SettingsWorkflow.previewProfile(.createFactory(key: "xcode", id: q,
            name: "Xcode"), current: current)
        #expect(factory.kind == .createFactory && factory.after?.id == q)
        #expect(factory.after?.values.fields.isEmpty == false)
        #expect(factory.activeProfileAfter == nil && !factory.delta.touchesActiveProfile)
        let clone = try SettingsWorkflow.previewProfile(.clone(sourceID: p, newID: q,
                                                                 name: "Clone"), current: current)
        #expect(clone.after?.id == q && clone.after?.values == create.after?.values)
        #expect(clone.activeProfileAfter == nil)
        let rename = try SettingsWorkflow.previewProfile(.rename(id: p, name: "Renamed"),
                                                           current: current)
        #expect(rename.before?.name == "Build" && rename.after?.name == "Renamed")
        #expect(rename.fieldChanges.isEmpty && rename.effect == .none)
        let activate = try SettingsWorkflow.previewProfile(.activate(p), current: current)
        #expect(activate.delta.profiles.isEmpty && activate.delta.touchesActiveProfile)
        #expect(activate.delta.activeProfileEdit == p && activate.effect == .invalidate)
        let active = envelope(create.after, active: p)
        let delete = try SettingsWorkflow.previewProfile(.delete(id: p), current: active)
        #expect(delete.delta.profiles == [.delete(id: p, base: create.after!)])
        #expect(delete.delta.touchesActiveProfile && delete.delta.activeProfileEdit == nil)
        #expect(delete.effect == .invalidate)
    }

    @Test func lifecycleNegatives() throws {
        let profile = SavedProfile(id: p, name: "One", values: .init())
        #expect(throws: SettingsWorkflowError.invalidActivation(q)) {
            _ = try SettingsWorkflow.previewProfile(.activate(q), current: envelope(profile))
        }
        #expect(throws: SessionProfileError.duplicateID(p)) {
            _ = try SettingsWorkflow.previewProfile(.create(id: p, name: "Again",
                values: .init()), current: envelope(profile))
        }
        let lowPower = SettingID(rawValue: "scan.onLowPower")
        let protected = SavedProfile(id: p, name: "Protected",
            values: .init(fields: [lowPower: .choice("pauseAll")]))
        #expect(throws: SessionProfileError.protectionWeakening(lowPower)) {
            _ = try SessionProfiles.update(id: p, values: .init(), inherited: .init(),
                                           in: [protected])
        }
        #expect(throws: SessionProfileError.protectionWeakening(lowPower)) {
            _ = try SettingsWorkflow.previewProfile(.update(id: p, values: .init()),
                                                     current: envelope(protected))
        }
        let equalRemoval = try SessionProfiles.update(id: p, values: .init(),
            inherited: .init(fields: [lowPower: .choice("pauseAll")]), in: [protected])
        #expect(equalRemoval[0].values.fields[lowPower] == nil)
        let strengthened = try SessionProfiles.update(id: p,
            values: .init(fields: [lowPower: .choice("pauseAll")]), inherited: .init(),
            in: [profile])
        #expect(strengthened[0].values.fields[lowPower] == .choice("pauseAll"))
        #expect(throws: SessionProfileError.missingProfile(q)) {
            _ = try SessionProfiles.update(id: q, values: .init(), inherited: .init(),
                                           in: [profile])
        }
        #expect(throws: SessionProfileError.duplicateID(p)) {
            _ = try SessionProfiles.update(id: p, values: .init(), inherited: .init(),
                                           in: [profile, profile])
        }
        let duplicate = SettingsEnvelope(schemaVersion: 2, revision: 7,
            config: TidyConfig(schemaVersion: 2),
            preferences: PolicyPreferences(profiles: [profile, profile]))
        #expect(throws: SettingsWorkflowError.duplicateProfile(p)) {
            _ = try SettingsWorkflow.previewProfile(.activate(nil), current: duplicate)
        }
    }

    @Test func selectiveResetPreservesImmutableState() throws {
        let profile = SavedProfile(id: p, name: "Build",
            values: .init(fields: [workers: .integer(1)]))
        // Project fixtures must use a project-capable field; requestedWorkers is global/profile only.
        let projects = ["local": PolicyValues(fields: [inactive: .integer(30)])]
        let current = envelope(profile, global: .init(fields: [
            inactive: .integer(90), workers: .integer(3)]),
                               projects: projects)
        let preview = try SettingsWorkflow.previewSelectiveReset(.init(
            globalPreferenceIDs: [inactive, workers], profileID: p,
            profileFieldIDs: [workers]), current: current)
        #expect(preview.immutableBoundaries == Set(SettingsResetBoundary.allCases))
        #expect(Set(preview.globalChanges.map(\.id)) == Set([inactive, workers]))
        #expect(preview.profileReset?.changes.map(\.id) == [workers])
        let sameID = try #require(preview.profileReset?.changes.first)
        #expect(sameID.oldValue == .integer(1) && sameID.newValue == nil)
        #expect(sameID.oldSource == .explicit && sameID.newSource == .registryDefault)
        #expect(preview.delta.global.contains(.init(id: inactive,
            baseValue: .integer(90), editedValue: nil)))
        #expect(preview.delta.global.contains(.init(id: workers,
            baseValue: .integer(3), editedValue: nil)))
        #expect(preview.delta.inert.isEmpty && !preview.delta.touchesActiveProfile)
        let applied = try PreferencesDocumentProjection.apply(preview.delta, to: current)
        #expect(applied.envelope.preferences?.global.fields[inactive] == nil)
        #expect(applied.envelope.preferences?.global.fields[workers] == nil)
        #expect(applied.envelope.preferences?.profiles.first?.values.fields[workers] == nil)
        #expect(applied.envelope.preferences?.projects == projects)
        #expect(applied.envelope.config == current.config)
    }

    @Test func resetNegatives() throws {
        let globalRestriction = SettingID(rawValue: "scan.onLowPower")
        let current = envelope(global: .init(fields: [
            inactive: .integer(90), globalRestriction: .choice("pauseAll")]))
        #expect(throws: SettingsWorkflowError.ineligibleGlobalReset(roots)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                globalPreferenceIDs: [roots]), current: current)
        }
        let unknown = SettingID(rawValue: "fixture.unknown")
        #expect(throws: SettingsWorkflowError.ineligibleGlobalReset(unknown)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                globalPreferenceIDs: [unknown]), current: current)
        }
        #expect(throws: SettingsWorkflowError.ineligibleGlobalReset(globalRestriction)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                globalPreferenceIDs: [globalRestriction]), current: current)
        }
        #expect(throws: SettingsWorkflowError.emptyConfirmation) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(), current: current)
        }
        let absentKnown = envelope(global: .init(fields: [globalRestriction: .choice("pauseAll")]))
        #expect(throws: SettingsWorkflowError.ineligibleGlobalReset(inactive)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                globalPreferenceIDs: [inactive]), current: absentKnown)
        }
        #expect(throws: SettingsWorkflowError.profileRequired) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                profileFieldIDs: [workers]), current: current)
        }
        #expect(throws: SettingsWorkflowError.missingProfile(q)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(profileID: q,
                profileFieldIDs: [workers]), current: current)
        }
        let excessive = Set((0...1_000).map {
            SettingID(rawValue: "fixture.reset.\($0)")
        })
        #expect(throws: SettingsWorkflowError.tooManySelectedFields) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(
                globalPreferenceIDs: excessive), current: current)
        }
        let restriction = SettingID(rawValue: "feature.headroom")
        let protected = SavedProfile(id: p, name: "Protected",
            values: .init(fields: [restriction: .bool(false)]))
        #expect(throws: SessionProfileError.restrictionResetRequiresPreview(restriction)) {
            _ = try SettingsWorkflow.previewSelectiveReset(.init(profileID: p,
                profileFieldIDs: [restriction]), current: envelope(protected))
        }
        let optedIn = try SettingsWorkflow.previewSelectiveReset(.init(profileID: p,
            profileFieldIDs: [restriction], includeOwnedProfileRestrictions: true),
            current: envelope(protected))
        #expect(optedIn.profileReset?.changes.map(\.id) == [restriction])
        #expect(SettingsWorkflow.maximumSelectedResetFields == 1_000)
    }

    @Test func importUISummaryIsPublicBoundedAndMinimal() throws {
        let analysisID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let row = SettingsImportRow(scope: .global, profileID: nil, id: "future.safe",
            idDigest: nil, outcome: .inert, value: .bool(true), valueKind: nil,
            valueDigest: nil)
        let analysis = SettingsImportAnalysis(analysisID: analysisID, rows: [row], collisions: [],
            committableImported: .init(), importedInert: [], current: .init())
        let summary = try SettingsImportUISummary(analysis)
        #expect(summary.analysisID == analysisID && summary.rows == [row])
        #expect(Set(Mirror(reflecting: summary).children.compactMap { $0.label }) ==
            Set(["analysisID", "rows", "collisions"]))
        let noID = SettingsImportAnalysis(rows: [], collisions: [], committableImported: .init(),
            importedInert: [], current: .init())
        #expect(throws: SettingsWorkflowError.missingAnalysisID) {
            _ = try SettingsImportUISummary(noID)
        }
        let overRows = SettingsImportAnalysis(analysisID: analysisID,
            rows: Array(repeating: row, count: 1_001), collisions: [],
            committableImported: .init(), importedInert: [], current: .init())
        #expect(throws: SettingsWorkflowError.tooManyImportRows) {
            _ = try SettingsImportUISummary(overRows)
        }
        let collisions = (0...50).map { index in
            ProfileImportCollision(profileID: UUID(uuidString: String(format:
                "90000000-0000-0000-0000-%012d", index))!, localName: "L", importedName: "I")
        }
        let overCollisions = SettingsImportAnalysis(analysisID: analysisID, rows: [],
            collisions: collisions, committableImported: .init(), importedInert: [], current: .init())
        #expect(throws: SettingsWorkflowError.tooManyImportCollisions) {
            _ = try SettingsImportUISummary(overCollisions)
        }
    }

    @Test func exportBoundary() throws {
        var config = TidyConfig(schemaVersion: 2); config.gitRoots = ["/secret/root"]
        let authority = SettingID(rawValue: "maintenance.mode")
        let localIdentity = SettingID(rawValue: "scope.currentProject")
        let inert = InertPortableSetting(scope: .global, profileID: nil,
            id: "future.safe", value: .bool(true), valueKind: nil,
            valueDigest: nil, redacted: false)
        let profile = SavedProfile(id: p, name: "Build",
            values: .init(fields: [workers: .integer(2)]))
        let current = SettingsEnvelope(schemaVersion: 2, revision: 9, config: config,
            preferences: .init(global: .init(fields: [inactive: .integer(90),
                authority: .choice("off"), localIdentity: .choice("private-project")]),
                profiles: [profile], projects: ["local": .init()]), activeProfileID: p,
            inertImports: [inert])
        let text = try #require(String(data:
            SettingsWorkflow.exportPortable(current: current), encoding: .utf8))
        #expect(text.contains("cleanup.inactiveDays"))
        #expect(!text.contains("/secret/root") && !text.contains("activeProfileID"))
        #expect(!text.contains("projects") && !text.contains("TidyConfig"))
        #expect(!text.contains(authority.rawValue) && !text.contains(localIdentity.rawValue))
        #expect(!text.contains("private-project"))
        #expect(text.contains("future.safe"))
    }
}
