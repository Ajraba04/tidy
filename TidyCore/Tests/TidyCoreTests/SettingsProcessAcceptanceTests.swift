import CryptoKit
import Darwin
import Foundation
import Testing
@_spi(TidyCoreTesting) @testable import TidyCore

private enum A2PError: Error { case invalid, missing, incomplete, timeout }
private struct A2PFile: Equatable {
    let data: Data
    let device: UInt64
    let inode: UInt64
    let mode: UInt16
}
private func a2pFile(_ url: URL, limit: Int = 1_048_576) throws -> A2PFile {
    let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else { throw A2PError.missing }
    defer { close(fd) }
    var s = stat()
    guard fstat(fd, &s) == 0, s.st_uid == getuid(),
          (s.st_mode & S_IFMT) == S_IFREG, s.st_size >= 0,
          s.st_size <= limit, (s.st_mode & 0o022) == 0 else { throw A2PError.invalid }
    var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = Darwin.read(fd, &buffer, min(buffer.count, limit + 1 - data.count))
        if count < 0 && errno == EINTR { continue }
        guard count >= 0 else { throw A2PError.invalid }
        if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
        guard data.count <= limit else { throw A2PError.invalid }
    }
    return A2PFile(data: data, device: UInt64(s.st_dev), inode: UInt64(s.st_ino),
                   mode: UInt16(s.st_mode & 0o777))
}
private func a2pWrite(_ data: Data, _ url: URL) throws {
    let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw A2PError.invalid }
    defer { close(fd) }
    var offset = 0
    while offset < data.count {
        let n = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), data.count - offset) }
        if n < 0 && errno == EINTR { continue }
        guard n > 0 else { throw A2PError.invalid }
        offset += n
    }
}
private func a2pRoot() throws -> URL {
    guard let p = realpath("/private/tmp", nil) else { throw A2PError.invalid }
    defer { free(p) }
    let root = URL(fileURLWithPath: String(cString: p), isDirectory: true)
        .appendingPathComponent("tidy-t05-a2p-\(UUID().uuidString)", isDirectory: true)
    guard mkdir(root.path, 0o700) == 0 else { throw A2PError.invalid }
    print("Retained A2P artifacts: \(root.path)")
    return root
}
private func a2pHash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
private func a2pEnvironment(root: URL) throws -> [String: String] {
    guard let inheritedHome = ProcessInfo.processInfo.environment["HOME"],
          inheritedHome.hasPrefix("/"), !inheritedHome.utf8.contains(0) else { throw A2PError.invalid }
    let fd = open(inheritedHome, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw A2PError.invalid }
    defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
          info.st_uid == getuid() else { throw A2PError.invalid }
    return ["PATH": "/usr/bin:/bin", "HOME": inheritedHome, "TMPDIR": root.path]
}
private func a2pEnvelope(_ revision: UInt64, _ days: Int) -> SettingsEnvelope {
    let preferences = revision == 0 ? nil : PolicyPreferences(global: PolicyValues(fields: [
        SettingID(rawValue: "cleanup.transcriptDays"): .integer(Int64(days)),
    ]))
    return SettingsEnvelope(schemaVersion: 2, revision: revision,
                            config: TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: days),
                            preferences: preferences)
}
private func a2pLegacy() throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(TidyConfig(schemaVersion: 1))
}
private func a2pJSON(_ url: URL) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: a2pFile(url, limit: 16_384).data) as? [String: Any] else {
        throw A2PError.invalid
    }
    return value
}
private func a2pReap(_ session: ProcessSession, seconds: Int = 10) async throws -> (Int32, Int32) {
    let exit = await session.observeOwnedExit(within: .seconds(seconds))
    let observed = session.observationSnapshot()
    guard case .reapedWithoutIdentity(let pid, let raw) = exit,
          pid > 0, session.identity == nil, observed.consumingReapCount == 1,
          observed.signalAttempts == 0, (raw & 0x7f) == 0 else { throw A2PError.incomplete }
    let code = (raw >> 8) & 0xff
    print("A2P owned reap: pid=\(pid) raw=\(raw) exit=\(code) reaps=\(observed.consumingReapCount) signals=\(observed.signalAttempts)")
    return (pid, code)
}

private actor A2PBuild {
    static let shared = A2PBuild()
    private var result: URL?
    // Prevent retry/overlap after an uncertain compiler outcome.
    private var attempted = false
    private var retainedCompiler: ProcessSession?
    func binary() async throws -> URL {
        if let result { return result }
        guard !attempted else { throw A2PError.incomplete }
        attempted = true
        let root = try a2pRoot()
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let sourceRoot = package.appendingPathComponent("Sources/TidyCore")
        guard let enumerator = FileManager.default.enumerator(at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw A2PError.missing
        }
        var sources = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
        guard !sources.isEmpty else { throw A2PError.missing }
        sources.append(package.appendingPathComponent("Tests/TidyCoreTests/Fixtures/T05SettingsProcessDriver.swift"))
        var manifest: [String: String] = [:]
        for source in sources {
            manifest[source.path] = a2pHash(try a2pFile(source).data)
        }
        for required in ["Policy/SessionProfile.swift", "Policy/SettingsTransfer.swift"] {
            guard manifest[package.appendingPathComponent("Sources/TidyCore/\(required)").path] != nil else {
                throw A2PError.incomplete
            }
        }
        try a2pWrite(try JSONEncoder().encode(manifest), root.appendingPathComponent("source-sha256.json"))
        let output = root.appendingPathComponent("settings-process-driver")
        #if arch(arm64)
        let target = "arm64-apple-macos14.0"
        #elseif arch(x86_64)
        let target = "x86_64-apple-macos14.0"
        #else
        throw A2PError.invalid
        #endif
        let args = ["swiftc", "-parse-as-library", "-swift-version", "5", "-Onone", "-j", "2", "-target", target,
                    "-module-cache-path", root.appendingPathComponent("module-cache").path,
                    "-module-name", "TidySettingsProcessFixture"] + sources.map(\.path) + ["-lsqlite3", "-o", output.path]
        try a2pWrite(try JSONEncoder().encode(args), root.appendingPathComponent("compiler-arguments.json"))
        let compiler = try await ProcessSession.launchForTesting(ProcessTestRequest(executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: args, environment: a2pEnvironment(root: root),
            kind: .readOnly, deadline: .seconds(120)), gate: ProcessJobGate.isolatedForTesting(limit: 1), identityCapture: .failClosed)
        retainedCompiler = compiler
        // The Controller may raise this bounded compiler budget after reviewing a real timeout.
        do {
            let captured = await compiler.collect()
            try a2pWrite(captured.stdout.bytes, root.appendingPathComponent("compiler.stdout"))
            try a2pWrite(captured.stderr.bytes, root.appendingPathComponent("compiler.stderr"))
            let (_, code) = try await a2pReap(compiler, seconds: 2)
            compiler.abandonWithoutSignal()
            guard captured.end == .exited(0), code == 0,
                  !captured.stdout.truncated, !captured.stderr.truncated,
                  captured.stdout.eofObserved, captured.stderr.eofObserved else { throw A2PError.incomplete }
        } catch {
            let originalError = error
            do { _ = try await a2pReap(compiler, seconds: 2) }
            catch { Issue.record("Compiler exit unproven; owner and build artifacts retained: \(root.path)") }
            compiler.abandonWithoutSignal()
            // retainedCompiler and the production supervisor keep real ownership.
            throw originalError
        }
        _ = try a2pFile(output, limit: 128 * 1_048_576)
        result = output
        return output
    }
}

private final class A2PRun {
    let root: URL
    let directory: URL
    let binary: URL
    let gate: ProcessJobGate
    var children: [(ProcessSession, URL)] = []
    init(binary: URL) throws {
        guard geteuid() != 0 else { throw A2PError.invalid }
        self.binary = binary
        root = try a2pRoot(); directory = root.appendingPathComponent("settings")
        gate = try ProcessJobGate.isolatedForTesting(limit: 2)
        guard mkdir(directory.path, 0o700) == 0 else { throw A2PError.invalid }
        try a2pWrite(a2pLegacy(), directory.appendingPathComponent("config.json"))
    }
    func launch(_ mode: String) async throws -> (ProcessSession, URL) {
        let control = root.appendingPathComponent(UUID().uuidString)
        guard mkdir(control.path, 0o700) == 0 else { throw A2PError.invalid }
        let session = try await ProcessSession.launchForTesting(ProcessTestRequest(executable: binary,
            arguments: [mode, root.path, control.lastPathComponent],
            environment: a2pEnvironment(root: root),
            kind: .readOnly, deadline: .seconds(10)), gate: gate, identityCapture: .failClosed)
        children.append((session, control))
        return (session, control)
    }
    func wait(_ control: URL, _ name: String) async throws -> [String: Any] {
        let end = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < end {
            if let value = try? a2pJSON(control.appendingPathComponent(name)) { return value }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw A2PError.timeout
    }
    func release(_ control: URL, _ name: String) throws {
        try a2pWrite(Data([82]), control.appendingPathComponent(name))
    }
    func snapshot() throws -> [String: A2PFile] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        guard names.count <= 12 else { throw A2PError.invalid }
        return try Dictionary(uniqueKeysWithValues: names.map { ($0, try a2pFile(directory.appendingPathComponent($0))) })
    }
    func terminal(_ child: (ProcessSession, URL), code: Int32 = 0) async throws -> [String: Any] {
        let (_, actual) = try await a2pReap(child.0)
        #expect(actual == code)
        child.0.abandonWithoutSignal()
        return try a2pJSON(child.1.appendingPathComponent("result.json"))
    }
    func save(_ mode: String, revision: UInt64, days: Int) async throws {
        let child = try await launch(mode)
        let result = try await terminal(child)
        #expect(result["outcome"] as? String == "saved")
        #expect(result["revision"] as? UInt64 == revision)
        #expect(try a2pFile(directory.appendingPathComponent("config.json")).data == SettingsDecoding.encode(a2pEnvelope(revision, days)))
    }
    func seed() async throws {
        try await save("seed-one", revision: 1, days: 180)
        #expect(try a2pFile(directory.appendingPathComponent("config.backup.json")).data == a2pLegacy())
        try await save("seed-two", revision: 2, days: 181)
        #expect(try a2pFile(directory.appendingPathComponent("config.backup.json")).data ==
            SettingsDecoding.encode(a2pEnvelope(1, 180)))
    }
    func finish() async {
        for (session, _) in children {
            do { _ = try await a2pReap(session) }
            catch { Issue.record("Unproven A2P child exit; ownership and all files retained: \(root.path)") }
            session.abandonWithoutSignal()
        }
    }
}
private func withA2P(_ body: (A2PRun) async throws -> Void) async throws {
    let run = try A2PRun(binary: await A2PBuild.shared.binary())
    do { try await body(run) }
    catch { await run.finish(); throw error }
    await run.finish()
}
private func a2pRecovery(_ run: A2PRun) async throws {
    let before = try run.snapshot()
    let probe = try await run.launch("probe")
    let report = try await run.terminal(probe)
    #expect(report["disposition"] as? String == "recoveryReadOnly")
    #expect(report["envelope"] is NSNull)
    #expect(report["update"] as? String == "readOnlyRecovery")
    #expect(report["preview"] as? String == "readOnlyRecovery")
    #expect(try run.snapshot() == before)
}
private func a2pMetadata(_ files: [String: A2PFile]) throws -> String {
    let lock = try #require(files["config.lock"])
    let store = try #require(files["config.store.json"])
    #expect(lock.mode == 0o600 && store.mode == 0o600)
    let a = try JSONSerialization.jsonObject(with: lock.data) as? [String: Any]
    let b = try JSONSerialization.jsonObject(with: store.data) as? [String: Any]
    let id = try #require(a?["storeID"] as? String)
    #expect(UUID(uuidString: id) != nil)
    #expect(Set(a?.keys.map { $0 } ?? []) == ["schema", "storeID"])
    #expect(Set(b?.keys.map { $0 } ?? []) == ["schema", "storeID"])
    #expect(a?["schema"] as? Int == 1 && b?["schema"] as? Int == 1)
    #expect(b?["storeID"] as? String == id)
    return id
}

@Suite(.serialized)
struct SettingsProcessAcceptanceTests {
    @Test(arguments: ["bootstrap-hold", "stable-hold"])
    func independentWritersContendThenRejectStaleLoadedBytes(_ mode: String) async throws {
        try await withA2P { run in
            if mode == "stable-hold" { try await run.seed() }
            let before = try run.snapshot()
            let winner = try await run.launch(mode)
            let winnerLoaded = try await run.wait(winner.1, "loaded.json")
            let loser = try await run.launch("contender")
            let loserLoaded = try await run.wait(loser.1, "loaded.json")
            let loadedRevision: UInt64 = mode == "bootstrap-hold" ? 0 : 2
            let loadedDays = mode == "bootstrap-hold" ? 45 : 181
            let loadedBytes = try SettingsDecoding.encode(a2pEnvelope(loadedRevision, loadedDays))
            #expect(winnerLoaded["envelope"] as? String == loadedBytes.base64EncodedString())
            #expect(loserLoaded["envelope"] as? String == loadedBytes.base64EncodedString())
            #expect(winnerLoaded["revision"] as? UInt64 == loadedRevision)
            #expect(loserLoaded["revision"] as? UInt64 == loadedRevision)
            try winner.0.releaseStartByte()
            _ = try await run.wait(winner.1, "paused.json")
            let held = try run.snapshot()
            try loser.0.releaseStartByte()
            let denied = try await run.wait(loser.1, "first.json")
            #expect(denied["outcome"] as? String == "unavailable")
            #expect(try run.snapshot() == held)
            try run.release(winner.1, "resume")
            let won = try await run.terminal(winner)
            #expect(won["outcome"] as? String == "saved")
            try run.release(loser.1, "retry")
            let lost = try await run.terminal(loser)
            #expect(lost["outcome"] as? String == "changedExternally")
            let (winnerPID, _) = try await a2pReap(winner.0)
            let (loserPID, _) = try await a2pReap(loser.0)
            #expect(winnerPID != loserPID)
            let after = try run.snapshot()
            let revision: UInt64 = mode == "bootstrap-hold" ? 1 : 3
            #expect(try after["config.json"]?.data == SettingsDecoding.encode(a2pEnvelope(revision, 211)))
            #expect(after["config.backup.json"]?.data == before["config.json"]?.data)
            #expect(Set(after.keys) == ["config.json", "config.backup.json", "config.lock", "config.store.json"])
            #expect(after.values.allSatisfy { $0.mode == 0o600 })
            #expect(after["config.lock"] == held["config.lock"])
            if mode == "stable-hold" { #expect(after["config.store.json"] == before["config.store.json"]) }
            _ = try a2pMetadata(after)
            let probe = try await run.launch("probe")
            let result = try await run.terminal(probe)
            #expect(result["disposition"] as? String == "loaded")
            #expect(result["revision"] as? UInt64 == revision)
            #expect(try result["envelope"] as? String == SettingsDecoding.encode(a2pEnvelope(revision, 211)).base64EncodedString())
            #expect(try run.snapshot() == after)
        }
    }

    @Test func bootstrapWinnerDeathCannotBeCompletedByAnotherProcess() async throws {
        try await withA2P { run in
            let original = try run.snapshot()
            let winner = try await run.launch("bootstrap-death"), loser = try await run.launch("once-contender")
            let winnerLoaded = try await run.wait(winner.1, "loaded.json")
            let loserLoaded = try await run.wait(loser.1, "loaded.json")
            let loadedBytes = try SettingsDecoding.encode(a2pEnvelope(0, 45))
            #expect(winnerLoaded["envelope"] as? String == loadedBytes.base64EncodedString())
            #expect(loserLoaded["envelope"] as? String == loadedBytes.base64EncodedString())
            try winner.0.releaseStartByte()
            _ = try await run.wait(winner.1, "paused.json")
            let held = try run.snapshot()
            #expect(Set(held.keys) == ["config.json", "config.lock"])
            #expect(held["config.json"] == original["config.json"])
            let lock = try #require(held["config.lock"])
            let identity = try a2pJSON(run.directory.appendingPathComponent("config.lock"))
            #expect(lock.mode == 0o600 && lock.data.count <= 1024)
            #expect(Set(identity.keys) == ["schema", "storeID"])
            #expect(identity["schema"] as? Int == 1)
            #expect(UUID(uuidString: try #require(identity["storeID"] as? String)) != nil)
            try loser.0.releaseStartByte()
            let denied = try await run.terminal(loser)
            #expect(denied["outcome"] as? String == "unavailable")
            #expect(try run.snapshot() == held)
            try run.release(winner.1, "resume")
            let (winnerPID, exit) = try await a2pReap(winner.0)
            let (loserPID, _) = try await a2pReap(loser.0)
            #expect(exit == 80 && winnerPID != loserPID)
            #expect(try run.snapshot() == held)
            try await a2pRecovery(run)
        }
    }

    @Test(arguments: [1, 2, 3, 4, 5])
    func abruptPublicationPrefixReopensFromExactRetainedArtifacts(_ prefix: Int) async throws {
        try await withA2P { run in
            try await run.seed()
            let before = try run.snapshot()
            let storeID = try a2pMetadata(before)
            let old = try #require(before["config.json"]?.data)
            let revision1Bytes = try SettingsDecoding.encode(a2pEnvelope(1, 180))
            #expect(before["config.backup.json"]?.data == revision1Bytes)
            let candidate = try SettingsDecoding.encode(a2pEnvelope(3, 211))
            let child = try await run.launch("p\(prefix)")
            let (_, code) = try await a2pReap(child.0)
            #expect(code == Int32(80 + prefix))
            #expect(!FileManager.default.fileExists(atPath: child.1.appendingPathComponent("result.json").path))
            let files = try run.snapshot()
            #expect(files["config.lock"] == before["config.lock"])
            #expect(files["config.store.json"] == before["config.store.json"])
            #expect(files.values.allSatisfy { $0.mode == 0o600 })
            #expect(files["config.json"]?.data == (prefix >= 4 ? candidate : old))
            #expect(files["config.backup.json"]?.data == (prefix >= 3 ? old : revision1Bytes))
            if prefix < 4 { #expect(files["config.json"] == before["config.json"]) }
            if prefix < 3 { #expect(files["config.backup.json"] == before["config.backup.json"]) }
            var expected: Set<String> = ["config.json", "config.backup.json", "config.lock", "config.store.json"]
            if prefix < 5 {
                expected.insert("config.pending.json")
                let marker = try a2pJSON(run.directory.appendingPathComponent("config.pending.json"))
                #expect(Set(marker.keys) == ["schema", "storeID", "transactionID", "oldRevision", "newRevision",
                    "oldConfigSHA256", "candidateSHA256", "candidateName", "backupName"])
                let tx = try #require(marker["transactionID"] as? String)
                #expect(UUID(uuidString: tx) != nil)
                let candidateName = ".config-candidate-\(tx)", backupName = ".config-backup-\(tx)"
                #expect(marker["schema"] as? Int == 1 && marker["storeID"] as? String == storeID)
                #expect(marker["oldRevision"] as? Int == 2 && marker["newRevision"] as? Int == 3)
                #expect(marker["oldConfigSHA256"] as? String == a2pHash(old))
                #expect(marker["candidateSHA256"] as? String == a2pHash(candidate))
                #expect(marker["candidateName"] as? String == candidateName)
                #expect(marker["backupName"] as? String == backupName)
                if prefix == 2 || prefix == 3 {
                    expected.insert(candidateName); #expect(files[candidateName]?.data == candidate)
                }
                if prefix == 2 { expected.insert(backupName); #expect(files[backupName]?.data == old) }
                #expect(Set(files.keys) == expected)
                try await a2pRecovery(run)
            } else {
                #expect(Set(files.keys) == expected)
                let probe = try await run.launch("probe")
                let result = try await run.terminal(probe)
                #expect(result["disposition"] as? String == "loaded")
                #expect(result["revision"] as? UInt64 == 3)
                #expect(result["envelope"] as? String == candidate.base64EncodedString())
                #expect(try run.snapshot() == files)
            }
        }
    }
}
