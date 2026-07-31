import Foundation

/// Finds an executable's absolute path without ever trusting the caller's
/// inherited `PATH`. Xcode-owned tools resolve through `xcrun --find`; other
/// CLIs are looked up in a small, fixed list of install locations. If a tool
/// cannot be found this way, callers must render a "not found" row — never
/// fall back to a shell that would search the user's PATH.
public enum ToolLocator: Sendable {
    static let xcrunPath = "/usr/bin/xcrun"

    static let fixedSearchDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    public static func locate(_ name: String) -> String? {
        if let found = locateViaXcrun(name) {
            return found
        }
        for directory in fixedSearchDirectories {
            let candidate = directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static func isAvailable(_ name: String) -> Bool {
        locate(name) != nil
    }

    private static func locateViaXcrun(_ name: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: xcrunPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrunPath)
        process.arguments = ["--find", name]
        process.environment = ProcessRunner.minimalEnvironment

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty,
            FileManager.default.isExecutableFile(atPath: path)
        else {
            return nil
        }
        return path
    }
}
