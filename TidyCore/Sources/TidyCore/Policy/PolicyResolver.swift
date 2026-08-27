import Foundation

public enum PolicyResolver {
    private static let gib: Int64 = 1_073_741_824
    private static let layers = PolicyLayer.allCases
    private enum HeadroomFailure: Error { case invalidForVolume }

    public static func resolve(_ inputs: PolicyInputs) throws -> EffectivePolicy {
        for layer in layers {
            if let values = inputs.layers[layer] {
                try PolicyValidator.validateStructure(values, at: layer)
            }
        }
        try PolicyValidator.validateMergedQuietHours(inputs.layers)

        let itemRows = CleanCatalog.allItems.flatMap { PolicyDefaults.itemRows(catalogID: $0.id) }
        let definitions = PolicyDefaults.rows + itemRows
        var fields: [SettingID: EffectiveField] = [:]

        for definition in definitions {
            if definition.resolution == .authority {
                fields[definition.id] = EffectiveField(value: .unavailable(.authorityUnavailable),
                    sources: [.localAuthority], reason: .authorityUnavailable)
            } else if isDeferred(definition.id) {
                continue
            } else if definition.resolution == .preference {
                fields[definition.id] = preference(definition, inputs: inputs)
            } else {
                fields[definition.id] = restriction(definition, inputs: inputs)
            }
        }

        resolveItemInheritance(definitions: itemRows, fields: &fields, inputs: inputs)
        let exclusions = resolveCollections(fields: &fields, inputs: inputs)
        let (manualBytes, manualItems) = try resolveManualLimits(fields: &fields, inputs: inputs)
        resolveHeadroom(fields: &fields, inputs: inputs)
        resolveBudgets(fields: &fields, inputs: inputs)
        let scan = resolveScan(fields: &fields, inputs: inputs)

        let allowedFeatures = Set(FeatureSettings.featureIDs.filter { feature in
            fields[SettingID(rawValue: "feature.\(feature)")]?.value == .stored(.bool(true))
        })
        return EffectivePolicy(fields: fields, allowedFeatures: allowedFeatures,
            walkWorkers: scan.workers, readOnlyProcesses: scan.processes,
            scanAdmission: scan.admission, manualBatchBytes: manualBytes,
            manualBatchItems: manualItems, exclusions: exclusions)
    }

    private static func isDeferred(_ id: SettingID) -> Bool {
        let raw = id.rawValue
        return raw == "scope.excludedRoots" || raw == "scope.pinnedProjects" ||
            raw == "browsers.keepCookieDomains" || raw == "cleanup.requestedBatchGiB" ||
            raw == "cleanup.requestedBatchItems" || raw == "cleanup.hardBatchGiB" ||
            raw == "cleanup.hardBatchItems" || raw == "scan.requestedWorkers" ||
            raw == "scan.readOnlyProcesses" || raw.hasPrefix("headroom.") ||
            (raw.hasPrefix("budget.") && (raw.hasSuffix("highGiB") || raw.hasSuffix("lowGiB"))) ||
            (raw.hasPrefix("item.") && !raw.hasSuffix(".enabled"))
    }

    private static func preference(_ definition: SettingDefinition, inputs: PolicyInputs) -> EffectiveField {
        var value = definition.defaultValue
        var source: FieldSource = .builtIn
        for layer in layers {
            if let explicit = inputs.layers[layer]?.fields[definition.id] {
                value = explicit
                source = .layer(layer)
            }
        }
        return EffectiveField(value: .stored(value), sources: [source],
                              reason: source == .builtIn ? .defaultValue : .replaced)
    }

    private static func restriction(_ definition: SettingDefinition, inputs: PolicyInputs) -> EffectiveField {
        switch definition.rule {
        case .boolean:
            if definition.id.rawValue == "monitor.suppressHiddenSampling" {
                return trueDominantBoolean(definition, inputs: inputs)
            }
            return falseDominantBoolean(definition, inputs: inputs)
        case .choices:
            if definition.id.rawValue == "scan.onLowPower" || definition.id.rawValue == "scan.onSeriousThermal" {
                return pauseRestriction(definition, inputs: inputs)
            }
            return preference(definition, inputs: inputs)
        default:
            return preference(definition, inputs: inputs)
        }
    }

    private static func falseDominantBoolean(_ definition: SettingDefinition,
                                             inputs: PolicyInputs) -> EffectiveField {
        let explicit = explicitValues(definition.id, inputs: inputs)
        guard !explicit.isEmpty else {
            return EffectiveField(value: .stored(definition.defaultValue), sources: [.builtIn], reason: .defaultValue)
        }
        let defaultFalse = definition.defaultValue == .bool(false)
        let requiresGlobal = defaultFalse && (definition.id.rawValue == "feature.maintenance" ||
            definition.id.rawValue.hasSuffix(".manualActions") || definition.id.rawValue.hasSuffix(".enabled"))
        let globalTrue = inputs.layers[.global]?.fields[definition.id] == .bool(true)
        let hasFalse = explicit.contains { $0.value == .bool(false) }
        let allowed = (!requiresGlobal || globalTrue) && !hasFalse
        var sources = explicit.map(\.source)
        if requiresGlobal && inputs.layers[.global]?.fields[definition.id] == nil {
            sources.insert(.builtIn, at: 0)
        }
        return EffectiveField(value: .stored(.bool(allowed)), sources: orderedSources(sources),
                              reason: allowed ? .replaced : .denied)
    }

    private static func trueDominantBoolean(_ definition: SettingDefinition,
                                            inputs: PolicyInputs) -> EffectiveField {
        let explicit = explicitValues(definition.id, inputs: inputs)
        guard !explicit.isEmpty else {
            return EffectiveField(value: .stored(definition.defaultValue), sources: [.builtIn], reason: .defaultValue)
        }
        let value = explicit.contains { $0.value == .bool(true) }
        return EffectiveField(value: .stored(.bool(value)), sources: orderedSources(explicit.map(\.source)),
                              reason: value ? .denied : .replaced)
    }

    private static func pauseRestriction(_ definition: SettingDefinition,
                                         inputs: PolicyInputs) -> EffectiveField {
        let explicit = explicitValues(definition.id, inputs: inputs)
        guard !explicit.isEmpty else {
            return EffectiveField(value: .stored(definition.defaultValue), sources: [.builtIn], reason: .defaultValue)
        }
        let pauseAll = explicit.contains { $0.value == .choice("pauseAll") }
        return EffectiveField(value: .stored(.choice(pauseAll ? "pauseAll" : "pauseDiscretionary")),
            sources: orderedSources(explicit.map(\.source)), reason: pauseAll ? .denied : .replaced)
    }

    private static func resolveCollections(fields: inout [SettingID: EffectiveField],
                                           inputs: PolicyInputs) -> Set<String> {
        for raw in ["scope.excludedRoots", "scope.pinnedProjects", "browsers.keepCookieDomains"] {
            let id = SettingID(rawValue: raw)
            var combined = Set<String>()
            var sources: [FieldSource] = []
            for layer in layers {
                if case .strings(let values)? = inputs.layers[layer]?.fields[id] {
                    combined.formUnion(values)
                    sources.append(.layer(layer))
                }
            }
            var reason: FieldReason = sources.isEmpty ? .defaultValue : .union
            if raw == "scope.excludedRoots", !inputs.mandatoryExclusions.isEmpty {
                combined.formUnion(inputs.mandatoryExclusions)
                sources.append(.immutable)
                reason = .protected
            }
            if sources.isEmpty { sources = [.builtIn] }
            fields[id] = EffectiveField(value: .stored(.strings(combined.sorted())),
                                        sources: orderedSources(sources), reason: reason)
        }
        if case .stored(.strings(let values))? = fields[SettingID(rawValue: "scope.excludedRoots")]?.value {
            return Set(values)
        }
        return inputs.mandatoryExclusions
    }

    private static func resolveItemInheritance(definitions: [SettingDefinition],
                                               fields: inout [SettingID: EffectiveField],
                                               inputs: PolicyInputs) {
        let bases = ["inactiveDays": "cleanup.inactiveDays", "minimumItemMiB": "cleanup.minimumItemMiB",
                     "retainRecentArtifacts": "cleanup.retainRecentArtifacts"]
        for definition in definitions where definition.defaultValue == .null {
            var explicit: (SettingValue, FieldSource)?
            for layer in layers {
                if let value = inputs.layers[layer]?.fields[definition.id] {
                    explicit = (value, .layer(layer))
                }
            }
            if let explicit, explicit.0 != .null {
                fields[definition.id] = EffectiveField(value: .stored(explicit.0), sources: [explicit.1], reason: .replaced)
            } else {
                let suffix = String(definition.id.rawValue.split(separator: ".").last!)
                let baseID = SettingID(rawValue: bases[suffix]!)
                let inherited = fields[baseID]?.value ?? .stored(.null)
                fields[definition.id] = EffectiveField(value: inherited, sources: [.builtIn], reason: .inherited)
            }
        }
    }

    private static func resolveManualLimits(fields: inout [SettingID: EffectiveField],
                                            inputs: PolicyInputs) throws -> (Int64, Int) {
        let gibResult = try resolveManualLimit(requestID: "cleanup.requestedBatchGiB",
            capID: "cleanup.hardBatchGiB", immutable: PolicyDefaults.hardLimits[.manualGiB]!, inputs: inputs)
        let itemResult = try resolveManualLimit(requestID: "cleanup.requestedBatchItems",
            capID: "cleanup.hardBatchItems", immutable: PolicyDefaults.hardLimits[.manualItems]!, inputs: inputs)
        fields[gibResult.requestID] = gibResult.requestField
        fields[gibResult.capID] = gibResult.capField
        fields[itemResult.requestID] = itemResult.requestField
        fields[itemResult.capID] = itemResult.capField
        return (try PolicyValidator.bytes(gib: gibResult.value, for: gibResult.requestID), Int(itemResult.value))
    }

    private struct ManualResolution {
        let requestID: SettingID
        let capID: SettingID
        let value: Int64
        let requestField: EffectiveField
        let capField: EffectiveField
    }

    private static func resolveManualLimit(requestID rawRequest: String, capID rawCap: String,
                                           immutable: Int64, inputs: PolicyInputs) throws -> ManualResolution {
        let requestID = SettingID(rawValue: rawRequest)
        let capID = SettingID(rawValue: rawCap)
        let requestDefinition = PolicyDefaults.rows.first { $0.id == requestID }!
        var request = integer(requestDefinition.defaultValue)!
        var requestSource: FieldSource = .builtIn
        var caps: [(Int64, FieldSource)] = []
        for layer in layers {
            if let value = inputs.layers[layer]?.fields[requestID], let amount = integer(value) {
                request = amount
                requestSource = .layer(layer)
            }
            if let value = inputs.layers[layer]?.fields[capID], let amount = integer(value) {
                caps.append((amount, .layer(layer)))
            }
        }
        let userCap = caps.map(\.0).min()
        let afterUser = min(request, userCap ?? request)
        let final = min(afterUser, immutable)
        var requestSources = [requestSource] + caps.map(\.1)
        var reason: FieldReason = requestSource == .builtIn ? .defaultValue : .replaced
        if afterUser < request { reason = .strictestCap }
        if final < afterUser {
            requestSources.append(.immutable)
            reason = .strictestCap
        }
        let capField: EffectiveField
        if let userCap {
            capField = EffectiveField(value: .stored(.integer(userCap)),
                                      sources: orderedSources(caps.map(\.1)), reason: .strictestCap)
        } else {
            capField = EffectiveField(value: .stored(.null), sources: [.builtIn], reason: .defaultValue)
        }
        return ManualResolution(requestID: requestID, capID: capID, value: final,
            requestField: EffectiveField(value: .stored(.integer(final)), sources: orderedSources(requestSources), reason: reason),
            capField: capField)
    }

    private enum HeadroomSelection {
        case automatic(FieldSource)
        case fixed(Int64, FieldSource)
        var source: FieldSource {
            switch self { case .automatic(let source), .fixed(_, let source): return source }
        }
        var automatic: Bool { if case .automatic = self { return true }; return false }
    }

    private static func resolveHeadroom(fields: inout [SettingID: EffectiveField], inputs: PolicyInputs) {
        let names = ["target", "warning", "clear"]
        guard let selected = inputs.selectedVolumeID, inputs.approvedVolumeIDs.contains(selected) else {
            for name in names { setUnavailableHeadroom(name, reason: .unmatchedVolume, fields: &fields, inputs: inputs) }
            return
        }
        guard let capacity = inputs.capacityBytes, capacity > 0 else {
            for name in names { setUnavailableHeadroom(name, reason: .capacityUnavailable, fields: &fields, inputs: inputs) }
            return
        }
        let targetSelection = headroomSelection("target", volume: selected, inputs: inputs)
        let warningSelection = headroomSelection("warning", volume: selected, inputs: inputs)
        let clearSelection = headroomSelection("clear", volume: selected, inputs: inputs)
        do {
            let target: Int64
            switch targetSelection {
            case .automatic: target = min(20 * gib, capacity / 10)
            case .fixed(let amount, _): target = try PolicyValidator.bytes(gib: amount, for: SettingID(rawValue: "headroom.targetGiB"))
            }
            guard targetSelection.automatic || target <= min(1_024 * gib, capacity / 2) else {
                throw HeadroomFailure.invalidForVolume
            }
            let warning: Int64
            switch warningSelection {
            case .automatic: warning = target
            case .fixed(let amount, _): warning = try PolicyValidator.bytes(gib: amount, for: SettingID(rawValue: "headroom.warningGiB"))
            }
            let clear: Int64
            switch clearSelection {
            case .automatic:
                let (sum, overflow) = warning.addingReportingOverflow(min(2 * gib, capacity / 50))
                guard !overflow else { throw HeadroomFailure.invalidForVolume }
                clear = sum
            case .fixed(let amount, _): clear = try PolicyValidator.bytes(gib: amount, for: SettingID(rawValue: "headroom.clearGiB"))
            }
            guard warning < clear, clear <= capacity else { throw HeadroomFailure.invalidForVolume }
            for (name, amount, selection) in [("target", target, targetSelection),
                                               ("warning", warning, warningSelection),
                                               ("clear", clear, clearSelection)] {
                fields[SettingID(rawValue: "headroom.\(name)GiB")] = EffectiveField(value: .bytes(amount),
                    sources: [selection.source], reason: selection.automatic ? .automatic : .replaced)
            }
        } catch {
            for name in names { setUnavailableHeadroom(name, reason: .invalidForVolume, fields: &fields, inputs: inputs) }
        }
    }

    private static func headroomSelection(_ name: String, volume: UUID,
                                          inputs: PolicyInputs) -> HeadroomSelection {
        var selection: HeadroomSelection = .automatic(.builtIn)
        let genericID = SettingID(rawValue: "headroom.\(name)GiB")
        let volumeID = SettingID(rawValue: "headroom.volumeOverrides.\(volume.uuidString)")
        for layer in layers {
            if let value = inputs.layers[layer]?.fields[genericID] {
                if case .integer(let amount) = value { selection = .fixed(amount, .layer(layer)) }
                if value == .null { selection = .automatic(.layer(layer)) }
            }
            if case .volume(let override)? = inputs.layers[layer]?.fields[volumeID] {
                let field = name == "target" ? override.target : name == "warning" ? override.warning : override.clear
                switch field {
                case .inherit: break
                case .automatic: selection = .automatic(.volume(layer, volume))
                case .fixedGiB(let amount): selection = .fixed(amount, .volume(layer, volume))
                }
            }
        }
        return selection
    }

    private static func setUnavailableHeadroom(_ name: String, reason: FieldReason,
                                               fields: inout [SettingID: EffectiveField], inputs: PolicyInputs) {
        let id = SettingID(rawValue: "headroom.\(name)GiB")
        var sources: [FieldSource] = [.builtIn]
        if let selected = inputs.selectedVolumeID {
            let selection = headroomSelection(name, volume: selected, inputs: inputs)
            sources = [selection.source]
        }
        if !sources.contains(.immutable) { sources.append(.immutable) }
        fields[id] = EffectiveField(value: .unavailable(reason), sources: orderedSources(sources), reason: reason)
    }

    private static func resolveBudgets(fields: inout [SettingID: EffectiveField], inputs: PolicyInputs) {
        for budget in ExperienceSettings.budgetIDs {
            let enabledID = SettingID(rawValue: "budget.\(budget).enabled")
            let highID = SettingID(rawValue: "budget.\(budget).highGiB")
            let lowID = SettingID(rawValue: "budget.\(budget).lowGiB")
            let highDefinition = PolicyDefaults.rows.first { $0.id == highID }!
            let lowDefinition = PolicyDefaults.rows.first { $0.id == lowID }!
            let high = preference(highDefinition, inputs: inputs)
            let low = preference(lowDefinition, inputs: inputs)

            let availability: FieldReason?
            if inputs.selectedVolumeID == nil || !inputs.approvedVolumeIDs.contains(inputs.selectedVolumeID!) {
                availability = .unmatchedVolume
            } else if inputs.capacityBytes == nil || inputs.capacityBytes! <= 0 {
                availability = .capacityUnavailable
            } else {
                availability = nil
            }
            if let availability {
                invalidateBudget(enabledID: enabledID, highID: highID, lowID: lowID,
                                 high: high, low: low, reason: availability, fields: &fields)
                continue
            }
            guard case .stored(.integer(let highGiB)) = high.value else {
                fields[highID] = EffectiveField(value: .unavailable(.notConfigured), sources: high.sources, reason: .notConfigured)
                fields[lowID] = EffectiveField(value: .unavailable(.notConfigured), sources: low.sources, reason: .notConfigured)
                if let enabled = fields[enabledID], enabled.value == .stored(.bool(true)) {
                    fields[enabledID] = EffectiveField(value: .stored(.bool(false)),
                        sources: orderedSources(enabled.sources + [.immutable]), reason: .notConfigured)
                }
                continue
            }
            let capacity = inputs.capacityBytes!
            guard let highBytes = try? PolicyValidator.bytes(gib: highGiB, for: highID),
                  highBytes <= min(1_024 * gib, capacity / 2) else {
                invalidateBudget(enabledID: enabledID, highID: highID, lowID: lowID,
                                 high: high, low: low, reason: .invalidForVolume, fields: &fields)
                continue
            }
            let lowBytes: Int64
            var lowSources = low.sources
            let lowReason: FieldReason
            if case .stored(.integer(let lowGiB)) = low.value {
                guard let bytes = try? PolicyValidator.bytes(gib: lowGiB, for: lowID), bytes < highBytes else {
                    invalidateBudget(enabledID: enabledID, highID: highID, lowID: lowID,
                                     high: high, low: low, reason: .invalidForVolume, fields: &fields)
                    continue
                }
                lowBytes = bytes
                lowReason = low.reason
            } else {
                lowBytes = highBytes / 5 * 4 + highBytes % 5 * 4 / 5
                lowSources = orderedSources(low.sources + high.sources)
                lowReason = .automatic
            }
            fields[highID] = high
            fields[lowID] = EffectiveField(value: .bytes(lowBytes), sources: lowSources, reason: lowReason)
        }
    }

    private static func invalidateBudget(enabledID: SettingID, highID: SettingID, lowID: SettingID,
                                         high: EffectiveField, low: EffectiveField, reason: FieldReason,
                                         fields: inout [SettingID: EffectiveField]) {
        let enabled = fields[enabledID] ?? EffectiveField(value: .stored(.bool(false)), sources: [.builtIn], reason: .defaultValue)
        fields[enabledID] = EffectiveField(value: .stored(.bool(false)),
            sources: orderedSources(enabled.sources + [.immutable]), reason: reason)
        fields[highID] = EffectiveField(value: .unavailable(reason),
            sources: orderedSources(high.sources + [.immutable]), reason: reason)
        fields[lowID] = EffectiveField(value: .unavailable(reason),
            sources: orderedSources(low.sources + [.immutable]), reason: reason)
    }

    private static func resolveScan(fields: inout [SettingID: EffectiveField],
                                    inputs: PolicyInputs) -> (workers: Int, processes: Int, admission: ScanAdmission) {
        let presetID = SettingID(rawValue: "scan.preset")
        let workerID = SettingID(rawValue: "scan.requestedWorkers")
        let processID = SettingID(rawValue: "scan.readOnlyProcesses")
        let presetField = fields[presetID]!
        let preset: String
        if case .stored(.choice(let value)) = presetField.value { preset = value } else { preset = "eco" }

        func storedCount(_ id: SettingID, default amount: Int64) -> (Int, FieldSource, FieldReason) {
            var value = amount
            var source: FieldSource = .builtIn
            for layer in layers {
                if let explicit = inputs.layers[layer]?.fields[id], let integer = integer(explicit) {
                    value = integer
                    source = .layer(layer)
                }
            }
            return (Int(value), source, source == .builtIn ? .defaultValue : .replaced)
        }
        let storedWorkers = storedCount(workerID, default: 1)
        let storedProcesses = storedCount(processID, default: 1)
        var workers: Int
        var processes: Int
        var workerSources: [FieldSource]
        var processSources: [FieldSource]
        var workerReason: FieldReason
        var processReason: FieldReason
        switch preset {
        case "balanced":
            workers = 2; processes = 2
            workerSources = presetField.sources; processSources = presetField.sources
            workerReason = .preset; processReason = .preset
        case "custom":
            workers = storedWorkers.0; processes = storedProcesses.0
            workerSources = [storedWorkers.1]; processSources = [storedProcesses.1]
            workerReason = storedWorkers.2; processReason = storedProcesses.2
        default:
            workers = 1; processes = 1
            workerSources = presetField.sources; processSources = presetField.sources
            workerReason = .preset; processReason = .preset
        }

        let cpuLimit = max(0, min(Int(PolicyDefaults.hardLimits[.walkWorkers]!), inputs.logicalCPUCount))
        if workers > cpuLimit {
            workers = cpuLimit
            workerSources.append(.immutable)
            workerReason = .cpuCeiling
        }
        let processLimit = Int(PolicyDefaults.hardLimits[.commandJobs]!)
        if processes > processLimit {
            processes = processLimit
            processSources.append(.immutable)
            processReason = .pressureCeiling
        }

        let lowRule = fields[SettingID(rawValue: "scan.onLowPower")]?.value == .stored(.choice("pauseAll"))
        let thermalRule = fields[SettingID(rawValue: "scan.onSeriousThermal")]?.value == .stored(.choice("pauseAll"))
        let pressureActive = inputs.lowPower || inputs.seriousThermal
        let pauseAll = inputs.critical || (inputs.lowPower && lowRule) || (inputs.seriousThermal && thermalRule)
        let admission: ScanAdmission
        if pauseAll {
            admission = .paused
            if workers != 0 { workers = 0; workerSources.append(.immutable); workerReason = .pressureCeiling }
            if processes != 0 { processes = 0; processSources.append(.immutable); processReason = .pressureCeiling }
        } else if pressureActive {
            admission = .userRequestedOnly
            if workers > 1 { workers = 1; workerSources.append(.immutable); workerReason = .pressureCeiling }
        } else {
            admission = .discretionaryAllowed
        }
        fields[workerID] = EffectiveField(value: .stored(.integer(Int64(workers))),
                                          sources: orderedSources(workerSources), reason: workerReason)
        fields[processID] = EffectiveField(value: .stored(.integer(Int64(processes))),
                                           sources: orderedSources(processSources), reason: processReason)
        return (workers, processes, admission)
    }

    private struct ExplicitValue {
        let value: SettingValue
        let source: FieldSource
    }

    private static func explicitValues(_ id: SettingID, inputs: PolicyInputs) -> [ExplicitValue] {
        layers.compactMap { layer in
            inputs.layers[layer]?.fields[id].map { ExplicitValue(value: $0, source: .layer(layer)) }
        }
    }

    private static func integer(_ value: SettingValue) -> Int64? {
        if case .integer(let integer) = value { return integer }
        return nil
    }

    private static func orderedSources(_ sources: [FieldSource]) -> [FieldSource] {
        var unique: [FieldSource] = []
        for source in sources where !unique.contains(source) { unique.append(source) }
        return unique.sorted { rank($0) < rank($1) }
    }

    private static func rank(_ source: FieldSource) -> Int {
        switch source {
        case .builtIn: return 0
        case .layer(.global): return 10
        case .volume(.global, _): return 11
        case .layer(.profile): return 20
        case .volume(.profile, _): return 21
        case .layer(.project): return 30
        case .volume(.project, _): return 31
        case .layer(.run): return 40
        case .volume(.run, _): return 41
        case .immutable: return 50
        case .localAuthority: return 60
        }
    }
}
