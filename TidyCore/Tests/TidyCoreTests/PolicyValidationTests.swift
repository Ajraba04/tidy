import Foundation
import Testing
@testable import TidyCore
@Suite struct PolicyValidationTests {
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
