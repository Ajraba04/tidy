import Foundation

/// Read-only command transport. No shell, inherited PATH lookup, mutation
/// selector, or accepted-effect authority is exposed here.
public enum ProcessRunner: Sendable {
    public struct Output: Sendable {
        public let exitCode: Int32
        public let standardOutput: String
        public let standardError: String
        public let timedOut: Bool
        public let outputComplete: Bool

        public var succeeded: Bool { exitCode == 0 && !timedOut && outputComplete }
    }

    public static let minimalEnvironment: [String: String] = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": NSHomeDirectory()
    ]
    public static let defaultTimeout: TimeInterval = 60
    private static let gate = try! ProcessJobGate(limit: 2)

    /// Bounded retention and observation, not a process-tree kill guarantee.
    /// Incomplete or invalid output cannot become a successful parsed prefix.
    @discardableResult
    public static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = ProcessRunner.defaultTimeout
    ) async throws -> Output {
        guard timeout.isFinite, timeout >= 0, timeout <= Double(Int32.max) else {
            throw POSIXError(.EINVAL)
        }
        let request = ProcessRequest(executable: executableURL, arguments: arguments,
            environment: environment ?? minimalEnvironment, kind: .readOnly, deadline: .seconds(timeout))
        let session = try await ProcessSession.launch(request, gate: gate)
        return legacyOutput(await session.collect())
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

    static func jobSnapshot() async -> ProcessGateSnapshot { await gate.snapshot() }

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
