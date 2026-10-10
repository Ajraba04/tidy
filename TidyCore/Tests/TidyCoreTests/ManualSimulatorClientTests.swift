import Darwin
import Foundation
import Testing
@_spi(TidyCoreTesting) @testable import TidyCore

private actor SimulatorClientReadFixture: ManualSimulatorReading {
    let deviceID: UUID
    var state: String
    var duplicate = false
    private var requests: [ManualSimulatorReadRequest] = []
    private var observedLease: ProcessTerminalVerificationLease?
    init(id: UUID, state: String = "Booted", duplicate: Bool = false) {
        deviceID = id; self.state = state; self.duplicate = duplicate
    }
    func read(_ request: ManualSimulatorReadRequest,
              terminalLease: ProcessTerminalVerificationLease?) async throws -> Data {
        requests.append(request)
        if let terminalLease { observedLease = terminalLease }
        switch request.component {
        case .devices:
            let row = "{\"udid\":\"\(deviceID.uuidString)\",\"name\":\"Owned fixture\",\"state\":\"\(state)\",\"isAvailable\":true,\"deviceTypeIdentifier\":\"com.apple.CoreSimulator.SimDeviceType.iPhone-17\"}"
            return Data("{\"devices\":{\"com.apple.CoreSimulator.SimRuntime.iOS-27-0\":[\(row)\(duplicate ? "," + row : "")]}}".utf8)
        case .runtimes:
            return Data(#"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","buildversion":"24A434","isAvailable":true,"supportedDeviceTypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17"}]}]}"#.utf8)
        case .pairs: return Data(#"{"pairs":{}}"#.utf8)
        }
    }
    func observed() -> [ManualSimulatorReadRequest] { requests }
    func lease() -> ProcessTerminalVerificationLease? { observedLease }
}

private struct SimulatorClientFixture {
    let root: URL
    let producer: AppleSimulatorProducerIdentity
    let object: ManualSimulatorObject
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/TidyManualSimulator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let set = root.appendingPathComponent("devices")
        let developer = root.appendingPathComponent("developer")
        for path in [set, developer] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        // A harmless owned direct child stands in for a producer only in this
        // fixture. No simctl process or actual device is touched.
        let executable = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/bin/cat"))
        producer = AppleSimulatorProducerIdentity(resolver: executable, simctl: executable,
            developerDirectory: try LocalRootApproval.verify(directory: developer),
            deviceSet: try LocalRootApproval.verify(directory: set), xcodeVersion: "27.0",
            xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        object = ManualSimulatorObject(udid: UUID(),
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            name: "Owned fixture", state: .booted, isAvailable: true)
    }
    var binding: ManualServiceOperationBinding {
        get throws { try ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(object), producer: .appleSimulator(producer)) }
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Pinned manual simulator client", .serialized)
struct ManualSimulatorClientTests {
    @Test("complete inventory uses only pinned simctl and exact device-set requests")
    func pinnedCompleteReads() async throws {
        let fixture = try SimulatorClientFixture(); defer { fixture.cleanup() }
        let reader = SimulatorClientReadFixture(id: fixture.object.udid)
        let client = try ManualSimulatorClient.forTesting(producer: fixture.producer, reader: reader)
        let inventory = try await client.inventory()
        #expect(inventory.deviceSet == fixture.producer.deviceSet)
        #expect(inventory.devices == [fixture.object])
        let requests = await reader.observed()
        #expect(requests.map(\.component) == [.devices, .runtimes, .pairs])
        for request in requests {
            #expect(request.executable == fixture.producer.simctl)
            #expect(request.arguments == ["--set", fixture.producer.deviceSet.canonicalPath,
                "list", request.component.rawValue, "-j"])
            #expect(request.environment["DEVELOPER_DIR"] == fixture.producer.developerDirectory.canonicalPath)
            #expect(request.environment["HOME"] == "/var/empty")
            #expect(request.environment.keys.sorted() == ["DEVELOPER_DIR", "HOME", "PATH"])
        }
        let candidates = try await client.candidates()
        #expect(candidates == [try fixture.binding])
    }

    @Test("duplicate or foreign identities cannot pass preflight", arguments: [false, true])
    func wrongObjectOrDuplicate(duplicate: Bool) async throws {
        let fixture = try SimulatorClientFixture(); defer { fixture.cleanup() }
        let reader = SimulatorClientReadFixture(id: duplicate ? fixture.object.udid : UUID(), duplicate: duplicate)
        let client = try ManualSimulatorClient.forTesting(producer: fixture.producer, reader: reader)
        await #expect(throws: Error.self) { try await client.preflight(fixture.binding) }
    }

    @Test("changed device set rejects before any read")
    func changedDeviceSet() async throws {
        let fixture = try SimulatorClientFixture(); defer { fixture.cleanup() }
        let reader = SimulatorClientReadFixture(id: fixture.object.udid)
        let client = try ManualSimulatorClient.forTesting(producer: fixture.producer, reader: reader)
        let old = URL(fileURLWithPath: fixture.producer.deviceSet.canonicalPath)
        try FileManager.default.moveItem(at: old, to: fixture.root.appendingPathComponent("old-devices"))
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: false)
        await #expect(throws: Error.self) { try await client.inventory() }
        #expect(await reader.observed().isEmpty)
    }

    @Test("sealed owned fixture provenance is required for a shutdown receipt", arguments: ["success", "wrongProducer", "booted", "foreignID"])
    func ownedShutdownReceipt(variant: String) async throws {
        let fixture = try SimulatorClientFixture(); defer { fixture.cleanup() }
        let other = try SimulatorClientFixture(); defer { other.cleanup() }
        let reader = SimulatorClientReadFixture(id: variant == "foreignID" ? UUID() : fixture.object.udid,
            state: variant == "booted" ? "Booted" : "Shutdown")
        let client = try ManualSimulatorClient.forTesting(producer: variant == "wrongProducer" ? other.producer : fixture.producer, reader: reader)
        let admission = try MutationAdmissionStore(directory: fixture.root.appendingPathComponent("journal"))
        #expect(admission.acquire() == .ready)
        defer { admission.release() }
        let journal = try RunJournal(store: admission,
            storage: DurableJournalStorage(directory: fixture.root.appendingPathComponent("journal")))
        let binding = try ManualServiceEffectBinding(reviewID: UUID(), coordinatorID: UUID(),
            policyRevision: 1, authorityRevision: 1,
            installation: LocalInstallationIdentity.verify(directory: fixture.root), operation: fixture.binding)
        let runID = UUID(), operationID = UUID()
        try journal.append(.init(runID: runID, sequence: 1, phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(.init(runID: runID, sequence: 2, phase: .confirmed, operationID: nil, status: nil, reason: nil))
        let submission = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID, binding: binding, journal: journal)
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let launch = try await ProcessRunner.launchManualSimulatorFixtureForTesting(submission: submission,
            gate: gate, deadline: ContinuousClock.now.advanced(by: .seconds(2)))
        try launch.session.releaseStartByte()
        // The method accepts only opaque launch provenance. A raw ProcessSession
        // or a caller-supplied permit cannot be substituted at this API boundary.
        if variant == "success" {
            let receipt = try await client.terminalReceiptForTesting(launch: launch, within: .seconds(2))
            #expect(receipt.binding == binding)
            #expect(receipt.runID == runID && receipt.operationID == operationID)
            #expect(receipt.invocationOrigin == .cooperativeFixture)
            #expect(receipt.invocationDigest == launch.invocation.invocationDigest)
            #expect(receipt.childSessionID == (try launch.session.reapedMutationReceipt()).sessionID)
            #expect(receipt.childIdentity == (try launch.session.reapedMutationReceipt()).identity)
            #expect(receipt.rawWaitStatus == 0)
            #expect(receipt.observedDevice.state == .shutdown)
            #expect(receipt.postconditionDigest.count == 32)
            #expect(await reader.observed().map(\.component) == [.devices, .runtimes, .pairs])
            try await gate.closeTerminalVerificationForTesting(receipt.terminalVerificationLease)
        } else {
            await #expect(throws: Error.self) {
                try await client.terminalReceiptForTesting(launch: launch, within: .seconds(2))
            }
            #expect(try admission.unfinishedIntentsWhileLocked().first?.phase == .submitted)
            if variant == "wrongProducer" { #expect(await reader.observed().isEmpty) }
            // Test-isolated cleanup observes the actual child even when rejection
            // occurred before terminal-read admission. It creates no success proof.
            if let lease = await reader.lease() {
                try await gate.closeTerminalVerificationForTesting(lease)
            } else {
                _ = await launch.session.observeOwnedExit(within: .seconds(2))
                let lease = try await launch.session.transferReapedMutationToTerminalVerification(within: .seconds(1))
                try await gate.closeTerminalVerificationForTesting(lease)
            }
        }
    }
}
