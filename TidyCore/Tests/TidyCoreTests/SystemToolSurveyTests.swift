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

@Suite("SimctlClient")
struct SimctlClientTests {
    @Test("lists devices without crashing")
    func listsDevicesWithoutCrashing() async {
        let devices = await SimctlClient.listDevices()
        for device in devices {
            #expect(!device.udid.isEmpty)
            #expect(!device.runtimeIdentifier.isEmpty)
        }
    }

    @Test("lists runtimes without crashing")
    func listsRuntimesWithoutCrashing() async {
        let runtimes = await SimctlClient.listRuntimes()
        for runtime in runtimes {
            #expect(!runtime.identifier.isEmpty)
        }
    }

    @Test("idle runtimes are a subset of all runtimes and exclude anything with a device")
    func idleRuntimesAreConsistent() async {
        async let allRuntimes = SimctlClient.listRuntimes()
        async let allDevices = SimctlClient.listDevices()
        let idle = await SimctlClient.idleRuntimes()

        let runtimes = await allRuntimes
        let devices = await allDevices
        let usedIdentifiers = Set(devices.map(\.runtimeIdentifier))

        let idleIdentifiers = Set(idle.map(\.identifier))
        #expect(idleIdentifiers.isSubset(of: Set(runtimes.map(\.identifier))))
        #expect(idleIdentifiers.isDisjoint(with: usedIdentifiers))
    }
}
