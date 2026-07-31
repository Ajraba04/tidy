import Foundation

/// Runs a resolved executable with an explicit, minimal environment. Never
/// invokes a shell, so there is no argument-splitting or PATH lookup to get
/// wrong.
public enum ProcessRunner: Sendable {
    public struct Output: Sendable {
        public let exitCode: Int32
        public let standardOutput: String
        public let standardError: String
        public let timedOut: Bool

        public var succeeded: Bool { exitCode == 0 && !timedOut }
    }

    public static let minimalEnvironment: [String: String] = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": NSHomeDirectory()
    ]

    public static let defaultTimeout: TimeInterval = 60

    /// Runs the tool and captures its output.
    ///
    /// Reads both pipes to EOF concurrently with waiting for exit, each on
    /// its own detached task. A chatty command (e.g. `simctl list -j`) can
    /// write more than the pipe's OS buffer (typically 64 KB); reading only
    /// one stream at a time, or only after the process exits, can deadlock
    /// against a child still blocked writing the other stream.
    ///
    /// Exit is detected by polling `process.isRunning` rather than calling
    /// `Process.waitUntilExit()`. That call blocks inside its own nested
    /// run loop waiting for a termination notification, and in practice —
    /// confirmed with a debugger, reproducibly, on this toolchain — that
    /// notification can be lost when `waitUntilExit()` runs on a different
    /// thread than `run()`, which a detached task guarantees: the stuck
    /// thread sat waiting forever for a child that `pgrep` showed had
    /// already exited. `FileHandle.readabilityHandler` combined with
    /// `Process.terminationHandler` was tried first and deadlocked the same
    /// way, for the same underlying reason. Polling a plain property has no
    /// notification to lose.
    ///
    /// `timeout` is a hard backstop regardless of cause: past it, the
    /// process is killed and `Output.timedOut` is set, so a caller can
    /// never hang forever no matter what goes wrong underneath.
    ///
    /// Each call also ties up multiple OS threads for its duration (one per
    /// detached task below), all doing genuinely blocking work rather than
    /// cooperatively yielding. Swift's concurrency thread pool is sized for
    /// a small number of cores, not for that — enough concurrent callers
    /// (e.g. a big test suite, or several catalog items scanned at once)
    /// can exhaust every pool thread. `ProcessConcurrencyGate` bounds how
    /// many calls run at once so the rest queue instead of exhausting it.
    @discardableResult
    public static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = ProcessRunner.defaultTimeout
    ) async throws -> Output {
        await ProcessConcurrencyGate.shared.acquire()
        do {
            let output = try await runUnguarded(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                timeout: timeout
            )
            await ProcessConcurrencyGate.shared.release()
            return output
        } catch {
            await ProcessConcurrencyGate.shared.release()
            throw error
        }
    }

    private static func runUnguarded(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
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
        async let exitResult = waitForExit(process, timeout: timeout)

        let (out, err, result) = await (outData, errData, exitResult)

        return Output(
            exitCode: result.exitCode,
            standardOutput: String(data: out, encoding: .utf8) ?? "",
            standardError: String(data: err, encoding: .utf8) ?? "",
            timedOut: result.timedOut
        )
    }

    /// Fire-and-forget form for commands whose output nobody reads (mirrors
    /// the shell script's `run() { "$@" >/dev/null 2>&1 }`). Returns whether
    /// the process exited zero.
    @discardableResult
    public static func runDiscardingOutput(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = ProcessRunner.defaultTimeout
    ) async -> Bool {
        (try? await run(executableURL: executableURL, arguments: arguments, environment: environment, timeout: timeout).succeeded) ?? false
    }

    private static func readToEndOfFile(_ handle: FileHandle) async -> Data {
        await Task.detached(priority: .utility) {
            handle.readDataToEndOfFile()
        }.value
    }

    private struct ExitResult: Sendable {
        let exitCode: Int32
        let timedOut: Bool
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) async -> ExitResult {
        await Task.detached(priority: .utility) {
            let deadline = Date().addingTimeInterval(timeout)
            let pollInterval: UInt32 = 20_000 // 20ms, in microseconds

            while process.isRunning {
                if Date() >= deadline {
                    // SIGKILL, not terminate()/SIGTERM: this path exists
                    // specifically for the case where something is already
                    // not behaving as expected, so nothing here should rely
                    // on the child cooperating.
                    kill(process.processIdentifier, SIGKILL)
                    // Draining the exit status (however it eventually
                    // arrives) isn't needed for a caller who only wants to
                    // know the run timed out.
                    return ExitResult(exitCode: -1, timedOut: true)
                }
                usleep(pollInterval)
            }

            return ExitResult(exitCode: process.terminationStatus, timedOut: false)
        }.value
    }
}

/// Bounds how many `ProcessRunner.run` calls are actually in flight at
/// once. Extra callers queue (FIFO) rather than each grabbing several more
/// threads out of Swift's cooperative pool.
actor ProcessConcurrencyGate {
    static let shared = ProcessConcurrencyGate(maxConcurrent: 4)

    private let maxConcurrent: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func acquire() async {
        if active < maxConcurrent {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        active += 1
    }

    func release() {
        active -= 1
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}
