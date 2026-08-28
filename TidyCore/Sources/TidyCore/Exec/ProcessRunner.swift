import Foundation

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
        let kind: AuthorizedJobKind
        /// Every current T08.3 declaration is a direct-child-only shape.
        let maximumDescendants: Int
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

        fileprivate init(_ declaration: DeclaredInvocation, timeout: TimeInterval) {
            executableURL = declaration.executableURL
            arguments = declaration.arguments
            environment = ProcessRunner.minimalEnvironment
            kind = declaration.kind
            deadline = .seconds(timeout)
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

    static func runSimctlRuntimes(xcrunURL: URL) async throws -> Output {
        try await run(try declared(.simctlRuntimes, executableURL: xcrunURL,
            arguments: ["simctl", "list", "runtimes", "-j"]))
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
                                 arguments: [String]) throws -> DeclaredInvocation {
        guard matches(caller, executableURL: executableURL, arguments: arguments) else {
            throw ProcessRunnerError.undeclaredInvocation
        }
        return DeclaredInvocation(executableURL: executableURL,
                                  arguments: arguments, kind: .readOnly,
                                  maximumDescendants: 0)
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
