import CryptoKit
import Foundation

public enum InertScope: String, Equatable, Sendable { case global, profile }
public enum InertSafeValue: Equatable, Sendable { case bool(Bool), integer(Int64), null }
public enum RedactedValueKind: String, Equatable, Sendable { case choice, strings, volume }

public struct InertPortableSetting: Equatable, Sendable {
    public let scope: InertScope
    public let profileID: UUID?
    public let id: String
    public let value: InertSafeValue?
    public let valueKind: RedactedValueKind?
    public let valueDigest: String?
    public let redacted: Bool

    public init(scope: InertScope, profileID: UUID?, id: String, value: InertSafeValue?,
                valueKind: RedactedValueKind?, valueDigest: String?, redacted: Bool) {
        self.scope = scope; self.profileID = profileID; self.id = id; self.value = value
        self.valueKind = valueKind; self.valueDigest = valueDigest; self.redacted = redacted
    }
}

public struct PortableSettingsState: Equatable, Sendable {
    public var preferences: PolicyPreferences
    public var inertImports: [InertPortableSetting]
    public init(preferences: PolicyPreferences = .init(),
                inertImports: [InertPortableSetting] = []) {
        self.preferences = preferences; self.inertImports = inertImports
    }
}

public enum PortableClassification: Equatable, Sendable {
    case portable, requiresLocalReassociation, rejectedAuthority, rejectedNonPortable
}

public enum SettingsImportOutcome: String, Equatable, Sendable {
    case committable, inert, redacted, requiresLocalReassociation, rejectedAuthority
    case rejectedProtectionWeakening, rejectedInvalid, rejectedNonPortable
    case rejectedUnsupportedLayer, collision
}

public struct SettingsImportRow: Equatable, Sendable {
    public let scope: InertScope
    public let profileID: UUID?
    public let id: String?
    public let idDigest: String?
    public let outcome: SettingsImportOutcome
    public let value: SettingValue?
    public let valueKind: RedactedValueKind?
    public let valueDigest: String?

    public init(scope: InertScope, profileID: UUID?, id: String?, idDigest: String?,
                outcome: SettingsImportOutcome, value: SettingValue?,
                valueKind: RedactedValueKind?, valueDigest: String?) {
        self.scope = scope; self.profileID = profileID; self.id = id; self.idDigest = idDigest
        self.outcome = outcome; self.value = value; self.valueKind = valueKind
        self.valueDigest = valueDigest
    }
}

public struct ProfileImportCollision: Equatable, Sendable {
    public let profileID: UUID
    public let localName: String
    public let importedName: String
    public init(profileID: UUID, localName: String, importedName: String) {
        self.profileID = profileID; self.localName = localName; self.importedName = importedName
    }
}

public struct SettingsImportAnalysis: Equatable, Sendable {
    public let rows: [SettingsImportRow]
    public let collisions: [ProfileImportCollision]
    internal let committableImported: PolicyPreferences
    internal let importedInert: [InertPortableSetting]
    internal let current: PortableSettingsState

    internal init(rows: [SettingsImportRow], collisions: [ProfileImportCollision],
                  committableImported: PolicyPreferences,
                  importedInert: [InertPortableSetting], current: PortableSettingsState) {
        self.rows = rows; self.collisions = collisions
        self.committableImported = committableImported; self.importedInert = importedInert
        self.current = current
    }
}

public enum ProfileCollisionChoice: Equatable, Sendable { case keepLocal, replace, clone(UUID) }

public struct ResolvedSettingsImport: Equatable, Sendable {
    public let candidate: PortableSettingsState
    public let rows: [SettingsImportRow]
    public init(candidate: PortableSettingsState, rows: [SettingsImportRow]) {
        self.candidate = candidate; self.rows = rows
    }
}

public enum SettingsTransferError: Error, Equatable, Sendable {
    case malformed, oversized, unsupportedSchema(Int), invalidDocument
    case candidateInvalid(SettingID)
    case missingCollisionChoice(UUID), unexpectedCollisionChoice(UUID)
    case cloneIDCollision(UUID), tooManyProfiles
}

public enum PortableSettingPolicy {
    typealias Partitions = (portable: Set<SettingID>, reassociation: Set<SettingID>,
        authority: Set<SettingID>, nonportable: Set<SettingID>,
        dynamicCatalogPortable: Set<SettingID>)

    private static let cachedPartitions: Partitions = {
        let featureNames = ["headroom", "buildPrep", "projects", "rescue",
                            "ecosystems", "budgets", "history", "maintenance"]
        let ecosystemNames = ["apple", "android", "node", "languages", "homebrew",
                              "docker", "ides", "models", "git", "data"]
        let budgetNames = ["apple-derived-data", "apple-simulators", "android", "docker",
                           "package-caches", "models", "ides", "git", "data", "other"]
        func ids(_ strings: [String]) -> Set<SettingID> {
            Set(strings.map { SettingID(rawValue: $0) })
        }
        let fixed = ids([
            "cleanup.inactiveDays", "cleanup.transcriptDays", "cleanup.recentProtectionDays",
            "cleanup.warmProjectCount", "cleanup.minimumCandidateMiB", "cleanup.minimumItemMiB",
            "cleanup.retainRecentArtifacts", "cleanup.costCeiling", "cleanup.requestedBatchGiB",
            "cleanup.requestedBatchItems", "cleanup.hardBatchGiB", "cleanup.hardBatchItems",
            "cleanup.manualInactiveAcknowledgementMinutes", "headroom.targetGiB",
            "headroom.warningGiB", "headroom.clearGiB", "scan.preset", "scan.requestedWorkers",
            "scan.readOnlyProcesses", "scan.defaultScope", "scan.sliceSeconds",
            "scan.uiBatchesPerSecond", "scan.onLowPower", "scan.onSeriousThermal",
            "scan.resumeAfterCriticalSeconds", "scan.cacheEnabled", "scan.cacheMiB",
            "scan.cacheExpiryHours", "monitor.visibleIntervalSeconds",
            "monitor.hiddenIntervalSeconds", "monitor.rawHistoryEnabled", "monitor.rawHistoryHours",
            "monitor.suppressHiddenSampling", "rescue.showAdvancedMemoryActions",
            "rescue.quitTimeoutSeconds", "notifications.pressureSustainSeconds",
            "notifications.recoverySeconds", "notifications.cooldownMinutes",
            "notifications.quietHoursEnabled", "notifications.quietStart", "notifications.quietEnd",
            "history.enabled", "history.retentionDays", "history.maxMiB", "ui.density", "ui.units",
            "ui.cards", "ui.ecosystemOrder", "ui.showBadges", "ui.advancedSettings",
            "export.redactDiagnostics"
        ] + featureNames.map { "feature.\($0)" }
          + ecosystemNames.flatMap { ["ecosystem.\($0).inventory", "ecosystem.\($0).manualActions"] }
          + budgetNames.flatMap { ["budget.\($0).enabled", "budget.\($0).highGiB", "budget.\($0).lowGiB"] })
        let dynamic = Set(CleanCatalog.allItems.flatMap { item in
            ["enabled", "inactiveDays", "minimumItemMiB", "retainRecentArtifacts"].map {
                SettingID(rawValue: "item.\(item.id).\($0)")
            }
        })
        return (fixed.union(dynamic), ids([
            "scope.projectRoots", "scope.externalVolumes", "scope.currentProject",
            "simulators.approvedDeletionUDIDs", "tools.approvedExecutables",
            "docker.approvedEndpoints", "rescue.approvedApplications"
        ]), ids([
            "monitor.backgroundEnabled", "notifications.enabled", "maintenance.mode",
            "maintenance.maxGiB", "maintenance.maxItems", "maintenance.deadlineSeconds",
            "maintenance.minimumAgeDays", "maintenance.minimumIntervalHours", "app.launchAtLogin"
        ]), ids(["scope.excludedRoots", "scope.pinnedProjects", "browsers.keepCookieDomains"]), dynamic)
    }()

    static var classificationPartitions: Partitions { cachedPartitions }

    public static func classify(id: SettingID, value: SettingValue,
                                layer: PolicyLayer) throws -> PortableClassification {
        if id.rawValue.hasPrefix("headroom.volumeOverrides.") {
            guard let definition = PolicyValidator.definition(for: id) else {
                throw PolicyFieldError(id: id, reason: .unknownKey)
            }
            try validate(value, id: id, layer: layer, definition: definition, allowAuthority: true)
            return .requiresLocalReassociation
        }
        guard let definition = PolicyValidator.definition(for: id) else {
            throw PolicyFieldError(id: id, reason: .unknownKey)
        }
        let p = classificationPartitions
        let classification: PortableClassification
        if p.portable.contains(id) { classification = .portable }
        else if p.reassociation.contains(id) { classification = .requiresLocalReassociation }
        else if p.authority.contains(id) { classification = .rejectedAuthority }
        else if p.nonportable.contains(id) { classification = .rejectedNonPortable }
        else { throw PolicyFieldError(id: id, reason: .unknownKey) }
        try validate(value, id: id, layer: layer, definition: definition,
                     allowAuthority: classification != .portable)
        return classification
    }

    private static func validate(_ value: SettingValue, id: SettingID, layer: PolicyLayer,
                                 definition: SettingDefinition, allowAuthority: Bool) throws {
        if definition.resolution == .authority && allowAuthority {
            try validateAuthorityValue(value, definition: definition)
            return
        }
        guard definition.layers.contains(layer) else {
            throw PolicyFieldError(id: id, reason: .unsupportedLayer)
        }
        try PolicyValidator.validateStructure(.init(fields: [id: value]), at: layer)
    }

    private static func valueKindMatches(_ value: SettingValue, _ kind: ValueKind) -> Bool {
        switch (kind, value) {
        case (.bool, .bool), (.integer, .integer), (.choice, .choice), (.clock, .choice),
             (.orderedIDs, .strings), (.setIDs, .strings), (.domains, .strings),
             (.localIdentityList, .strings), (.volumeOverride, .volume): return true
        case (.optionalInteger, .integer), (.optionalInteger, .null),
             (.optionalProjectID, .choice), (.optionalProjectID, .null): return true
        default: return false
        }
    }

    private static func validateAuthorityValue(_ value: SettingValue,
                                               definition: SettingDefinition) throws {
        guard valueKindMatches(value, definition.kind) else {
            throw PolicyFieldError(id: definition.id, reason: .invalidType)
        }
        switch definition.rule {
        case .boolean: return
        case .integer(let low, let high):
            guard case .integer(let number) = value, (low...high).contains(number) else {
                throw PolicyFieldError(id: definition.id, reason: .outOfRange)
            }
        case .choices(let choices):
            guard case .choice(let choice) = value, choices.contains(choice) else {
                throw PolicyFieldError(id: definition.id, reason: .outOfRange)
            }
        case .identityList:
            guard case .strings(let strings) = value, strings.count <= 1_000,
                  Set(strings).count == strings.count,
                  strings.allSatisfy({ $0.utf8.count <= 4_096 }) else {
                throw PolicyFieldError(id: definition.id, reason: .invalidIdentity)
            }
        default:
            throw PolicyFieldError(id: definition.id, reason: .invalidType)
        }
    }
}

public enum SettingsTransfer {
    private struct ParsedProfile { let profile: SavedProfile; let inertIDs: Set<String> }
    private struct InertKey: Hashable { let scope: InertScope; let profileID: UUID?; let id: String }

    public static func analyze(bytes: Data,
                               current: PortableSettingsState) throws -> SettingsImportAnalysis {
        let rootValue: StrictJSON.Value
        do { rootValue = try StrictJSON.parse(bytes) }
        catch StrictJSONError.oversized { throw SettingsTransferError.oversized }
        catch { throw SettingsTransferError.malformed }
        do { return try analyze(rootValue, current: current) }
        catch let error as SettingsTransferError { throw error }
        catch is StrictJSONError { throw SettingsTransferError.malformed }
        catch { throw SettingsTransferError.invalidDocument }
    }

    private static func analyze(_ value: StrictJSON.Value,
                                current: PortableSettingsState) throws -> SettingsImportAnalysis {
        let root = try value.object()
        guard Set(root.keys) == ["schemaVersion", "global", "profiles", "inertImports"] else {
            throw SettingsTransferError.invalidDocument
        }
        let schema = try required(root, "schemaVersion").integer()
        guard schema == 1 else { throw SettingsTransferError.unsupportedSchema(schema) }
        var rows: [SettingsImportRow] = []
        var importedInert: [InertPortableSetting] = []
        var importedGlobal = PolicyValues()
        let globalObject = try closedPolicy(required(root, "global"))
        for key in globalObject.keys.sorted(by: utf8Less) {
            try analyzeField(idText: key, raw: globalObject[key]!, scope: .global,
                profileID: nil, layer: .global, baseline: current.preferences.global,
                evolving: &importedGlobal, inertRecords: &importedInert, rows: &rows)
        }
        var importedProfiles: [SavedProfile] = []
        var importedIDs = Set<UUID>()
        for rawProfile in try required(root, "profiles").array() {
            let object = try rawProfile.object()
            guard Set(object.keys) == ["id", "name", "values"] else {
                throw SettingsTransferError.invalidDocument
            }
            let idText = try required(object, "id").string()
            guard let profileID = UUID(uuidString: idText), idText == profileID.uuidString.lowercased(),
                  importedIDs.insert(profileID).inserted else {
                throw SettingsTransferError.invalidDocument
            }
            let name = try required(object, "name").string()
            guard validName(name) else { throw SettingsTransferError.invalidDocument }
            var profileValues = PolicyValues()
            let fields = try closedPolicy(required(object, "values"))
            var inherited = current.preferences.global
            for (key, value) in importedGlobal.fields { inherited.fields[key] = value }
            for key in fields.keys.sorted(by: utf8Less) {
                try analyzeField(idText: key, raw: fields[key]!, scope: .profile,
                    profileID: profileID, layer: .profile, baseline: inherited,
                    evolving: &profileValues, inertRecords: &importedInert, rows: &rows)
            }
            importedProfiles.append(.init(id: profileID, name: name, values: profileValues))
        }
        let profileSet = Set(importedProfiles.map(\.id))
        var importedInertKeys = Set(importedInert.map {
            InertKey(scope: $0.scope, profileID: $0.profileID, id: $0.id)
        })
        for raw in try required(root, "inertImports").array() {
            let item = try parseInert(raw, profileIDs: profileSet)
            let key = InertKey(scope: item.scope, profileID: item.profileID, id: item.id)
            guard importedInertKeys.insert(key).inserted else {
                throw SettingsTransferError.invalidDocument
            }
            importedInert.append(item)
            rows.append(row(for: item, outcome: item.redacted ? .redacted : .inert))
        }
        let collisions = importedProfiles.compactMap { imported -> ProfileImportCollision? in
            guard let local = current.preferences.profiles.first(where: { $0.id == imported.id }) else {
                return nil
            }
            return .init(profileID: imported.id, localName: local.name, importedName: imported.name)
        }.sorted { $0.profileID.uuidString < $1.profileID.uuidString }
        return SettingsImportAnalysis(rows: sortedRows(rows), collisions: collisions,
            committableImported: .init(global: importedGlobal, profiles: importedProfiles),
            importedInert: sortedInert(importedInert), current: current)
    }

    public static func resolve(_ analysis: SettingsImportAnalysis,
                               choices: [UUID: ProfileCollisionChoice]) throws -> ResolvedSettingsImport {
        do { try validateCandidate(analysis.current) }
        catch { throw SettingsTransferError.invalidDocument }
        let collisionIDs = Set(analysis.collisions.map(\.profileID))
        for id in collisionIDs where choices[id] == nil {
            throw SettingsTransferError.missingCollisionChoice(id)
        }
        for id in choices.keys where !collisionIDs.contains(id) {
            throw SettingsTransferError.unexpectedCollisionChoice(id)
        }
        var candidate = analysis.current
        for (id, value) in analysis.committableImported.global.fields {
            candidate.preferences.global.fields[id] = value
        }
        var rows = analysis.rows
        var usedIDs = Set(candidate.preferences.profiles.map(\.id))
        var importedProfileMap: [UUID: UUID] = [:]
        for imported in analysis.committableImported.profiles.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            if let index = candidate.preferences.profiles.firstIndex(where: { $0.id == imported.id }) {
                switch choices[imported.id]! {
                case .keepLocal:
                    importedProfileMap[imported.id] = imported.id
                case .replace:
                    candidate.preferences.profiles[index] = imported
                    importedProfileMap[imported.id] = imported.id
                case .clone(let newID):
                    guard !usedIDs.contains(newID) else { throw SettingsTransferError.cloneIDCollision(newID) }
                    usedIDs.insert(newID)
                    candidate.preferences.profiles.append(.init(id: newID, name: imported.name,
                                                                values: imported.values))
                    importedProfileMap[imported.id] = newID
                }
            } else {
                candidate.preferences.profiles.append(imported)
                usedIDs.insert(imported.id)
                importedProfileMap[imported.id] = imported.id
            }
        }
        guard candidate.preferences.profiles.count <= SessionProfiles.maximumCount else {
            throw SettingsTransferError.tooManyProfiles
        }
        let currentByKey = Dictionary(uniqueKeysWithValues: analysis.current.inertImports.map {
            (InertKey(scope: $0.scope, profileID: $0.profileID, id: $0.id), $0)
        })
        var merged = currentByKey
        for collision in analysis.collisions {
            guard choices[collision.profileID] == .replace else { continue }
            for key in merged.keys where key.scope == .profile && key.profileID == collision.profileID {
                if let discarded = merged.removeValue(forKey: key) {
                    rows.append(row(for: discarded, outcome: .collision))
                }
            }
        }
        for item in analysis.importedInert {
            var mapped = item
            if item.scope == .profile, let original = item.profileID {
                if collisionIDs.contains(original) {
                    switch choices[original]! {
                    case .keepLocal:
                        rows.append(row(for: item, outcome: .collision)); continue
                    case .replace: break
                    case .clone(let newID):
                        mapped = remap(item, to: newID)
                    }
                } else if let destination = importedProfileMap[original], destination != original {
                    mapped = remap(item, to: destination)
                }
            }
            let key = InertKey(scope: mapped.scope, profileID: mapped.profileID, id: mapped.id)
            if let existing = merged[key] {
                if existing != mapped { rows.append(row(for: mapped, outcome: .collision)) }
            } else { merged[key] = mapped }
        }
        candidate.inertImports = sortedInert(Array(merged.values))
        candidate.preferences.profiles.sort { $0.id.uuidString < $1.id.uuidString }
        do { try validateCandidate(candidate) }
        catch let error as PolicyFieldError { throw SettingsTransferError.candidateInvalid(error.id) }
        catch let error as SessionProfileError {
            if case .protectionWeakening(let id) = error { throw SettingsTransferError.candidateInvalid(id) }
            throw SettingsTransferError.invalidDocument
        }
        catch let error as SettingsTransferError { throw error }
        catch { throw SettingsTransferError.invalidDocument }
        do { _ = try export(candidate) }
        catch { throw SettingsTransferError.invalidDocument }
        return .init(candidate: candidate, rows: sortedRows(rows))
    }

    public static func export(_ state: PortableSettingsState) throws -> Data {
        var sanitized = state
        sanitized.preferences.projects = [:]
        do {
            try validateRawStringBounds(state)
            try validateProjectsAndCounts(state.preferences.projects)
            sanitized.preferences.global = try sanitizedValues(state.preferences.global,
                                                                layer: .global, inherited: nil)
            sanitized.preferences.profiles = try state.preferences.profiles.map {
                SavedProfile(id: $0.id, name: $0.name,
                             values: try sanitizedValues($0.values, layer: .profile,
                                 inherited: sanitized.preferences.global))
            }.sorted { $0.id.uuidString < $1.id.uuidString }
        } catch { throw SettingsTransferError.invalidDocument }
        do { try validateCandidate(sanitized) }
        catch { throw SettingsTransferError.invalidDocument }
        let root: StrictJSON.Value = .object([
            "schemaVersion": .number("1"),
            "global": policyValue(sanitized.preferences.global),
            "profiles": .array(sanitized.preferences.profiles.map(profileValue)),
            "inertImports": .array(sortedInert(sanitized.inertImports).map(inertValue))
        ])
        do { return try StrictJSON.canonicalData(root) }
        catch StrictJSONError.oversized { throw SettingsTransferError.oversized }
        catch { throw SettingsTransferError.invalidDocument }
    }

    private static func analyzeField(idText: String, raw: StrictJSON.Value,
                                     scope: InertScope, profileID: UUID?, layer: PolicyLayer,
                                     baseline: PolicyValues, evolving: inout PolicyValues,
                                     inertRecords: inout [InertPortableSetting],
                                     rows: inout [SettingsImportRow]) throws {
        let parsed = try settingValue(raw)
        guard safeID(idText) else {
            rows.append(.init(scope: scope, profileID: profileID, id: nil,
                idDigest: digest(.string(idText)), outcome: .redacted, value: nil,
                valueKind: nil, valueDigest: nil))
            return
        }
        let id = SettingID(rawValue: idText)
        guard PolicyValidator.definition(for: id) != nil else {
            let record = try unknownInert(id: idText, raw: raw, value: parsed,
                                          scope: scope, profileID: profileID)
            inertRecords.append(record)
            rows.append(row(for: record, outcome: record.redacted ? .redacted : .inert))
            return
        }
        let classification: PortableClassification
        do { classification = try PortableSettingPolicy.classify(id: id, value: parsed, layer: layer) }
        catch let error as PolicyFieldError where error.reason == .unsupportedLayer {
            rows.append(importRow(scope, profileID, idText, .rejectedUnsupportedLayer)); return
        } catch {
            rows.append(importRow(scope, profileID, idText, .rejectedInvalid)); return
        }
        switch classification {
        case .requiresLocalReassociation:
            rows.append(importRow(scope, profileID, idText, .requiresLocalReassociation)); return
        case .rejectedAuthority:
            rows.append(importRow(scope, profileID, idText, .rejectedAuthority)); return
        case .rejectedNonPortable:
            rows.append(importRow(scope, profileID, idText, .rejectedNonPortable)); return
        case .portable: break
        }
        if let definition = PolicyValidator.definition(for: id), definition.resolution == .restriction {
            let inherited = baseline.fields[id] ?? definition.defaultValue
            if try PolicyRestrictionValidator.relation(candidate: parsed, baseline: inherited,
                                                       for: id) == .weaker {
                rows.append(importRow(scope, profileID, idText, .rejectedProtectionWeakening)); return
            }
        }
        var candidate = evolving
        candidate.fields[id] = parsed
        if !contextFreeValid(candidate, inherited: baseline) {
            rows.append(importRow(scope, profileID, idText, .rejectedInvalid)); return
        }
        evolving = candidate
        rows.append(.init(scope: scope, profileID: profileID, id: idText, idDigest: nil,
                          outcome: .committable, value: parsed, valueKind: nil, valueDigest: nil))
    }

    private static func contextFreeValid(_ values: PolicyValues, inherited: PolicyValues) -> Bool {
        var merged = inherited.fields
        for (id, value) in values.fields { merged[id] = value }
        let start = merged[.init(rawValue: "notifications.quietStart")]
        let end = merged[.init(rawValue: "notifications.quietEnd")]
        if case .choice(let a)? = start, case .choice(let b)? = end, a == b { return false }
        if case .integer(let warning)? = merged[.init(rawValue: "headroom.warningGiB")],
           case .integer(let clear)? = merged[.init(rawValue: "headroom.clearGiB")], warning >= clear {
            return false
        }
        for budget in ["apple-derived-data", "apple-simulators", "android", "docker",
                       "package-caches", "models", "ides", "git", "data", "other"] {
            if case .integer(let low)? = merged[.init(rawValue: "budget.\(budget).lowGiB")],
               case .integer(let high)? = merged[.init(rawValue: "budget.\(budget).highGiB")], low >= high {
                return false
            }
        }
        return true
    }

    private static func validateCandidate(_ state: PortableSettingsState) throws {
        guard state.preferences.profiles.count <= 50, state.inertImports.count <= 1_000 else {
            throw SettingsTransferError.invalidDocument
        }
        var count = 0
        func add(_ amount: Int) throws {
            let (next, overflow) = count.addingReportingOverflow(amount)
            guard !overflow, next <= 4_096 else { throw SettingsTransferError.invalidDocument }
            count = next
        }
        guard state.preferences.global.fields.count <= 1_000 else {
            throw SettingsTransferError.invalidDocument
        }
        try add(state.preferences.global.fields.count)
        try PolicyRestrictionValidator.validate(state.preferences.global,
                                                 inherited: .init(), at: .global)
        try validateValueStringBounds(state.preferences.global)
        if let id = relationError(global: state.preferences.global, overlay: .init()) {
            throw PolicyFieldError(id: id, reason: .invalidRelation)
        }
        var profileIDs = Set<UUID>()
        for profile in state.preferences.profiles {
            guard profileIDs.insert(profile.id).inserted, validName(profile.name),
                  profile.values.fields.count <= 1_000 else { throw SettingsTransferError.invalidDocument }
            try add(profile.values.fields.count)
            try PolicyRestrictionValidator.validate(profile.values,
                inherited: state.preferences.global, at: .profile)
            try validateValueStringBounds(profile.values)
            if let id = relationError(global: state.preferences.global, overlay: profile.values) {
                throw PolicyFieldError(id: id, reason: .invalidRelation)
            }
            for id in profile.values.fields.keys {
                guard let definition = PolicyValidator.definition(for: id),
                      definition.kind != .volumeOverride,
                      definition.kind != .optionalProjectID else {
                    throw PolicyFieldError(id: id, reason: .unsupportedLayer)
                }
            }
        }
        try validateProjectsAndCounts(state.preferences.projects) { try add($0) }
        var inertKeys = Set<InertKey>()
        for item in state.inertImports {
            guard validInert(item, profileIDs: profileIDs),
                  inertKeys.insert(.init(scope: item.scope, profileID: item.profileID,
                                        id: item.id)).inserted else {
                throw SettingsTransferError.invalidDocument
            }
        }
    }

    private static func sanitizedValues(_ values: PolicyValues, layer: PolicyLayer,
                                        inherited: PolicyValues?) throws -> PolicyValues {
        var result = PolicyValues()
        for (id, value) in values.fields {
            guard let definition = PolicyValidator.definition(for: id) else {
                throw SettingsTransferError.invalidDocument
            }
            let classification = try PortableSettingPolicy.classify(id: id, value: value,
                                                                      layer: layer)
            guard classification == .portable else { continue }
            if definition.resolution == .restriction {
                let baseline = inherited?.fields[id] ?? definition.defaultValue
                if try PolicyRestrictionValidator.relation(candidate: value, baseline: baseline,
                                                           for: id) == .weaker { continue }
            }
            result.fields[id] = value
        }
        return result
    }

    private static func validateProjectsAndCounts(_ projects: [String: PolicyValues],
                                                  add: ((Int) throws -> Void)? = nil) throws {
        guard projects.count <= 1_000 else { throw SettingsTransferError.invalidDocument }
        for (project, values) in projects {
            guard !project.isEmpty, project.utf8.count <= 4_096,
                  values.fields.count <= 1_000 else {
                throw SettingsTransferError.invalidDocument
            }
            try add?(values.fields.count)
            try PolicyValidator.validateStructure(values, at: .project)
            try validateValueStringBounds(values)
        }
    }

    private static func validateRawStringBounds(_ state: PortableSettingsState) throws {
        try validateValueStringBounds(state.preferences.global)
        for profile in state.preferences.profiles {
            guard profile.name.utf8.count <= 4_096 else { throw SettingsTransferError.invalidDocument }
            try validateValueStringBounds(profile.values)
        }
        for (id, values) in state.preferences.projects {
            guard id.utf8.count <= 4_096 else { throw SettingsTransferError.invalidDocument }
            try validateValueStringBounds(values)
        }
    }

    private static func validateValueStringBounds(_ values: PolicyValues) throws {
        for (id, value) in values.fields {
            switch value {
            case .choice(let string):
                guard string.utf8.count <= 4_096 else {
                    throw PolicyFieldError(id: id, reason: .outOfRange)
                }
            case .strings(let strings):
                guard strings.count <= 1_000,
                      strings.allSatisfy({ $0.utf8.count <= 4_096 }) else {
                    throw PolicyFieldError(id: id, reason: .outOfRange)
                }
            default: break
            }
        }
    }

    private static func relationError(global: PolicyValues,
                                      overlay: PolicyValues) -> SettingID? {
        func value(_ raw: String) -> SettingValue? {
            let id = SettingID(rawValue: raw)
            return overlay.fields[id] ?? global.fields[id] ?? PolicyValidator.definition(for: id)?.defaultValue
        }
        let quietEnd = SettingID(rawValue: "notifications.quietEnd")
        if case .choice(let start)? = value("notifications.quietStart"),
           case .choice(let end)? = value("notifications.quietEnd"), start == end { return quietEnd }
        let clearID = SettingID(rawValue: "headroom.clearGiB")
        if case .integer(let warning)? = value("headroom.warningGiB"),
           case .integer(let clear)? = value("headroom.clearGiB"), warning >= clear { return clearID }
        for budget in ["apple-derived-data", "apple-simulators", "android", "docker",
                       "package-caches", "models", "ides", "git", "data", "other"] {
            let lowID = SettingID(rawValue: "budget.\(budget).lowGiB")
            if case .integer(let low)? = value("budget.\(budget).lowGiB"),
               case .integer(let high)? = value("budget.\(budget).highGiB"), low >= high { return lowID }
        }
        return nil
    }

    private static func closedPolicy(_ value: StrictJSON.Value) throws -> [String: StrictJSON.Value] {
        let object = try value.object()
        guard Set(object.keys) == ["fields"] else { throw SettingsTransferError.invalidDocument }
        return try required(object, "fields").object()
    }

    private static func settingValue(_ raw: StrictJSON.Value) throws -> SettingValue {
        let object = try raw.object()
        guard object.count == 1, let (tag, payload) = object.first else {
            throw StrictJSONError.malformed
        }
        switch tag {
        case "bool": return .bool(try payload.bool())
        case "integer": return .integer(try payload.signedInteger())
        case "choice": return .choice(try payload.string())
        case "strings": return .strings(try payload.strings())
        case "null": guard try payload.bool() else { throw StrictJSONError.malformed }; return .null
        case "volume":
            let fields = try payload.object()
            guard Set(fields.keys) == ["target", "warning", "clear"] else {
                throw StrictJSONError.malformed
            }
            return .volume(.init(target: try volumeField(required(fields, "target")),
                                 warning: try volumeField(required(fields, "warning")),
                                 clear: try volumeField(required(fields, "clear"))))
        default: throw StrictJSONError.malformed
        }
    }

    private static func volumeField(_ raw: StrictJSON.Value) throws -> VolumeField {
        let object = try raw.object()
        guard object.count == 1, let (tag, payload) = object.first else {
            throw StrictJSONError.malformed
        }
        switch tag {
        case "inherit": guard try payload.bool() else { throw StrictJSONError.malformed }; return .inherit
        case "automatic": guard try payload.bool() else { throw StrictJSONError.malformed }; return .automatic
        case "fixedGiB": return .fixedGiB(try payload.signedInteger())
        default: throw StrictJSONError.malformed
        }
    }

    private static func unknownInert(id: String, raw: StrictJSON.Value, value: SettingValue,
                                     scope: InertScope, profileID: UUID?) throws -> InertPortableSetting {
        switch value {
        case .bool(let value): return .init(scope: scope, profileID: profileID, id: id,
            value: .bool(value), valueKind: nil, valueDigest: nil, redacted: false)
        case .integer(let value): return .init(scope: scope, profileID: profileID, id: id,
            value: .integer(value), valueKind: nil, valueDigest: nil, redacted: false)
        case .null: return .init(scope: scope, profileID: profileID, id: id,
            value: .null, valueKind: nil, valueDigest: nil, redacted: false)
        case .choice: return redacted(id, raw, scope, profileID, .choice)
        case .strings: return redacted(id, raw, scope, profileID, .strings)
        case .volume: return redacted(id, raw, scope, profileID, .volume)
        }
    }

    private static func redacted(_ id: String, _ raw: StrictJSON.Value, _ scope: InertScope,
                                 _ profileID: UUID?, _ kind: RedactedValueKind) -> InertPortableSetting {
        .init(scope: scope, profileID: profileID, id: id, value: nil, valueKind: kind,
              valueDigest: digest(raw), redacted: true)
    }

    private static func parseInert(_ raw: StrictJSON.Value,
                                   profileIDs: Set<UUID>) throws -> InertPortableSetting {
        let object = try raw.object()
        guard Set(object.keys) == ["scope", "profileID", "id", "value", "valueKind",
                                   "valueDigest", "label"] else {
            throw SettingsTransferError.invalidDocument
        }
        guard let scope = InertScope(rawValue: try required(object, "scope").string()) else {
            throw SettingsTransferError.invalidDocument
        }
        let profileID: UUID?
        switch try required(object, "profileID") {
        case .null: profileID = nil
        case .string(let text):
            guard let id = UUID(uuidString: text), text == id.uuidString.lowercased() else {
                throw SettingsTransferError.invalidDocument
            }
            profileID = id
        default: throw SettingsTransferError.invalidDocument
        }
        guard (scope == .global && profileID == nil) ||
              (scope == .profile && profileID.map(profileIDs.contains) == true) else {
            throw SettingsTransferError.invalidDocument
        }
        let id = try required(object, "id").string()
        guard safeID(id) else { throw SettingsTransferError.invalidDocument }
        let valueRaw = try required(object, "value")
        let kindRaw = try required(object, "valueKind")
        let digestRaw = try required(object, "valueDigest")
        let labelRaw = try required(object, "label")
        if case .null = kindRaw, case .null = digestRaw, case .null = labelRaw {
            let safe: InertSafeValue
            switch try settingValue(valueRaw) {
            case .bool(let value): safe = .bool(value)
            case .integer(let value): safe = .integer(value)
            case .null: safe = .null
            default: throw SettingsTransferError.invalidDocument
            }
            return .init(scope: scope, profileID: profileID, id: id, value: safe,
                         valueKind: nil, valueDigest: nil, redacted: false)
        }
        guard case .null = valueRaw,
              let kind = RedactedValueKind(rawValue: try kindRaw.string()),
              case .string(let digest) = digestRaw, validDigest(digest),
              case .string("redacted") = labelRaw else {
            throw SettingsTransferError.invalidDocument
        }
        return .init(scope: scope, profileID: profileID, id: id, value: nil,
                     valueKind: kind, valueDigest: digest, redacted: true)
    }

    private static func validInert(_ item: InertPortableSetting,
                                   profileIDs: Set<UUID>) -> Bool {
        guard safeID(item.id), item.id.utf8.count <= 4_096,
              (item.scope == .global && item.profileID == nil ||
               item.scope == .profile && item.profileID.map(profileIDs.contains) == true) else {
            return false
        }
        if item.redacted {
            return item.value == nil && item.valueKind != nil && item.valueDigest.map(validDigest) == true
        }
        return item.value != nil && item.valueKind == nil && item.valueDigest == nil
    }

    private static func policyValue(_ values: PolicyValues) -> StrictJSON.Value {
        .object(["fields": .object(Dictionary(uniqueKeysWithValues: values.fields.map {
            ($0.key.rawValue, settingValue($0.value))
        }))])
    }

    private static func profileValue(_ profile: SavedProfile) -> StrictJSON.Value {
        .object(["id": .string(profile.id.uuidString.lowercased()), "name": .string(profile.name),
                 "values": policyValue(profile.values)])
    }

    private static func settingValue(_ value: SettingValue) -> StrictJSON.Value {
        switch value {
        case .bool(let value): return .object(["bool": .bool(value)])
        case .integer(let value): return .object(["integer": .number(String(value))])
        case .choice(let value): return .object(["choice": .string(value)])
        case .strings(let value): return .object(["strings": .array(value.map(StrictJSON.Value.string))])
        case .null: return .object(["null": .bool(true)])
        case .volume(let value): return .object(["volume": .object([
            "target": volumeValue(value.target), "warning": volumeValue(value.warning),
            "clear": volumeValue(value.clear)])])
        }
    }

    private static func volumeValue(_ value: VolumeField) -> StrictJSON.Value {
        switch value {
        case .inherit: return .object(["inherit": .bool(true)])
        case .automatic: return .object(["automatic": .bool(true)])
        case .fixedGiB(let value): return .object(["fixedGiB": .number(String(value))])
        }
    }

    private static func inertValue(_ item: InertPortableSetting) -> StrictJSON.Value {
        let value: StrictJSON.Value
        if let safe = item.value {
            switch safe {
            case .bool(let bool): value = .object(["bool": .bool(bool)])
            case .integer(let integer): value = .object(["integer": .number(String(integer))])
            case .null: value = .object(["null": .bool(true)])
            }
        } else { value = .null }
        return .object([
            "scope": .string(item.scope.rawValue),
            "profileID": item.profileID.map { .string($0.uuidString.lowercased()) } ?? .null,
            "id": .string(item.id), "value": value,
            "valueKind": item.valueKind.map { .string($0.rawValue) } ?? .null,
            "valueDigest": item.valueDigest.map(StrictJSON.Value.string) ?? .null,
            "label": item.redacted ? .string("redacted") : .null
        ])
    }

    private static func required(_ object: [String: StrictJSON.Value],
                                 _ key: String) throws -> StrictJSON.Value {
        guard let value = object[key] else { throw SettingsTransferError.invalidDocument }
        return value
    }

    private static func row(for item: InertPortableSetting,
                            outcome: SettingsImportOutcome) -> SettingsImportRow {
        .init(scope: item.scope, profileID: item.profileID, id: item.id, idDigest: nil,
              outcome: outcome, value: nil, valueKind: item.valueKind,
              valueDigest: item.valueDigest)
    }

    private static func importRow(_ scope: InertScope, _ profileID: UUID?, _ id: String,
                                  _ outcome: SettingsImportOutcome) -> SettingsImportRow {
        .init(scope: scope, profileID: profileID, id: id, idDigest: nil,
              outcome: outcome, value: nil, valueKind: nil, valueDigest: nil)
    }

    private static func remap(_ item: InertPortableSetting,
                              to id: UUID) -> InertPortableSetting {
        .init(scope: item.scope, profileID: id, id: item.id, value: item.value,
              valueKind: item.valueKind, valueDigest: item.valueDigest, redacted: item.redacted)
    }

    private static func sortedInert(_ values: [InertPortableSetting]) -> [InertPortableSetting] {
        values.sorted {
            let left = [$0.scope.rawValue, $0.profileID?.uuidString.lowercased() ?? "", $0.id,
                        $0.valueKind?.rawValue ?? "", $0.valueDigest ?? ""]
            let right = [$1.scope.rawValue, $1.profileID?.uuidString.lowercased() ?? "", $1.id,
                         $1.valueKind?.rawValue ?? "", $1.valueDigest ?? ""]
            return tupleLess(left, right)
        }
    }

    private static func sortedRows(_ values: [SettingsImportRow]) -> [SettingsImportRow] {
        values.sorted {
            tupleLess([$0.scope.rawValue, $0.profileID?.uuidString.lowercased() ?? "",
                       $0.id ?? "", $0.idDigest ?? "", $0.outcome.rawValue],
                      [$1.scope.rawValue, $1.profileID?.uuidString.lowercased() ?? "",
                       $1.id ?? "", $1.idDigest ?? "", $1.outcome.rawValue])
        }
    }

    private static func tupleLess(_ lhs: [String], _ rhs: [String]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right { return utf8Less(left, right) }
        return false
    }

    private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 4_096 &&
        name.trimmingCharacters(in: .whitespacesAndNewlines) == name
    }

    private static func safeID(_ value: String) -> Bool {
        guard let first = value.utf8.first, value.utf8.count <= 256,
              (first >= 97 && first <= 122) || (first >= 48 && first <= 57) else { return false }
        return value.utf8.dropFirst().allSatisfy {
            ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) ||
            $0 == 46 || $0 == 95 || $0 == 45
        }
    }

    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    private static func digest(_ value: StrictJSON.Value) -> String {
        let data = (try? StrictJSON.canonicalData(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
