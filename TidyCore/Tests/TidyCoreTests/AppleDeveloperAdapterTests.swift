import Foundation
import Testing
@testable import TidyCore

@Suite("Apple developer adapter")
struct AppleDeveloperAdapterTests {
    @Test("simctl fixture binds exact UDID and mutation remains unavailable")
    func parsesExactDeviceAndDeniesDispatch() throws {
        let bytes = Data(#"{"devices":{"runtime.fixture":[{"udid":"11111111-1111-1111-1111-111111111111","name":"Fixture","state":"Shutdown","isAvailable":true}]}}"#.utf8)
        let device = try #require(AppleDeveloperAdapter.parseSimctlDevices(bytes)?.first)
        #expect(device.udid.uuidString == "11111111-1111-1111-1111-111111111111")
        let record = try #require(AppleDeveloperAdapter.inventoryRecords(
            fromSimctlData: bytes, scopeID: "fixture")?.first)
        #expect(record.resource == .simulator(udid: device.udid,
                                             runtimeID: "runtime.fixture"))
        #expect(record.capability == .inventoryOnly)
        let spec = AppleDeveloperAdapter.effectSpec(for: device, operation: .delete)
        #expect(spec.exactArgv == ["simctl", "delete", device.udid.uuidString])
        if case .unavailable = spec.availability {} else {
            Issue.record("mutation enabled")
        }
        #expect(AppleDeveloperAdapter.parseSimctlDevices(Data("{}".utf8)) == nil)
    }
}
