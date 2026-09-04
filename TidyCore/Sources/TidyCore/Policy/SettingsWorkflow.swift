import Foundation

public enum SettingsProfileWorkflowRequest: Equatable, Sendable {
    case create(id: UUID, name: String, values: PolicyValues)
    case createFactory(key: String, id: UUID, name: String)
    case clone(sourceID: UUID, newID: UUID, name: String)
    case update(id: UUID, values: PolicyValues)
    case rename(id: UUID, name: String)
    case delete(id: UUID)
    case activate(UUID?)
}

public enum SettingsProfileWorkflowKind: String, Equatable, Sendable {
    case create, createFactory, clone, update, rename, delete, activate, deactivate
}

public struct SettingsProfileWorkflowPreview: Equatable, Sendable {
    public let kind: SettingsProfileWorkflowKind
    public let baseRevision: UInt64
    public let profileID: UUID?
    public let before: SavedProfile?
    public let after: SavedProfile?
    public let activeProfileBefore: UUID?
    public let activeProfileAfter: UUID?
    public let fieldChanges: [ProfileFieldDiff]
    public let effect: AuthorityEffect
    public let delta: PreferencesDocumentDelta
}

public enum SettingsResetBoundary: String, CaseIterable, Equatable, Hashable, Sendable {
    case mandatoryJournal, appSupportRoot, projects, globalRestrictions
    case localIdentities, authority, inertQuarantine
}

public struct SettingsSelectiveResetRequest: Equatable, Sendable {
    public let globalPreferenceIDs: Set<SettingID>
    public let profileID: UUID?
    public let profileFieldIDs: Set<SettingID>
    public let includeOwnedProfileRestrictions: Bool

    public init(globalPreferenceIDs: Set<SettingID> = [], profileID: UUID? = nil,
                profileFieldIDs: Set<SettingID> = [],
                includeOwnedProfileRestrictions: Bool = false) {
        self.globalPreferenceIDs = globalPreferenceIDs
        self.profileID = profileID
        self.profileFieldIDs = profileFieldIDs
        self.includeOwnedProfileRestrictions = includeOwnedProfileRestrictions
    }
}

public struct SettingsSelectiveResetPreview: Equatable, Sendable {
    public let baseRevision: UInt64
    public let globalChanges: [ProfileFieldDiff]
    public let profileReset: ProfileResetPreview?
    public let immutableBoundaries: Set<SettingsResetBoundary>
    public let effect: AuthorityEffect
    public let delta: PreferencesDocumentDelta
}

public struct SettingsImportUISummary: Equatable, Sendable {
    public let analysisID: SettingsImportAnalysisID
    public let rows: [SettingsImportRow]
    public let collisions: [ProfileImportCollision]

    public init(_ analysis: SettingsImportAnalysis) throws {
        guard let analysisID = analysis.analysisID else {
            throw SettingsWorkflowError.missingAnalysisID
        }
        guard analysis.rows.count <= SettingsWorkflow.maximumPresentedImportRows else {
            throw SettingsWorkflowError.tooManyImportRows
        }
        guard analysis.collisions.count <= SettingsWorkflow.maximumPresentedImportCollisions else {
            throw SettingsWorkflowError.tooManyImportCollisions
        }
        self.analysisID = analysisID
        self.rows = analysis.rows
        self.collisions = analysis.collisions
    }
}

public enum SettingsWorkflowError: Error, Equatable, Sendable {
    case missingProfile(UUID), duplicateProfile(UUID), invalidActivation(UUID)
    case ineligibleGlobalReset(SettingID), profileRequired, emptyConfirmation
    case tooManySelectedFields, missingAnalysisID, tooManyImportRows
    case tooManyImportCollisions, unsupportedAuthority
}

public enum SettingsWorkflow {
    public static let maximumSelectedResetFields = 1_000
    public static let maximumPresentedImportRows = 1_000
    public static let maximumPresentedImportCollisions = 50
    public static let immutableResetBoundaries = Set(SettingsResetBoundary.allCases)

    public static func previewProfile(_ request: SettingsProfileWorkflowRequest,
                                      current: SettingsEnvelope) throws
        -> SettingsProfileWorkflowPreview {
        let preferences = current.preferences ?? PolicyPreferences()
        try rejectDuplicateProfiles(preferences.profiles)
        let inherited = preferences.global
        let beforeProfiles = preferences.profiles
        var afterProfiles = beforeProfiles
        var profileID: UUID?
        var before: SavedProfile?
        var after: SavedProfile?
        var changes: [ProfileFieldDiff] = []
        var profileEdits: [ProfileDocumentEdit] = []
        var touchesActive = false
        var activeAfter = current.activeProfileID
        let kind: SettingsProfileWorkflowKind

        switch request {
        case .create(let id, let name, let values):
            kind = .create; profileID = id
            afterProfiles = try SessionProfiles.create(id: id, name: name, values: values,
                inherited: inherited, in: beforeProfiles)
            after = afterProfiles.first { $0.id == id }
            if let after {
                let empty = SavedProfile(id: id, name: after.name, values: .init())
                changes = try SessionProfiles.diff(base: empty, candidate: after,
                                                   inherited: inherited)
                profileEdits = [.insert(after)]
            }
        case .createFactory(let key, let id, let name):
            kind = .createFactory; profileID = id
            afterProfiles = try SessionProfiles.createFactory(key: key, id: id, name: name,
                inherited: inherited, in: beforeProfiles)
            after = afterProfiles.first { $0.id == id }
            if let after {
                let empty = SavedProfile(id: id, name: after.name, values: .init())
                changes = try SessionProfiles.diff(base: empty, candidate: after,
                                                   inherited: inherited)
                profileEdits = [.insert(after)]
            }
        case .clone(let sourceID, let newID, let name):
            kind = .clone; profileID = newID
            afterProfiles = try SessionProfiles.clone(sourceID: sourceID, newID: newID,
                name: name, inherited: inherited, in: beforeProfiles)
            after = afterProfiles.first { $0.id == newID }
            if let after {
                let empty = SavedProfile(id: newID, name: after.name, values: .init())
                changes = try SessionProfiles.diff(base: empty, candidate: after,
                                                   inherited: inherited)
                profileEdits = [.insert(after)]
            }
        case .update(let id, let values):
            kind = .update; profileID = id
            before = beforeProfiles.first { $0.id == id }
            afterProfiles = try SessionProfiles.update(id: id, values: values,
                inherited: inherited, in: beforeProfiles)
            after = afterProfiles.first { $0.id == id }
            if let before, let after {
                changes = try SessionProfiles.diff(base: before, candidate: after,
                                                   inherited: inherited)
                profileEdits = [.update(id: id, base: before, edited: after)]
            }
        case .rename(let id, let name):
            kind = .rename; profileID = id
            before = beforeProfiles.first { $0.id == id }
            afterProfiles = try SessionProfiles.rename(id: id, name: name,
                inherited: inherited, in: beforeProfiles)
            after = afterProfiles.first { $0.id == id }
            if let before, let after {
                profileEdits = [.update(id: id, base: before, edited: after)]
            }
        case .delete(let id):
            kind = .delete; profileID = id
            before = beforeProfiles.first { $0.id == id }
            afterProfiles = try SessionProfiles.delete(id: id, inherited: inherited,
                                                       in: beforeProfiles)
            if let before {
                let empty = SavedProfile(id: id, name: before.name, values: .init())
                changes = try SessionProfiles.diff(base: before, candidate: empty,
                                                   inherited: inherited)
                profileEdits = [.delete(id: id, base: before)]
            }
            if current.activeProfileID == id {
                touchesActive = true; activeAfter = nil
            }
        case .activate(let selected):
            kind = selected == nil ? .deactivate : .activate
            if let selected,
               !beforeProfiles.contains(where: { $0.id == selected }) {
                throw SettingsWorkflowError.invalidActivation(selected)
            }
            profileID = selected ?? current.activeProfileID
            touchesActive = true; activeAfter = selected
        }

        let delta = PreferencesDocumentDelta(baseRevision: current.revision,
            profiles: profileEdits, activeProfileBase: current.activeProfileID,
            activeProfileEdit: activeAfter, touchesActiveProfile: touchesActive)
        let applied = try apply(delta, current: current)
        return SettingsProfileWorkflowPreview(kind: kind, baseRevision: current.revision,
            profileID: profileID, before: before, after: after,
            activeProfileBefore: current.activeProfileID,
            activeProfileAfter: applied.envelope.activeProfileID,
            fieldChanges: changes, effect: applied.effect, delta: delta)
    }

    public static func previewSelectiveReset(_ request: SettingsSelectiveResetRequest,
                                             current: SettingsEnvelope) throws
        -> SettingsSelectiveResetPreview {
        let selectedCount = request.globalPreferenceIDs.union(request.profileFieldIDs).count
        guard selectedCount <= maximumSelectedResetFields else {
            throw SettingsWorkflowError.tooManySelectedFields
        }
        guard selectedCount > 0 else { throw SettingsWorkflowError.emptyConfirmation }
        guard request.profileFieldIDs.isEmpty || request.profileID != nil else {
            throw SettingsWorkflowError.profileRequired
        }
        let preferences = current.preferences ?? PolicyPreferences()
        try rejectDuplicateProfiles(preferences.profiles)
        var globalEdits: [PreferenceFieldEdit] = []
        var globalChanges: [ProfileFieldDiff] = []
        var candidateGlobal = preferences.global
        for id in request.globalPreferenceIDs.sorted(by: utf8Less) {
            guard let value = preferences.global.fields[id],
                  let definition = PolicyValidator.definition(for: id),
                  definition.layers.contains(.global),
                  definition.resolution == .preference,
                  definition.effect != .consent,
                  (try? PortableSettingPolicy.classify(id: id, value: value,
                                                       layer: .global)) == .portable else {
                throw SettingsWorkflowError.ineligibleGlobalReset(id)
            }
            globalEdits.append(.init(id: id, baseValue: value, editedValue: nil))
            candidateGlobal.fields.removeValue(forKey: id)
            globalChanges.append(.init(id: id, oldValue: value, newValue: nil,
                defaultValue: definition.defaultValue, resolution: definition.resolution,
                effect: definition.effect, rule: definition.rule, oldSource: .explicit,
                newSource: .registryDefault))
        }

        var profileReset: ProfileResetPreview?
        var profileEdits: [ProfileDocumentEdit] = []
        if !request.profileFieldIDs.isEmpty {
            guard let profileID = request.profileID else {
                throw SettingsWorkflowError.profileRequired
            }
            guard preferences.profiles.contains(where: { $0.id == profileID }) else {
                throw SettingsWorkflowError.missingProfile(profileID)
            }
            let reset: ProfileResetPreview
            do {
                reset = try SessionProfiles.previewReset(id: profileID,
                    fieldIDs: request.profileFieldIDs,
                    includeOwnedRestrictions: request.includeOwnedProfileRestrictions,
                    inherited: candidateGlobal, in: preferences.profiles)
            } catch SessionProfileError.missingProfile {
                throw SettingsWorkflowError.missingProfile(profileID)
            }
            profileReset = reset
            profileEdits = [.update(id: profileID, base: reset.base, edited: reset.candidate)]
        } else if let profileID = request.profileID,
                  !preferences.profiles.contains(where: { $0.id == profileID }) {
            throw SettingsWorkflowError.missingProfile(profileID)
        }
        let delta = PreferencesDocumentDelta(baseRevision: current.revision,
            global: globalEdits, profiles: profileEdits)
        let applied = try apply(delta, current: current)
        return SettingsSelectiveResetPreview(baseRevision: current.revision,
            globalChanges: globalChanges, profileReset: profileReset,
            immutableBoundaries: immutableResetBoundaries,
            effect: applied.effect, delta: delta)
    }

    public static func exportPortable(current: SettingsEnvelope) throws -> Data {
        try SettingsTransfer.export(.init(
            preferences: current.preferences ?? .init(),
            inertImports: current.inertImports))
    }

    private static func rejectDuplicateProfiles(_ profiles: [SavedProfile]) throws {
        var ids = Set<UUID>()
        for profile in profiles where !ids.insert(profile.id).inserted {
            throw SettingsWorkflowError.duplicateProfile(profile.id)
        }
    }

    private static func apply(_ delta: PreferencesDocumentDelta,
                              current: SettingsEnvelope) throws -> AppliedPreferencesDocument {
        do { return try PreferencesDocumentProjection.apply(delta, to: current) }
        catch PreferencesDocumentProjectionError.unsupportedAuthority {
            throw SettingsWorkflowError.unsupportedAuthority
        }
    }

    private static func utf8Less(_ lhs: SettingID, _ rhs: SettingID) -> Bool {
        lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8)
    }
}
