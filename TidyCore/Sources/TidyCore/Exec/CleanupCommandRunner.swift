import Foundation

/// Narrow effect transport for legacy cleanup helpers. Supplying a runner
/// never grants authority; `CapabilityRegistry` remains the effect boundary.
public struct CleanupCommandOutput: Sendable {
    public let succeeded: Bool
    public let standardOutput: String
    public let standardError: String

    public init(succeeded: Bool, standardOutput: String = "", standardError: String = "") {
        self.succeeded = succeeded
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol CleanupCommandRunning: Sendable {
    func run(executableName: String, arguments: [String], timeout: TimeInterval) async -> CleanupCommandOutput
}

public struct SystemCleanupCommandRunner: CleanupCommandRunning {
    public init() {}

    public func run(executableName: String, arguments: [String], timeout: TimeInterval) async -> CleanupCommandOutput {
        guard let path = ToolLocator.locate(executableName) else {
            return CleanupCommandOutput(succeeded: false, standardError: "\(executableName) not found")
        }
        do {
            let output = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: path), arguments: arguments, timeout: timeout
            )
            return CleanupCommandOutput(
                succeeded: output.succeeded,
                standardOutput: output.standardOutput,
                standardError: output.standardError
            )
        } catch {
            return CleanupCommandOutput(succeeded: false, standardError: error.localizedDescription)
        }
    }
}
