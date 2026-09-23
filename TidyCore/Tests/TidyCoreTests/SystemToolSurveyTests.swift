import Foundation
import Testing
@testable import TidyCore

@Suite("ProcessSurvey")
struct ProcessSurveyTests {
    @Test("reports plausible top memory consumers")
    func reportsPlausibleConsumers() async {
        let results = await ProcessSurvey.topMemoryConsumers(limit: 8)
        #expect(!results.isEmpty)
        #expect(results.count <= 8)
        for usage in results {
            #expect(usage.residentBytes > 0)
            #expect(!usage.name.isEmpty)
        }
    }

    @Test("respects the requested limit")
    func respectsLimit() async {
        let results = await ProcessSurvey.topMemoryConsumers(limit: 3)
        #expect(results.count <= 3)
    }
}

@Suite("ContainerSpaceInfo")
struct ContainerSpaceInfoTests {
    @Test("reports sane figures for the root container")
    func reportsSaneFigures() async {
        guard let info = await ContainerSpaceInfo.current() else { return }
        #expect(info.totalBytes > 0)
        #expect(info.freeBytes >= 0)
        #expect(info.freeBytes <= info.totalBytes)
    }
}

@Suite("SnapshotLister")
struct SnapshotListerTests {
    @Test("never crashes, and every identifier it returns matches the expected prefix")
    func neverCrashesAndMatchesPrefix() async {
        let snapshots = await SnapshotLister.listLocalSnapshots()
        for snapshot in snapshots {
            #expect(snapshot.identifier.hasPrefix("com.apple.TimeMachine"))
        }
    }

    @Test("dateComponent strips the well-known prefix and suffix")
    func dateComponentStripsPrefixAndSuffix() {
        let snapshot = LocalSnapshot(identifier: "com.apple.TimeMachine.2026-07-31-120000.local")
        #expect(snapshot.dateComponent == "2026-07-31-120000")
    }
}

@Suite("SimctlClient isolated response parsing")
struct SimctlClientTests {
    private let devicesJSON = #"{"devices":{"runtime.fixture":[{"udid":"11111111-1111-1111-1111-111111111111","name":"Fixture","state":"Shutdown","isAvailable":true}]}}"#
    private let runtimesJSON = #"{"runtimes":[{"identifier":"runtime.fixture","name":"Used"},{"identifier":"runtime.idle","name":"Idle"}]}"#

    @Test("device response keeps the exact runtime and device identity without a service launch")
    func listsDevicesWithoutCrashing() {
        let devices = SimctlClient.decodeDevices(Data(devicesJSON.utf8))
        #expect(devices.count == 1)
        #expect(devices.first?.udid == "11111111-1111-1111-1111-111111111111")
        #expect(devices.first?.runtimeIdentifier == "runtime.fixture")
        #expect(SimctlClient.decodeDevices(Data("invalid".utf8)).isEmpty)
    }

    @Test("runtime response rejects invalid and oversized output")
    func listsRuntimesWithoutCrashing() {
        #expect(SimctlClient.decodeRuntimes(Data(runtimesJSON.utf8)).count == 2)
        #expect(SimctlClient.decodeRuntimes(Data("{}".utf8)).isEmpty)
        #expect(SimctlClient.decodeRuntimes(Data(repeating: 32, count: 1_048_577)).isEmpty)
    }

    @Test("idle runtimes exclude any runtime referenced by a device")
    func idleRuntimesAreConsistent() {
        let devices = SimctlClient.decodeDevices(Data(devicesJSON.utf8))
        let runtimes = SimctlClient.decodeRuntimes(Data(runtimesJSON.utf8))
        let idle = SimctlClient.idleRuntimes(devices: devices, runtimes: runtimes)
        #expect(idle.map(\.identifier) == ["runtime.idle"])
    }
}
