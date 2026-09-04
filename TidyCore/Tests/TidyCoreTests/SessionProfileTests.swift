import Foundation
import Testing
@testable import TidyCore

@Suite struct SessionProfileTests {
    let a = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    let b = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!

    func id(_ raw: String) -> SettingID { .init(rawValue: raw) }
    func values(_ pairs: [(String, SettingValue)]) -> PolicyValues {
        .init(fields: Dictionary(uniqueKeysWithValues: pairs.map { (id($0.0), $0.1) }))
    }

    @Test func everyRestrictionDefinitionHasExactlyOneComparator() throws {
        let definitions = PolicyDefaults.rows + CleanCatalog.allItems.flatMap {
            PolicyDefaults.itemRows(catalogID: $0.id)
        }
        let restrictionIDs = definitions.filter { $0.resolution == .restriction }.map(\.id)
        #expect(Set(restrictionIDs).count == restrictionIDs.count)
        #expect(PolicyRestrictionValidator.coveredSettingIDs == Set(restrictionIDs))
        for definition in definitions where definition.resolution == .restriction {
            #expect(try PolicyRestrictionValidator.relation(
                candidate: definition.defaultValue, baseline: definition.defaultValue,
                for: definition.id) == .equal)
        }
    }

    @Test func booleanAndInverseBooleanDirectionsAreExact() throws {
        #expect(try PolicyRestrictionValidator.relation(candidate: .bool(false), baseline: .bool(true),
            for: id("feature.headroom")) == .stricter)
        #expect(try PolicyRestrictionValidator.relation(candidate: .bool(true), baseline: .bool(false),
            for: id("feature.headroom")) == .weaker)
        #expect(try PolicyRestrictionValidator.relation(candidate: .bool(true), baseline: .bool(false),
            for: id("monitor.suppressHiddenSampling")) == .stricter)
        #expect(try PolicyRestrictionValidator.relation(candidate: .bool(false), baseline: .bool(true),
            for: id("monitor.suppressHiddenSampling")) == .weaker)
    }

    @Test func pauseSetsAndCapsAreMonotone() throws {
        #expect(try PolicyRestrictionValidator.relation(candidate: .choice("pauseAll"),
            baseline: .choice("pauseDiscretionary"), for: id("scan.onLowPower")) == .stricter)
        #expect(try PolicyRestrictionValidator.relation(candidate: .strings(["/a", "/b"]),
            baseline: .strings(["/a"]), for: id("scope.excludedRoots")) == .stricter)
        #expect(try PolicyRestrictionValidator.relation(candidate: .strings(["/b"]),
            baseline: .strings(["/a"]), for: id("scope.excludedRoots")) == .weaker)
        #expect(try PolicyRestrictionValidator.relation(candidate: .integer(8), baseline: .null,
            for: id("cleanup.hardBatchGiB")) == .stricter)
        #expect(try PolicyRestrictionValidator.relation(candidate: .integer(8), baseline: .integer(12),
            for: id("cleanup.hardBatchGiB")) == .stricter)
        #expect(try PolicyRestrictionValidator.relation(candidate: .null, baseline: .integer(8),
            for: id("cleanup.hardBatchGiB")) == .weaker)
    }

    @Test func validProfileCannotWeakenInheritedProtection() throws {
        let inherited = values([("feature.maintenance", .bool(false)),
                                ("scope.pinnedProjects", .strings(["critical"]))])
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try PolicyRestrictionValidator.validate(
                values([("feature.maintenance", .bool(true))]), inherited: inherited, at: .profile)
        }
        #expect(throws: SessionProfileError.protectionWeakening(id("scope.pinnedProjects"))) {
            try PolicyRestrictionValidator.validate(
                values([("scope.pinnedProjects", .strings([]))]), inherited: inherited, at: .profile)
        }
        try PolicyRestrictionValidator.validate(
            values([("feature.maintenance", .bool(false)),
                    ("scope.pinnedProjects", .strings(["critical", "private"]))]),
            inherited: inherited, at: .profile)
    }

    @Test func createTrimsNameAllowsDuplicateNamesAndRejectsDuplicateIDs() throws {
        let first = try SessionProfiles.create(id: a, name: "  Work \n", values: .init(),
            inherited: .init(), in: [])
        #expect(first == [SavedProfile(id: a, name: "Work", values: .init())])
        let second = try SessionProfiles.create(id: b, name: "Work", values: .init(),
            inherited: .init(), in: first)
        #expect(second.map(\.name) == ["Work", "Work"])
        #expect(throws: SessionProfileError.duplicateID(a)) {
            try SessionProfiles.create(id: a, name: "Again", values: .init(),
                inherited: .init(), in: second)
        }
        #expect(throws: SessionProfileError.invalidName) {
            try SessionProfiles.rename(id: a, name: " \n ", inherited: .init(), in: second)
        }
    }

    @Test func profileBoundAndUnsupportedOrAuthorityFieldsReject() throws {
        let fifty = (0..<50).map { index in
            SavedProfile(id: UUID(uuidString: String(format:
                "00000000-0000-0000-0000-%012d", index))!, name: "P\(index)", values: .init())
        }
        #expect(throws: SessionProfileError.tooManyProfiles) {
            try SessionProfiles.create(id: a, name: "51", values: .init(), inherited: .init(), in: fifty)
        }
        #expect(throws: PolicyFieldError(id: id("scope.projectRoots"), reason: .authorityIsLocal)) {
            try SessionProfiles.create(id: a, name: "A",
                values: values([("scope.projectRoots", .strings(["/tmp"]))]),
                inherited: .init(), in: [])
        }
        #expect(throws: PolicyFieldError(id: id("scan.preset"), reason: .unsupportedLayer)) {
            try PolicyRestrictionValidator.validate(
                values([("scan.preset", .choice("eco"))]), inherited: .init(), at: .project)
        }
    }

    @Test func canonicalProjectAndVolumeIdentitiesCannotEnterProfiles() throws {
        let volumeA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let volumeB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        for volume in [volumeA, volumeB] {
            let fieldID = id("headroom.volumeOverrides.\(volume.uuidString)")
            #expect(throws: SessionProfileError.nonProfileField(fieldID)) {
                try SessionProfiles.create(id: a, name: "Volume",
                    values: PolicyValues(fields: [fieldID: .volume(.init(
                        target: .fixedGiB(10), warning: .automatic, clear: .inherit))]),
                    inherited: .init(), in: [])
            }
        }
        let projectID = id("scope.currentProject")
        #expect(throws: SessionProfileError.nonProfileField(projectID)) {
            try SessionProfiles.create(id: a, name: "Project",
                values: PolicyValues(fields: [projectID: .choice("project-1")]),
                inherited: .init(), in: [])
        }
    }

    @Test func cloneAndFactoryAppendWithoutActivationOrTemplateIdentity() throws {
        let source = SavedProfile(id: a, name: "Source",
            values: values([("scan.preset", .choice("eco"))]))
        let cloned = try SessionProfiles.clone(sourceID: a, newID: b, name: " Copy ",
            inherited: .init(), in: [source])
        #expect(cloned[0] == source)
        #expect(cloned[1].id == b)
        #expect(cloned[1].name == "Copy")
        #expect(cloned[1].values == source.values)
        #expect(SessionProfiles.factoryKeys == ["xcode", "android", "flutter", "web", "localAI", "battery"])
        let factory = try SessionProfiles.createFactory(key: "battery", id: b, name: "Battery",
            inherited: .init(), in: [])
        #expect(factory == [SavedProfile(id: b, name: "Battery",
            values: try PolicyDefaults.factory("battery"))])
    }

    @Test func diffIsStableAndUsesDefinitionMetadataWithoutCopy() throws {
        let base = SavedProfile(id: a, name: "A",
            values: values([("scan.preset", .choice("eco"))]))
        let candidate = SavedProfile(id: a, name: "A", values: values([
            ("scan.preset", .choice("balanced")), ("ui.units", .choice("decimal"))]))
        let changes = try SessionProfiles.diff(base: base, candidate: candidate, inherited: .init())
        #expect(changes.map { $0.id.rawValue } == ["scan.preset", "ui.units"])
        #expect(changes[0].oldValue == .choice("eco"))
        #expect(changes[0].newValue == .choice("balanced"))
        #expect(changes[0].defaultValue == .choice("eco"))
        #expect(changes[0].resolution == .preference)
        #expect(changes[0].effect == .invalidate)
        #expect(changes[0].oldSource == .explicit && changes[0].newSource == .explicit)
    }

    @Test func selectiveResetRequiresExplicitRestrictionPreviewAndTouchesNothingElse() throws {
        let profile = SavedProfile(id: a, name: "A", values: values([
            ("scan.preset", .choice("balanced")),
            ("feature.headroom", .bool(false)),
            ("ui.units", .choice("decimal"))]))
        #expect(throws: SessionProfileError.restrictionResetRequiresPreview(id("feature.headroom"))) {
            try SessionProfiles.previewReset(id: a,
                fieldIDs: [id("scan.preset"), id("feature.headroom")],
                includeOwnedRestrictions: false, inherited: .init(), in: [profile])
        }
        let preview = try SessionProfiles.previewReset(id: a,
            fieldIDs: [id("scan.preset"), id("feature.headroom")],
            includeOwnedRestrictions: true, inherited: .init(), in: [profile])
        #expect(preview.base == profile)
        #expect(preview.candidate.values.fields == [id("ui.units"): .choice("decimal")])
        #expect(preview.changes.map { $0.id.rawValue } == ["feature.headroom", "scan.preset"])
    }

    @Test func deleteAndRenamePreserveArrayPositionAndNeverActivate() throws {
        let profiles = [SavedProfile(id: a, name: "A", values: .init()),
                        SavedProfile(id: b, name: "B", values: .init())]
        #expect(try SessionProfiles.rename(id: b, name: " Renamed ", inherited: .init(), in: profiles).map(\.name)
            == ["A", "Renamed"])
        #expect(try SessionProfiles.delete(id: a, inherited: .init(), in: profiles) == [profiles[1]])
        let missing = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        #expect(throws: SessionProfileError.missingProfile(missing)) {
            try SessionProfiles.delete(id: missing, inherited: .init(), in: profiles)
        }
    }

    @Test func everyRestrictionExercisesEqualStricterAndWeakerDirections() throws {
        let definitions = PolicyDefaults.rows + CleanCatalog.allItems.flatMap {
            PolicyDefaults.itemRows(catalogID: $0.id)
        }
        for definition in definitions where definition.resolution == .restriction {
            let equal: SettingValue
            let stricter: SettingValue
            let weaker: SettingValue
            switch definition.rule {
            case .boolean:
                if definition.id.rawValue == "monitor.suppressHiddenSampling" {
                    equal = .bool(false); stricter = .bool(true); weaker = .bool(false)
                    #expect(try PolicyRestrictionValidator.relation(candidate: stricter,
                        baseline: equal, for: definition.id) == .stricter)
                    #expect(try PolicyRestrictionValidator.relation(candidate: weaker,
                        baseline: stricter, for: definition.id) == .weaker)
                } else {
                    equal = .bool(true); stricter = .bool(false); weaker = .bool(true)
                    #expect(try PolicyRestrictionValidator.relation(candidate: stricter,
                        baseline: equal, for: definition.id) == .stricter)
                    #expect(try PolicyRestrictionValidator.relation(candidate: weaker,
                        baseline: stricter, for: definition.id) == .weaker)
                }
            case .choices:
                equal = .choice("pauseDiscretionary"); stricter = .choice("pauseAll")
                #expect(try PolicyRestrictionValidator.relation(candidate: stricter,
                    baseline: equal, for: definition.id) == .stricter)
                #expect(try PolicyRestrictionValidator.relation(candidate: equal,
                    baseline: stricter, for: definition.id) == .weaker)
            case .exclusions:
                equal = .strings(["/safe"]); stricter = .strings(["/safe", "/private"])
                #expect(try PolicyRestrictionValidator.relation(candidate: stricter,
                    baseline: equal, for: definition.id) == .stricter)
                #expect(try PolicyRestrictionValidator.relation(candidate: .strings(["/other"]),
                    baseline: equal, for: definition.id) == .weaker)
            case .pins:
                equal = .strings(["critical"]); stricter = .strings(["critical", "private"])
                #expect(try PolicyRestrictionValidator.relation(candidate: stricter,
                    baseline: equal, for: definition.id) == .stricter)
                #expect(try PolicyRestrictionValidator.relation(candidate: .strings(["other"]),
                    baseline: equal, for: definition.id) == .weaker)
            case .domains:
                equal = .strings(["a.example"]); stricter = .strings(["a.example", "b.example"])
                #expect(try PolicyRestrictionValidator.relation(candidate: stricter,
                    baseline: equal, for: definition.id) == .stricter)
                #expect(try PolicyRestrictionValidator.relation(candidate: .strings(["c.example"]),
                    baseline: equal, for: definition.id) == .weaker)
            case .optionalInteger:
                equal = .integer(10); stricter = .integer(5)
                #expect(try PolicyRestrictionValidator.relation(candidate: stricter,
                    baseline: equal, for: definition.id) == .stricter)
                #expect(try PolicyRestrictionValidator.relation(candidate: .integer(20),
                    baseline: equal, for: definition.id) == .weaker)
                #expect(try PolicyRestrictionValidator.relation(candidate: .integer(10),
                    baseline: .null, for: definition.id) == .stricter)
                #expect(try PolicyRestrictionValidator.relation(candidate: .null,
                    baseline: equal, for: definition.id) == .weaker)
            default:
                Issue.record("Unhandled R rule for \(definition.id.rawValue)")
                continue
            }
            #expect(try PolicyRestrictionValidator.relation(candidate: equal,
                baseline: equal, for: definition.id) == .equal)
        }
    }

    @Test func comparatorRejectsUnknownNonRestrictionMalformedAndInventedShapes() throws {
        #expect(throws: PolicyFieldError(id: id("unknown.setting"), reason: .unknownKey)) {
            try PolicyRestrictionValidator.relation(candidate: .bool(false), baseline: .bool(true),
                for: id("unknown.setting"))
        }
        #expect(throws: SessionProfileError.notRestriction(id("scan.preset"))) {
            try PolicyRestrictionValidator.relation(candidate: .choice("eco"), baseline: .choice("eco"),
                for: id("scan.preset"))
        }
        #expect(throws: PolicyFieldError(id: id("feature.headroom"), reason: .invalidType)) {
            try PolicyRestrictionValidator.relation(candidate: .integer(1), baseline: .bool(true),
                for: id("feature.headroom"))
        }
        #expect(throws: PolicyFieldError(id: id("cleanup.hardBatchItems"), reason: .outOfRange)) {
            try PolicyRestrictionValidator.relation(candidate: .integer(101), baseline: .integer(10),
                for: id("cleanup.hardBatchItems"))
        }
        for (raw, bad) in [("scope.excludedRoots", SettingValue.strings(["relative"])),
                           ("scope.pinnedProjects", .strings(["x", "x"])),
                           ("browsers.keepCookieDomains", .strings(["HTTPS://BAD"]))] {
            #expect(throws: PolicyFieldError.self) {
                try PolicyRestrictionValidator.relation(candidate: bad, baseline: .strings([]), for: id(raw))
            }
        }
        let invented = SettingDefinition(id: id("invented.r"), kind: .integer,
            defaultValue: .integer(1), rule: .integer(1, 2), resolution: .restriction,
            effect: .invalidate, layers: [.profile], group: "fixture")
        #expect(throws: PolicyFieldError(id: id("invented.r"), reason: .invalidType)) {
            try PolicyRestrictionValidator.relation(candidate: .integer(1), baseline: .integer(1),
                definition: invented)
        }
    }

    @Test func everyProfileNameEntryPointUsesUTF8ByteLimit() throws {
        let ascii4096 = String(repeating: "a", count: 4_096)
        let ascii4097 = ascii4096 + "a"
        let multi4096 = String(repeating: "é", count: 2_048)
        let multi4098 = multi4096 + "é"
        let first = try SessionProfiles.create(id: a, name: ascii4096, values: .init(),
            inherited: .init(), in: [])
        #expect(first[0].name.utf8.count == 4_096)
        #expect(try SessionProfiles.rename(id: a, name: multi4096,
            inherited: .init(), in: first)[0].name.utf8.count == 4_096)
        let clonedAtLimit = try SessionProfiles.clone(sourceID: a, newID: b,
            name: "  \(multi4096)  ", inherited: .init(), in: first)
        #expect(clonedAtLimit.last?.name == multi4096)
        #expect(clonedAtLimit.last?.name.utf8.count == 4_096)
        let factoryID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let factoryAtLimit = try SessionProfiles.createFactory(key: "xcode", id: factoryID,
            name: "\n\(ascii4096)\n", inherited: .init(), in: first)
        #expect(factoryAtLimit.last?.name == ascii4096)
        #expect(factoryAtLimit.last?.name.utf8.count == 4_096)
        for bad in [ascii4097, multi4098] {
            #expect(throws: SessionProfileError.invalidName) {
                try SessionProfiles.create(id: b, name: bad, values: .init(), inherited: .init(), in: first)
            }
            #expect(throws: SessionProfileError.invalidName) {
                try SessionProfiles.clone(sourceID: a, newID: b, name: bad,
                    inherited: .init(), in: first)
            }
            #expect(throws: SessionProfileError.invalidName) {
                try SessionProfiles.createFactory(key: "xcode", id: b, name: bad,
                    inherited: .init(), in: first)
            }
            #expect(throws: SessionProfileError.invalidName) {
                try SessionProfiles.rename(id: a, name: bad, inherited: .init(), in: first)
            }
        }
    }

    @Test func malformedExistingArraysFailBeforeOperationSpecificErrors() throws {
        let duplicate = [SavedProfile(id: a, name: "A", values: .init()),
                         SavedProfile(id: a, name: "Again", values: .init())]
        #expect(throws: SessionProfileError.duplicateID(a)) {
            try SessionProfiles.rename(id: b, name: "B", inherited: .init(), in: duplicate)
        }
        #expect(throws: SessionProfileError.duplicateID(a)) {
            try SessionProfiles.delete(id: b, inherited: .init(), in: duplicate)
        }
        let source = [SavedProfile(id: a, name: "A", values: .init())]
        #expect(throws: SessionProfileError.duplicateID(a)) {
            try SessionProfiles.clone(sourceID: a, newID: a, name: "Copy",
                inherited: .init(), in: source)
        }
        #expect(throws: SessionProfileError.missingProfile(b)) {
            try SessionProfiles.clone(sourceID: b, newID: UUID(), name: "Copy",
                inherited: .init(), in: source)
        }
        #expect(throws: SessionProfileError.duplicateID(a)) {
            try SessionProfiles.createFactory(key: "xcode", id: a, name: "Factory",
                inherited: .init(), in: source)
        }
        let fiftyOne = (0..<51).map { index in
            SavedProfile(id: UUID(uuidString: String(format:
                "10000000-0000-0000-0000-%012d", index))!, name: "P\(index)", values: .init())
        }
        #expect(throws: SessionProfileError.tooManyProfiles) {
            try SessionProfiles.delete(id: b, inherited: .init(), in: fiftyOne)
        }
    }

    @Test func allFactoriesAreExactAndProviderOutputIsValidated() throws {
        let keys = ["xcode", "android", "flutter", "web", "localAI", "battery"]
        var profiles: [SavedProfile] = []
        for (index, key) in keys.enumerated() {
            let profileID = UUID(uuidString: String(format:
                "20000000-0000-0000-0000-%012d", index))!
            profiles = try SessionProfiles.createFactory(key: key, id: profileID,
                name: "  \(key)  ", inherited: .init(), in: profiles)
            #expect(profiles.last == SavedProfile(id: profileID, name: key,
                values: try PolicyDefaults.factory(key)))
        }
        #expect(throws: SessionProfileError.invalidFactory("missing")) {
            try SessionProfiles.createFactory(key: "missing", id: UUID(), name: "Missing",
                inherited: .init(), in: profiles)
        }
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.createFactory(key: "fixture", id: UUID(), name: "Fixture",
                inherited: values([("feature.maintenance", .bool(false))]), in: [],
                provider: { _ in self.values([("feature.maintenance", .bool(true))]) })
        }
    }

    @Test func everyProfileEntryPointRevalidatesStructureAndMonotonicity() throws {
        let inherited = values([("feature.maintenance", .bool(false))])
        let weaker = SavedProfile(id: a, name: "Weak",
            values: values([("feature.maintenance", .bool(true))]))
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.create(id: a, name: "Weak", values: weaker.values,
                inherited: inherited, in: [])
        }
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.clone(sourceID: a, newID: b, name: "Clone",
                inherited: inherited, in: [weaker])
        }
        let malformed = SavedProfile(id: a, name: "Bad",
            values: values([("headroom.volumeOverrides.not-a-uuid", .null)]))
        #expect(throws: PolicyFieldError.self) {
            try SessionProfiles.rename(id: a, name: "Still bad", inherited: .init(), in: [malformed])
        }
        #expect(throws: PolicyFieldError.self) {
            try SessionProfiles.delete(id: a, inherited: .init(), in: [malformed])
        }
    }

    @Test func everyArrayWrapperValidatesUnrelatedProfilesAndSharedPrecedence() throws {
        let inherited = values([("feature.maintenance", .bool(false))])
        let good = SavedProfile(id: a, name: "Good",
            values: values([("scan.preset", .choice("eco"))]))
        let malformed = SavedProfile(id: b, name: "Malformed",
            values: values([("ui.units", .choice("not-a-unit"))]))
        let weakID = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
        let weaker = SavedProfile(id: weakID, name: "Weaker",
            values: values([("feature.maintenance", .bool(true))]))
        let newID = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!

        #expect(throws: PolicyFieldError(id: id("ui.units"), reason: .outOfRange)) {
            try SessionProfiles.create(id: newID, name: " ", values: .init(),
                inherited: inherited, in: [good, malformed])
        }
        #expect(throws: PolicyFieldError(id: id("ui.units"), reason: .outOfRange)) {
            try SessionProfiles.clone(sourceID: a, newID: newID, name: "Clone",
                inherited: inherited, in: [good, malformed])
        }
        #expect(throws: PolicyFieldError(id: id("ui.units"), reason: .outOfRange)) {
            try SessionProfiles.createFactory(key: "xcode", id: newID, name: "Factory",
                inherited: inherited, in: [good, malformed])
        }
        #expect(throws: PolicyFieldError(id: id("ui.units"), reason: .outOfRange)) {
            try SessionProfiles.rename(id: newID, name: "Missing",
                inherited: inherited, in: [good, malformed])
        }
        #expect(throws: PolicyFieldError(id: id("ui.units"), reason: .outOfRange)) {
            try SessionProfiles.delete(id: newID, inherited: inherited, in: [good, malformed])
        }
        #expect(throws: PolicyFieldError(id: id("ui.units"), reason: .outOfRange)) {
            try SessionProfiles.previewReset(id: a, fieldIDs: [],
                includeOwnedRestrictions: false, inherited: inherited, in: [good, malformed])
        }

        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.create(id: newID, name: "New", values: .init(),
                inherited: inherited, in: [good, weaker])
        }
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.clone(sourceID: a, newID: newID, name: "Clone",
                inherited: inherited, in: [good, weaker])
        }
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.createFactory(key: "xcode", id: newID, name: "Factory",
                inherited: inherited, in: [good, weaker])
        }
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.rename(id: a, name: "Renamed",
                inherited: inherited, in: [good, weaker])
        }
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.delete(id: a, inherited: inherited, in: [good, weaker])
        }
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.previewReset(id: a, fieldIDs: [],
                includeOwnedRestrictions: false, inherited: inherited, in: [good, weaker])
        }

        var uniqueOverLimit = (0..<51).map { index in
            SavedProfile(id: UUID(uuidString: String(format:
                "30000000-0000-0000-0000-%012d", index))!, name: "P\(index)", values: .init())
        }
        uniqueOverLimit[50] = SavedProfile(id: uniqueOverLimit[50].id, name: "Bad",
            values: values([("ui.units", .choice("not-a-unit"))]))
        #expect(throws: SessionProfileError.tooManyProfiles) {
            try SessionProfiles.create(id: newID, name: "New", values: .init(),
                inherited: inherited, in: uniqueOverLimit)
        }
        var duplicateOverLimit = uniqueOverLimit
        duplicateOverLimit.append(SavedProfile(id: uniqueOverLimit[0].id,
            name: "Duplicate", values: values([("ui.units", .choice("not-a-unit"))])))
        #expect(throws: SessionProfileError.duplicateID(uniqueOverLimit[0].id)) {
            try SessionProfiles.delete(id: newID, inherited: inherited, in: duplicateOverLimit)
        }
    }

    @Test func diffRejectsIdentityAndInvalidSidesAndReportsAbsentProvenance() throws {
        let base = SavedProfile(id: a, name: "A", values: values([
            ("scan.preset", .choice("eco")), ("feature.headroom", .bool(false))]))
        let wrong = SavedProfile(id: b, name: "B", values: .init())
        #expect(throws: SessionProfileError.profileIdentityMismatch(expected: a, actual: b)) {
            try SessionProfiles.diff(base: base, candidate: wrong, inherited: .init())
        }
        let invalid = SavedProfile(id: a, name: "A",
            values: values([("scan.preset", .integer(1))]))
        #expect(throws: PolicyFieldError.self) {
            try SessionProfiles.diff(base: invalid, candidate: base, inherited: .init())
        }
        #expect(throws: PolicyFieldError.self) {
            try SessionProfiles.diff(base: base, candidate: invalid, inherited: .init())
        }
        let inherited = values([("scan.preset", .choice("balanced"))])
        let removed = SavedProfile(id: a, name: "A", values: .init())
        let changes = try SessionProfiles.diff(base: base, candidate: removed, inherited: inherited)
        #expect(changes.map { $0.id.rawValue } == ["feature.headroom", "scan.preset"])
        #expect(changes[0].resolution == .restriction)
        #expect(changes[0].newSource == .registryDefault)
        #expect(changes[1].newSource == .inherited)
        let inserted = try SessionProfiles.diff(base: removed, candidate: base, inherited: inherited)
        #expect(inserted.map { $0.id.rawValue } == ["feature.headroom", "scan.preset"])

        let protection = values([("feature.maintenance", .bool(false))])
        let weak = SavedProfile(id: a, name: "Weak",
            values: values([("feature.maintenance", .bool(true))]))
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.diff(base: weak, candidate: removed, inherited: protection)
        }
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.diff(base: removed, candidate: weak, inherited: protection)
        }
    }

    @Test func resetNegativePathsAndProvenanceAreExactAndPure() throws {
        let profile = SavedProfile(id: a, name: "A", values: values([
            ("scan.preset", .choice("eco")), ("feature.headroom", .bool(false)),
            ("ui.units", .choice("decimal"))]))
        let original = [profile]
        #expect(throws: SessionProfileError.missingProfile(b)) {
            try SessionProfiles.previewReset(id: b, fieldIDs: [],
                includeOwnedRestrictions: true, inherited: .init(), in: original)
        }
        for raw in ["ui.density", "budget.other.enabled"] {
            #expect(throws: SessionProfileError.nonProfileField(id(raw))) {
                try SessionProfiles.previewReset(id: a, fieldIDs: [id(raw)],
                    includeOwnedRestrictions: true, inherited: .init(), in: original)
            }
        }
        let empty = try SessionProfiles.previewReset(id: a, fieldIDs: [],
            includeOwnedRestrictions: false, inherited: .init(), in: original)
        #expect(empty.base == profile && empty.candidate == profile && empty.changes.isEmpty)
        #expect(original == [profile])
        let inherited = values([("scan.preset", .choice("balanced"))])
        let reset = try SessionProfiles.previewReset(id: a,
            fieldIDs: [id("scan.preset"), id("feature.headroom")],
            includeOwnedRestrictions: true, inherited: inherited, in: original)
        #expect(inherited == values([("scan.preset", .choice("balanced"))]))
        #expect(reset.changes.first { $0.id == id("scan.preset") }?.newSource == .inherited)
        #expect(reset.changes.first { $0.id == id("feature.headroom") }?.newSource == .registryDefault)
        let invalidRetained = SavedProfile(id: a, name: "A", values: values([
            ("scan.preset", .choice("eco")), ("ui.units", .choice("not-a-unit"))]))
        #expect(throws: PolicyFieldError.self) {
            try SessionProfiles.previewReset(id: a, fieldIDs: [id("scan.preset")],
                includeOwnedRestrictions: false, inherited: .init(), in: [invalidRetained])
        }
        let protection = values([("feature.maintenance", .bool(false))])
        let weakRetained = SavedProfile(id: a, name: "A", values: values([
            ("scan.preset", .choice("eco")), ("feature.maintenance", .bool(true))]))
        #expect(throws: SessionProfileError.protectionWeakening(id("feature.maintenance"))) {
            try SessionProfiles.previewReset(id: a, fieldIDs: [id("scan.preset")],
                includeOwnedRestrictions: false, inherited: protection, in: [weakRetained])
        }
    }
}
