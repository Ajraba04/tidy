import CryptoKit
import Foundation

enum ManualSimulatorClientError: Error {
    case invalidIdentity, authorityDenied, wrongBinding, unsupportedProducer
    case invalidDeadline, expired, terminalUnproven, fixtureOnly
}

/// Complete inventory commands only. There is no raw command, alternate set,
/// search filter, mutation verb, shell or inherited environment input.
struct ManualSimulatorReadRequest: Sendable {
    enum Component: String, CaseIterable, Hashable, Sendable { case devices, runtimes, pairs }
    let producer: AppleSimulatorProducerIdentity
    let component: Component
    let timeout: Duration
    var executable: LocalExecutableApproval { producer.simctl }
    var arguments: [String] {
        ["--set", producer.deviceSet.canonicalPath, "list", component.rawValue, "-j"]
    }
    var environment: [String: String] {
        ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty",
         "DEVELOPER_DIR": producer.developerDirectory.canonicalPath]
    }
    fileprivate init(producer: AppleSimulatorProducerIdentity, component: Component, timeout: Duration) {
        self.producer = producer; self.component = component; self.timeout = timeout
    }
}

/// Production conformance must use a compiled read-only ProcessRunner
/// declaration and the supplied terminal lease when present. Returning bytes
/// through this protocol never creates execution authority or producer proof.
protocol ManualSimulatorReading: Sendable {
    func read(_ request: ManualSimulatorReadRequest,
              terminalLease: ProcessTerminalVerificationLease?) async throws -> Data
}

/// Fixture evidence only: an owned child exit and a complete injected producer
/// postcondition. It does not prove a production shutdown command's arguments.
struct BoundSimulatorServiceReceipt: Sendable {
    let binding: ManualServiceEffectBinding
    let runID: UUID
    let operationID: UUID
    let invocationOrigin: ManualSimulatorShutdownInvocation.Origin
    let invocationDigest: Data
    let childSessionID: UUID
    let childIdentity: ProcessInstanceIdentity
    let rawWaitStatus: Int32
    let observedDevice: ManualSimulatorObject
    let postconditionDigest: Data
    let terminalVerificationLease: ProcessTerminalVerificationLease

    fileprivate init(launch: ManualSimulatorOwnedLaunch, child: ReapedMutationReceipt,
                     device: ManualSimulatorObject, inventory: ManualSimulatorInventory,
                     lease: ProcessTerminalVerificationLease) throws {
        guard launch.invocation.origin == .cooperativeFixture, child.isIsolatedFixture,
              child.rawStatus == 0, lease.sessionID == child.sessionID,
              lease.ownedIdentity == child.identity, lease.rawStatus == child.rawStatus else {
            throw ManualSimulatorClientError.terminalUnproven
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(inventory)
        guard bytes.count <= 3 * BoundedAdapterData.maximumBytes else {
            throw ManualServiceInventoryError.capacity
        }
        binding = launch.invocation.binding
        runID = launch.invocation.runID; operationID = launch.invocation.operationID
        invocationOrigin = launch.invocation.origin; invocationDigest = launch.invocation.invocationDigest
        childSessionID = child.sessionID
        childIdentity = child.identity; rawWaitStatus = child.rawStatus
        observedDevice = device; postconditionDigest = Data(SHA256.hash(data: bytes))
        terminalVerificationLease = lease
    }
}

/// Native evidence is a separate type from injected fixture observations. Only
/// this file's accepted native client can combine fixed launch provenance,
/// consuming-owned reap evidence and complete production postconditions.
struct NativeSimulatorServiceReceipt: Sendable {
    let binding: ManualServiceEffectBinding
    let runID: UUID
    let operationID: UUID
    let invocationOrigin: ManualSimulatorShutdownInvocation.Origin
    let invocationDigest: Data
    let childSessionID: UUID
    let childIdentity: ProcessInstanceIdentity
    let rawWaitStatus: Int32
    let observedDevice: ManualSimulatorObject
    let postconditionDigest: Data
    let terminalVerificationLease: ProcessTerminalVerificationLease

    fileprivate init(launch: ManualSimulatorOwnedLaunch, child: ReapedMutationReceipt,
                     device: ManualSimulatorObject, inventory: ManualSimulatorInventory,
                     lease: ProcessTerminalVerificationLease) throws {
        guard launch.invocation.origin == .nativeShutdown, !child.isIsolatedFixture,
              child.rawStatus == 0, lease.sessionID == child.sessionID,
              lease.ownedIdentity == child.identity, lease.rawStatus == child.rawStatus else {
            throw ManualSimulatorClientError.terminalUnproven
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(inventory)
        guard bytes.count <= 3 * BoundedAdapterData.maximumBytes else {
            throw ManualServiceInventoryError.capacity
        }
        binding = launch.invocation.binding
        runID = launch.invocation.runID; operationID = launch.invocation.operationID
        invocationOrigin = launch.invocation.origin; invocationDigest = launch.invocation.invocationDigest
        childSessionID = child.sessionID
        childIdentity = child.identity; rawWaitStatus = child.rawStatus
        observedDevice = device; postconditionDigest = Data(SHA256.hash(data: bytes))
        terminalVerificationLease = lease
    }
}

final class ManualSimulatorClient: Sendable {
    private struct NativeContext: Sendable {
        let binding: ManualServiceOperationBinding
        let grant: ManualServicePolicyGrant
    }
    private let producer: AppleSimulatorProducerIdentity
    private let reader: (any ManualSimulatorReading)?
    private let authority: LocalAuthoritySnapshot?
    private let fixture: Bool
    private let nativeContext: NativeContext?

    private init(producer: AppleSimulatorProducerIdentity, reader: (any ManualSimulatorReading)?,
                 authority: LocalAuthoritySnapshot?, fixture: Bool, nativeContext: NativeContext? = nil) {
        self.producer = producer; self.reader = reader; self.authority = authority; self.fixture = fixture
        self.nativeContext = nativeContext
    }

    /// The only native client factory accepts an opaque policy grant and a
    /// compiled accepted binding. There is deliberately no injected reader.
    static func acceptedNative(binding: ManualServiceOperationBinding,
                               grant: ManualServicePolicyGrant) throws -> ManualSimulatorClient {
        try AppleSimulatorOperation.requireAcceptedProducer(for: binding)
        try grant.validateScope(for: binding)
        guard case .appleSimulator(let producer) = binding.producer,
              producer.isInspectedCandidateVersion else { throw ManualSimulatorClientError.unsupportedProducer }
        let client = ManualSimulatorClient(producer: producer, reader: nil, authority: grant.authority,
            fixture: false, nativeContext: NativeContext(binding: binding, grant: grant))
        try client.validateAuthority()
        return client
    }

    /// Approved reads only. The parent discovery service captures the current
    /// resolver, actual simctl, developer directory, explicit set and supported
    /// version evidence. Local grants are rechecked at every read boundary.
    static func inventoryOnly(producer: AppleSimulatorProducerIdentity,
                              reader: any ManualSimulatorReading,
                              authority: LocalAuthoritySnapshot) throws -> ManualSimulatorClient {
        try producer.validate()
        guard producer.isInspectedCandidateVersion else { throw ManualSimulatorClientError.unsupportedProducer }
        let client = ManualSimulatorClient(producer: producer, reader: reader, authority: authority, fixture: false)
        try client.validateAuthority()
        return client
    }

    /// Internal injected fixture client; it provides no native process launcher
    /// and cannot create a production receipt. Terminal evidence additionally
    /// requires an actual owned child from an isolated test gate.
    static func forTesting(producer: AppleSimulatorProducerIdentity,
                           reader: any ManualSimulatorReading) throws -> ManualSimulatorClient {
        try producer.validate()
        guard producer.isInspectedCandidateVersion else { throw ManualSimulatorClientError.unsupportedProducer }
        return ManualSimulatorClient(producer: producer, reader: reader, authority: nil, fixture: true)
    }

    func inventory() async throws -> ManualSimulatorInventory {
        try await inventory(terminalLease: nil, deadline: ContinuousClock.now.advanced(by: .seconds(30)))
    }

    func candidates() async throws -> [ManualServiceOperationBinding] {
        let current = try await inventory()
        return current.devices.compactMap { device in
            guard let candidate = try? ManualProducerInventory.shutdownCandidate(id: device.udid,
                inventory: current, producer: producer) else { return nil }
            return try? ManualServiceOperationBinding(adapter: .appleSimulatorShutdownV1,
                object: .simulator(candidate), producer: .appleSimulator(producer))
        }
    }

    func preflight(_ binding: ManualServiceOperationBinding) async throws -> ManualSimulatorObject {
        let reviewed = try validateBinding(binding)
        let current = try await inventory()
        let observed = try ManualProducerInventory.shutdownCandidate(id: reviewed.udid,
            inventory: current, producer: producer)
        guard observed == reviewed else { throw ManualSimulatorClientError.wrongBinding }
        return observed
    }

    /// The accepted native route may observe no work when the exact reviewed
    /// device is already Shutdown. This creates no effect receipt or intent.
    func preflightNative(_ binding: ManualServiceOperationBinding,
                         deadline: ContinuousClock.Instant) async throws -> ManualSimulatorObject {
        guard !fixture, let context = nativeContext, context.binding == binding else {
            throw ManualSimulatorClientError.fixtureOnly
        }
        try AppleSimulatorOperation.requireAcceptedProducer(for: binding)
        try context.grant.validateScope(for: binding)
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero, remaining <= .seconds(30) else { throw ManualSimulatorClientError.invalidDeadline }
        let reviewed = try validateBinding(binding)
        let current = try await inventory(terminalLease: nil, deadline: deadline)
        let observed = try ManualProducerInventory.shutdownCandidate(id: reviewed.udid,
            inventory: current, producer: producer)
        guard observed.udid == reviewed.udid, observed.runtimeIdentifier == reviewed.runtimeIdentifier,
              observed.deviceTypeIdentifier == reviewed.deviceTypeIdentifier,
              observed.name == reviewed.name, observed.isAvailable == reviewed.isAvailable,
              observed.state == .booted || observed.state == .shutdown else { throw ManualSimulatorClientError.wrongBinding }
        try context.grant.validateScope(for: binding)
        return observed
    }

    /// No receipt can be made from a status Boolean, caller-supplied wait code,
    /// PID disappearance or a reconstructed process identity. The session's own
    /// consuming reaper and gate issue the required opaque evidence first. The
    /// launch itself binds the actual separately-declared cooperative command;
    /// a raw session cannot be substituted behind caller-supplied operation IDs.
    func terminalReceiptForTesting(launch: ManualSimulatorOwnedLaunch,
                                   within lifetime: Duration = .seconds(5)) async throws -> BoundSimulatorServiceReceipt {
        guard fixture else { throw ManualSimulatorClientError.fixtureOnly }
        guard lifetime > .zero, lifetime <= .seconds(30) else { throw ManualSimulatorClientError.invalidDeadline }
        let invocation = launch.invocation
        guard invocation.origin == .cooperativeFixture else { throw ManualSimulatorClientError.fixtureOnly }
        try invocation.binding.validate()
        let reviewed = try validateBinding(invocation.binding.operation)
        guard invocation.executable == producer.simctl,
              invocation.operationBindingDigest == (try invocation.binding.operation.canonicalDigest()),
              invocation.invocationDigest.count == SHA256.Digest.byteCount else {
            throw ManualSimulatorClientError.wrongBinding
        }
        let session = launch.session
        let deadline = ContinuousClock.now.advanced(by: lifetime)
        _ = await session.observeOwnedExit(within: lifetime)
        let child = try session.reapedMutationReceipt()
        guard child.isIsolatedFixture else { throw ManualSimulatorClientError.fixtureOnly }
        guard child.rawStatus == 0,
              child.identity.executablePath == invocation.executable.canonicalPath,
              child.identity.executableDevice == invocation.executable.device,
              child.identity.executableInode == invocation.executable.inode else {
            throw ManualSimulatorClientError.terminalUnproven
        }
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero else { throw ManualSimulatorClientError.expired }
        let lease = try await session.transferReapedMutationToTerminalVerification(within: remaining)
        let current = try await inventory(terminalLease: lease, deadline: deadline)
        let observed = try ManualProducerInventory.shutdownCandidate(id: reviewed.udid,
            inventory: current, producer: producer)
        guard observed.udid == reviewed.udid, observed.runtimeIdentifier == reviewed.runtimeIdentifier,
              observed.deviceTypeIdentifier == reviewed.deviceTypeIdentifier,
              observed.name == reviewed.name, observed.isAvailable,
              observed.state == .shutdown else { throw ManualSimulatorClientError.terminalUnproven }
        try lease.checkValidity()
        return try BoundSimulatorServiceReceipt(launch: launch, child: child, device: observed,
            inventory: current, lease: lease)
    }

    /// An already launched mutation keeps bounded terminal collection even if
    /// its initiating task is cancelled. The detached worker retains the owned
    /// session and lease; failure never clears the outstanding obligation.
    func terminalReceipt(launch: ManualSimulatorOwnedLaunch,
                         within lifetime: Duration = .seconds(30)) async throws -> NativeSimulatorServiceReceipt {
        guard !fixture, let context = nativeContext,
              launch.invocation.origin == .nativeShutdown else { throw ManualSimulatorClientError.fixtureOnly }
        try AppleSimulatorOperation.requireAcceptedProducer(for: context.binding)
        guard lifetime > .zero, lifetime <= .seconds(30) else { throw ManualSimulatorClientError.invalidDeadline }
        let invocation = launch.invocation
        guard invocation.binding.operation == context.binding else { throw ManualSimulatorClientError.wrongBinding }
        try AppleSimulatorOperation.validateGrant(context.grant, binding: invocation.binding)
        let expected = try ManualSimulatorShutdownInvocation.describe(binding: invocation.binding,
            runID: invocation.runID, operationID: invocation.operationID)
        guard invocation.executable == expected.executable, invocation.arguments == expected.arguments,
              invocation.environment == expected.environment,
              invocation.operationBindingDigest == expected.operationBindingDigest,
              invocation.invocationDigest == expected.invocationDigest else {
            throw ManualSimulatorClientError.wrongBinding
        }
        let deadline = ContinuousClock.now.advanced(by: lifetime)
        return try await Task.detached {
            try await self.collectNativeReceipt(launch: launch, deadline: deadline)
        }.value
    }

    private func collectNativeReceipt(launch: ManualSimulatorOwnedLaunch,
                                      deadline: ContinuousClock.Instant) async throws -> NativeSimulatorServiceReceipt {
        let reviewed = try validateBinding(launch.invocation.binding.operation)
        let remainingForExit = ContinuousClock.now.duration(to: deadline)
        guard remainingForExit > .zero else { throw ManualSimulatorClientError.expired }
        _ = await launch.session.observeOwnedExit(within: remainingForExit)
        let child = try launch.session.reapedMutationReceipt()
        let executable = launch.invocation.executable
        guard !child.isIsolatedFixture, child.rawStatus == 0,
              child.identity.executablePath == executable.canonicalPath,
              child.identity.executableDevice == executable.device,
              child.identity.executableInode == executable.inode else {
            throw ManualSimulatorClientError.terminalUnproven
        }
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero else { throw ManualSimulatorClientError.expired }
        let lease = try await launch.session.transferReapedMutationToTerminalVerification(within: remaining)
        let current = try await inventory(terminalLease: lease, deadline: deadline)
        let observed = try ManualProducerInventory.shutdownCandidate(id: reviewed.udid,
            inventory: current, producer: producer)
        guard observed.udid == reviewed.udid, observed.runtimeIdentifier == reviewed.runtimeIdentifier,
              observed.deviceTypeIdentifier == reviewed.deviceTypeIdentifier,
              observed.name == reviewed.name, observed.isAvailable, observed.state == .shutdown else {
            throw ManualSimulatorClientError.terminalUnproven
        }
        guard let context = nativeContext else { throw ManualSimulatorClientError.fixtureOnly }
        try AppleSimulatorOperation.requireAcceptedProducer(for: context.binding)
        try AppleSimulatorOperation.validateGrant(context.grant, binding: launch.invocation.binding)
        try lease.checkValidity()
        guard ContinuousClock.now < deadline else { throw ManualSimulatorClientError.expired }
        return try NativeSimulatorServiceReceipt(launch: launch, child: child, device: observed,
            inventory: current, lease: lease)
    }

    private func inventory(terminalLease: ProcessTerminalVerificationLease?,
                           deadline: ContinuousClock.Instant) async throws -> ManualSimulatorInventory {
        let inventoryReader: any ManualSimulatorReading
        if let context = nativeContext {
            try await validateNativeProducer(context, terminalLease: terminalLease, deadline: deadline)
            inventoryReader = ManualSimulatorNativeReader(authority: context.grant.authority, deadline: deadline)
        } else if let reader {
            inventoryReader = reader
        } else {
            throw ManualSimulatorClientError.authorityDenied
        }
        var replies: [ManualSimulatorReadRequest.Component: Data] = [:]
        for component in ManualSimulatorReadRequest.Component.allCases {
            if terminalLease == nil { try Task.checkCancellation() }
            try terminalLease?.checkValidity()
            try await validateCurrentIdentity()
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { throw ManualSimulatorClientError.expired }
            let request = ManualSimulatorReadRequest(producer: producer, component: component,
                timeout: min(remaining, .seconds(10)))
            let bytes = try await inventoryReader.read(request, terminalLease: terminalLease)
            guard bytes.count <= BoundedAdapterData.maximumBytes else { throw ManualServiceInventoryError.capacity }
            if terminalLease == nil { try Task.checkCancellation() }
            try terminalLease?.checkValidity()
            try await validateCurrentIdentity()
            guard ContinuousClock.now < deadline else { throw ManualSimulatorClientError.expired }
            replies[component] = bytes
        }
        guard let devices = replies[.devices], let runtimes = replies[.runtimes], let pairs = replies[.pairs] else {
            throw ManualServiceInventoryError.malformed
        }
        if let context = nativeContext {
            try await validateNativeProducer(context, terminalLease: terminalLease, deadline: deadline)
        }
        return try ManualProducerInventory.parseSimulator(devices: devices, runtimes: runtimes,
            pairs: pairs, deviceSet: producer.deviceSet)
    }

    private func validateNativeProducer(_ context: NativeContext,
                                        terminalLease: ProcessTerminalVerificationLease?,
                                        deadline: ContinuousClock.Instant) async throws {
        try AppleSimulatorOperation.requireAcceptedProducer(for: context.binding)
        try terminalLease?.checkValidity()
        let producer = self.producer
        let bootstrap = ManualSimulatorReadBootstrap(resolver: producer.resolver, simctl: producer.simctl,
            developerDirectory: producer.developerDirectory, deviceSet: producer.deviceSet,
            authority: context.grant.authority)
        try await Task.detached {
            try context.grant.validateScope(for: context.binding)
            try bootstrap.checkCurrent(deadline: deadline)
            let metadata = try ManualSimulatorDiscovery.readVersionMetadata(
                developerDirectory: producer.developerDirectory, deadline: deadline)
            guard metadata.version == producer.xcodeVersion, metadata.build == producer.xcodeBuild else {
                throw ManualSimulatorClientError.unsupportedProducer
            }
            try AppleSimulatorOperation.requireAppleSignature(producer.resolver)
            try AppleSimulatorOperation.requireAppleSignature(producer.simctl)
        }.value
        try terminalLease?.checkValidity()
        let resolved = try await ProcessRunner.runManualSimulatorResolver(resolver: producer.resolver,
            deviceSet: producer.deviceSet, authority: context.grant.authority, deadline: deadline,
            terminalLease: terminalLease)
        guard try ManualSimulatorDiscovery.parseResolvedSimctl(resolved).path == producer.simctl.canonicalPath else {
            throw ManualSimulatorClientError.invalidIdentity
        }
        let version = try await ProcessRunner.runManualSimctlVersion(bootstrap, deadline: deadline,
            terminalLease: terminalLease)
        guard try ManualSimulatorDiscovery.parseCoreSimulatorVersion(version) == producer.coreSimulatorVersion else {
            throw ManualSimulatorClientError.unsupportedProducer
        }
        try await validateCurrentIdentity()
        try terminalLease?.checkValidity()
        guard ContinuousClock.now < deadline else { throw ManualSimulatorClientError.expired }
    }

    private func validateBinding(_ binding: ManualServiceOperationBinding) throws -> ManualSimulatorObject {
        try binding.validate()
        if let context = nativeContext, binding != context.binding { throw ManualSimulatorClientError.wrongBinding }
        guard binding.adapter == .appleSimulatorShutdownV1,
              binding.producer == .appleSimulator(producer),
              case .simulator(let object) = binding.object else { throw ManualSimulatorClientError.wrongBinding }
        return object
    }

    private func validateAuthority() throws {
        if fixture { return }
        if let context = nativeContext {
            try AppleSimulatorOperation.requireAcceptedProducer(for: context.binding)
            try context.grant.checkCurrent()
        }
        guard let authority, authority.isCurrent,
              authority.permits(.localExecutable(producer.resolver)),
              authority.permits(.localExecutable(producer.simctl)),
              authority.permits(.localRoot(producer.developerDirectory)),
              authority.permits(.localRoot(producer.deviceSet)) else { throw ManualSimulatorClientError.authorityDenied }
    }

    private func validateCurrentIdentity() async throws {
        try validateAuthority()
        let producer = self.producer
        try await Task.detached {
            guard try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: producer.resolver.canonicalPath)) == producer.resolver,
                  try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: producer.simctl.canonicalPath)) == producer.simctl,
                  try LocalRootApproval.verify(directory: URL(fileURLWithPath: producer.developerDirectory.canonicalPath)) == producer.developerDirectory,
                  try LocalRootApproval.verify(directory: URL(fileURLWithPath: producer.deviceSet.canonicalPath)) == producer.deviceSet else {
                throw ManualSimulatorClientError.invalidIdentity
            }
        }.value
        try validateAuthority()
    }
}
