import Darwin
import Foundation

private enum DriverFailure: Error { case invalid }
private struct DriverContext: Sendable {
    let mode: String
    let root: URL
    let control: URL
    var config: URL { root.appendingPathComponent("settings/config.json") }
    init() throws {
        let a = CommandLine.arguments
        let modes: Set<String> = ["seed-one", "seed-two", "probe", "bootstrap-hold", "bootstrap-death",
                                  "stable-hold", "contender", "once-contender", "p1", "p2", "p3", "p4", "p5"]
        guard a.count == 4, modes.contains(a[1]), UUID(uuidString: a[3]) != nil,
              let base = realpath("/private/tmp", nil),
              let actual = realpath(a[2], nil) else { throw DriverFailure.invalid }
        defer { free(base); free(actual) }
        let url = URL(fileURLWithPath: a[2], isDirectory: true)
        guard String(cString: actual) == a[2], url.deletingLastPathComponent().path == String(cString: base),
              url.lastPathComponent.hasPrefix("tidy-t05-a2p-"),
              UUID(uuidString: String(url.lastPathComponent.dropFirst("tidy-t05-a2p-".count))) != nil else {
            throw DriverFailure.invalid
        }
        mode = a[1]; root = url; control = url.appendingPathComponent(a[3])
        for directory in [root, control, root.appendingPathComponent("settings")] {
            var s = stat()
            guard lstat(directory.path, &s) == 0, (s.st_mode & S_IFMT) == S_IFDIR,
                  s.st_uid == getuid(), s.st_mode & 0o777 == 0o700 else { throw DriverFailure.invalid }
        }
    }
    func report(_ name: String, _ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count <= 16_384 else { throw DriverFailure.invalid }
        let fd = open(control.appendingPathComponent(name).path,
                      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw DriverFailure.invalid }
        defer { close(fd) }
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), data.count - offset) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw DriverFailure.invalid }
            offset += n
        }
    }
    func waitFile(_ name: String) {
        let end = ContinuousClock.now.advanced(by: .seconds(4))
        while ContinuousClock.now < end {
            let fd = open(control.appendingPathComponent(name).path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            if fd >= 0 {
                var s = stat(); var byte: UInt8 = 0
                let valid = fstat(fd, &s) == 0 && (s.st_mode & S_IFMT) == S_IFREG && s.st_uid == getuid()
                    && s.st_size == 1 && s.st_mode & 0o777 == 0o600 && Darwin.read(fd, &byte, 1) == 1 && byte == 82
                close(fd)
                if valid { return }
                _exit(126)
            }
            if errno != ENOENT { _exit(126) }
            Thread.sleep(forTimeInterval: 0.005)
        }
        _exit(125)
    }
    func start() {
        let end = ContinuousClock.now.advanced(by: .seconds(4))
        while ContinuousClock.now < end {
            var p = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let n = poll(&p, 1, 20)
            if n < 0 && errno == EINTR { continue }
            if n < 0 { _exit(126) }
            if n > 0 {
                var byte: UInt8 = 0
                if p.revents & Int16(POLLIN) != 0 && Darwin.read(STDIN_FILENO, &byte, 1) == 1 && byte == 71 { return }
                _exit(126)
            }
        }
        _exit(125)
    }
}

private final class PrefixIO: JournalPOSIXIO, @unchecked Sendable {
    let context: DriverContext
    let real = DarwinJournalIO()
    // SettingsStore's accepted transaction contract is synchronous under actor isolation.
    // This wrapper is used by exactly one store, never shared with another thread/store.
    private var nextDirectoryBoundary: Int?
    init(_ context: DriverContext) { self.context = context }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        try real.write(fd: fd, bytes: bytes, offset: offset)
    }
    func path(_ fd: Int32) throws -> String {
        var bytes = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &bytes) == 0 else { throw DriverFailure.invalid }
        return URL(fileURLWithPath: String(cString: bytes)).lastPathComponent
    }
    func pause() throws {
        try context.report("paused.json", ["boundary": context.mode])
        context.waitFile("resume")
    }
    func syncFile(fd: Int32) throws {
        try real.syncFile(fd: fd)
        let name = try path(fd)
        if name == "config.lock" && ["bootstrap-hold", "bootstrap-death"].contains(context.mode) {
            try pause()
            if context.mode == "bootstrap-death" { _exit(80) }
        }
        if name == "config.pending.json" { nextDirectoryBoundary = 1 }
        if name.hasPrefix(".config-backup-") && context.mode == "p2" { _exit(82) }
    }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        try real.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
        if destination == "config.backup.json" { nextDirectoryBoundary = 3 }
        if destination == "config.json" { nextDirectoryBoundary = 4 }
    }
    func syncDirectory(fd: Int32) throws {
        try real.syncDirectory(fd: fd)
        guard let prefix = nextDirectoryBoundary else { return }
        nextDirectoryBoundary = nil
        if context.mode == "p\(prefix)" { _exit(Int32(80 + prefix)) }
        if prefix == 1 && context.mode == "stable-hold" { try pause() }
    }
}
private func outcome(_ error: Error) -> String {
    switch error {
    case SettingsStoreError.unavailable: return "unavailable"
    case SettingsStoreError.changedExternally: return "changedExternally"
    case SettingsStoreError.staleRevision: return "staleRevision"
    case SettingsStoreError.readOnlyRecovery: return "readOnlyRecovery"
    default: return "unexpected:\(String(describing: error))"
    }
}
@main private struct SettingsProcessDriver {
    static func main() async {
        // A direct self-exit is allowed only in this nonshipping executable.
        Thread.detachNewThread { Thread.sleep(forTimeInterval: 8); _exit(124) }
        do {
            let c = try DriverContext()
            let injected = ["bootstrap-hold", "bootstrap-death", "stable-hold", "p1", "p2", "p3", "p4", "p5"].contains(c.mode)
            let store = injected ? SettingsStore(url: c.config, io: PrefixIO(c)) : SettingsStore(url: c.config)
            let loaded = await store.load()
            if c.mode == "probe" {
                var report: [String: Any] = ["disposition": String(describing: loaded.disposition), "envelope": NSNull()]
                if let envelope = loaded.envelope {
                    report["revision"] = envelope.revision
                    report["envelope"] = try SettingsDecoding.encode(envelope).base64EncodedString()
                }
                if loaded.disposition == .recoveryReadOnly {
                    do { _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(211)); report["update"] = "saved" }
                    catch { report["update"] = outcome(error) }
                    do { _ = try await store.previewRollback(); report["preview"] = "issued" }
                    catch { report["preview"] = outcome(error) }
                }
                try c.report("result.json", report)
                _exit(0)
            }
            guard let envelope = loaded.envelope else { throw DriverFailure.invalid }
            if ["bootstrap-hold", "bootstrap-death", "stable-hold", "contender", "once-contender"].contains(c.mode) {
                try c.report("loaded.json", ["revision": envelope.revision,
                    "envelope": try SettingsDecoding.encode(envelope).base64EncodedString()])
                c.start()
            }
            let days = c.mode == "seed-one" ? 180 : (c.mode == "seed-two" ? 181 : 211)
            var report: [String: Any]
            do {
                let saved = try await store.update(expectedRevision: envelope.revision, change: .transcriptAgeDays(days))
                if c.mode == "p5" { _exit(85) }
                report = ["outcome": "saved", "revision": saved.revision,
                          "envelope": try SettingsDecoding.encode(saved).base64EncodedString()]
            } catch { report = ["outcome": outcome(error)] }
            if c.mode == "contender" {
                try c.report("first.json", report)
                c.waitFile("retry")
                do {
                    let saved = try await store.update(expectedRevision: envelope.revision, change: .transcriptAgeDays(212))
                    report = ["outcome": "saved", "revision": saved.revision]
                } catch { report = ["outcome": outcome(error)] }
            }
            try c.report("result.json", report)
            _exit(0)
        } catch {
            // No attempted recovery, replacement or cleanup after a fixture failure.
            _exit(123)
        }
    }
}
