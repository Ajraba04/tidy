import Darwin
import Foundation
import Testing
@_spi(TidyCoreTesting) @testable import TidyCore

private func describedSimulatorEffect(udid: UUID = UUID(), setPath: String = "/private/tmp/owned-set") throws -> ManualServiceEffectBinding {
    let developer = LocalRootApproval(canonicalPath: "/Applications/FixtureXcode.app/Contents/Developer",
        volumeID: UUID(), device: 1, inode: 2)
    let set = LocalRootApproval(canonicalPath: setPath, volumeID: UUID(), device: 1, inode: 3)
    let producer = AppleSimulatorProducerIdentity(
        resolver: LocalExecutableApproval(canonicalPath: "/usr/bin/xcrun", device: 1, inode: 4),
        simctl: LocalExecutableApproval(canonicalPath: developer.canonicalPath + "/usr/bin/simctl", device: 1, inode: 5),
        developerDirectory: developer, deviceSet: set, xcodeVersion: "27.0", xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
    let object = ManualSimulatorObject(udid: udid,
        runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
        deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
        name: "Metadata only; never launched", state: .booted, isAvailable: true)
    return try ManualServiceEffectBinding(reviewID: UUID(), coordinatorID: UUID(), policyRevision: 1,
        authorityRevision: 1,
        installation: LocalInstallationIdentity(canonicalDirectoryPath: "/private/tmp/authority",
            volumeDevice: 1, directoryInode: 6, ownerUID: geteuid()),
        operation: ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
            object: .simulator(object), producer: .appleSimulator(producer)))
}

@Suite("Fixed manual simulator launch provenance", .serialized)
struct ManualSimulatorLaunchTests {
    @Test("native invocation metadata selects one exact UDID and one explicit set")
    func exactFixedInvocationMetadata() throws {
        let udid = UUID()
        let binding = try describedSimulatorEffect(udid: udid)
        let runID = UUID(), operationID = UUID()
        let invocation = try ManualSimulatorShutdownInvocation.describe(binding: binding,
            runID: runID, operationID: operationID)
        #expect(invocation.origin == .nativeShutdown)
        #expect(invocation.arguments == ["--set", "/private/tmp/owned-set", "shutdown", udid.uuidString])
        #expect(invocation.executable.canonicalPath == "/Applications/FixtureXcode.app/Contents/Developer/usr/bin/simctl")
        #expect(invocation.environment == ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty",
            "DEVELOPER_DIR": "/Applications/FixtureXcode.app/Contents/Developer"])
        #expect(invocation.runID == runID && invocation.operationID == operationID)
        #expect(invocation.binding == binding)
        let expectedBindingDigest = try binding.operation.canonicalDigest()
        #expect(invocation.operationBindingDigest == expectedBindingDigest)
        #expect(invocation.invocationDigest.count == 32)
        let repeatDescription = try ManualSimulatorShutdownInvocation.describe(binding: binding,
            runID: runID, operationID: operationID)
        #expect(repeatDescription.invocationDigest == invocation.invocationDigest)
        // Description does not admit any provider or issue launch authority.
        #expect(ManualServiceAcceptanceRegistry.denial(for: binding.operation) == .producerAcceptanceMissing)
    }

    @Test("different operation bindings cannot share sealed invocation provenance")
    func changedBindingChangesInvocationDigest() throws {
        let runID = UUID(), operationID = UUID()
        let first = try ManualSimulatorShutdownInvocation.describe(binding: describedSimulatorEffect(),
            runID: runID, operationID: operationID)
        let second = try ManualSimulatorShutdownInvocation.describe(binding: describedSimulatorEffect(setPath: "/private/tmp/another-owned-set"),
            runID: runID, operationID: operationID)
        #expect(first.operationBindingDigest != second.operationBindingDigest)
        #expect(first.invocationDigest != second.invocationDigest)
    }

    @Test("a cooperative fixture owns a real child and carries distinct fixed invocation provenance")
    func ownedCooperativeLaunchMetadata() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/TidyLaunchProvenance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let approved = try LocalRootApproval.verify(directory: root)
        let cat = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/bin/cat"))
        let producer = AppleSimulatorProducerIdentity(resolver: cat, simctl: cat,
            developerDirectory: approved, deviceSet: approved, xcodeVersion: "27.0", xcodeBuild: "27A266a", coreSimulatorVersion: "1171.7")
        let object = ManualSimulatorObject(udid: UUID(), runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
            name: "Owned cat protocol only", state: .booted, isAvailable: true)
        let binding = try ManualServiceEffectBinding(reviewID: UUID(), coordinatorID: UUID(), policyRevision: 1,
            authorityRevision: 1, installation: LocalInstallationIdentity.verify(directory: root),
            operation: ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
                object: .simulator(object), producer: .appleSimulator(producer)))
        let directory = root.appendingPathComponent("journal")
        let admission = try MutationAdmissionStore(directory: directory)
        #expect(admission.acquire() == .ready)
        defer { admission.release() }
        let journal = try RunJournal(store: admission, storage: DurableJournalStorage(directory: directory))
        let runID = UUID(), operationID = UUID()
        try journal.append(.init(runID: runID, sequence: 1, phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(.init(runID: runID, sequence: 2, phase: .confirmed, operationID: nil, status: nil, reason: nil))
        let submission = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID, binding: binding, journal: journal)
        let gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        let launch = try await ProcessRunner.launchManualSimulatorFixtureForTesting(submission: submission,
            gate: gate, deadline: ContinuousClock.now.advanced(by: .seconds(2)))
        #expect(launch.invocation.origin == .cooperativeFixture)
        #expect(launch.invocation.executable == cat)
        #expect(launch.invocation.arguments.isEmpty)
        #expect(launch.invocation.runID == runID && launch.invocation.operationID == operationID)
        #expect(launch.invocation.binding == binding)
        let expectedBindingDigest = try binding.operation.canonicalDigest()
        #expect(launch.invocation.operationBindingDigest == expectedBindingDigest)
        #expect(try admission.unfinishedIntentsWhileLocked().first?.phase == .submitted)
        #expect(launch.session.identity != nil)
        try launch.session.releaseStartByte()
        _ = await launch.session.observeOwnedExit(within: .seconds(2))
        let child = try launch.session.reapedMutationReceipt()
        #expect(child.rawStatus == 0)
        #expect(child.identity.executablePath == cat.canonicalPath)
        let lease = try await launch.session.transferReapedMutationToTerminalVerification(within: .seconds(1))
        try await gate.closeTerminalVerificationForTesting(lease)
        await #expect(throws: Error.self) {
            try await ProcessRunner.launchManualSimulatorFixtureForTesting(submission: submission,
                gate: gate, deadline: ContinuousClock.now.advanced(by: .seconds(1)))
        }
    }
}
