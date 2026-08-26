# T05 A.2P Actual Process Acceptance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task, only after Controller assignment and independent entry review. Steps use checkbox (`- [ ]`) syntax for tracking. This document is a proposal, not source-entry approval.

**Goal:** Prove settings bootstrap/stable-lock exclusion and retained-artifact reopen across actual independent processes and abrupt owned-child exits at P1–P5.

**Architecture:** A nonshipping Swift fixture is compiled with the actual checked-in TidyCore sources into a retained canonical UUID build directory. Its only entry point calls SettingsStore and delegates every persistence operation to DarwinJournalIO; its internal seam only observes completed operations, pauses, or exits its own process. The parent uses the accepted T04.B ProcessSession owner/reaper, never a second launcher or PID-based cleanup.

**Tech Stack:** Swift 5.10+, Swift Testing, Foundation/Darwin/CryptoKit, macOS 14+, local TidyCore, system swiftc and sqlite3; zero third-party dependencies.

## Global Constraints

- Native Swift/SwiftUI, macOS 14+, local TidyCore package, zero third-party runtime dependencies.
- Intel x86_64 and Apple Silicon arm64 supported; both require build and device evidence.
- No internet requests, telemetry, remote updates, repository fetches, model downloads, or remote package dependencies at runtime.
- Local IPC to an explicitly identified local tool service is allowed. No remote Docker contexts, TCP endpoints, SSH endpoints, or daemon auto-start during discovery.
- No repository deletion, database deletion, Docker volume deletion, local-model deletion, generic duplicate-file deletion, arbitrary scripts, or automatic force-quitting.
- No kernel tuning, swap-file manipulation, launch-agent disabling, privileged persistent helper, or changes to other tools' settings.
- No full-home scans on popover open or timers. No repository-supplied executable/config evaluation merely to discover a project.
- No change to signing, publishing, deployment, or remote Git state is authorized by this document.

The binding T05 A.1 interface, A.2 protocol and A.2P obligations remain in `docs/superpowers/tasks/T05-settings-and-ui-safety.md`. This card does not change schema defaults, app wiring, policy authority, recovery authority, import limits, journal handling, or any T06 contract. A.1/A.2 builds remain non-deployable until A.3's separate acceptance. This is abrupt **process** exit evidence, not physical power-loss evidence.

## Entry gates and ownership

1. A.2F production implementation and independent review are accepted, including JournalPOSIXIO ownership and exact P0–Return order. Do not assume the concurrently changing source already satisfies this gate.
2. T04.B is implemented, independently launcher-audited and accepted with actual-child reap evidence. Its approved declarations alone are insufficient. Read its process supplement and implementation brief. Do not implement B within A.2P or replace it with Foundation.Process, a shell, wait-any, polling reaping, or a private process runner.
3. Controller schedules one compiler/package job at a time, `--jobs 2`, and assigns this complete RED batch. Review the source allowlist against the accepted checkpoint before the compiler runs. Changes to that list require a recorded narrow amendment, not source auto-discovery.
4. Independently review this proposal before any source/test entry. Current preparation ran no tests, builds, helper executable, signal, or Git command.

Future source ownership is exactly:

| File | Responsibility |
|---|---|
| `TidyCore/Tests/TidyCoreTests/SettingsProcessAcceptanceTests.swift` (new) | Real owner lifecycle, compiler invocation, owned scratch, exact outcome assertions and all eight scenario executions below |
| `TidyCore/Tests/TidyCoreTests/Fixtures/T05SettingsProcessDriver.swift` (new) | Nonforking settings-only driver, real-I/O observation, finite handshake and owned self-exit |
| `TidyCore/Package.swift` (narrow edit) | Add `Fixtures/T05SettingsProcessDriver.swift` to the existing test-target exclude list; preserve `Fixtures/T04ProcessFixture.c`, Config resources and sqlite3 linkage |

No production source changes are required or authorized by this plan. In particular no new SettingsStore callback, public initializer, environment backdoor, shipped executable product, conditional production compilation, persistence algorithm, or settings repair helper is introduced. If the accepted A.2F cannot be observed through its existing seam as specified, stop with the exact mismatch for Controller review.

### Packaging and visibility, concretely

The test itself uses `@testable import TidyCore`, as existing package tests do. The helper is **not** a SwiftPM executable target and does **not** import an internal API across a module boundary. One explicitly listed compilation invokes system swiftc with the actual production source paths plus the driver as a single module named `TidySettingsProcessFixture`. There are no copied or rewritten production source files. This avoids depending on SwiftPM private object-file layouts or weakening public access control. Excluding the driver's `@main` file from the test target prevents a test-bundle entry-point collision. The shipped `TidyCore` library product and app target remain unchanged.

The exact source allowlist below includes B's three accepted process files. Any missing file is a gate failure, not permission to omit it or create a stub. `-target arm64-apple-macos14.0` or `x86_64-apple-macos14.0` is selected from the host compilation architecture; this does not claim the untested architecture. `-lsqlite3` preserves the package's existing system linker requirement. All compiler arguments are an array passed to the production process owner, never shell text.

T04.B's `ProcessRequest.environment` is an explicit `[String: String]`, with no declared implicit HOME inheritance. Both requests therefore use the same small helper below: read the already-existing parent HOME, require an absolute non-NUL pathname opening as a current-user-owned directory without following a final symlink, and pass its **original unchanged string**. Missing/invalid HOME stops the fixture before launch; it is not replaced with scratch or guessed from another source. Only TMPDIR is scoped to the owned root; PATH remains the fixed system-tool list. Do not copy B's historical scratch-HOME examples: A.2P preserves the actual HOME and does not create an alternate home/cache hierarchy or redirect module caches. This changes only the proposed A.2P request dictionaries, not B's interfaces or documents.

### Lifetime and evidence

- Every run root is a canonical `/private/tmp` child named `tidy-t05-a2p-<UUID>`, owner-only. Only its `settings` child is passed to SettingsStore; control/report files live outside that directory. Child `TMPDIR` points inside its root and is never used to infer the root's authorized parent.
- Every driver has a private UUID control directory and starts an independent eight-second watchdog thread. The thread can only `_exit(124)` its own process. Four-second handshake deadlines `_exit(125)` instead of waiting forever. These are fail-safe fixture deadlines, not hard-real-time guarantees against arbitrary kernel stalls.
- Driver launch uses the already-approved `.failClosed` identity seam. It suppresses positive signal identity and cannot invent an exit, syscall result or authority. Parent requires the actual `.reapedWithoutIdentity(pid:status:)`, exactly one consuming reap and zero signal attempts. Distinct overlapping children must have distinct actually reaped PIDs. No PID is ever a signal target.
- All requests are fixture-only `.readOnly` process jobs, which is a process accounting classification, **not** a claim that scratch writes are read-only. No registered effect/capability is created. Missing identity means the owner may never signal even when its deadline expires. Compiler uses the same fail-only path; compiler descendants are not claimed quiescent.
- Parent reads control/report files via no-follow, nonblocking bounded regular-file reads; no inherited pipe read is added. T04.B still owns bounded stdout/stderr collection. Reaping precedes interpreting terminal report files as final outcomes.
- On every success or error, the parent observes each retained session for bounded actual reaping, then calls abandonWithoutSignal to close local collection/control endpoints. Unproven exit records a failure and retains ownership/artifacts. Task cancellation is never a join.
- **Every build and run directory is retained, even on success.** There is no deletion code. This also preserves crash evidence and avoids claiming compiler-descendant termination from direct-child reaping. The production owner retains unresolved supervision; local abandonment cannot cancel its ownership obligation.
- P1–P4 `_exit` runs inside the existing I/O seam **after** the real completed boundary. P5 `_exit(85)` is immediately after `update` returns success: a narrow after-final-unlink boundary, not an arbitrary instruction-accurate crash before API return. No driver's success report is written on P1–P5 crash modes.

## Exact outcome matrix

Seed every initialized case by two fault-free child saves: a complete schema1 fixture (revision0), then threshold180/revision1, then threshold181/revision2. Preserve initial exact legacy bytes, revision1 bytes and revision2 bytes. Crash candidate is threshold211/revision3. Compare complete config values, exact bytes, file mode/device/inode where unchanged, immutable lock/store identity, marker fields/digests and complete directory membership.

| Boundary | Exact durable-prefix expectation before fresh reopen |
|---|---|
| Bootstrap death after real lock sync | Original legacy config exact; synchronized lock only; no store identity, backup, marker or staging; fresh child recoveryReadOnly, no envelope; denied update/preview preserve snapshot |
| P1 after marker directory sync | Config revision2 exact, backup revision1 exact, pending marker with exact revision2→3 hashes; no staging |
| P2 after backup staging file sync | Same config/backup, both exact candidate and old-config staging bytes, same marker |
| P3 after backup rename directory sync | Config revision2 exact, backup exact revision2; candidate stage remains, backup stage absent, marker remains |
| P4 after config rename directory sync | Config candidate revision3 exact, backup revision2 exact; no staging; marker remains |
| P5 after update success/final unlink | Config candidate revision3 exact, backup revision2 exact; no marker/staging; fresh child ordinary loaded revision3 |

P1–P4 fresh probe uses `SettingsStore(url:)`, never injected I/O. It must return recoveryReadOnly/nil envelope, reject update and preview with readOnlyRecovery, and leave every byte/name/mode/inode unchanged. P5 probe is read-only ordinary load, exact revision/config, without another edit. There is no power-loss claim or implicit recovery/finalization.

## Task 1: Complete parent RED and real owner fixture

**Files:** Create `TidyCore/Tests/TidyCoreTests/SettingsProcessAcceptanceTests.swift`; modify only the `TidyCoreTests` exclude list in `TidyCore/Package.swift`.

**Interfaces consumed:** Accepted SettingsStore public load/update/preview methods; internal `SettingsDecoding.encode(_:)`; accepted `ProcessRequest`, throwing `ProcessJobGate.init(limit:)`, `ProcessSession.launch(_:gate:identityCapture:)`, `observeOwnedExit(within:)`, `observationSnapshot()`, `abandonWithoutSignal()`, and `releaseStartByte()` from the T04.B supplement.

**Interfaces produced:** This private test file contains every parent helper. Its only external input is the checked-in driver path; every child argument and expected outcome is below.

- [ ] Add this complete test file before the driver. The initial RED is the natural missing checked-in driver, not deliberately unsafe production code.

```swift
import CryptoKit
import Darwin
import Foundation
import Testing
@testable import TidyCore

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
    SettingsEnvelope(schemaVersion: 2, revision: revision,
                     config: TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: days))
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
        let names = """
        Browsers/ChromiumCookieCleaner.swift Browsers/CookieDomainSuggester.swift
        Catalog/CleanCatalog.swift Catalog/CleanCatalog+Android.swift Catalog/CleanCatalog+Browsers.swift
        Catalog/CleanCatalog+DependencyCaches.swift Catalog/CleanCatalog+Extras.swift Catalog/CleanCatalog+Git.swift
        Catalog/CleanCatalog+Helpers.swift Catalog/CleanCatalog+Memory.swift Catalog/CleanCatalog+SafeCaches.swift
        Catalog/CleanCatalog+System.swift Catalog/CleanCatalog+Xcode.swift
        Detect/ContainerSpaceInfo.swift Detect/GitRepoScanner.swift Detect/GitRootDiscovery.swift
        Detect/LargestItemsScanner.swift Detect/LaunchAgentsSurvey.swift Detect/ProcessSurvey.swift
        Detect/RestartReclaimSurvey.swift Detect/SimctlClient.swift Detect/SnapshotLister.swift
        Detect/StaleNodeModulesScanner.swift Detect/ToolchainDetector.swift Detect/TranscriptPruneScanner.swift
        Detect/UnclaimedSpaceScanner.swift
        Engine/CleanEngine.swift Engine/ConfigStore.swift Engine/DefaultCustomActionExecutors.swift
        Engine/GitHousekeeper.swift Engine/MemoryReclaimer.swift Engine/RunLog.swift Engine/ScanEngine.swift
        Engine/SimulatorPruner.swift Engine/SnapshotDeleter.swift
        Exec/CleanupCommandRunner.swift Exec/ProcessRunner.swift Exec/ProcessSession.swift
        Exec/ProcessIdentity.swift Exec/ProcessJobGate.swift Exec/ToolLocator.swift
        Execution/CapabilityRegistry.swift Execution/ConfirmedPlan.swift Execution/ExecutionCoordinator.swift
        Execution/ExecutionPolicyBridge.swift Execution/GuardedFileDeleter.swift Execution/JournalPOSIXIO.swift
        Execution/JournalStorage.swift Execution/MutationAdmissionStore.swift Execution/PolicyInvalidationBarrier.swift
        Execution/ResourcePreflight.swift Execution/RunJournal.swift
        Measure/ByteFormat.swift Measure/DiskStats.swift Measure/HomeSurvey.swift Measure/MemoryStats.swift
        Measure/PathDisplay.swift Measure/SizeScanner.swift Measure/SwapStats.swift
        Model/ActionDescriptor.swift Model/CleanAction.swift Model/CleanCategory.swift Model/CleanEnvironment.swift
        Model/CleanItem.swift Model/CleanPlan.swift Model/PlanSelection.swift Model/ResourceIdentity.swift
        Model/RunReport.swift Model/ScanReport.swift Model/TargetPath.swift Model/TidyConfig.swift
        Model/Tier.swift Model/ToolchainID.swift
        Policy/SettingsEnvelope.swift Policy/SettingsPublication.swift Policy/SettingsStore.swift
        Safety/AppRunningCheck.swift Safety/PathGuard.swift Safety/PermissionBroker.swift
        """.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var sources = names.map { package.appendingPathComponent("Sources/TidyCore/\($0)") }
        sources.append(package.appendingPathComponent("Tests/TidyCoreTests/Fixtures/T05SettingsProcessDriver.swift"))
        var manifest: [String: String] = [:]
        for source in sources {
            manifest[source.path] = a2pHash(try a2pFile(source).data)
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
                    "-module-name", "TidySettingsProcessFixture"] + sources.map(\.path) + ["-lsqlite3", "-o", output.path]
        try a2pWrite(try JSONEncoder().encode(args), root.appendingPathComponent("compiler-arguments.json"))
        let compiler = try await ProcessSession.launch(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: args, environment: a2pEnvironment(root: root),
            kind: .readOnly, deadline: .seconds(120)), gate: ProcessJobGate(limit: 1), identityCapture: .failClosed)
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
        gate = try ProcessJobGate(limit: 2)
        guard mkdir(directory.path, 0o700) == 0 else { throw A2PError.invalid }
        try a2pWrite(a2pLegacy(), directory.appendingPathComponent("config.json"))
    }
    func launch(_ mode: String) async throws -> (ProcessSession, URL) {
        let control = root.appendingPathComponent(UUID().uuidString)
        guard mkdir(control.path, 0o700) == 0 else { throw A2PError.invalid }
        let session = try await ProcessSession.launch(ProcessRequest(executable: binary,
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
            let winner = try await run.launch(mode), loser = try await run.launch("contender")
            let winnerLoaded = try await run.wait(winner.1, "loaded.json")
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
            let priorBackup = try #require(before["config.backup.json"]?.data)
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
            #expect(files["config.backup.json"]?.data == (prefix >= 3 ? old : priorBackup))
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
```

- [ ] In `Package.swift`, replace only the accepted B exclude value with `exclude: ["Fixtures/T04ProcessFixture.c", "Fixtures/T05SettingsProcessDriver.swift"],` before the existing Config resources. Do not alter products, target linkage or resource handling.
- [ ] Controller runs the focused command below once the parent test file can compile against accepted B/A.2F. Expected natural RED: checked-in driver is absent (`A2PError.missing` before compiler dispatch); record that as fixture-absence RED, not a production behavioral regression. Zero selected tests is never RED/GREEN evidence.

```sh
cd /private/tmp/tidy-headroom.wUbV9h/TidyCore
swift test --filter SettingsProcessAcceptanceTests --jobs 2
```

## Task 2: Complete settings-only child and actual process evidence

**Files:** Create `TidyCore/Tests/TidyCoreTests/Fixtures/T05SettingsProcessDriver.swift` only.

**Interfaces consumed:** The actual production SettingsStore, SettingsDecoding, JournalPOSIXIO and DarwinJournalIO compiled into the same fixture module; no copied persistence code. All observation basenames are fixed protocol names. Existing final unlink remains entirely in production.

**Interfaces produced:** Exact CLI `MODE ROOT CONTROL_UUID`; modes `seed-one`, `seed-two`, `probe`, `bootstrap-hold`, `bootstrap-death`, `stable-hold`, `contender`, `once-contender`, and `p1`–`p5`; report filenames and exit codes match Task1.

- [ ] Add this complete child source. It never forks, spawns commands, calls app/tool APIs, signals another process, opens live settings, repairs files or deletes any fixture.

```swift
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
```

- [ ] Self-review the actual source before any launch: verify no new process launcher, sole external compiler request, child nonforking status, `_exit` restricted to the driver, `.failClosed` on both compiler/driver, no signals, no deletion, no catch that loses a returned session, and no blocking inherited-pipe read. Verify installed Darwin F_GETPATH/poll imports during the scheduled compile; compilation errors are not behavior evidence.
- [ ] Controller runs the same focused command. Expect three test methods with **eight parameterized executions**: two contention cases, one bootstrap-death case and five crash-prefix cases. Every case must run; no retries, skips or replaced same-process tests can satisfy the matrix. Correct A.2F may pass the first behavioral run; do not manufacture production faults for RED.
- [ ] If behavioral RED exposes an A.2F/B defect, retain the failing artifacts and return the exact failure to Controller. Production remediation requires a separate source assignment; A.2P does not expand its file ownership to make the test pass.
- [ ] Record per-case actual raw wait status, decoded exit, PID distinction for overlapping children, zero signal attempts, one consuming reap, retained root, complete bytes/names/inodes, marker matrix and fresh fault-free child outcome. Driver124/125/126, missing reports, unproven reaping, extra directory files or a mismatched prefix are failures, even if SettingsStore appears readable.
- [ ] Controller schedules the regression command below only after actual launcher source audit and focused success. B's original host-command tests remain under their existing separate execution audit.

```sh
cd /private/tmp/tidy-headroom.wUbV9h/TidyCore
swift test --filter 'SettingsMigrationTests|SettingsPublicationTests|SettingsProcessAcceptanceTests' --jobs 2
```

- [ ] Hand the allowlisted source diff and recorded evidence to Controller for independent adversarial source/acceptance review. Controller owns any commit. Do not run `git add`, commit, push, app launch, release, live migration, repair or app integration under this plan.

## Self-review and remaining gates

- Coverage: actual overlapping preloaded processes test both stable-lock and bootstrap contention; transient contention must not latch the loser, and winner success must invalidate its stale loaded bytes. A separate winner-death test preserves partial bootstrap and launches a fresh no-seam recovery reader. Five child exits and five fresh readers establish the exact P1–P5 retained-artifact matrix.
- No replacement proof: same-process actors, injected errno, marker existence alone, elapsed time, PID absence and process exit alone cannot satisfy these assertions. P5 is deliberately the allowed ordinary loaded state after real final unlink.
- No architecture/authority decision remains open in this proposal. Source eligibility still depends on accepted B and A.2F, the exact allowlist reconciliation, independent entry review and Controller assignment. Any material API/source-order mismatch returns to Controller instead of widening the seam.
- This document establishes no executed process acceptance, production readiness, policy-commit behavior, app crash recovery, physical power-loss durability, supported Intel/macOS14 evidence, T04.C acceptance or full T05 completion. A.3 and every later integration/release gate remain unchanged.
