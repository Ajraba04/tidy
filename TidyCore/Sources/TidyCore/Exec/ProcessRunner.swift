import Foundation

/// Runs a resolved executable with an explicit, minimal environment. Never
/// invokes a shell, so there is no argument-splitting or PATH lookup to get
/// wrong.
public enum ProcessRunner: Sendable {
    public struct Output: Sendable {
        public let exitCode: Int32
        public let standardOutput: String
        public let standardError: String

        public var succeeded: Bool { exitCode == 0 }
    }

    public static let minimalEnvironment: [String: String] = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": NSHomeDirectory()
    ]

    /// Runs the tool and captures its output.
    ///
    /// Reads both pipes to EOF concurrently with waiting for exit, each on
    /// its own detached task. A chatty command (e.g. `simctl list -j`) can
    /// write more than the pipe's OS buffer (typically 64 KB); reading only
    /// one stream at a time, or only after the process exits, can deadlock
    /// against a child still blocked writing the other stream.
    ///
    /// This deliberately avoids `Process.terminationHandler` and
    /// `FileHandle.readabilityHandler`: paired with `DispatchGroup`, that
    /// combination is the textbook-recommended approach, but it reliably
    /// deadlocked when this package's tests ran inside `swiftpm-testing-helper`
    /// (reproduced with a minimal standalone script and confirmed via a
    /// debugger — the process went fully idle with no thread doing any
    /// work, meaning some expected callback simply never fired in that
    /// host). Blocking reads on detached tasks avoid both handler APIs
    /// entirely and do not exhibit the hang.
    @discardableResult
    public static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> Output {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment ?? minimalEnvironment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        async let outData = readToEndOfFile(outPipe.fileHandleForReading)
        async let errData = readToEndOfFile(errPipe.fileHandleForReading)
        async let exitCode = waitForExit(process)

        let (out, err, code) = await (outData, errData, exitCode)

        return Output(
            exitCode: code,
            standardOutput: String(data: out, encoding: .utf8) ?? "",
            standardError: String(data: err, encoding: .utf8) ?? ""
        )
    }

    /// Fire-and-forget form for commands whose output nobody reads (mirrors
    /// the shell script's `run() { "$@" >/dev/null 2>&1 }`). Returns whether
    /// the process exited zero.
    @discardableResult
    public static func runDiscardingOutput(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) async -> Bool {
        (try? await run(executableURL: executableURL, arguments: arguments, environment: environment).succeeded) ?? false
    }

    private static func readToEndOfFile(_ handle: FileHandle) async -> Data {
        await Task.detached(priority: .utility) {
            handle.readDataToEndOfFile()
        }.value
    }

    private static func waitForExit(_ process: Process) async -> Int32 {
        await Task.detached(priority: .utility) {
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }
}
