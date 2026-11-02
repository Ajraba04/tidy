import Foundation
import CryptoKit
import Darwin

/// A real session combined with the immutable declaration used to launch it.
/// Metadata alone cannot construct this value or stand in for an owned reap.
struct ManualSimulatorOwnedLaunch: Sendable {
    let session: ProcessSession
    let invocation: ManualSimulatorShutdownInvocation
    let submissionHookAttempts: Int
    private let issuingSubmission: ManualServiceSubmission
    fileprivate init(session: ProcessSession, invocation: ManualSimulatorShutdownInvocation,
                     issuingSubmission: ManualServiceSubmission, submissionHookAttempts: Int = 0) {
        self.session = session; self.invocation = invocation
        self.submissionHookAttempts = submissionHookAttempts
        self.issuingSubmission = issuingSubmission
    }
    func requireIssuingSubmission(_ submission: ManualServiceSubmission) throws {
        guard issuingSubmission === submission else { throw JournalError.invalidTransition }
    }
}

/// Only Runner's fixed native/fixture declarations can construct the hook or
/// its immutable context. No callback is exposed on public test requests.
final class ManualSimulatorSubmissionHook: @unchecked Sendable {
    enum Origin: String, Codable, Sendable { case nativeShutdown, cooperativeFixture, rejectedSpawnFixture }
    let invocation: ManualSimulatorShutdownInvocation
    let attemptedExecutablePath: String
    let origin: Origin
    let deadline: ContinuousClock.Instant
    private let submission: ManualServiceSubmission
    private let effectCancellation: EffectCancellationToken?
    private let lock = NSLock()
    private var attemptCount = 0
    var attempts: Int { lock.withLock { attemptCount } }
    var isFixture: Bool { origin != .nativeShutdown }
    var admissionCancellation: EffectCancellationToken? { effectCancellation }

    fileprivate init(submission: ManualServiceSubmission, invocation: ManualSimulatorShutdownInvocation,
                     attemptedExecutablePath: String, origin: Origin, deadline: ContinuousClock.Instant,
                     effectCancellation: EffectCancellationToken? = nil) {
        self.submission = submission; self.invocation = invocation
        self.attemptedExecutablePath = attemptedExecutablePath; self.origin = origin; self.deadline = deadline
        self.effectCancellation = effectCancellation
    }

    func matches(executable: URL, arguments: [String], environment: [String: String]) -> Bool {
        executable.path == attemptedExecutablePath && arguments == invocation.arguments
            && environment == invocation.environment
    }

    func commit() throws -> ManualSimulatorSubmissionCommit {
        lock.lock(); defer { lock.unlock() }
        try Task.checkCancellation()
        guard effectCancellation?.isCancelled != true else { throw CancellationError() }
        guard attemptCount == 0 else { throw JournalError.invalidTransition }
        attemptCount = 1
        let permit = try submission.beginSubmission()
        guard permit.binding == invocation.binding, permit.runID == invocation.runID,
              permit.operationID == invocation.operationID else { throw JournalError.invalidTransition }
        return try ManualSimulatorSubmissionCommit(permit: permit, invocation: invocation,
            origin: origin, attemptedExecutablePath: attemptedExecutablePath, attempts: attemptCount)
    }
}

/// Internal fixed-cat fixture synchronization, never a supplied validator or
/// production callback. The final validator has a bounded two-second hold.
final class ManualSimulatorFinalValidationPause: @unchecked Sendable {
    private let condition = NSCondition()
    private var count = 0
    private var held = false
    private var released = false
    private var hook: ManualSimulatorSubmissionHook?

    fileprivate func observe(_ hook: ManualSimulatorSubmissionHook) {
        condition.lock(); self.hook = hook; condition.unlock()
    }
    fileprivate func reachFixedFixtureValidator() throws {
        condition.lock(); defer { condition.unlock() }
        count += 1
        guard count == 3 else { return }
        held = true; condition.broadcast()
        let deadline = Date().addingTimeInterval(2)
        while !released {
            guard condition.wait(until: deadline) else {
                released = true; condition.broadcast()
                throw POSIXError(.ETIMEDOUT)
            }
        }
    }
    func waitUntilHeld() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if isHeld { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        resume()
        throw POSIXError(.ETIMEDOUT)
    }
    private var isHeld: Bool { condition.lock(); defer { condition.unlock() }; return held }
    func resume() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
    var validationCount: Int { condition.lock(); defer { condition.unlock() }; return count }
    var submissionHookAttempts: Int {
        condition.lock(); let observed = hook; condition.unlock()
        return observed?.attempts ?? 0
    }
}

struct ManualSimulatorSubmissionCommit: Sendable {
    let permit: ManualServiceDispatchPermit
    let invocationDigest: Data
    let origin: ManualSimulatorSubmissionHook.Origin
    let attemptedExecutablePath: String
    let attempts: Int
    private struct Encoding: Encodable {
        let schema: Int
        let declarationDigest: Data
        let origin: ManualSimulatorSubmissionHook.Origin
        let attemptedExecutablePath: String
    }
    fileprivate init(permit: ManualServiceDispatchPermit, invocation: ManualSimulatorShutdownInvocation,
                     origin: ManualSimulatorSubmissionHook.Origin, attemptedExecutablePath: String, attempts: Int) throws {
        self.permit = permit; self.origin = origin; self.attemptedExecutablePath = attemptedExecutablePath
        self.attempts = attempts
        invocationDigest = try Self.digest(declarationDigest: invocation.invocationDigest,
            origin: origin, attemptedExecutablePath: attemptedExecutablePath)
    }
    /// Pure archival reconstruction. This digest conveys no launch authority.
    static func digest(declarationDigest: Data, origin: ManualSimulatorSubmissionHook.Origin,
                       attemptedExecutablePath: String) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(Encoding(schema: 1, declarationDigest: declarationDigest,
            origin: origin, attemptedExecutablePath: attemptedExecutablePath))
        return Data(SHA256.hash(data: bytes))
    }
}

public enum ProcessRunnerError: Error, Equatable, Sendable {
    case undeclaredInvocation
    case nestedLaunch
    case needExceedsCompiledDescriptor
}

/// Read-only command transport. No shell, inherited PATH lookup, mutation
/// selector, descendant claim, or accepted-effect authority is exposed here.
public enum ProcessRunner: Sendable {
    public struct Output: Sendable {
        public let exitCode: Int32
        public let standardOutput: String
        public let standardError: String
        public let timedOut: Bool
        public let outputComplete: Bool

        public var succeeded: Bool { exitCode == 0 && !timedOut && outputComplete }
    }

    /// Reviewed built-in caller identity and command shape are compiled
    /// together. Callers never provide a descendant count or process cap.
    private enum BuiltInCallerID: String, Sendable {
        case toolLocatorXcrunFind
        case simctlDevices
        case simctlRuntimes
        case localSnapshots
        case containerSpace
        case processSurvey
        case compatibilityEcho
        case compatibilityFalse
        case compatibilityTrue
        case compatibilityCat
        case compatibilitySleep
    }

    enum AuthorizedJobKind: Sendable { case readOnly, mutation }

    fileprivate struct DeclaredInvocation: Sendable {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
        let kind: AuthorizedJobKind
        let validateImmediatelyBeforeSpawn: @Sendable () throws -> Void
        let manualSubmissionHook: ManualSimulatorSubmissionHook?
        /// Every current T08.3 declaration is a direct-child-only shape.
        let maximumDescendants: Int

        init(executableURL: URL, arguments: [String],
             environment: [String: String] = ProcessRunner.minimalEnvironment,
             kind: AuthorizedJobKind, maximumDescendants: Int,
             validateImmediatelyBeforeSpawn: @escaping @Sendable () throws -> Void = {},
             manualSubmissionHook: ManualSimulatorSubmissionHook? = nil) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
            self.kind = kind
            self.maximumDescendants = maximumDescendants
            self.validateImmediatelyBeforeSpawn = validateImmediatelyBeforeSpawn
            self.manualSubmissionHook = manualSubmissionHook
        }
    }

    /// Opaque launch authority. Its initializer is file-private so no other
    /// TidyCore production source can manufacture a request, select mutation,
    /// or route a launch around the compiled descriptor table.
    struct AuthorizedLaunch: Sendable {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
        let kind: AuthorizedJobKind
        let deadline: Duration
        let validateImmediatelyBeforeSpawn: @Sendable () throws -> Void
        let manualSubmissionHook: ManualSimulatorSubmissionHook?

        fileprivate init(_ declaration: DeclaredInvocation, timeout: TimeInterval) {
            executableURL = declaration.executableURL
            arguments = declaration.arguments
            environment = declaration.environment
            kind = declaration.kind
            deadline = .seconds(timeout)
            validateImmediatelyBeforeSpawn = declaration.validateImmediatelyBeforeSpawn
            manualSubmissionHook = declaration.manualSubmissionHook
        }
    }

    @TaskLocal private static var launchDepth = 0

    public static let minimalEnvironment: [String: String] = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": NSHomeDirectory()
    ]
    public static let defaultTimeout: TimeInterval = 60

    nonisolated static var productionGateIdentity: ObjectIdentifier {
        ObjectIdentifier(ProcessJobGate.shared)
    }
    nonisolated static var productionPhysicalLimit: Int { ProcessJobGate.shared.physicalLimit }

    /// The scheduler supplies only its resolved, revisioned observation. The
    /// process gate remains the policy owner and the sole permit owner.
    static func applySchedulerObservation(settingsRevision: UInt64?, observationEpoch: UInt64,
                                          resolvedReadOnlyCap: Int) async
      -> ProcessPolicyUpdateResult {
        guard let settings = settingsRevision else { return .rejectedInvalid }
        return await ProcessJobGate.shared.applyReadOnlyCap(resolvedReadOnlyCap,
            revision: ProcessPolicyRevision(settings: settings, observation: observationEpoch))
    }

    /// Compatibility surface accepts only a small compiled set of harmless
    /// direct-child command shapes. Unknown commands reject before gate, pipe,
    /// PID, or session activity.
    @discardableResult
    public static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = ProcessRunner.defaultTimeout
    ) async throws -> Output {
        guard environment == nil || environment == minimalEnvironment,
              let declaration = classify(executableURL: executableURL, arguments: arguments)
        else { throw ProcessRunnerError.undeclaredInvocation }
        return try await run(declaration, timeout: timeout)
    }

    @discardableResult
    public static func runDiscardingOutput(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = ProcessRunner.defaultTimeout
    ) async -> Bool {
        (try? await run(executableURL: executableURL, arguments: arguments,
                       environment: environment, timeout: timeout).succeeded) ?? false
    }

    static func runXcrunFind(_ name: String) async throws -> Output {
        try await run(try declared(.toolLocatorXcrunFind,
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--find", name]))
    }

    static func runSimctlDevices(xcrunURL: URL) async throws -> Output {
        try await run(try declared(.simctlDevices, executableURL: xcrunURL,
            arguments: ["simctl", "list", "devices", "-j"]))
    }

    static func runApprovedSimctlDevices(approval: AppleReadApproval) async throws -> Output {
        guard approval.isCurrent else { throw ProcessRunnerError.undeclaredInvocation }
        let url = URL(fileURLWithPath: approval.executable.canonicalPath)
        let declaration = try declared(.simctlDevices, executableURL: url,
            arguments: ["simctl", "list", "devices", "-j"],
            validateImmediatelyBeforeSpawn: {
                guard approval.isCurrent else { throw ProcessRunnerError.undeclaredInvocation }
            })
        return try await run(declaration)
    }

    static func runSimctlRuntimes(xcrunURL: URL) async throws -> Output {
        try await run(try declared(.simctlRuntimes, executableURL: xcrunURL,
            arguments: ["simctl", "list", "runtimes", "-j"]))
    }

    /// Groundwork only: the compiled registry currently rejects this route
    /// before discovery, gate admission or a durable intent transition.
    static func launchManualSimulatorShutdown(submission: ManualServiceSubmission,
                                             grant: ManualServicePolicyGrant,
                                             deadline: ContinuousClock.Instant,
                                             cancellation: EffectCancellationToken) async throws -> ManualSimulatorNativeLaunchOutcome {
        let binding = submission.effectBinding
        try AppleSimulatorOperation.requireAcceptedProducer(for: binding.operation)
        try AppleSimulatorOperation.validateGrant(grant, binding: binding)
        let invocation = try ManualSimulatorShutdownInvocation.describe(binding: binding,
            runID: submission.runID, operationID: submission.operationID)
        guard case .appleSimulator(let producer) = binding.operation.producer else {
            throw ManualServiceReviewError.bindingMismatch
        }
        let bootstrap = ManualSimulatorReadBootstrap(resolver: producer.resolver, simctl: producer.simctl,
            developerDirectory: producer.developerDirectory, deviceSet: producer.deviceSet, authority: grant.authority)
        let resolved = try await runManualSimulatorResolver(resolver: producer.resolver,
            deviceSet: producer.deviceSet, authority: grant.authority, deadline: deadline)
        guard try ManualSimulatorDiscovery.parseResolvedSimctl(resolved).path == producer.simctl.canonicalPath else {
            throw ManualServiceInventoryError.identityMismatch
        }
        let version = try await runManualSimctlVersion(bootstrap, deadline: deadline)
        guard try ManualSimulatorDiscovery.parseCoreSimulatorVersion(version) == producer.coreSimulatorVersion else {
            throw ManualServiceInventoryError.unsupportedProducer
        }
        let validate: @Sendable () throws -> Void = {
            try AppleSimulatorOperation.requireAcceptedProducer(for: binding.operation)
            try AppleSimulatorOperation.validateGrant(grant, binding: binding)
            try bootstrap.checkCurrent(deadline: deadline)
            let metadata = try ManualSimulatorDiscovery.readVersionMetadata(
                developerDirectory: producer.developerDirectory, deadline: deadline)
            guard metadata.version == producer.xcodeVersion, metadata.build == producer.xcodeBuild else {
                throw ManualServiceInventoryError.unsupportedProducer
            }
            try AppleSimulatorOperation.requireAppleSignature(producer.resolver)
            try AppleSimulatorOperation.requireAppleSignature(producer.simctl)
            try grant.checkCurrent()
        }
        let hook = ManualSimulatorSubmissionHook(submission: submission, invocation: invocation,
            attemptedExecutablePath: invocation.executable.canonicalPath, origin: .nativeShutdown,
            deadline: deadline, effectCancellation: cancellation)
        return try await launchManualSimulatorHook(invocation: invocation, submission: submission,
            hook: hook, gate: nil, validate: validate)
    }

    static func launchManualSimulatorHookFixtureForTesting(submission: ManualServiceSubmission,
                                                           gate: ProcessJobGate,
                                                           deadline: ContinuousClock.Instant,
                                                           finalValidationPause: ManualSimulatorFinalValidationPause? = nil,
                                                           effectCancellation: EffectCancellationToken? = nil) async throws -> ManualSimulatorNativeLaunchOutcome {
        try await launchManualSimulatorHookFixture(submission: submission, gate: gate,
            deadline: deadline, rejectedSpawn: false, finalValidationPause: finalValidationPause,
            effectCancellation: effectCancellation)
    }

    static func rejectManualSimulatorSpawnFixtureForTesting(submission: ManualServiceSubmission,
                                                           gate: ProcessJobGate,
                                                           deadline: ContinuousClock.Instant) async throws -> ManualSimulatorNativeLaunchOutcome {
        try await launchManualSimulatorHookFixture(submission: submission, gate: gate,
            deadline: deadline, rejectedSpawn: true)
    }

    /// The queue fixture can use only an isolated gate whose two read slots
    /// remain held. It shares the actual hook admission path and fixed cat shape.
    static func launchQueuedManualSimulatorHookFixtureForTesting(submission: ManualServiceSubmission,
                                                                gate: ProcessJobGate,
                                                                deadline: ContinuousClock.Instant,
                                                                effectCancellation: EffectCancellationToken) async throws -> ManualSimulatorNativeLaunchOutcome {
        try await launchManualSimulatorHookFixture(submission: submission, gate: gate,
            deadline: deadline, rejectedSpawn: false, effectCancellation: effectCancellation,
            occupiedQueueFixture: true)
    }

    private static func launchManualSimulatorHookFixture(submission: ManualServiceSubmission,
                                                         gate: ProcessJobGate,
                                                         deadline: ContinuousClock.Instant,
                                                         rejectedSpawn: Bool,
                                                         finalValidationPause: ManualSimulatorFinalValidationPause? = nil,
                                                         effectCancellation: EffectCancellationToken? = nil,
                                                         occupiedQueueFixture: Bool = false) async throws -> ManualSimulatorNativeLaunchOutcome {
        guard gate.isTestIsolation else { throw ManualServiceReviewError.providerUnavailable }
        try Task.checkCancellation()
        let state = await gate.snapshot()
        let expectedSlots = occupiedQueueFixture ? 2 : 0
        guard state.active == expectedSlots, state.activeReaders == expectedSlots,
              state.queued == 0, state.unresolvedMutations == 0 else {
            throw ManualServiceReviewError.busy
        }
        let cat = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/bin/cat"))
        let binding = submission.effectBinding
        let invocation = try ManualSimulatorShutdownInvocation.cooperativeFixture(binding: binding,
            runID: submission.runID, operationID: submission.operationID, executable: cat)
        let attemptedPath = rejectedSpawn
            ? binding.installation.canonicalDirectoryPath + "/.tidy-fixed-absent-executable"
            : cat.canonicalPath
        let validate: @Sendable () throws -> Void = {
            guard try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/bin/cat")) == cat,
                  try LocalInstallationIdentity.verify(directory: URL(fileURLWithPath:
                    binding.installation.canonicalDirectoryPath)) == binding.installation else {
                throw ManualServiceInventoryError.identityMismatch
            }
            if rejectedSpawn {
                var value = stat()
                guard lstat(attemptedPath, &value) == -1, errno == ENOENT else {
                    throw ManualServiceInventoryError.invalidIdentity
                }
            }
            guard ContinuousClock.now < deadline else { throw ManualSimulatorClientError.expired }
            try finalValidationPause?.reachFixedFixtureValidator()
        }
        let hook = ManualSimulatorSubmissionHook(submission: submission, invocation: invocation,
            attemptedExecutablePath: attemptedPath,
            origin: rejectedSpawn ? .rejectedSpawnFixture : .cooperativeFixture,
            deadline: deadline, effectCancellation: effectCancellation)
        finalValidationPause?.observe(hook)
        return try await launchManualSimulatorHook(invocation: invocation, submission: submission,
            hook: hook, gate: gate, validate: validate)
    }

    private static func launchManualSimulatorHook(invocation: ManualSimulatorShutdownInvocation,
                                                  submission: ManualServiceSubmission,
                                                  hook: ManualSimulatorSubmissionHook,
                                                  gate: ProcessJobGate?,
                                                  validate: @escaping @Sendable () throws -> Void) async throws -> ManualSimulatorNativeLaunchOutcome {
        guard launchDepth == 0 else { throw ProcessRunnerError.nestedLaunch }
        let remaining = ContinuousClock.now.duration(to: hook.deadline)
        guard remaining > .zero, remaining <= .seconds(30) else { throw ManualSimulatorClientError.invalidDeadline }
        try Task.checkCancellation()
        try validate()
        let components = remaining.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        let declaration = DeclaredInvocation(executableURL: URL(fileURLWithPath: hook.attemptedExecutablePath),
            arguments: invocation.arguments, environment: invocation.environment, kind: .mutation,
            maximumDescendants: 0, validateImmediatelyBeforeSpawn: validate, manualSubmissionHook: hook)
        let authorization = AuthorizedLaunch(declaration, timeout: seconds)
        return try await $launchDepth.withValue(launchDepth + 1) {
            do {
                let session: ProcessSession
                if let gate {
                    session = try await ProcessSession.launchManualSimulatorFixture(authorization, gate: gate)
                } else {
                    session = try await ProcessSession.launch(authorization)
                }
                // No fallible metadata work occurs after successful spawn.
                return .launched(ManualSimulatorOwnedLaunch(session: session, invocation: invocation,
                    issuingSubmission: submission, submissionHookAttempts: hook.attempts))
            } catch let failure as ManualSimulatorRejectedSpawn {
                return .notSpawned(failure.receipt)
            }
        }
    }

    /// Separate owned-child fixture declaration. No argument, executable or
    /// environment overrides exist, and the production gate is unreachable.
    /// This does not activate a native simctl declaration or accepted producer.
    static func launchManualSimulatorFixtureForTesting(submission: ManualServiceSubmission,
                                                       gate: ProcessJobGate,
                                                       deadline: ContinuousClock.Instant) async throws -> ManualSimulatorOwnedLaunch {
        guard gate.isTestIsolation else { throw ManualServiceReviewError.providerUnavailable }
        guard launchDepth == 0 else { throw ProcessRunnerError.nestedLaunch }
        try Task.checkCancellation()
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero, remaining <= .seconds(30) else { throw ManualSimulatorClientError.invalidDeadline }
        let state = await gate.snapshot()
        guard state.active == 0, state.queued == 0, state.unresolvedMutations == 0 else {
            throw ManualServiceReviewError.busy
        }
        let catURL = URL(fileURLWithPath: "/bin/cat")
        let executable = try LocalExecutableApproval.verify(executable: catURL)
        let binding = submission.effectBinding
        let (_, producer) = try ManualSimulatorShutdownInvocation.simulatorBinding(binding)
        guard executable.canonicalPath == "/bin/cat", producer.simctl == executable else {
            throw ManualServiceInventoryError.identityMismatch
        }
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw ManualSimulatorClientError.expired }
        // Conservative durable boundary before even this harmless fixture can
        // spawn. Do not place this single-use transition in the validator that
        // ProcessSession may call more than once. Every later failure remains
        // possibly submitted; an Error cannot manufacture a no-effect proof.
        let permit = try submission.beginSubmission()
        let invocation = try ManualSimulatorShutdownInvocation.cooperativeFixture(binding: permit.binding,
            runID: permit.runID, operationID: permit.operationID, executable: executable)
        guard try LocalExecutableApproval.verify(executable: catURL) == executable else {
            throw ManualServiceInventoryError.identityMismatch
        }
        let childDuration = ContinuousClock.now.duration(to: deadline)
        guard childDuration > .zero else { throw ManualSimulatorClientError.expired }
        return try await $launchDepth.withValue(launchDepth + 1) {
            let request = ProcessTestRequest(executable: catURL, arguments: [],
                environment: invocation.environment, kind: .mutation, deadline: childDuration)
            let session = try await ProcessSession.launchForTesting(request, gate: gate)
            // Once a child exists, always return its retained owner, even when
            // identity capture failed or cancellation raced with the spawn.
            return ManualSimulatorOwnedLaunch(session: session, invocation: invocation, issuingSubmission: submission)
        }
    }

    /// Fixed approved resolver query. An inherited developer directory, PATH,
    /// or writable HOME can never select a different producer for this route.
    static func runManualSimulatorResolver(resolver: LocalExecutableApproval,
                                          deviceSet: LocalRootApproval,
                                          authority: LocalAuthoritySnapshot,
                                          deadline: ContinuousClock.Instant,
                                          terminalLease: ProcessTerminalVerificationLease? = nil) async throws -> Data {
        let validate: @Sendable () throws -> Void = {
            try terminalLease?.checkValidity()
            try ManualSimulatorDiscovery.requireInitialAuthority(resolver: resolver,
                deviceSet: deviceSet, authority: authority)
            try ManualSimulatorDiscovery.requireExistingDeviceSet(deviceSet, deadline: deadline)
        }
        try validate()
        let declaration = DeclaredInvocation(executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["--find", "simctl"], environment: manualSimulatorEnvironment,
            kind: .readOnly, maximumDescendants: 0, validateImmediatelyBeforeSpawn: validate)
        let data = try await runManualSimulatorDeclaration(declaration, deadline: deadline, terminalLease: terminalLease)
        try validate()
        return data
    }

    static func runManualSimctlVersion(_ bootstrap: ManualSimulatorReadBootstrap,
                                      deadline: ContinuousClock.Instant,
                                      terminalLease: ProcessTerminalVerificationLease? = nil) async throws -> Data {
        let validate: @Sendable () throws -> Void = {
            try terminalLease?.checkValidity()
            try bootstrap.checkCurrent(deadline: deadline)
        }
        try validate()
        var environment = manualSimulatorEnvironment
        environment["DEVELOPER_DIR"] = bootstrap.developerDirectory.canonicalPath
        let declaration = DeclaredInvocation(executableURL: URL(fileURLWithPath: bootstrap.simctl.canonicalPath),
            arguments: ["--version"], environment: environment, kind: .readOnly,
            maximumDescendants: 0, validateImmediatelyBeforeSpawn: validate)
        let data = try await runManualSimulatorDeclaration(declaration, deadline: deadline, terminalLease: terminalLease)
        try validate()
        return data
    }

    static func runManualSimulatorInventory(_ request: ManualSimulatorReadRequest,
                                           authority: LocalAuthoritySnapshot,
                                           deadline: ContinuousClock.Instant,
                                           terminalLease: ProcessTerminalVerificationLease?) async throws -> Data {
        let producer = request.producer
        guard producer.isInspectedCandidateVersion else { throw ProcessRunnerError.undeclaredInvocation }
        let bootstrap = ManualSimulatorReadBootstrap(resolver: producer.resolver, simctl: producer.simctl,
            developerDirectory: producer.developerDirectory, deviceSet: producer.deviceSet, authority: authority)
        let validate: @Sendable () throws -> Void = {
            try terminalLease?.checkValidity()
            try bootstrap.checkCurrent(deadline: deadline)
        }
        try validate()
        var environment = manualSimulatorEnvironment
        environment["DEVELOPER_DIR"] = producer.developerDirectory.canonicalPath
        // Reconstruct the compiled shape rather than accepting caller argv or
        // environment, even though the request's initializer is already private.
        let arguments = ["--set", producer.deviceSet.canonicalPath, "list", request.component.rawValue, "-j"]
        let declaration = DeclaredInvocation(executableURL: URL(fileURLWithPath: producer.simctl.canonicalPath),
            arguments: arguments, environment: environment, kind: .readOnly,
            maximumDescendants: 0, validateImmediatelyBeforeSpawn: validate)
        let data = try await runManualSimulatorDeclaration(declaration, deadline: deadline,
            maximumDuration: request.timeout, terminalLease: terminalLease)
        try validate()
        return data
    }

    private static let manualSimulatorEnvironment = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty"
    ]

    private static func runManualSimulatorDeclaration(_ declaration: DeclaredInvocation,
                                                     deadline: ContinuousClock.Instant,
                                                     maximumDuration: Duration = .seconds(10),
                                                     terminalLease: ProcessTerminalVerificationLease? = nil) async throws -> Data {
        guard launchDepth == 0 else { throw ProcessRunnerError.nestedLaunch }
        guard declaration.kind == .readOnly, declaration.maximumDescendants == 0 else {
            throw ProcessRunnerError.undeclaredInvocation
        }
        let readDeadline = min(deadline, ContinuousClock.now.advanced(by: min(maximumDuration, .seconds(10))))
        return try await $launchDepth.withValue(launchDepth + 1) {
            let remaining = ContinuousClock.now.duration(to: readDeadline)
            guard remaining > .zero else { throw ManualSimulatorClientError.expired }
            let components = remaining.components
            let timeout = Double(components.seconds) + Double(components.attoseconds) / 1e18
            let authorization = AuthorizedLaunch(declaration, timeout: timeout)
            let session: ProcessSession
            do {
                session = try await ProcessSession.launchDeadlineBoundRead(authorization,
                    deadline: readDeadline, terminalLease: terminalLease)
            } catch ProcessReadAdmissionError.expired {
                throw ManualSimulatorClientError.expired
            }
            let output = await session.collect()
            guard case .exited(0) = output.end, output.stdout.eofObserved, output.stderr.eofObserved,
                  !output.stdout.truncated, !output.stderr.truncated,
                  output.stdout.bytes.count <= BoundedAdapterData.maximumBytes else {
                throw ProcessRunnerError.undeclaredInvocation
            }
            return output.stdout.bytes
        }
    }

    static func runLocalSnapshots(tmutilURL: URL, volumePath: String) async throws -> Output {
        try await run(try declared(.localSnapshots, executableURL: tmutilURL,
            arguments: ["listlocalsnapshots", volumePath]))
    }

    static func runContainerSpace(diskutilURL: URL, volumePath: String) async throws -> Output {
        try await run(try declared(.containerSpace, executableURL: diskutilURL,
            arguments: ["info", "-plist", volumePath]))
    }

    static func runProcessSurvey(psURL: URL) async throws -> Output {
        try await run(try declared(.processSurvey, executableURL: psURL,
            arguments: ["-Ao", "rss,comm", "-m"]))
    }

    static func runDockerImages(approval: DockerReadApproval) async throws -> Output {
        try await runApprovedDocker(approval: approval,
            arguments: ["image", "ls", "--no-trunc", "--format", "{{json .}}"])
    }

    static func runDockerContainers(approval: DockerReadApproval) async throws -> Output {
        try await runApprovedDocker(approval: approval,
            arguments: ["container", "ls", "--all", "--no-trunc", "--format", "{{json .}}"])
    }

    static func jobSnapshot() async -> ProcessGateSnapshot { await ProcessJobGate.shared.snapshot() }

    private static func run(_ declaration: DeclaredInvocation,
                            timeout: TimeInterval = defaultTimeout) async throws -> Output {
        guard launchDepth == 0 else { throw ProcessRunnerError.nestedLaunch }
        guard timeout.isFinite, timeout >= 0, timeout <= Double(Int32.max) else {
            throw POSIXError(.EINVAL)
        }
        guard declaration.maximumDescendants == 0 else {
            throw ProcessRunnerError.needExceedsCompiledDescriptor
        }
        return try await $launchDepth.withValue(launchDepth + 1) {
            let authorization = AuthorizedLaunch(declaration, timeout: timeout)
            let session = try await ProcessSession.launch(authorization)
            return legacyOutput(await session.collect())
        }
    }

    private static func declared(_ caller: BuiltInCallerID, executableURL: URL,
                                 arguments: [String],
                                 validateImmediatelyBeforeSpawn:
                                    @escaping @Sendable () throws -> Void = {}) throws
        -> DeclaredInvocation {
        guard matches(caller, executableURL: executableURL, arguments: arguments) else {
            throw ProcessRunnerError.undeclaredInvocation
        }
        return DeclaredInvocation(executableURL: executableURL,
                                  arguments: arguments, kind: .readOnly,
                                  maximumDescendants: 0,
                                  validateImmediatelyBeforeSpawn: validateImmediatelyBeforeSpawn)
    }

    private static func runApprovedDocker(approval: DockerReadApproval,
                                          arguments: [String]) async throws -> Output {
        guard approval.isCurrent else {
            throw ProcessRunnerError.undeclaredInvocation
        }
        let executableURL = URL(fileURLWithPath: approval.executable.canonicalPath)
        let dockerArguments = ["--host", approval.endpoint] + arguments
        let declaration = DeclaredInvocation(executableURL: executableURL,
            arguments: dockerArguments,
            environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": "/var/empty",
                "DOCKER_CONFIG": "/dev/null"
            ], kind: .readOnly, maximumDescendants: 0,
            validateImmediatelyBeforeSpawn: {
                guard approval.isCurrent else { throw ProcessRunnerError.undeclaredInvocation }
            })
        let output = try await run(declaration)
        guard approval.isCurrent else {
            throw ProcessRunnerError.undeclaredInvocation
        }
        return output
    }

    private static func classify(executableURL: URL,
                                 arguments: [String]) -> DeclaredInvocation? {
        for caller in [BuiltInCallerID.compatibilityEcho, .compatibilityFalse,
                       .compatibilityTrue, .compatibilityCat, .compatibilitySleep] {
            if let declaration = try? declared(caller, executableURL: executableURL,
                                               arguments: arguments) { return declaration }
        }
        return nil
    }

    private static func matches(_ caller: BuiltInCallerID, executableURL: URL,
                                arguments: [String]) -> Bool {
        let path = executableURL.standardizedFileURL.path
        guard executableURL.isFileURL, path.hasPrefix("/"),
              arguments.allSatisfy({ $0.utf8.count <= 4_096 && !$0.utf8.contains(0) })
        else { return false }
        switch caller {
        case .toolLocatorXcrunFind:
            guard path == "/usr/bin/xcrun", arguments.count == 2,
                  arguments[0] == "--find" else { return false }
            let name = arguments[1]
            return !name.isEmpty && name.utf8.count <= 128
                && name.allSatisfy { $0.isLetter || $0.isNumber || "-._+".contains($0) }
        case .simctlDevices:
            return path == "/usr/bin/xcrun"
                && arguments == ["simctl", "list", "devices", "-j"]
        case .simctlRuntimes:
            return path == "/usr/bin/xcrun"
                && arguments == ["simctl", "list", "runtimes", "-j"]
        case .localSnapshots:
            return path == "/usr/bin/tmutil" && arguments.count == 2
                && arguments[0] == "listlocalsnapshots" && arguments[1].hasPrefix("/")
        case .containerSpace:
            return path == "/usr/sbin/diskutil" && arguments.count == 3
                && arguments[0...1] == ["info", "-plist"] && arguments[2].hasPrefix("/")
        case .processSurvey:
            return path == "/bin/ps" && arguments == ["-Ao", "rss,comm", "-m"]
        case .compatibilityEcho:
            return path == "/bin/echo" && arguments.count <= 32
        case .compatibilityFalse:
            return path == "/usr/bin/false" && arguments.isEmpty
        case .compatibilityTrue:
            return path == "/usr/bin/true" && arguments.isEmpty
        case .compatibilityCat:
            return path == "/bin/cat" && arguments.count == 1 && arguments[0].hasPrefix("/")
        case .compatibilitySleep:
            guard path == "/bin/sleep", arguments.count == 1,
                  let seconds = Double(arguments[0]) else { return false }
            return seconds.isFinite && (0...60).contains(seconds)
        }
    }

    /// Denial-only test seam: production launch has no claimed-needs input.
    static func validateNeedForTesting(executableURL: URL, arguments: [String],
                                       claimedDescendants: Int) throws {
        guard let declaration = classify(executableURL: executableURL, arguments: arguments)
        else { throw ProcessRunnerError.undeclaredInvocation }
        guard claimedDescendants >= 0,
              claimedDescendants <= declaration.maximumDescendants else {
            throw ProcessRunnerError.needExceedsCompiledDescriptor
        }
    }

    /// Denial-only test seam proving nested launch rejection precedes acquire.
    static func runInsideNestedScopeForTesting(executableURL: URL,
                                               arguments: [String]) async throws -> Output {
        try await $launchDepth.withValue(1) {
            try await run(executableURL: executableURL, arguments: arguments)
        }
    }

    static func legacyOutput(_ output: BoundedProcessOutput) -> Output {
        let stdout = String(data: output.stdout.bytes, encoding: .utf8)
        let stderr = String(data: output.stderr.bytes, encoding: .utf8)
        let complete = output.stdout.eofObserved && output.stderr.eofObserved
            && !output.stdout.truncated && !output.stderr.truncated && stdout != nil && stderr != nil
        let code: Int32
        if case .exited(let value) = output.end { code = value }
        else { code = -1 }
        return Output(exitCode: code, standardOutput: complete ? stdout! : "",
            standardError: complete ? stderr! : "", timedOut: output.end == .readOnlyTimedOut,
            outputComplete: complete)
    }
}
