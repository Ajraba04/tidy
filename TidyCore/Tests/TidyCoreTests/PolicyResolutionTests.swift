import Foundation
import Testing
@testable import TidyCore
@Suite struct PolicyResolutionTests {
    @Test func defaultFalseRequiresOwningGlobalAndFalseDominates() throws {
        for id in ["ecosystem.docker.manualActions", "feature.maintenance", "budget.docker.enabled"] {
            let enabled = try PolicyResolver.resolve(input([.global:values([id:.bool(true)])]))
            #expect(enabled.fields[key(id)] == EffectiveField(value:.stored(.bool(true)),
                sources:[.layer(.global)],reason:.replaced))
            let childOnly = try PolicyResolver.resolve(input([.profile:values([id:.bool(true)])]))
            #expect(childOnly.fields[key(id)] == EffectiveField(value:.stored(.bool(false)),
                sources:[.builtIn,.layer(.profile)],reason:.denied))
            let denied = try PolicyResolver.resolve(input([
                .global:values([id:.bool(false)]),.profile:values([id:.bool(true)])]))
            #expect(denied.fields[key(id)] == EffectiveField(value:.stored(.bool(false)),
                sources:[.layer(.global),.layer(.profile)],reason:.denied))
        }
    }
    @Test func unionsCapsAndEqualReplacementsHaveLiteralProvenance() throws {
        let result = try PolicyResolver.resolve(input([
            .global:values(["scope.excludedRoots":.strings(["/fixture/z"]),
                "scope.pinnedProjects":.strings(["project-b"]),
                "browsers.keepCookieDomains":.strings(["b.invalid"]),
                "cleanup.requestedBatchGiB":.integer(40),"cleanup.requestedBatchItems":.integer(80),
                "cleanup.hardBatchGiB":.integer(8),"cleanup.hardBatchItems":.integer(10),
                "ui.units":.choice("binary")]),
            .profile:values(["scope.excludedRoots":.strings(["/fixture/a","/fixture/z"]),
                "scope.pinnedProjects":.strings(["project-a","project-b"]),
                "browsers.keepCookieDomains":.strings(["a.invalid","b.invalid"]),
                "cleanup.hardBatchGiB":.integer(12),"cleanup.hardBatchItems":.integer(6),
                "ui.units":.choice("binary")])]))
        #expect(result.fields[key("scope.excludedRoots")] == EffectiveField(
            value:.stored(.strings(["/fixture/a","/fixture/protected","/fixture/z"])),
            sources:[.layer(.global),.layer(.profile),.immutable],reason:.protected))
        #expect(result.fields[key("scope.pinnedProjects")] == EffectiveField(
            value:.stored(.strings(["project-a","project-b"])),
            sources:[.layer(.global),.layer(.profile)],reason:.union))
        #expect(result.fields[key("browsers.keepCookieDomains")] == EffectiveField(
            value:.stored(.strings(["a.invalid","b.invalid"])),
            sources:[.layer(.global),.layer(.profile)],reason:.union))
        for (id,amount) in [("cleanup.hardBatchGiB",Int64(8)),("cleanup.hardBatchItems",6),
                            ("cleanup.requestedBatchGiB",8),("cleanup.requestedBatchItems",6)] {
            #expect(result.fields[key(id)] == EffectiveField(value:.stored(.integer(amount)),
                sources:[.layer(.global),.layer(.profile)],reason:.strictestCap))
        }
        #expect(result.manualBatchBytes == 8*GiB); #expect(result.manualBatchItems == 6)
        #expect(result.fields[key("ui.units")] == EffectiveField(value:.stored(.choice("binary")),
            sources:[.layer(.profile)],reason:.replaced))
    }
    @Test func scanAdmissionAndNumericProvenanceAreDistinct() throws {
        var eco = input()
        let normal = try PolicyResolver.resolve(eco)
        #expect(normal.scanAdmission == .discretionaryAllowed)
        #expect(normal.fields[key("scan.requestedWorkers")] == EffectiveField(
            value:.stored(.integer(1)),sources:[.builtIn],reason:.preset))
        eco.lowPower = true
        let lowEco = try PolicyResolver.resolve(eco)
        #expect(lowEco.scanAdmission == .userRequestedOnly)
        #expect(lowEco.walkWorkers == 1); #expect(lowEco.readOnlyProcesses == 1)
        #expect(lowEco.fields[key("scan.requestedWorkers")] == EffectiveField(
            value:.stored(.integer(1)),sources:[.builtIn],reason:.preset))
        var i = input([.global:values(["scan.preset":.choice("custom"),
            "scan.requestedWorkers":.integer(4),"scan.readOnlyProcesses":.integer(2)]),
            .profile:values(["scan.preset":.choice("balanced")])])
        let balanced = try PolicyResolver.resolve(i)
        for id in ["scan.requestedWorkers","scan.readOnlyProcesses"] {
            #expect(balanced.fields[key(id)] == EffectiveField(value:.stored(.integer(2)),
                sources:[.layer(.profile)],reason:.preset))
        }
        i.logicalCPUCount = 1
        let cpu = try PolicyResolver.resolve(i)
        #expect(cpu.fields[key("scan.requestedWorkers")] == EffectiveField(value:.stored(.integer(1)),
            sources:[.layer(.profile),.immutable],reason:.cpuCeiling))
        i.logicalCPUCount = 8; i.lowPower = true
        let low = try PolicyResolver.resolve(i)
        #expect(low.scanAdmission == .userRequestedOnly)
        #expect(low.fields[key("scan.requestedWorkers")] == EffectiveField(value:.stored(.integer(1)),
            sources:[.layer(.profile),.immutable],reason:.pressureCeiling))
        #expect(low.fields[key("scan.readOnlyProcesses")] == EffectiveField(value:.stored(.integer(2)),
            sources:[.layer(.profile)],reason:.preset))
        i.layers[.profile] = values(["scan.preset":.choice("balanced"),
            "scan.onLowPower":.choice("pauseAll")])
        i.lowPower = false
        #expect(try PolicyResolver.resolve(i).scanAdmission == .discretionaryAllowed)
        i.lowPower = true; i.seriousThermal = true
        let paused = try PolicyResolver.resolve(i)
        #expect(paused.scanAdmission == .paused)
        #expect(paused.walkWorkers == 0); #expect(paused.readOnlyProcesses == 0)
        for id in ["scan.requestedWorkers","scan.readOnlyProcesses"] {
            #expect(paused.fields[key(id)] == EffectiveField(value:.stored(.integer(0)),
                sources:[.layer(.profile),.immutable],reason:.pressureCeiling))
        }
        i.layers[.profile] = values(["scan.onSeriousThermal":.choice("pauseAll")])
        #expect(try PolicyResolver.resolve(i).scanAdmission == .paused)
        i.layers[.profile] = values([:])
        #expect(try PolicyResolver.resolve(i).scanAdmission == .userRequestedOnly)
        i.lowPower = false; i.seriousThermal = false; i.critical = true
        let critical = try PolicyResolver.resolve(i)
        #expect(critical.scanAdmission == .paused)
        #expect(critical.walkWorkers == 0); #expect(critical.readOnlyProcesses == 0)
        for id in ["scan.requestedWorkers","scan.readOnlyProcesses"] {
            #expect(critical.fields[key(id)] == EffectiveField(value:.stored(.integer(0)),
                sources:[.layer(.global),.immutable],reason:.pressureCeiling))
        }
    }
    @Test func budgetByteRoundingAndUnavailableObservations() throws {
        let fractional = try PolicyResolver.resolve(input([.global:values([
            "budget.docker.enabled":.bool(true),"budget.docker.highGiB":.integer(1)])]))
        #expect(fractional.fields[key("budget.docker.highGiB")] == EffectiveField(
            value:.stored(.integer(1)),sources:[.layer(.global)],reason:.replaced))
        #expect(fractional.fields[key("budget.docker.lowGiB")] == EffectiveField(
            value:.bytes(858_993_459),sources:[.builtIn,.layer(.global)],reason:.automatic))
        #expect(fractional.fields[key("budget.docker.enabled")] == EffectiveField(
            value:.stored(.bool(true)),sources:[.layer(.global)],reason:.replaced))
        let enabled = values(["budget.models.enabled":.bool(true)])
        let cases: [(PolicyInputs,FieldReason)] = [
            (input([.global:enabled],capacity:40*GiB),.invalidForVolume),
            (input([.global:enabled],capacity:nil),.capacityUnavailable),
            (input([.global:enabled],selected:nil),.unmatchedVolume),
            (input([.global:enabled],selected:volumeB,approved:[volumeA]),.unmatchedVolume)]
        for (context,reason) in cases {
            let result = try PolicyResolver.resolve(context)
            #expect(result.fields[key("budget.models.enabled")] == EffectiveField(
                value:.stored(.bool(false)),sources:[.layer(.global),.immutable],reason:reason))
            for id in ["budget.models.highGiB","budget.models.lowGiB"] {
                #expect(result.fields[key(id)] == EffectiveField(value:.unavailable(reason),
                    sources:[.builtIn,.immutable],reason:reason))
            }
        }
    }
    @Test func replacementsAndIndependentRestrictions() throws {
        let ordered: [(PolicyLayer, Int64)] = [(.global,20),(.profile,30),(.project,35),(.run,40)]
        var layers: [PolicyLayer:PolicyValues] = [:]
        for (layer, amount) in ordered {
            layers[layer] = values(["cleanup.requestedBatchGiB":.integer(amount)])
            let result = try PolicyResolver.resolve(input(layers))
            #expect(result.manualBatchBytes == amount*GiB)
            #expect(result.fields[key("cleanup.requestedBatchGiB")]?.sources == [.layer(layer)])
        }
        layers[.global] = values(["cleanup.hardBatchGiB":.integer(8),"scope.excludedRoots":.strings(["/fixture/one"])])
        layers[.profile] = values(["cleanup.hardBatchGiB":.integer(12),"scope.excludedRoots":.strings(["/fixture/two"])])
        let capped = try PolicyResolver.resolve(input(layers))
        #expect(capped.manualBatchBytes == 8*GiB)
        #expect(capped.exclusions == ["/fixture/protected","/fixture/one","/fixture/two"])
        let ready = try PolicyResolver.resolve(input([
            .global:values(["cleanup.hardBatchGiB":.integer(8)]),
            .profile:PolicyDefaults.factory("xcode")]))
        #expect(ready.fields[key("headroom.targetGiB")]?.value == .bytes(15*GiB))
        #expect(ready.manualBatchBytes == 8*GiB)
        let disabled = try PolicyResolver.resolve(input([
            .global:values(["feature.projects":.bool(false)]),
            .profile:values(["feature.projects":.bool(true)])]))
        #expect(!disabled.allowedFeatures.contains("projects"))
        #expect(disabled.fields[key("feature.projects")]?.reason == .denied)
        let battery = try PolicyResolver.resolve(input([.profile:PolicyDefaults.factory("battery")]))
        #expect(battery.fields[key("monitor.suppressHiddenSampling")]?.value == .stored(.bool(true)))
        #expect(battery.fields[key("maintenance.mode")]?.value == .unavailable(.authorityUnavailable))
    }
    @Test func genericThenVolumeAtEveryLayer() throws {
        for layer in PolicyLayer.allCases {
            let fields: [(String,Int64,Int64)] = [("target",12,20),("warning",16,12),("clear",40,18)]
            for (name,inherited,automatic) in fields {
                let cases: [(VolumeField,Int64)] = [(.inherit,inherited),(.automatic,automatic),(.fixedGiB(30),30)]
                for (field,expected) in cases {
                    var override = VolumeOverride(target:.inherit,warning:.inherit,clear:.inherit)
                    switch name {
                    case "target": override.target = field
                    case "warning": override.warning = field
                    default: override.clear = field
                    }
                    let result = try PolicyResolver.resolve(input([layer:values([
                        "headroom.targetGiB":.integer(12),"headroom.warningGiB":.integer(16),
                        "headroom.clearGiB":.integer(40),
                        "headroom.volumeOverrides.\(volumeA.uuidString)":.volume(override)])]))
                    let resolved = try #require(result.fields[key("headroom.\(name)GiB")])
                    #expect(resolved.value == .bytes(expected*GiB))
                    #expect(resolved.sources == (field == .inherit ? [.layer(layer)] : [.volume(layer,volumeA)]))
                }
            }
        }
        let result = try PolicyResolver.resolve(input([
            .global:values(["headroom.targetGiB":.integer(10)]),
            .profile:values(["headroom.volumeOverrides.\(volumeA.uuidString)":.volume(.init(target:.fixedGiB(30),warning:.inherit,clear:.inherit))]),
            .run:values(["headroom.targetGiB":.integer(40)])]))
        #expect(result.fields[key("headroom.targetGiB")]?.value == .bytes(40*GiB))
        #expect(result.fields[key("headroom.targetGiB")]?.sources == [.layer(.run)])
    }
    @Test func unavailableAndUnmatchedAreNotZeroOrAuthorization() throws {
        for requested in [SettingValue.null, .integer(10)] {
            let result = try PolicyResolver.resolve(input([.global:values(["headroom.targetGiB":requested])],capacity:nil))
            #expect(result.fields[key("headroom.targetGiB")]?.value == .unavailable(.capacityUnavailable))
        }
        let retained = values(["headroom.volumeOverrides.\(volumeB.uuidString)":.volume(.init(target:.fixedGiB(30),warning:.inherit,clear:.inherit))])
        let result = try PolicyResolver.resolve(input([.global:retained],selected:volumeB,approved:[volumeA]))
        #expect(result.fields[key("headroom.targetGiB")]?.value == .unavailable(.unmatchedVolume))
        let small = try PolicyResolver.resolve(input([.profile:PolicyDefaults.factory("localAI")],capacity:40*GiB))
        #expect(small.fields[key("headroom.targetGiB")]?.value == .unavailable(.invalidForVolume))
        #expect(small.fields[key("budget.models.enabled")]?.value == .stored(.bool(false)))
    }
    @Test func immutablePressureAndCPUCeilings() throws {
        var i = input([.global:values(["scan.preset":.choice("custom"),"scan.requestedWorkers":.integer(4),"scan.readOnlyProcesses":.integer(2)])])
        i.logicalCPUCount = 2
        #expect(try PolicyResolver.resolve(i).walkWorkers == 2)
        i.lowPower = true
        #expect(try PolicyResolver.resolve(i).walkWorkers == 1)
        i.layers[.profile] = try PolicyDefaults.factory("battery")
        #expect(try PolicyResolver.resolve(i).walkWorkers == 0)
        i.seriousThermal = true
        #expect(try PolicyResolver.resolve(i).walkWorkers == 0)
        i.layers[.profile] = values(["scan.onLowPower":.choice("pauseDiscretionary"),
            "scan.onSeriousThermal":.choice("pauseAll")])
        #expect(try PolicyResolver.resolve(i).walkWorkers == 0)
        i.critical = true
        #expect(try PolicyResolver.resolve(i).walkWorkers == 0)
        #expect(try PolicyResolver.resolve(i).readOnlyProcesses == 0)
    }
    @Test func explicitlyEnabledUnconfiguredBudgetIsForcedOffWithProvenance() throws {
        let result = try PolicyResolver.resolve(input([.global:values([
            "budget.android.enabled":.bool(true)])]))
        #expect(result.fields[key("budget.android.enabled")] == EffectiveField(
            value:.stored(.bool(false)),sources:[.layer(.global),.immutable],reason:.notConfigured))
        for id in ["budget.android.highGiB","budget.android.lowGiB"] {
            #expect(result.fields[key(id)] == EffectiveField(
                value:.unavailable(.notConfigured),sources:[.builtIn],reason:.notConfigured))
        }
    }
}
