import Foundation

public struct PolicyFieldError: Error, Equatable, Sendable {
    public let id: SettingID
    public let reason: Reason

    public init(id: SettingID, reason: Reason) {
        self.id = id
        self.reason = reason
    }

    public enum Reason: String, Sendable {
        case unknownKey, unsupportedLayer, authorityIsLocal, invalidType, outOfRange
        case invalidRelation, invalidIdentity, malformed, boundsUnavailable
    }
}

public enum PolicyValidator {
    private static let gib: Int64 = 1_073_741_824
    private static let cards = Set(["disk", "memoryPressure", "swap", "thermal", "power"])
    private static let volumePrefix = "headroom.volumeOverrides."

    public static func validateStructure(_ values: PolicyValues, at layer: PolicyLayer) throws {
        for (id, value) in values.fields {
            guard let definition = definition(for: id) else {
                throw PolicyFieldError(id: id, reason: .unknownKey)
            }
            guard definition.resolution != .authority else {
                throw PolicyFieldError(id: id, reason: .authorityIsLocal)
            }
            guard definition.layers.contains(layer) else {
                throw PolicyFieldError(id: id, reason: .unsupportedLayer)
            }
            try validate(value, for: definition)
        }
        let startID = SettingID(rawValue: "notifications.quietStart")
        let endID = SettingID(rawValue: "notifications.quietEnd")
        if case .choice(let start)? = values.fields[startID],
           case .choice(let end)? = values.fields[endID], start == end {
            throw PolicyFieldError(id: endID, reason: .invalidRelation)
        }
    }

    public static func validateEdit(_ values: PolicyValues, at layer: PolicyLayer,
                                    context: PolicyInputs) throws {
        try validateStructure(values, at: layer)
        var candidate = context
        let old = context.layers[layer] ?? PolicyValues()
        candidate.layers[layer] = values
        for currentLayer in PolicyLayer.allCases {
            if let document = candidate.layers[currentLayer] {
                try validateStructure(document, at: currentLayer)
            }
        }
        try validateMergedQuietHours(candidate.layers)

        let edited = Set(values.fields.compactMap { id, value in
            old.fields[id] == value ? nil : id
        })
        let editedHeadroom = edited.filter {
            $0.rawValue == "headroom.targetGiB" || $0.rawValue == "headroom.warningGiB" ||
            $0.rawValue == "headroom.clearGiB" || $0.rawValue.hasPrefix(volumePrefix)
        }
        if !editedHeadroom.isEmpty {
            try validateEditedHeadroom(candidate, edited: editedHeadroom)
        }
        try validateEditedBudgets(candidate, edited: edited)
    }

    public static func integerInput(_ text: String, for id: SettingID) throws -> Int64 {
        guard !text.isEmpty else { throw PolicyFieldError(id: id, reason: .malformed) }
        let scalars = Array(text.unicodeScalars)
        let start = scalars.first?.value == 45 ? 1 : 0
        guard start < scalars.count,
              scalars[start...].allSatisfy({ (48...57).contains($0.value) }),
              let value = Int64(text) else {
            throw PolicyFieldError(id: id, reason: .malformed)
        }
        return value
    }

    public static func bytes(gib: Int64, for id: SettingID) throws -> Int64 {
        let (result, overflow) = gib.multipliedReportingOverflow(by: self.gib)
        guard !overflow else { throw PolicyFieldError(id: id, reason: .outOfRange) }
        return result
    }

    static func definition(for id: SettingID) -> SettingDefinition? {
        if let exact = PolicyDefaults.rows.first(where: { $0.id == id }) { return exact }
        if id.rawValue.hasPrefix(volumePrefix),
           let uuid = UUID(uuidString: String(id.rawValue.dropFirst(volumePrefix.count))) {
            let definition = PolicyDefaults.volumeRow(id: uuid)
            return SettingDefinition(id: id, kind: definition.kind, defaultValue: definition.defaultValue,
                rule: definition.rule, resolution: definition.resolution, effect: definition.effect,
                layers: definition.layers, group: definition.group)
        }
        for catalogID in CleanCatalog.allItems.map(\.id) {
            if let item = PolicyDefaults.itemRows(catalogID: catalogID).first(where: { $0.id == id }) {
                return item
            }
        }
        return nil
    }

    static func validateMergedQuietHours(_ layers: [PolicyLayer: PolicyValues]) throws {
        let startID = SettingID(rawValue: "notifications.quietStart")
        let endID = SettingID(rawValue: "notifications.quietEnd")
        var start = "22:00"
        var end = "08:00"
        for layer in PolicyLayer.allCases {
            if case .choice(let value)? = layers[layer]?.fields[startID] { start = value }
            if case .choice(let value)? = layers[layer]?.fields[endID] { end = value }
        }
        if start == end { throw PolicyFieldError(id: endID, reason: .invalidRelation) }
    }

    private static func validate(_ value: SettingValue, for definition: SettingDefinition) throws {
        let validKind: Bool
        switch definition.kind {
        case .bool: if case .bool = value { validKind = true } else { validKind = false }
        case .integer: if case .integer = value { validKind = true } else { validKind = false }
        case .optionalInteger:
            if case .integer = value { validKind = true } else if value == .null { validKind = true } else { validKind = false }
        case .choice, .clock: if case .choice = value { validKind = true } else { validKind = false }
        case .orderedIDs, .setIDs, .domains, .localIdentityList:
            if case .strings = value { validKind = true } else { validKind = false }
        case .optionalProjectID:
            if case .choice = value { validKind = true } else if value == .null { validKind = true } else { validKind = false }
        case .volumeOverride: if case .volume = value { validKind = true } else { validKind = false }
        }
        guard validKind else { throw PolicyFieldError(id: definition.id, reason: .invalidType) }

        switch definition.rule {
        case .boolean: break
        case .integer(let low, let high):
            guard case .integer(let integer) = value, (low...high).contains(integer) else {
                throw PolicyFieldError(id: definition.id, reason: .outOfRange)
            }
        case .optionalInteger(let low, let high):
            if case .integer(let integer) = value, !(low...high).contains(integer) {
                throw PolicyFieldError(id: definition.id, reason: .outOfRange)
            }
        case .choices(let choices):
            guard case .choice(let choice) = value, choices.contains(choice) else {
                throw PolicyFieldError(id: definition.id, reason: .outOfRange)
            }
        case .identityList:
            guard case .strings(let strings) = value else { return }
            try validateList(strings, id: definition.id, requireUnique: true)
        case .domains:
            guard case .strings(let strings) = value else { return }
            try validateList(strings, id: definition.id, requireUnique: true)
            guard strings.allSatisfy(validDomain) else {
                throw PolicyFieldError(id: definition.id, reason: .invalidIdentity)
            }
        case .projectID:
            if case .choice(let project) = value, !validOpaqueID(project) {
                throw PolicyFieldError(id: definition.id, reason: .invalidIdentity)
            }
        case .exclusions, .pins:
            guard case .strings(let strings) = value else { return }
            try validateList(strings, id: definition.id, requireUnique: true)
            guard strings.allSatisfy({ !$0.isEmpty }) else {
                throw PolicyFieldError(id: definition.id, reason: .invalidIdentity)
            }
        case .headroomTarget, .headroomWarning, .headroomClear, .budgetHigh:
            if case .integer(let integer) = value, !(1...1_024).contains(integer) {
                throw PolicyFieldError(id: definition.id, reason: .outOfRange)
            }
        case .budgetLow:
            if case .integer(let integer) = value, !(0...1_023).contains(integer) {
                throw PolicyFieldError(id: definition.id, reason: .outOfRange)
            }
        case .volumeOverride:
            guard case .volume(let override) = value else { return }
            for field in [override.target, override.warning, override.clear] {
                if case .fixedGiB(let integer) = field, !(1...1_024).contains(integer) {
                    throw PolicyFieldError(id: definition.id, reason: .outOfRange)
                }
            }
        case .cards:
            guard case .strings(let strings) = value else { return }
            try validateList(strings, id: definition.id, requireUnique: true)
            guard Set(strings).isSubset(of: cards) else {
                throw PolicyFieldError(id: definition.id, reason: .invalidIdentity)
            }
        case .ecosystemOrder:
            guard case .strings(let strings) = value else { return }
            try validateList(strings, id: definition.id, requireUnique: true)
            guard strings.count == FeatureSettings.ecosystemIDs.count,
                  Set(strings) == Set(FeatureSettings.ecosystemIDs) else {
                throw PolicyFieldError(id: definition.id, reason: .invalidIdentity)
            }
        case .clock, .quietEnd:
            guard case .choice(let clock) = value, validClock(clock) else {
                throw PolicyFieldError(id: definition.id, reason: .outOfRange)
            }
        }
    }

    private static func validateList(_ strings: [String], id: SettingID, requireUnique: Bool) throws {
        guard strings.count <= 1_000, strings.allSatisfy({ $0.count <= 4_096 }) else {
            throw PolicyFieldError(id: id, reason: .outOfRange)
        }
        if requireUnique, Set(strings).count != strings.count {
            throw PolicyFieldError(id: id, reason: .invalidIdentity)
        }
    }

    private static func validOpaqueID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 4_096 && !value.unicodeScalars.contains(where: { $0.value < 32 })
    }

    private static func validDomain(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 253, !value.contains("://"), !value.contains("/"),
              !value.contains(" "), value == value.lowercased() else { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { label in
            guard !label.isEmpty, label.count <= 63, label.first != "-", label.last != "-" else { return false }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    private static func validClock(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }

    private enum HeadroomSelection {
        case automatic(FieldSource)
        case fixed(Int64, FieldSource)
    }

    private static func validateEditedHeadroom(_ context: PolicyInputs, edited: Set<SettingID>) throws {
        let editedVolumes = edited.filter { $0.rawValue.hasPrefix(volumePrefix) }
            .sorted { $0.rawValue < $1.rawValue }
        for volumeID in editedVolumes {
            let suffix = String(volumeID.rawValue.dropFirst(volumePrefix.count))
            guard let editedUUID = UUID(uuidString: suffix),
                  let selected = context.selectedVolumeID,
                  editedUUID == selected,
                  context.approvedVolumeIDs.contains(editedUUID) else {
                throw PolicyFieldError(id: volumeID, reason: .boundsUnavailable)
            }
        }
        let volumeErrorID = editedVolumes.first
        guard let selected = context.selectedVolumeID, context.approvedVolumeIDs.contains(selected) else {
            throw PolicyFieldError(id: volumeErrorID ?? edited.sorted(by: { $0.rawValue < $1.rawValue })[0], reason: .boundsUnavailable)
        }
        guard let capacity = context.capacityBytes, capacity > 0 else {
            throw PolicyFieldError(id: volumeErrorID ?? edited.sorted(by: { $0.rawValue < $1.rawValue })[0], reason: .boundsUnavailable)
        }

        func selection(_ fieldName: String) -> HeadroomSelection {
            var result: HeadroomSelection = .automatic(.builtIn)
            let genericID = SettingID(rawValue: "headroom.\(fieldName)GiB")
            let overrideID = SettingID(rawValue: volumePrefix + selected.uuidString)
            for layer in PolicyLayer.allCases {
                if let value = context.layers[layer]?.fields[genericID] {
                    if case .integer(let integer) = value { result = .fixed(integer, .layer(layer)) }
                    if value == .null { result = .automatic(.layer(layer)) }
                }
                if case .volume(let override)? = context.layers[layer]?.fields[overrideID] {
                    let field = fieldName == "target" ? override.target : fieldName == "warning" ? override.warning : override.clear
                    switch field {
                    case .inherit: break
                    case .automatic: result = .automatic(.volume(layer, selected))
                    case .fixedGiB(let integer): result = .fixed(integer, .volume(layer, selected))
                    }
                }
            }
            return result
        }

        let targetSelection = selection("target")
        let target: Int64
        switch targetSelection {
        case .automatic: target = min(20 * gib, capacity / 10)
        case .fixed(let amount, _):
            target = try bytes(gib: amount, for: SettingID(rawValue: "headroom.targetGiB"))
            if target > min(1_024 * gib, capacity / 2) {
                throw PolicyFieldError(id: errorID(for: "target", edited: edited, volume: volumeErrorID), reason: .outOfRange)
            }
        }
        let warningSelection = selection("warning")
        let warning: Int64
        switch warningSelection {
        case .automatic: warning = target
        case .fixed(let amount, _): warning = try bytes(gib: amount, for: SettingID(rawValue: "headroom.warningGiB"))
        }
        let clearSelection = selection("clear")
        let clear: Int64
        switch clearSelection {
        case .automatic:
            let increment = min(2 * gib, capacity / 50)
            let (sum, overflow) = warning.addingReportingOverflow(increment)
            guard !overflow else {
                throw PolicyFieldError(id: errorID(for: "clear", edited: edited, volume: volumeErrorID), reason: .outOfRange)
            }
            clear = sum
        case .fixed(let amount, _): clear = try bytes(gib: amount, for: SettingID(rawValue: "headroom.clearGiB"))
        }
        guard warning < clear else {
            throw PolicyFieldError(id: errorID(for: "clear", edited: edited, volume: volumeErrorID), reason: .invalidRelation)
        }
        guard clear <= capacity else {
            throw PolicyFieldError(id: errorID(for: "clear", edited: edited, volume: volumeErrorID), reason: .outOfRange)
        }
    }

    private static func errorID(for field: String, edited: Set<SettingID>, volume: SettingID?) -> SettingID {
        if let volume { return volume }
        let id = SettingID(rawValue: "headroom.\(field)GiB")
        if edited.contains(id) { return id }
        return edited.sorted(by: { $0.rawValue < $1.rawValue })[0]
    }

    private static func validateEditedBudgets(_ context: PolicyInputs, edited: Set<SettingID>) throws {
        for budget in ExperienceSettings.budgetIDs {
            let prefix = "budget.\(budget)."
            let relevant = edited.filter { $0.rawValue.hasPrefix(prefix) }
            guard !relevant.isEmpty else { continue }
            let highID = SettingID(rawValue: prefix + "highGiB")
            let lowID = SettingID(rawValue: prefix + "lowGiB")
            guard let selected = context.selectedVolumeID, context.approvedVolumeIDs.contains(selected),
                  let capacity = context.capacityBytes, capacity > 0 else {
                throw PolicyFieldError(id: highID, reason: .boundsUnavailable)
            }
            var high = PolicyDefaults.rows.first(where: { $0.id == highID })?.defaultValue ?? .null
            var low: SettingValue = .null
            var enabled = false
            for layer in PolicyLayer.allCases {
                if let value = context.layers[layer]?.fields[highID] { high = value }
                if let value = context.layers[layer]?.fields[lowID] { low = value }
                if case .bool(let value)? = context.layers[layer]?.fields[SettingID(rawValue: prefix + "enabled")], layer == .global {
                    enabled = value
                }
            }
            guard case .integer(let highGiB) = high else {
                if enabled || relevant.contains(highID) || relevant.contains(lowID) {
                    throw PolicyFieldError(id: highID, reason: .boundsUnavailable)
                }
                continue
            }
            let highBytes = try bytes(gib: highGiB, for: highID)
            guard highBytes <= min(1_024 * gib, capacity / 2) else {
                throw PolicyFieldError(id: highID, reason: .outOfRange)
            }
            if case .integer(let lowGiB) = low {
                let lowBytes = try bytes(gib: lowGiB, for: lowID)
                guard lowBytes < highBytes else {
                    throw PolicyFieldError(id: lowID, reason: .invalidRelation)
                }
            }
        }
    }
}
