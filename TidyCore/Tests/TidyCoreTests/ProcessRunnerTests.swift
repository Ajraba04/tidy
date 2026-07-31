import Foundation
import Testing
@testable import TidyCore

@Suite("ProcessRunner")
struct ProcessRunnerTests {

    @Test("captures stdout from a simple command")
    func capturesStandardOutput() async throws {
        let output = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello", "tidy"]
        )
        #expect(output.succeeded)
        #expect(output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "hello tidy")
    }

    @Test("reports a non-zero exit code as not succeeded")
    func reportsNonZeroExitCode() async throws {
        let output = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            arguments: []
        )
        #expect(!output.succeeded)
        #expect(output.exitCode != 0)
    }

    @Test("never deadlocks on a chatty command whose output exceeds a pipe buffer")
    func drainsLargeOutputWithoutDeadlock() async throws {
        let scratchFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProcessRunnerTests-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: scratchFile) }

        // Comfortably exceeds a 64 KB pipe buffer, deterministically.
        let payload = Data(repeating: 0x41, count: 500_000)
        try payload.write(to: scratchFile)

        let output = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            arguments: [scratchFile.path]
        )
        #expect(output.succeeded)
        #expect(output.standardOutput.utf8.count == 500_000)
    }

    @Test("runDiscardingOutput reports success without capturing anything")
    func runDiscardingOutputReportsSuccess() async {
        let succeeded = await ProcessRunner.runDiscardingOutput(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["quiet"]
        )
        #expect(succeeded)
    }

    @Test("minimal environment carries no inherited PATH beyond the fixed one")
    func minimalEnvironmentIsFixed() {
        #expect(ProcessRunner.minimalEnvironment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
    }
}
