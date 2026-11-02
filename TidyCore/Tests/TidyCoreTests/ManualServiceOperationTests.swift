import CryptoKit
import Foundation
import Testing
@testable import TidyCore

@Suite("Manual service display bindings and complete inventory")
struct ManualServiceOperationTests {
    private let firstID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let secondID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let runtime = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
    private let deviceType = "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
    private let containerID = String(repeating: "a", count: 64)

    @Test func twoFixedAdaptersAndProductionAcceptanceAlwaysDenied() throws {
        #expect(ManualServiceAdapterID.allCases.count == 2)
        let inventory = try simulatorInventory()
        let producer = appleProducer()
        let object = try ManualProducerInventory.shutdownCandidate(
            id: firstID, inventory: inventory, producer: producer)
        let binding = try ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(object), producer: .appleSimulator(producer))
        #expect(ManualServiceAcceptanceRegistry.denial(for: binding) != nil)
        let docker = try dockerProducer()
        let container = try ManualProducerInventory.parseDockerContainer(
            inspect: json(containerRow()), expectedID: containerID)
        let dockerBinding = try ManualServiceOperationBinding(adapter: .dockerStoppedContainerRemovalV1,
            object: .container(container), producer: .docker(docker))
        #expect(ManualServiceAcceptanceRegistry.denial(for: dockerBinding) != nil)
    }

    @Test func sameDisplayNameCannotSelectAnotherSimulatorIdentity() throws {
        let inventory = try simulatorInventory()
        #expect(inventory.devices.count == 2)
        let first = try ManualProducerInventory.shutdownCandidate(
            id: firstID, inventory: inventory, producer: appleProducer())
        let second = try ManualProducerInventory.shutdownCandidate(
            id: secondID, inventory: inventory, producer: appleProducer())
        #expect(first.udid == firstID && first.state == .booted)
        #expect(second.udid == secondID && second.state == .shutdown)
        #expect(first.name == second.name)
        #expect(throws: (any Error).self) {
            _ = try ManualProducerInventory.shutdownCandidate(
                id: UUID(), inventory: inventory, producer: appleProducer())
        }
    }

    @Test func duplicateDevicesUnavailableRuntimeUnknownTypeAndIncompletePairsDeny() throws {
        var duplicate = deviceRows(); duplicate[1]["udid"] = firstID.uuidString
        for rows in [duplicate, [deviceRow(firstID, state: "Booting")],
                     [deviceRow(firstID, state: "invented")]] {
            #expect(throws: (any Error).self) {
                let value = try simulatorInventory(rows: rows)
                _ = try ManualProducerInventory.shutdownCandidate(
                    id: firstID, inventory: value, producer: appleProducer())
            }
        }
        for available in [false] {
            #expect(throws: (any Error).self) {
                let value = try simulatorInventory(runtimeAvailable: available)
                _ = try ManualProducerInventory.shutdownCandidate(
                    id: firstID, inventory: value, producer: appleProducer())
            }
        }
        var wrongType = deviceRows(); wrongType[0]["deviceTypeIdentifier"] = "unknown.type"
        #expect(throws: (any Error).self) { _ = try simulatorInventory(rows: wrongType) }
        #expect(throws: (any Error).self) {
            _ = try simulatorInventory(pairData: json(["pairs": ["broken": [:]]]))
        }
        #expect(throws: (any Error).self) {
            _ = try simulatorInventory(pairData: json(["pairs": [
                UUID().uuidString: ["watch": ["udid": firstID.uuidString],
                                    "phone": ["udid": secondID.uuidString]]]]))
        }
        #expect(throws: (any Error).self) {
            _ = try simulatorInventory(pairData: Data("{\"pairs\":".utf8))
        }
    }

    @Test func changedSetOrUnsupportedVersionCannotProduceShutdownCandidate() throws {
        let inventory = try simulatorInventory()
        #expect(throws: (any Error).self) {
            _ = try ManualProducerInventory.shutdownCandidate(id: firstID,
                inventory: inventory, producer: appleProducer(setInode: 99))
        }
        #expect(throws: (any Error).self) {
            _ = try ManualProducerInventory.shutdownCandidate(id: firstID,
                inventory: inventory, producer: appleProducer(xcodeVersion: "26.0"))
        }
    }

    @Test func completePairMembershipAndDuplicateRuntimeOrJSONKeysFailClosed() throws {
        let watchRuntime = "com.apple.CoreSimulator.SimRuntime.watchOS-27-0"
        let watchType = "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11"
        let ios: [String: Any] = ["identifier": runtime, "version": "27.0", "buildversion": "X1",
            "isAvailable": true, "supportedDeviceTypes": [["identifier": deviceType]]]
        let watch: [String: Any] = ["identifier": watchRuntime, "version": "27.0", "buildversion": "W1",
            "isAvailable": true, "supportedDeviceTypes": [["identifier": watchType]]]
        var watchDevice = deviceRow(secondID, state: "Booted"); watchDevice["deviceTypeIdentifier"] = watchType
        let devices = try json(["devices": [runtime: [deviceRow(firstID, state: "Booted")], watchRuntime: [watchDevice]]])
        let pairs = try json(["pairs": [UUID().uuidString: ["watch": ["udid": secondID.uuidString],
                                                         "phone": ["udid": firstID.uuidString]]]])
        let inventory = try ManualProducerInventory.parseSimulator(devices: devices,
            runtimes: json(["runtimes": [ios, watch]]), pairs: pairs, deviceSet: root())
        #expect(inventory.pairs.count == 1)
        for id in [firstID, secondID] {
            #expect(throws: (any Error).self) {
                _ = try ManualProducerInventory.shutdownCandidate(id: id, inventory: inventory, producer: appleProducer())
            }
        }
        #expect(throws: (any Error).self) {
            _ = try ManualProducerInventory.parseSimulator(devices: devices,
                runtimes: json(["runtimes": [ios, ios, watch]]), pairs: pairs, deviceSet: root())
        }
        #expect(throws: (any Error).self) {
            _ = try ManualProducerInventory.parseSimulator(devices: Data("{\"devices\":{},\"devices\":{}}".utf8),
                runtimes: json(["runtimes": []]), pairs: json(["pairs": [:]]), deviceSet: root())
        }
    }

    @Test func dockerOnlyAcceptsExactExitedUnmountedUnmanagedContainer() throws {
        let object = try ManualProducerInventory.parseDockerContainer(
            inspect: json(containerRow()), expectedID: containerID)
        #expect(object.id == containerID)
        #expect(object.requiresWholeContainerDataLossConfirmation)
        #expect(object.writableLayerBytes == nil, "Unknown size cannot become proof of no data")
        for invalidID in [String(repeating: "A", count: 64), String(repeating: "a", count: 12),
                          "sha256:" + containerID, String(repeating: "é", count: 64)] {
            var row = containerRow(); row["Id"] = invalidID
            #expect(throws: (any Error).self) {
                _ = try ManualProducerInventory.parseDockerContainer(
                    inspect: json(row), expectedID: invalidID)
            }
        }
        #expect(throws: (any Error).self) {
            _ = try ManualProducerInventory.parseDockerContainer(
                inspect: json(containerRow()), expectedID: String(repeating: "b", count: 64))
        }
        for state in ["running", "paused", "restarting", "removing", "dead", "unknown", "stopped"] {
            var row = containerRow(); row["State"] = ["Status": state,
                "Running": false, "Paused": false, "Restarting": false]
            #expect(throws: (any Error).self) {
                _ = try ManualProducerInventory.parseDockerContainer(inspect: json(row), expectedID: containerID)
            }
        }
        var missing = containerRow(); missing["State"] = ["Status": "exited", "Running": false]
        #expect(throws: (any Error).self) {
            _ = try ManualProducerInventory.parseDockerContainer(inspect: json(missing), expectedID: containerID)
        }
        var numericBoolean = containerRow()
        numericBoolean["State"] = ["Status": "exited", "Running": 0, "Paused": false, "Restarting": false]
        #expect(throws: (any Error).self) {
            _ = try ManualProducerInventory.parseDockerContainer(inspect: json(numericBoolean), expectedID: containerID)
        }
        #expect(throws: (any Error).self) {
            _ = try ManualProducerInventory.parseDockerContainers(
                inspections: [json(containerRow()), json(containerRow())], expectedIDs: [containerID, containerID])
        }
    }

    @Test func dockerMountDeclarationsDriversAndManagedPrefixesDeny() throws {
        var variants: [[String: Any]] = []
        var mount = containerRow(); mount["Mounts"] = [["Type": "bind"]]; variants.append(mount)
        for declaration: Any in [["/scratch": "rw"], ["invalid"], true] {
            var row = containerRow(), host = row["HostConfig"] as! [String: Any]
            host["Tmpfs"] = declaration; row["HostConfig"] = host; variants.append(row)
        }
        for field in ["VolumeDriver", "Binds", "VolumesFrom", "Mounts"] {
            var row = containerRow(), host = row["HostConfig"] as! [String: Any]
            host[field] = field == "VolumeDriver" ? "plugin" : ["declaration"] as Any
            row["HostConfig"] = host; variants.append(row)
        }
        for prefix in ["com.docker.compose.", "com.docker.stack.", "com.docker.swarm.", "io.kubernetes."] {
            var row = containerRow(); row["Config"] = ["Volumes": NSNull(), "Labels": [prefix + "owner": "value"]]
            variants.append(row)
        }
        var declared = containerRow(); declared["Config"] = ["Volumes": ["/data": [:]], "Labels": NSNull()]
        variants.append(declared)
        for row in variants {
            #expect(throws: (any Error).self) {
                _ = try ManualProducerInventory.parseDockerContainer(inspect: json(row), expectedID: containerID)
            }
        }
    }

    @Test func dockerVersionInfoAndPeerAreBoundButNeverAcceptance() throws {
        let producer = try dockerProducer()
        #expect(producer.daemonID == "daemon-fixture")
        #expect(producer.version.apiVersion == "1.51")
        #expect(throws: (any Error).self) { _ = try dockerProducer(serverVersion: "different") }
        #expect(throws: (any Error).self) { _ = try dockerProducer(peerPID: 0) }
        #expect(throws: (any Error).self) {
            _ = try ManualProducerInventory.parseDockerProducer(version: json([:]), info: json([:]),
                socket: socket(), peerPID: 1, peerUID: 501, peerBootID: firstID,
                peerStartSeconds: 1, peerStartMicroseconds: 2, peerExecutable: executable(),
                providerIdentifier: "unqualified-local")
        }
    }

    @Test func oversizedMalformedAndDeepInventoryCannotProduceBinding() throws {
        for data in [Data(repeating: 32, count: 2_097_153), Data("{".utf8),
                     Data((String(repeating: "[", count: 30) + "0" + String(repeating: "]", count: 30)).utf8)] {
            #expect(throws: (any Error).self) {
                _ = try ManualProducerInventory.parseDockerContainer(inspect: data, expectedID: containerID)
            }
        }
    }

    @Test func fullVersionedBindingDigestRoundTripsAndChangesWithProducerIdentity() throws {
        let inventory = try simulatorInventory()
        let object = try ManualProducerInventory.shutdownCandidate(
            id: firstID, inventory: inventory, producer: appleProducer())
        let binding = try ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(object), producer: .appleSimulator(appleProducer()))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(binding)
        #expect(try binding.canonicalDigest() == Data(SHA256.hash(data: data)))
        let decoded = try JSONDecoder().decode(ManualServiceOperationBinding.self, from: data)
        #expect(decoded == binding)
        #expect(try decoded.canonicalDigest() == binding.canonicalDigest())
        let changed = try ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(object), producer: .appleSimulator(appleProducer(toolInode: 99)))
        #expect(try changed.canonicalDigest() != binding.canonicalDigest())
        var wrongSchema = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        wrongSchema["schemaVersion"] = 99
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ManualServiceOperationBinding.self, from: json(wrongSchema))
        }
        #expect(throws: (any Error).self) {
            _ = try ManualServiceOperationBinding(adapter: .dockerStoppedContainerRemovalV1,
                object: .simulator(object), producer: .appleSimulator(appleProducer()))
        }
    }

    @Test func dockerDigestBindsPeerIncarnationSocketToolAndMutableReviewMetadata() throws {
        let object = try ManualProducerInventory.parseDockerContainer(inspect: json(containerRow()), expectedID: containerID)
        let original = try ManualServiceOperationBinding(adapter: .dockerStoppedContainerRemovalV1,
            object: .container(object), producer: .docker(dockerProducer()))
        let variants = try [dockerProducer(peerPID: 2), dockerProducer(peerBootID: secondID),
            dockerProducer(peerStartSeconds: 99), dockerProducer(peerStartMicroseconds: 99),
            dockerProducer(socketInode: 99), dockerProducer(peerToolInode: 99)]
        for producer in variants {
            let changed = try ManualServiceOperationBinding(adapter: .dockerStoppedContainerRemovalV1,
                object: .container(object), producer: .docker(producer))
            #expect(try changed.canonicalDigest() != original.canonicalDigest())
        }
        var renamed = containerRow(); renamed["Name"] = "/new-name"
        var config = renamed["Config"] as! [String: Any]; config["Env"] = ["VALUE=fixture"]
        renamed["Config"] = config
        let changedObject = try ManualProducerInventory.parseDockerContainer(inspect: json(renamed), expectedID: containerID)
        #expect(changedObject.id == object.id, "Mutable metadata does not select a different target")
        let changed = try ManualServiceOperationBinding(adapter: .dockerStoppedContainerRemovalV1,
            object: .container(changedObject), producer: .docker(dockerProducer()))
        #expect(try changed.canonicalDigest() != original.canonicalDigest())
        #expect(throws: (any Error).self) { _ = try dockerProducer(peerStartSeconds: -1) }
        #expect(throws: (any Error).self) { _ = try dockerProducer(peerStartMicroseconds: 1_000_000) }
    }

    @Test func reviewSummaryIsDisplayOnlyBoundedToSixtySecondsAndValidatedOnDecode() throws {
        let inventory = try simulatorInventory()
        let object = try ManualProducerInventory.shutdownCandidate(id: firstID, inventory: inventory, producer: appleProducer())
        let binding = try ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(object), producer: .appleSimulator(appleProducer()))
        let summary = try ManualServiceReviewSummary(reviewID: firstID, binding: binding,
            issuedAtMonotonicNanoseconds: 100, expiresAtMonotonicNanoseconds: 60_000_000_100)
        #expect(try JSONDecoder().decode(ManualServiceReviewSummary.self, from: JSONEncoder().encode(summary)) == summary)
        #expect(throws: (any Error).self) {
            _ = try ManualServiceReviewSummary(reviewID: firstID, binding: binding,
                issuedAtMonotonicNanoseconds: 100, expiresAtMonotonicNanoseconds: 60_000_000_101)
        }
        #expect(ManualServiceReviewSummary.maximumPendingReviewCount == 32)
        var oversized = try JSONSerialization.jsonObject(with: JSONEncoder().encode(appleProducer())) as! [String: Any]
        oversized["xcodeVersion"] = String(repeating: "x", count: 129)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(AppleSimulatorProducerIdentity.self, from: json(oversized))
        }
    }

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    private func root(_ path: String = "/private/fixture/set", inode: UInt64 = 2) -> LocalRootApproval {
        .init(canonicalPath: path, volumeID: firstID, device: 1, inode: inode)
    }
    private func executable(inode: UInt64 = 3) -> LocalExecutableApproval {
        .init(canonicalPath: "/private/fixture/simctl", device: 1, inode: inode)
    }
    private func socket() -> LocalSocketApproval {
        .init(canonicalPath: "/private/fixture/docker.sock", device: 1, inode: 4, ownerUID: 501)
    }
    private func appleProducer(setInode: UInt64 = 2, toolInode: UInt64 = 3,
                               xcodeVersion: String = "27.0") -> AppleSimulatorProducerIdentity {
        .init(resolver: executable(), simctl: executable(inode: toolInode),
              developerDirectory: root("/private/fixture/developer"), deviceSet: root(inode: setInode),
              xcodeVersion: xcodeVersion, xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
    }
    private func deviceRow(_ id: UUID, state: String) -> [String: Any] {
        ["udid": id.uuidString, "name": "Same display name", "state": state,
         "isAvailable": true, "deviceTypeIdentifier": deviceType]
    }
    private func deviceRows() -> [[String: Any]] {
        [deviceRow(firstID, state: "Booted"), deviceRow(secondID, state: "Shutdown")]
    }
    private func simulatorInventory(rows: [[String: Any]]? = nil, runtimeAvailable: Bool = true,
                                    pairData: Data? = nil) throws -> ManualSimulatorInventory {
        try ManualProducerInventory.parseSimulator(devices: json(["devices": [runtime: rows ?? deviceRows()]]),
            runtimes: json(["runtimes": [["identifier": runtime, "version": "27.0", "buildversion": "X1",
                "isAvailable": runtimeAvailable, "supportedDeviceTypes": [["identifier": deviceType]]]]]),
            pairs: pairData ?? json(["pairs": [:]]), deviceSet: root())
    }
    private func containerRow() -> [String: Any] {
        ["Id": containerID, "Name": "/same-name", "Created": "2026-10-10T00:00:00Z",
         "Image": "sha256:" + String(repeating: "b", count: 64),
         "State": ["Status": "exited", "Running": false, "Paused": false, "Restarting": false],
         "Mounts": [], "Config": ["Labels": NSNull(), "Volumes": NSNull()],
         "HostConfig": ["VolumeDriver": "", "Binds": NSNull(), "VolumesFrom": NSNull()]]
    }
    private func dockerProducer(serverVersion: String = "28.0.0", peerPID: Int32 = 1,
                                peerBootID: UUID? = nil, peerStartSeconds: Int64 = 1,
                                peerStartMicroseconds: Int32 = 2, socketInode: UInt64 = 4,
                                peerToolInode: UInt64 = 3) throws -> DockerProducerIdentity {
        try ManualProducerInventory.parseDockerProducer(
            version: json(["Version": "28.0.0", "ApiVersion": "1.51", "MinAPIVersion": "1.44", "Os": "linux", "Arch": "arm64"]),
            info: json(["ID": "daemon-fixture", "ServerVersion": serverVersion, "OSType": "linux", "Architecture": "aarch64"]),
            socket: .init(canonicalPath: socket().canonicalPath, device: 1, inode: socketInode, ownerUID: 501),
            peerPID: peerPID, peerUID: 501, peerBootID: peerBootID ?? firstID,
            peerStartSeconds: peerStartSeconds, peerStartMicroseconds: peerStartMicroseconds,
            peerExecutable: executable(inode: peerToolInode),
            providerIdentifier: "unqualified-local")
    }
}
