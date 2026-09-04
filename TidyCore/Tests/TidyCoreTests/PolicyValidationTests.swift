import Foundation
import Testing
@testable import TidyCore
@Suite struct PolicyValidationTests {
    @Test func exactTaggedWireFormRoundTripsAndRejectsAmbiguity() throws {
        let id = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
        let original = PolicyPreferences(global: values([
            "headroom.targetGiB": .integer(12),
            "headroom.volumeOverrides.\(id.uuidString)": .volume(.init(
                target: .fixedGiB(30), warning: .inherit, clear: .automatic))
        ]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(original)
        #expect(String(decoding: encoded, as: UTF8.self) ==
            #"{"global":{"fields":{"headroom.targetGiB":{"integer":12},"headroom.volumeOverrides.ABCDEF01-2345-6789-ABCD-EF0123456789":{"volume":{"clear":{"automatic":true},"target":{"fixedGiB":30},"warning":{"inherit":true}}}}},"profiles":[],"projects":{}}"#)
        #expect(try JSONDecoder().decode(PolicyPreferences.self, from: encoded) == original)

        let malformed = [
            #"{"fields":{"headroom.targetGiB":{}}}"#,
            #"{"fields":{"headroom.targetGiB":{"null":false}}}"#,
            #"{"fields":{"headroom.targetGiB":{"integer":12,"null":true}}}"#,
            #"{"fields":{"headroom.targetGiB":{"unknown":12}}}"#,
            #"{"fields":{"headroom.targetGiB":{"integer":12,"unknown":1}}}"#,
            #"{"fields":{"headroom.volumeOverrides.ABCDEF01-2345-6789-ABCD-EF0123456789":{"volume":{"target":{"fixedGiB":30},"warning":{"inherit":true}}}}}"#,
            #"{"fields":{"headroom.volumeOverrides.ABCDEF01-2345-6789-ABCD-EF0123456789":{"volume":{"target":{"fixedGiB":30,"automatic":true},"warning":{"inherit":true},"clear":{"automatic":true}}}}}"#,
            #"{"fields":{"headroom.volumeOverrides.ABCDEF01-2345-6789-ABCD-EF0123456789":{"volume":{"target":{"fixedGiB":30},"warning":{"inherit":false},"clear":{"automatic":true}}}}}"#,
            #"{"fields":{"headroom.volumeOverrides.ABCDEF01-2345-6789-ABCD-EF0123456789":{"volume":{"target":{"fixedGiB":30},"warning":{"inherit":true},"clear":{"automatic":true},"unknown":1}}}}"#
        ]
        for json in malformed {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(PolicyValues.self, from: Data(json.utf8))
            }
        }
    }

    @Test func volumeIDsRequireCanonicalUppercaseUUIDSpelling() {
        let canonical = "ABCDEF01-2345-6789-ABCD-EF0123456789"
        let lower = canonical.lowercased()
        let value = SettingValue.volume(.init(target: .inherit, warning: .automatic, clear: .fixedGiB(30)))
        let lowerID = key("headroom.volumeOverrides.\(lower)")
        #expect(throws: PolicyFieldError(id: lowerID, reason: .invalidIdentity)) {
            try PolicyValidator.validateStructure(.init(fields: [lowerID: value]), at: .global)
        }
        #expect(throws: PolicyFieldError(id: lowerID, reason: .invalidIdentity)) {
            try PolicyValidator.validateStructure(.init(fields: [
                key("headroom.volumeOverrides.\(canonical)"): value,
                lowerID: value
            ]), at: .global)
        }
        let malformedID = key("headroom.volumeOverrides.not-a-uuid")
        #expect(throws: PolicyFieldError(id: malformedID, reason: .invalidIdentity)) {
            try PolicyValidator.validateStructure(.init(fields: [malformedID: value]), at: .global)
        }
    }

    @Test func excludedRootsRequirePureLexicalCanonicalAbsolutePaths() throws {
        try PolicyValidator.validateStructure(values([
            "scope.excludedRoots": .strings(["/", "/fixture/a", "/fixture/a b"])
        ]), at: .global)
        for path in ["", "relative", "./relative", "../relative", "/fixture//a", "/fixture/./a",
                     "/fixture/../a", "/fixture/a/", "/fixture/\u{0007}a"] {
            #expect(throws: PolicyFieldError(id: key("scope.excludedRoots"), reason: .invalidIdentity)) {
                try PolicyValidator.validateStructure(values(["scope.excludedRoots": .strings([path])]), at: .global)
            }
        }
    }

    @Test func disablingBudgetNeverRequiresVolumeBounds() throws {
        let disabled = values(["budget.android.enabled": .bool(false)])
        try PolicyValidator.validateEdit(disabled, at: .global,
            context: input(capacity: nil, selected: nil, approved: []))
        try PolicyValidator.validateEdit(disabled, at: .global,
            context: input(capacity: nil, selected: volumeB, approved: [volumeA]))
        #expect(throws: PolicyFieldError(id: key("budget.android.highGiB"), reason: .boundsUnavailable)) {
            try PolicyValidator.validateEdit(values(["budget.android.enabled": .bool(true)]), at: .global,
                context: input(capacity: nil, selected: nil, approved: []))
        }
    }

    @Test func quietRelationUsesMergedOperandsNotLayerDefaults() throws {
        let start = values(["notifications.quietStart":.choice("21:00")])
        let end = values(["notifications.quietEnd":.choice("21:00")])
        try PolicyValidator.validateStructure(start,at:.global)
        try PolicyValidator.validateStructure(end,at:.profile)
        let error = PolicyFieldError(id:key("notifications.quietEnd"),reason:.invalidRelation)
        #expect(throws:error) {
            try PolicyResolver.resolve(input([.global:start,.profile:end]))
        }
        #expect(throws:error) {
            try PolicyValidator.validateEdit(end,at:.profile,context:input([.global:start]))
        }
        #expect(throws:error) {
            try PolicyValidator.validateStructure(values([
                "notifications.quietStart":.choice("21:00"),
                "notifications.quietEnd":.choice("21:00")]),at:.global)
        }
        let global = values(["notifications.quietEnd":.choice("09:00")])
        let profile = values(["notifications.quietStart":.choice("08:00")])
        try PolicyValidator.validateStructure(profile,at:.profile)
        try PolicyValidator.validateEdit(profile,at:.profile,context:input([.global:global]))
        let valid = try PolicyResolver.resolve(input([.global:global,.profile:profile]))
        #expect(valid.fields[key("notifications.quietStart")] == EffectiveField(
            value:.stored(.choice("08:00")),sources:[.layer(.profile)],reason:.replaced))
        #expect(valid.fields[key("notifications.quietEnd")] == EffectiveField(
            value:.stored(.choice("09:00")),sources:[.layer(.global)],reason:.replaced))
    }
    @Test func unmatchedVolumeCanPersistButCannotBorrowAnotherCapacity() throws {
        let id = key("headroom.volumeOverrides.\(volumeB.uuidString)")
        let retained = PolicyValues(fields:[id:.volume(.init(
            target:.fixedGiB(30),warning:.inherit,clear:.inherit))])
        try PolicyValidator.validateStructure(retained,at:.global)
        let bytes = try JSONEncoder().encode(retained)
        #expect(try JSONDecoder().decode(PolicyValues.self,from:bytes) == retained)
        #expect(throws:PolicyFieldError(id:id,reason:.boundsUnavailable)) {
            try PolicyValidator.validateEdit(retained,at:.global,context:input(selected:volumeA))
        }
        #expect(throws:PolicyFieldError(id:id,reason:.boundsUnavailable)) {
            try PolicyValidator.validateEdit(retained,at:.global,
                context:input(selected:volumeB,approved:[volumeA]))
        }
        try PolicyValidator.validateEdit(retained,at:.global,context:input(selected:volumeB))
        var edited = retained
        edited.fields[key("ui.units")] = .choice("decimal")
        try PolicyValidator.validateEdit(edited,at:.global,
            context:input([.global:retained],selected:volumeA))
    }
    @Test func budgetEnableErrorsIdentifyTheBoundNotAnUnrelatedField() {
        let enabled = values(["budget.models.enabled":.bool(true)])
        #expect(throws:PolicyFieldError(id:key("budget.models.highGiB"),reason:.outOfRange)) {
            try PolicyValidator.validateEdit(enabled,at:.global,context:input(capacity:40*GiB))
        }
        #expect(throws:PolicyFieldError(id:key("budget.models.highGiB"),reason:.boundsUnavailable)) {
            try PolicyValidator.validateEdit(enabled,at:.global,context:input(capacity:nil))
        }
    }
    @Test func everyNumericRangeRejectsBothNeighbors() throws {
        for row in fixtureRows() where row.resolution != .authority {
            let bounds: (Int64,Int64)?
            switch row.rule {
            case .integer(let a, let b), .optionalInteger(let a, let b): bounds = (a,b)
            default: bounds = nil
            }
            guard let (low,high) = bounds else { continue }
            for value in [low-1,high+1] {
                #expect(throws: PolicyFieldError(id:row.id,reason:.outOfRange)) {
                    try PolicyValidator.validateStructure(.init(fields:[row.id:.integer(value)]),at:.global)
                }
            }
        }
    }
    @Test func nonIntegralAndOverflowInputsNeverReachMultiplication() {
        for raw in ["NaN","Infinity","-Infinity","1.5","1e309","9223372036854775808"] {
            #expect(throws: PolicyFieldError.self) { try PolicyValidator.integerInput(raw,for:key("cleanup.requestedBatchGiB")) }
        }
        #expect(throws: PolicyFieldError.self) { try PolicyValidator.bytes(gib:Int64.max,for:key("cleanup.requestedBatchGiB")) }
    }
    @Test func keyLayerAuthorityAndIdentityTable() {
        let cases: [(String,SettingValue,PolicyLayer,PolicyFieldError.Reason)] = [
            ("feature.unknown",.bool(true),.global,.unknownKey),
            ("item.unknown.enabled",.bool(true),.global,.unknownKey),
            ("ui.units",.choice("binary"),.run,.unsupportedLayer),
            ("scan.sliceSeconds",.integer(300),.project,.unsupportedLayer),
            ("notifications.enabled",.bool(true),.global,.authorityIsLocal),
            ("scope.externalVolumes",.strings([volumeA.uuidString]),.profile,.authorityIsLocal),
            ("maintenance.mode",.choice("authorizedCaches"),.global,.authorityIsLocal),
            ("scan.defaultScope",.choice("fullHome"),.global,.outOfRange),
            ("ui.cards",.strings(["disk","disk"]),.global,.invalidIdentity),
            ("ui.ecosystemOrder",.strings(["apple"]),.global,.invalidIdentity),
            ("browsers.keepCookieDomains",.strings(["https://example.invalid/path"]),.global,.invalidIdentity),
            ("notifications.quietStart",.choice("24:00"),.global,.outOfRange)]
        for (id,value,layer,reason) in cases {
            #expect(throws: PolicyFieldError(id:key(id),reason:reason)) {
                try PolicyValidator.validateStructure(values([id:value]),at:layer)
            }
        }
    }
    @Test func relationsAndUnavailableBounds() {
        let cases: [([String:SettingValue],Int64?)] = [
            (["headroom.targetGiB":.integer(101)],200*GiB),
            (["headroom.warningGiB":.integer(20),"headroom.clearGiB":.integer(20)],200*GiB),
            (["headroom.clearGiB":.integer(201)],200*GiB),
            (["headroom.targetGiB":.integer(10)],nil),
            (["budget.docker.highGiB":.integer(30),"budget.docker.lowGiB":.integer(30)],200*GiB),
            (["notifications.quietStart":.choice("22:00"),"notifications.quietEnd":.choice("22:00")],200*GiB)]
        for (fields,capacity) in cases {
            #expect(throws: PolicyFieldError.self) {
                try PolicyValidator.validateEdit(values(fields),at:.global,context:input(capacity:capacity))
            }
        }
    }
    @Test func everyChangedVolumeOverrideIsValidatedInStableKeyOrder() {
        let volumeC = UUID(uuidString:"33333333-3333-3333-3333-333333333333")!
        let volumeBID = key("headroom.volumeOverrides.\(volumeB.uuidString)")
        let volumeCID = key("headroom.volumeOverrides.\(volumeC.uuidString)")
        let edited = PolicyValues(fields:[
            volumeCID:.volume(.init(target:.fixedGiB(35),warning:.inherit,clear:.inherit)),
            volumeBID:.volume(.init(target:.fixedGiB(30),warning:.inherit,clear:.inherit))])
        #expect(throws:PolicyFieldError(id:volumeBID,reason:.boundsUnavailable)) {
            try PolicyValidator.validateEdit(edited,at:.global,
                context:input(selected:volumeA,approved:[volumeA,volumeB,volumeC]))
        }
    }
}
