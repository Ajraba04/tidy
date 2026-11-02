import Foundation
import Testing
@testable import TidyCore

@Suite("Pinned simulator producer discovery metadata")
struct ManualSimulatorDiscoveryTests {
    @Test func datalessMetadataIsRejectedWithoutHydratingACloudFixture() {
        #expect(ManualSimulatorDiscovery.metadataIsLocallyPresent(flags: 0))
        #expect(!ManualSimulatorDiscovery.metadataIsLocallyPresent(flags: 0x40000000))
        #expect(!ManualSimulatorDiscovery.metadataIsLocallyPresent(flags: 0x40000002))
    }
    @Test func completeVersionMetadataAndExactSimctlVersion() throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "27.0",
            "ProductBuildVersion": "27A266a"], format: .binary, options: 0)
        let version = try ManualSimulatorDiscovery.parseVersionMetadata(plist)
        #expect(version.version == "27.0" && version.build == "27A266a")
        #expect(try ManualSimulatorDiscovery.parseCoreSimulatorVersion(
            Data("@(#)PROGRAM:simctl  PROJECT:CoreSimulator-1171.7\n".utf8)) == "1171.7")
    }
    @Test(arguments: ["", "1171.7", "@(#)PROGRAM:simctl  PROJECT:CoreSimulator-1171.7\nextra",
                      "@(#)PROGRAM:other  PROJECT:CoreSimulator-1171.7"])
    func malformedVersionDenied(value: String) throws {
        #expect(throws: Error.self) { try ManualSimulatorDiscovery.parseCoreSimulatorVersion(Data(value.utf8)) }
    }
    @Test func unknownOrMissingMetadataFailsClosed() throws {
        for data in [Data(), Data(repeating: 0x20, count: 65_537),
                     try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "27.0"], format: .binary, options: 0)] {
            #expect(throws: Error.self) { try ManualSimulatorDiscovery.parseVersionMetadata(data) }
        }
    }
    @Test func exactSelectedExecutablePathIsRequired() throws {
        #expect(try ManualSimulatorDiscovery.parseResolvedSimctl(
            Data("/Applications/Xcode.app/Contents/Developer/usr/bin/simctl\n".utf8)).path
            == "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl")
        for path in ["/usr/bin/simctl", "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl\nextra",
                     "/Applications/Xcode.app/Contents/Developer/usr/bin/../bin/simctl", "relative/simctl"] {
            #expect(throws: Error.self) { try ManualSimulatorDiscovery.parseResolvedSimctl(Data(path.utf8)) }
        }
    }
    @Test func existingDeviceSetMetadataIsRequiredAndNeverFollowedThroughALink() throws {
        let root = URL(fileURLWithPath: "/private/tmp/TidyExistingSet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let approval = try LocalRootApproval.verify(directory: root)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        #expect(throws: Error.self) { try ManualSimulatorDiscovery.requireExistingDeviceSet(approval, deadline: deadline) }
        let marker = root.appendingPathComponent("device_set.plist")
        let valid = try PropertyListSerialization.data(fromPropertyList:
            ["Version": 3, "DefaultDevices": [:], "DevicePairs": [:]] as [String: Any], format: .binary, options: 0)
        try valid.write(to: marker)
        try ManualSimulatorDiscovery.requireExistingDeviceSet(approval, deadline: deadline)
        try FileManager.default.moveItem(at: marker, to: root.appendingPathComponent("witness.plist"))
        try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: root.appendingPathComponent("witness.plist"))
        #expect(throws: Error.self) { try ManualSimulatorDiscovery.requireExistingDeviceSet(approval, deadline: deadline) }
        #expect(try Data(contentsOf: root.appendingPathComponent("witness.plist")) == valid)
        let malformed = try PropertyListSerialization.data(fromPropertyList: ["Version": true], format: .binary, options: 0)
        #expect(throws: Error.self) { try ManualSimulatorDiscovery.validateDeviceSetMetadata(malformed) }
    }
    @Test func discoveryWithoutExactLocalGrantsRejectsBeforeAnyProbe() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/TidyDiscovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalAuthorityStore(directory: root,
            installation: LocalInstallationIdentity.verify(directory: root))
        let set = try LocalRootApproval.verify(directory: root)
        let snapshot = try await store.snapshot()
        await #expect(throws: ManualServiceReviewError.authorityDenied) {
            _ = try await ManualSimulatorCandidateService.read(deviceSet: set, authority: snapshot)
        }
    }

    @Test("approved device-set options reject replaced roots and ancestor aliases",
          arguments: ["unchanged", "replacement", "rootAlias", "parentAlias", "markerAlias"])
    func approvedExistingSetsRequireCurrentRootIdentity(change: String) async throws {
        let base = URL(fileURLWithPath: "/private/tmp/TidyApprovedSet-\(UUID().uuidString)")
        let authorityDirectory = base.appendingPathComponent("authority")
        let parent = base.appendingPathComponent("parent")
        let set = parent.appendingPathComponent("devices")
        for url in [base, authorityDirectory, parent, set] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        defer { try? FileManager.default.removeItem(at: base) }
        let marker = set.appendingPathComponent("device_set.plist")
        let bytes = try PropertyListSerialization.data(fromPropertyList:
            ["Version": 3, "DefaultDevices": [:], "DevicePairs": [:]] as [String: Any], format: .binary, options: 0)
        try bytes.write(to: marker)
        let root = try LocalRootApproval.verify(directory: set)
        let store = try LocalAuthorityStore(directory: authorityDirectory,
            installation: LocalInstallationIdentity.verify(directory: authorityDirectory))
        let owner = LocalAuthorityOwner()
        let token = try await store.beginReview(scope: .localRoot(root), owner: owner,
            nowMonotonicNanoseconds: 1)
        let snapshot = try await store.confirm(token, owner: owner, nowMonotonicNanoseconds: 2)
        switch change {
        case "replacement":
            try FileManager.default.moveItem(at: set, to: parent.appendingPathComponent("old"))
            try FileManager.default.createDirectory(at: set, withIntermediateDirectories: false)
            try bytes.write(to: marker)
        case "rootAlias":
            let moved = parent.appendingPathComponent("old")
            try FileManager.default.moveItem(at: set, to: moved)
            try FileManager.default.createSymbolicLink(at: set, withDestinationURL: moved)
        case "parentAlias":
            let moved = base.appendingPathComponent("old-parent")
            try FileManager.default.moveItem(at: parent, to: moved)
            try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: moved)
        case "markerAlias":
            let moved = set.appendingPathComponent("witness.plist")
            try FileManager.default.moveItem(at: marker, to: moved)
            try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: moved)
        default: break
        }
        let result = await ManualSimulatorCandidateService.approvedExistingDeviceSets(authority: snapshot)
        #expect(result == (change == "unchanged" ? [root] : []))
        _ = try await store.revoke(.localRoot(root))
        #expect(await ManualSimulatorCandidateService.approvedExistingDeviceSets(authority: snapshot).isEmpty)
    }
}
