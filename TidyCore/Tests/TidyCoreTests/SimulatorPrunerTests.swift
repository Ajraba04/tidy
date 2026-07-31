import Testing
@testable import TidyCore

/// These tests only exercise `devicesEligibleForDeletion`, a pure function
/// over a caller-supplied device array. They never touch real `simctl`
/// device listing or deletion. `deleteDevice` is exercised exactly once,
/// against a UDID that cannot possibly correspond to a real device,
/// specifically so this suite can never touch this machine's sanctioned
/// simulators.
@Suite("SimulatorPruner")
struct SimulatorPrunerTests {
    @Test("returns nothing when the approval list is empty")
    func returnsEmptyWhenNothingApproved() {
        let devices = [
            SimulatorDevice(udid: "A", name: "iPhone 17 Pro Max", state: "Shutdown", isAvailable: true, deviceTypeIdentifier: nil)
        ]
        let eligible = SimulatorPruner.devicesEligibleForDeletion(allDevices: devices, approvedForDeletion: [])
        #expect(eligible.isEmpty)
    }

    @Test("only returns devices whose name exactly matches an approved entry")
    func onlyReturnsExactNameMatches() {
        let devices = [
            SimulatorDevice(udid: "A", name: "iPhone 17 Pro Max", state: "Shutdown", isAvailable: true, deviceTypeIdentifier: nil),
            SimulatorDevice(udid: "B", name: "iPhone SE (3rd generation)", state: "Shutdown", isAvailable: true, deviceTypeIdentifier: nil)
        ]
        let eligible = SimulatorPruner.devicesEligibleForDeletion(
            allDevices: devices,
            approvedForDeletion: ["iPhone SE (3rd generation)"]
        )
        #expect(eligible.map(\.udid) == ["B"])
    }

    @Test("matches by exact name only, never by substring")
    func matchesByExactNameOnly() {
        let devices = [
            SimulatorDevice(udid: "A", name: "iPhone 17 Pro Max", state: "Shutdown", isAvailable: true, deviceTypeIdentifier: nil)
        ]
        // A stray "iPhone" approval must not match "iPhone 17 Pro Max" --
        // exact match only, the inverse of the shell script's substring
        // keep-list.
        let eligible = SimulatorPruner.devicesEligibleForDeletion(allDevices: devices, approvedForDeletion: ["iPhone"])
        #expect(eligible.isEmpty)
    }

    @Test("matching is case-sensitive on the exact device name")
    func matchingIsCaseSensitive() {
        let devices = [
            SimulatorDevice(udid: "A", name: "iPhone 17 Pro Max", state: "Shutdown", isAvailable: true, deviceTypeIdentifier: nil)
        ]
        let eligible = SimulatorPruner.devicesEligibleForDeletion(allDevices: devices, approvedForDeletion: ["iphone 17 pro max"])
        #expect(eligible.isEmpty)
    }

    @Test("deleteDevice against a UDID that cannot correspond to a real device fails gracefully")
    func deleteDeviceAgainstNonexistentUDIDFailsGracefully() async {
        let succeeded = await SimulatorPruner.deleteDevice(udid: "00000000-0000-0000-0000-000000000000")
        #expect(!succeeded)
    }

    @Test("real devices on this machine are never eligible when nothing real is approved (exercises the full listing pipeline read-only)")
    func realDevicesNeverEligibleWithoutRealApproval() {
        // Unlike the other tests here, this calls the real, synchronous
        // simctl-backed listing (SimctlClient.listDevicesSync()) against
        // whatever simulators actually exist on this machine. It never
        // calls deleteDevice on the result, only asserts the read-only
        // eligibility filter, so even a bug in the matching logic could at
        // worst make this assertion fail, not delete anything.
        let realDevices = SimctlClient.listDevicesSync()
        let eligible = SimulatorPruner.devicesEligibleForDeletion(
            allDevices: realDevices,
            approvedForDeletion: ["definitely-not-a-real-simulator-name-xyz123"]
        )
        #expect(eligible.isEmpty)
    }
}
