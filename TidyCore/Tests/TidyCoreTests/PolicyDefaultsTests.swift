import Foundation
import Testing
@testable import TidyCore

let registryFixture = """
# id|kind|default|rule|class|effect|layers
feature.F|bool|b:true|boolean|R|i|G
feature.maintenance|bool|b:false|boolean|R|i|G
ecosystem.E.inventory|bool|b:true|boolean|R|i|G
ecosystem.E.manualActions|bool|b:false|boolean|R|i|G
item.I.enabled|bool|b:true|boolean|R|i|G
scope.projectRoots|localIdentityList|s:|identityList|A|c|A
scope.externalVolumes|localIdentityList|s:|identityList|A|c|A
scope.excludedRoots|setIDs|s:|exclusions|R|i|L
scope.pinnedProjects|setIDs|s:|pins|R|i|L
scope.currentProject|optionalProjectID|n|projectID|P|i|L
browsers.keepCookieDomains|domains|s:|domains|R|i|G
simulators.approvedDeletionUDIDs|localIdentityList|s:|identityList|A|c|A
tools.approvedExecutables|localIdentityList|s:|identityList|A|c|A
docker.approvedEndpoints|localIdentityList|s:|identityList|A|c|A
cleanup.inactiveDays|integer|i:60|integer:7:365|P|i|L
cleanup.transcriptDays|integer|i:45|integer:7:365|P|i|L
cleanup.recentProtectionDays|integer|i:7|integer:1:90|P|i|L
cleanup.warmProjectCount|integer|i:5|integer:0:50|P|i|L
cleanup.minimumCandidateMiB|integer|i:100|integer:1:102400|P|i|L
cleanup.minimumItemMiB|integer|i:1|integer:0:102400|P|i|L
cleanup.retainRecentArtifacts|integer|i:2|integer:0:100|P|i|L
cleanup.costCeiling|choice|e:low|choices:low,medium,high|P|i|L
cleanup.requestedBatchGiB|integer|i:10|integer:1:100|P|i|L
cleanup.requestedBatchItems|integer|i:20|integer:1:100|P|i|L
cleanup.hardBatchGiB|optionalInteger|n|optionalInteger:1:100|R|i|L
cleanup.hardBatchItems|optionalInteger|n|optionalInteger:1:100|R|i|L
cleanup.manualInactiveAcknowledgementMinutes|integer|i:10|integer:1:30|P|i|L
scan.preset|choice|e:eco|choices:eco,balanced,custom|P|i|G
scan.requestedWorkers|integer|i:1|integer:1:4|P|i|G
scan.readOnlyProcesses|integer|i:1|integer:1:2|P|i|G
scan.defaultScope|choice|e:quick|choices:quick,selectedProjects|P|i|G
scan.sliceSeconds|integer|i:300|integer:30:1800|P|i|G
scan.uiBatchesPerSecond|integer|i:4|integer:1:4|P|n|G
scan.onLowPower|choice|e:pauseDiscretionary|choices:pauseAll,pauseDiscretionary|R|i|G
scan.onSeriousThermal|choice|e:pauseDiscretionary|choices:pauseAll,pauseDiscretionary|R|i|G
scan.resumeAfterCriticalSeconds|integer|i:120|integer:120:900|P|i|G
scan.cacheEnabled|bool|b:true|boolean|P|i|G
scan.cacheMiB|integer|i:64|integer:8:128|P|i|G
scan.cacheExpiryHours|integer|i:24|integer:1:48|P|i|G
monitor.backgroundEnabled|bool|b:false|boolean|A|c|A
monitor.visibleIntervalSeconds|integer|i:5|integer:2:60|P|n|G
monitor.hiddenIntervalSeconds|integer|i:60|integer:60:900|P|n|G
monitor.rawHistoryEnabled|bool|b:false|boolean|P|n|G
monitor.rawHistoryHours|integer|i:24|integer:1:24|P|n|G
headroom.targetGiB|optionalInteger|n|headroomTarget|P|i|L
headroom.warningGiB|optionalInteger|n|headroomWarning|P|i|L
headroom.clearGiB|optionalInteger|n|headroomClear|P|i|L
headroom.volumeOverrides.V|volumeOverride|v|volumeOverride|P|i|L
rescue.approvedApplications|localIdentityList|s:|identityList|A|c|A
rescue.showAdvancedMemoryActions|bool|b:false|boolean|P|i|G
rescue.quitTimeoutSeconds|integer|i:15|integer:5:60|P|i|G
budget.B.enabled|bool|b:false|boolean|R|i|G
budget.apple-derived-data.highGiB|optionalInteger|i:15|budgetHigh|P|i|G
budget.apple-simulators.highGiB|optionalInteger|i:25|budgetHigh|P|i|G
budget.android.highGiB|optionalInteger|n|budgetHigh|P|i|G
budget.docker.highGiB|optionalInteger|i:30|budgetHigh|P|i|G
budget.package-caches.highGiB|optionalInteger|i:10|budgetHigh|P|i|G
budget.models.highGiB|optionalInteger|i:50|budgetHigh|P|i|G
budget.ides.highGiB|optionalInteger|n|budgetHigh|P|i|G
budget.git.highGiB|optionalInteger|n|budgetHigh|P|i|G
budget.data.highGiB|optionalInteger|n|budgetHigh|P|i|G
budget.other.highGiB|optionalInteger|n|budgetHigh|P|i|G
budget.B.lowGiB|optionalInteger|n|budgetLow|P|i|G
notifications.enabled|bool|b:false|boolean|A|c|A
notifications.pressureSustainSeconds|integer|i:60|integer:30:600|P|n|G
notifications.recoverySeconds|integer|i:120|integer:60:900|P|n|G
notifications.cooldownMinutes|integer|i:60|integer:15:1440|P|n|G
notifications.quietHoursEnabled|bool|b:false|boolean|P|n|G
notifications.quietStart|clock|e:22:00|clock|P|n|G
notifications.quietEnd|clock|e:08:00|quietEnd|P|n|G
maintenance.mode|choice|e:off|choices:off,notifyOnly,authorizedCaches|A|c|A
maintenance.maxGiB|integer|i:1|integer:1:5|A|c|A
maintenance.maxItems|integer|i:5|integer:1:20|A|c|A
maintenance.deadlineSeconds|integer|i:60|integer:30:120|A|c|A
maintenance.minimumAgeDays|integer|i:30|integer:30:365|A|c|A
maintenance.minimumIntervalHours|integer|i:24|integer:24:168|A|c|A
app.launchAtLogin|bool|b:false|boolean|A|c|A
history.enabled|bool|b:true|boolean|P|n|G
history.retentionDays|integer|i:30|integer:1:90|P|n|G
history.maxMiB|integer|i:10|integer:1:50|P|n|G
ui.density|choice|e:compact|choices:compact,detailed|P|n|G
ui.units|choice|e:binary|choices:binary,decimal|P|n|G
ui.cards|orderedIDs|s:disk,memoryPressure,swap,thermal,power|cards|P|n|G
ui.ecosystemOrder|orderedIDs|s:apple,android,node,languages,homebrew,docker,ides,models,git,data|ecosystemOrder|P|n|G
monitor.suppressHiddenSampling|bool|b:false|boolean|R|n|G
ui.showBadges|bool|b:true|boolean|P|n|G
ui.advancedSettings|bool|b:false|boolean|P|n|G
export.redactDiagnostics|bool|b:true|boolean|P|n|G
item.I.inactiveDays|optionalInteger|n|optionalInteger:7:365|P|i|L
item.I.minimumItemMiB|optionalInteger|n|optionalInteger:0:102400|P|i|L
item.I.retainRecentArtifacts|optionalInteger|n|optionalInteger:0:100|P|i|L
"""

let GiB: Int64 = 1_073_741_824
let volumeA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let volumeB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
let ecosystems = "apple,android,node,languages,homebrew,docker,ides,models,git,data".components(separatedBy: ",")
let budgets = "apple-derived-data,apple-simulators,android,docker,package-caches,models,ides,git,data,other".components(separatedBy: ",")
func key(_ s: String) -> SettingID { .init(rawValue: s) }
func values(_ pairs: [String: SettingValue]) -> PolicyValues {
    .init(fields: Dictionary(uniqueKeysWithValues: pairs.map { (key($0.key), $0.value) }))
}
func input(_ layers: [PolicyLayer: PolicyValues] = [:], capacity: Int64? = 200 * GiB,
           selected: UUID? = volumeA, approved: Set<UUID> = [volumeA, volumeB]) -> PolicyInputs {
    PolicyInputs(layers: layers, selectedVolumeID: selected, approvedVolumeIDs: approved,
        capacityBytes: capacity, logicalCPUCount: 8, lowPower:false, seriousThermal:false, critical:false,
        mandatoryExclusions: ["/fixture/protected"])
}
func fixtureValue(_ s: String) -> SettingValue {
    if s == "n" || s == "v" { return .null }
    let p = s.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
    switch p[0] {
    case "b": return .bool(p[1] == "true")
    case "i": return .integer(Int64(p[1])!)
    case "e": return .choice(p[1])
    case "s": return .strings(p[1].isEmpty ? [] : p[1].components(separatedBy: ","))
    default: preconditionFailure("Bad independent fixture")
    }
}
func fixtureRule(_ s: String) -> Rule {
    let p = s.components(separatedBy: ":")
    switch p[0] {
    case "boolean": return .boolean
    case "integer": return .integer(Int64(p[1])!, Int64(p[2])!)
    case "optionalInteger": return .optionalInteger(Int64(p[1])!, Int64(p[2])!)
    case "choices": return .choices(p[1].components(separatedBy: ","))
    case "identityList": return .identityList
    case "domains": return .domains
    case "projectID": return .projectID
    case "exclusions": return .exclusions
    case "pins": return .pins
    case "headroomTarget": return .headroomTarget
    case "headroomWarning": return .headroomWarning
    case "headroomClear": return .headroomClear
    case "volumeOverride": return .volumeOverride
    case "budgetHigh": return .budgetHigh
    case "budgetLow": return .budgetLow
    case "cards": return .cards
    case "ecosystemOrder": return .ecosystemOrder
    case "clock": return .clock
    case "quietEnd": return .quietEnd
    default: preconditionFailure("Bad independent rule")
    }
}
func fixtureRows() -> [SettingDefinition] {
    registryFixture.split(separator: "\n").filter { !$0.hasPrefix("#") }.flatMap { line in
        let p = line.components(separatedBy: "|")
        let expansions: [(String, [String])] = [
            (".F", "headroom,buildPrep,projects,rescue,ecosystems,budgets,history".components(separatedBy: ",")),
            (".E.", ecosystems), (".B.", budgets), (".I.", ["normal.extras.stale-node-modules"]),
            (".V", [volumeA.uuidString])]
        var ids = [p[0]]
        for (marker, members) in expansions where p[0].contains(marker) {
            let trailing = marker.hasSuffix(".") ? "." : ""
            ids = members.map { p[0].replacingOccurrences(of: marker, with: "." + $0 + trailing) }
        }
        return ids.map { id in
            let prefix = String(id.split(separator: ".")[0])
            let group = ["feature":"features", "ecosystem":"features", "item":"cleanup",
                         "app":"experience", "export":"data"][prefix] ?? prefix
            return SettingDefinition(id: key(id), kind: ValueKind(rawValue: p[1])!,
                defaultValue: fixtureValue(p[2]), rule: fixtureRule(p[3]),
                resolution: ["P":.preference, "R":.restriction, "A":.authority][p[4]]!,
                effect: ["i":.invalidate, "n":.none, "c":.consent][p[5]]!,
                layers: p[6] == "A" ? [] : p[6] == "G" ? [.global,.profile] : Set(PolicyLayer.allCases),
                group: group)
        }
    }
}
@Suite struct PolicyDefaultsTests {
    @Test func everyRegistryRowAndDefaultIsIndependent() throws {
        let expected = fixtureRows()
        let actual = PolicyDefaults.rows + PolicyDefaults.itemRows(catalogID: "normal.extras.stale-node-modules") +
            [PolicyDefaults.volumeRow(id: volumeA)]
        #expect(Set(actual.map(\.id)).count == actual.count)
        #expect(actual.sorted { $0.id.rawValue < $1.id.rawValue } == expected.sorted { $0.id.rawValue < $1.id.rawValue })
        let snapshot = try PolicyResolver.resolve(input())
        for row in expected where row.kind != .volumeOverride {
            let field = try #require(snapshot.fields[row.id])
            if row.resolution == .authority {
                #expect(field == EffectiveField(value: .unavailable(.authorityUnavailable), sources: [.localAuthority], reason: .authorityUnavailable))
            } else if row.id.rawValue == "scope.excludedRoots" {
                #expect(field.value == .stored(.strings(["/fixture/protected"])))
                #expect(field.sources == [.immutable]); #expect(field.reason == .protected)
            } else if row.id.rawValue.hasPrefix("item.") && row.defaultValue == .null {
                let inherited: [String:Int64] = ["inactiveDays":60,"minimumItemMiB":1,"retainRecentArtifacts":2]
                let suffix = String(row.id.rawValue.split(separator:".").last!)
                #expect(field.value == .stored(.integer(inherited[suffix]!)))
                #expect(field.sources == [.builtIn]); #expect(field.reason == .inherited)
            } else if row.id.rawValue.hasPrefix("headroom.") {
                let expectedBytes: [String:Int64] = ["headroom.targetGiB":20*GiB,"headroom.warningGiB":20*GiB,"headroom.clearGiB":22*GiB]
                #expect(field.value == .bytes(expectedBytes[row.id.rawValue]!))
                #expect(field.sources == [.builtIn]); #expect(field.reason == .automatic)
            } else if row.id.rawValue.hasPrefix("budget.") && row.id.rawValue.hasSuffix("lowGiB") {
                let lows: [String:Int64] = ["apple-derived-data":12,"apple-simulators":20,"docker":24,"package-caches":8,"models":40]
                let id = row.id.rawValue.components(separatedBy: ".")[1]
                #expect(field.value == (lows[id].map { .bytes($0*GiB) } ?? .unavailable(.notConfigured)))
                #expect(field.sources == [.builtIn])
            } else if row.id.rawValue.hasPrefix("budget.") && row.id.rawValue.hasSuffix("highGiB") && row.defaultValue == .null {
                #expect(field.value == .unavailable(.notConfigured)); #expect(field.sources == [.builtIn])
            } else {
                #expect(field.value == .stored(row.defaultValue)); #expect(field.sources == [.builtIn])
            }
        }
        #expect(snapshot.manualBatchBytes == 10*GiB); #expect(snapshot.manualBatchItems == 20)
        #expect(snapshot.walkWorkers == 1); #expect(snapshot.readOnlyProcesses == 1)
        #expect(snapshot.exclusions == ["/fixture/protected"])
        #expect(snapshot.fields[key("headroom.volumeOverrides.\(volumeA.uuidString)")] == nil)
        #expect(PolicyDefaults.hardLimits == [.manualGiB:100,.manualItems:100,
            .automaticGiB:5,.automaticItems:20,.walkWorkers:4,.commandJobs:2,.rawHistoryMiB:5])
    }
    @Test func exactFactoryProfiles() throws {
        let cases: [(String, Int64, [String], Bool)] = [
            ("xcode",15,["apple"],true),("android",20,["android"],true),
            ("flutter",20,["android","apple"],true),("web",5,["node"],true),
            ("localAI",30,["models"],false)]
        for (name, target, first, cost) in cases {
            var expected: [String:SettingValue] = ["headroom.targetGiB":.integer(target),
                "scan.preset":.choice("eco"),"scan.requestedWorkers":.integer(1),
                "scan.readOnlyProcesses":.integer(1),
                "ui.ecosystemOrder":.strings(first + ecosystems.filter { !first.contains($0) })]
            if cost { expected["cleanup.costCeiling"] = .choice("low"); expected["cleanup.warmProjectCount"] = .integer(5) }
            #expect(try PolicyDefaults.factory(name) == values(expected))
        }
        #expect(try PolicyDefaults.factory("battery") == values([
            "scan.preset":.choice("eco"),"scan.requestedWorkers":.integer(1),
            "scan.readOnlyProcesses":.integer(1),"scan.onLowPower":.choice("pauseAll"),
            "monitor.suppressHiddenSampling":.bool(true),"scan.defaultScope":.choice("quick")]))
    }
    @Test func legacyProjectionPreservesNondefaultsWithoutAuthority() throws {
        var legacy = TidyConfig(schemaVersion:2)
        legacy.staleNodeModulesThresholdDays = 90
        legacy.transcriptAgeThresholdDays = 120
        legacy.keepCookieDomains = ["keep.invalid"]
        legacy.gitRoots = ["/fixture/legacy-root"]
        legacy.appsApprovedForQuit = ["Old application name"]
        legacy.simulatorsApprovedForDeletion = ["Old simulator name"]
        legacy.allowRestartToReclaimSwap = true
        let projected = PolicyPreferences.project(legacy:legacy,saved:nil)
        #expect(projected.global.fields == values([
            "cleanup.transcriptDays":.integer(120),
            "item.normal.extras.stale-node-modules.inactiveDays":.integer(90),
            "browsers.keepCookieDomains":.strings(["keep.invalid"]),
            "rescue.showAdvancedMemoryActions":.bool(true)]).fields)
        let result = try PolicyResolver.resolve(input([.global:projected.global]))
        #expect(result.fields[key("cleanup.transcriptDays")]?.value == .stored(.integer(120)))
        #expect(result.fields[key("cleanup.inactiveDays")]?.value == .stored(.integer(60)))
        #expect(result.fields[key("item.normal.extras.stale-node-modules.inactiveDays")]?.value == .stored(.integer(90)))
        #expect(result.fields[key("scope.projectRoots")]?.value == .unavailable(.authorityUnavailable))
        #expect(result.fields[key("rescue.approvedApplications")]?.value == .unavailable(.authorityUnavailable))
        var newer = projected
        newer.global.fields[key("cleanup.transcriptDays")] = .integer(150)
        #expect(PolicyPreferences.project(legacy:legacy,saved:newer).global.fields[key("cleanup.transcriptDays")] == .integer(150))
    }
    @Test func presetSwitchesRetainOneStoredCustomPair() throws {
        var preferences = PolicyPreferences(global:values([
            "scan.preset":.choice("custom"),"scan.requestedWorkers":.integer(4),
            "scan.readOnlyProcesses":.integer(2)]),profiles:[],projects:[:])
        for (preset, workers, processes) in [("eco",1,1),("balanced",2,2),("custom",4,2)] {
            try preferences.selectPreset(preset)
            #expect(preferences.global.fields[key("scan.requestedWorkers")] == .integer(4))
            #expect(preferences.global.fields[key("scan.readOnlyProcesses")] == .integer(2))
            let result = try PolicyResolver.resolve(input([.global:preferences.global]))
            #expect(result.walkWorkers == workers); #expect(result.readOnlyProcesses == processes)
        }
        let profileID = UUID(uuidString:"33333333-3333-3333-3333-333333333333")!
        preferences.profiles = [SavedProfile(id:profileID,name:"Fixture",values:preferences.global)]
        try preferences.selectPreset("eco",profileID:profileID)
        #expect(preferences.global.fields[key("scan.preset")] == .choice("custom"))
        #expect(preferences.profiles[0].values.fields[key("scan.requestedWorkers")] == .integer(4))
        try preferences.selectPreset("custom",profileID:profileID)
        #expect(preferences.profiles[0].values.fields[key("scan.preset")] == .choice("custom"))
    }
}
