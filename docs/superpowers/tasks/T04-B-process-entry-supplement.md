# T04.B process entry supplement

Documentation-only entry contract, independently reviewed READY on 2026-08-26; see `docs/verification/T04-B-entry-review.md`. Complements the original T04 B card; final Controller corrections in `.superpowers/sdd/T04.B-entry-proposal.md` supersede its old items 2/3/6. Controller assignment after T04.A approval is still required before source work or process tests. No accepted effect, recovery proof or new capability is authorized by this file. Full-program acceptance remains required before push/release.

## Reconciled exact interfaces

Retain unchanged original ProcessRequest, ProcessEnd, CapturedStream, BoundedProcessOutput, ProcessIdentity, ProcessJobGate and public run/runDiscardingOutput signatures. Replace/add only:

```swift
enum OwnedProcessExit: Equatable, Sendable {
    case reaped(ProcessInstanceIdentity, Int32) // actual RAW waitpid status
    case reapedWithoutIdentity(pid: Int32, status: Int32) // actual raw status, no identity claim
    case unproven
}
enum ProcessIdentityCapture: Sendable { case system, failClosed }
final class ProcessSession: @unchecked Sendable {
    static func launch(_ request: ProcessRequest, gate: ProcessJobGate,
                       identityCapture: ProcessIdentityCapture = .system) async throws -> ProcessSession
    var identity: ProcessInstanceIdentity? { get }
    func collect() async -> BoundedProcessOutput
    func releaseStartByte() throws
    func abandonWithoutSignal()
    func observeOwnedExit(within timeout: Duration) async -> OwnedProcessExit
    func observationSnapshot() -> ProcessSessionObservation
    static func validateChildWaitDisposition() throws
}
struct ProcessSessionObservation: Sendable {
    let ownedExit: OwnedProcessExit
    let signalAttempts: Int
    let consumingReapCount: Int
}
extension ProcessRunner {
    static func legacyOutput(_ output: BoundedProcessOutput) -> Output
}
// Add inside existing public Output:
// public let outputComplete: Bool
// public var succeeded: Bool { exitCode == 0 && !timedOut && outputComplete }
```

Snapshot is observation-only, reading actual locked production counters: signalAttempts increments immediately before the sole kill syscall; consumingReapCount increments only on successful exact-child consumption. No fake identity/reaper/signal provider. `validateChildWaitDisposition` is the same production pre-spawn read-only sigaction check: reject SIG_IGN/SA_NOCLDWAIT and detected incompatible arrangements, never change global disposition. `legacyOutput` is the pure mapper actually called by run, not a duplicate test mapper. All additions except Output remain internal.

Controller-requested fail-only identity dependency: `.system` calls the actual identity probe; `.failClosed` routes through that probe's unavailable-result handling after actual spawn. It can only suppress identity, never supply a positive identity, exit status, syscall result or authorization. Public run always uses `.system`; no environment flag or public caller selector. Both paths keep the same actual child owner/reaper and gate. Deterministic tests below validate nil identity and actual reaping without creating effect/recovery authority.

OwnedProcessExit stores raw waitpid status; `.exited(N)` and public exitCode store decoded normal exit code N. A normal exit 7 has raw status 1792, not legacy exitCode 1792. Signalled/non-normal termination maps legacy exitCode -1, never zero. Mutation collect remains uncertain without accepted reconciliation even when its direct child exited zero. Reaping does not clear mutation admission.

outputComplete requires both EOFs, no truncation, and strict UTF-8 decoding of both streams. Any incomplete/invalid stream means both legacy strings empty. Empty valid streams are complete. `.readOnlyTimedOut` maps timedOut=true only when the actual command deadline wins; drain deadline after a known exit yields incomplete output with timedOut=false. Other non-exited ends map exitCode=-1, not invented timeout. A timeout remains a timeout if subsequent reaping succeeds. Cache completed collect and owned-exit results; late timers cannot rewrite them.

## Concrete ownership review

The non-consuming waitid observer plus locked consuming waitpid/signal closes the **in-process coordinated** race: the observer blocks off the cooperative executor with no session lock; on a real matching exit-class siginfo it locks, consumes only that PID with WNOHANG, caches status and marks reaped before unlocking. Signal checks unreaped ownership, no exit/ownership error, nonnil identity and fresh full match under that same lock, which stays held through positive-PID SIGTERM. An exit in that interval leaves a zombie and cannot free its PID until the coordinated consuming wait. No group/SIGKILL or mutation/abandon signal. At most one SIGTERM attempt. Retry EINTR only; zero/ECHILD/other errors are unproven, never fabricated exits. Retain supervisor/accounting after collect/abandon/cancellation. No consuming wait in collect/teardown, no polling reaper, and no post-spawn error drops ownership.

**Reject concurrent blocking waitpid or an identity check outside the reap/signal lock.** Validate waitid's positive matching si_pid and exit si_code, not merely return zero. Installed Darwin import names must be checked at source entry. One observer thread per admitted job stays bounded by the shared two-slot gate; incomplete ownership retains its reservation. Read-only release occurs once after owned reap/local observation cleanup; mutation reservations remain retained pending higher recovery accounting.

The lock cannot protect against unrelated wait-any consumers/global SIGCHLD changes. Current source grep found no explicit such handler, but Foundation Process remains in ToolLocator and synchronous SimctlClient/SnapshotLister. This is a compatibility risk, **not a detected conflict or a demand to prove all closed-source internals**. Enter bounded implementation with the exact coexistence regression below and production auto-reap check. If an observed runtime consumes foreign children or enables auto-reap, fail closed, retain unproven accounting and block that arrangement before subsequent dispatch. Do not silently alter global signals. Current-host coexistence evidence does not replace macOS14/Intel acceptance.

Further required launcher corrections: normalize pipe originals to FD>=3 with CLOEXEC before dup2/close (host stdio may be closed); check every syscall/action; nonblocking only parent read/control endpoints, child stdout/stderr stay blocking; audit closure of unrelated inherited descriptors as well as the six originals using supported Darwin spawn facilities. Dispatch cancellation must own final FD close after queued handlers stop; closing/reusing an FD while a handler can read it is unsound. Bound each handler to four reads/64KiB total and retention to 1MiB per stream. Control G writes need reviewed descriptor-local Darwin SIGPIPE protection, not process-global SIGPIPE ignore. EPIPE/EAGAIN/error is failed release, never a deferred retry outside the release boundary. Source owner must verify exact supported Darwin APIs before implementation.

Exact reviewed Darwin choices: use `F_DUPFD_CLOEXEC` with minimum 3 for original-FD normalization; checked `POSIX_SPAWN_CLOEXEC_DEFAULT` with explicit stdio file actions to exclude unrelated inherited descriptors; and checked `fcntl(controlWrite, F_SETNOSIGPIPE, 1)` before control writes. The installed SDK declares these, and Apple's [fcntl manual](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/fcntl.2) documents descriptor-local pipe/socket SIGPIPE suppression. Accept waitid observations only for matching positive `si_pid` and `CLD_EXITED`, `CLD_KILLED` or `CLD_DUMPED`. See `.superpowers/sdd/T04.B-darwin-api-notes.md`. These choices were included in the independent review; actual Swift compilation and runtime/device evidence remain implementation obligations.

## Fixture/package delta

Keep original flood/orphan/gated/slow modes, timings, observer acknowledgement and lifetime rules unchanged. Insert these complete branches inside main before flood:

```c
    if (!strcmp(argv[1], "exit-zero")) return 0;
    if (!strcmp(argv[1], "exit-seven")) return 7;
    if (!strcmp(argv[1], "coexist-seven")) { pause_ms(1500); return 7; }
    if (!strcmp(argv[1], "text")) {
        if (write(1, "out\n", 4) != 4 || write(2, "err\n", 4) != 4) return 93;
        return 0;
    }
    if (!strcmp(argv[1], "invalid-stdout")) {
        const unsigned char bad[] = { 0xC3, 0x28 };
        if (write(1, bad, sizeof(bad)) != sizeof(bad) || write(2, "err\n", 4) != 4) return 93;
        return 0;
    }
    if (!strcmp(argv[1], "invalid-stderr")) {
        const unsigned char bad[] = { 0xFF };
        if (write(1, "out\n", 4) != 4 || write(2, bad, sizeof(bad)) != sizeof(bad)) return 93;
        return 0;
    }
```

Package testTarget changes only by adding `exclude: ["Fixtures/T04ProcessFixture.c"]` before its existing `resources: [.copy("Fixtures/Config")]`. Never exclude all Fixtures. Compile only the checked-in fixture via the original clang request in UUID build scratch. Build artifacts remain preserved; no marker/time/PID-absence cleanup and no teardown signals.

## Complete changed test helpers

Add the following to the original B test file. Darwin raw-status bit interpretation must be checked against the installed SDK before source entry; C function-like WIFEXITED/WEXITSTATUS may not import into Swift.

```swift
private func requireOwnedStatus(_ session: ProcessSession) async throws -> Int32 {
    switch await session.observeOwnedExit(within: .seconds(6)) {
    case .reaped(let identity, let raw):
        try #require(session.identity == identity)
        return raw
    case .reapedWithoutIdentity(let pid, let raw):
        try #require(session.identity == nil && pid > 0)
        return raw
    case .unproven: throw FixtureError.observationIncomplete
    }
}
private func expectNormalExit(_ raw: Int32, code: Int32) {
    #expect((raw & 0x7f) == 0)
    #expect(((raw >> 8) & 0xff) == code)
}
private final class FoundationExitWitness: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var status: Int32?
    init(executable: URL, root: URL) throws {
        process.executableURL = executable
        process.arguments = ["coexist-seven", root.path]
        process.environment = ["HOME": root.path, "PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Retain witness/process until real Foundation termination; timeout never kills it.
        process.terminationHandler = { [self] child in
            lock.lock()
            status = child.terminationReason == .exit ? child.terminationStatus : -1
            lock.unlock()
            child.terminationHandler = nil
        }
        do { try process.run() }
        catch { process.terminationHandler = nil; throw error }
    }
    func observed() -> Int32? { lock.lock(); defer { lock.unlock() }; return status }
    func exit(within timeout: Duration) async throws -> Int32 {
        let until = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < until {
            if let value = observed() { return value }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw FixtureError.observationIncomplete
    }
}
```

Replace original ProcessScratch.launch, registerOrphanBeforeParentExit and dispose with:

```swift
    func launch(_ request: ProcessRequest, gate: ProcessJobGate,
                identityCapture: ProcessIdentityCapture = .system) async throws -> ProcessSession {
        do {
            let session = try await ProcessSession.launch(request, gate: gate,
                                                          identityCapture: identityCapture)
            add(session, orphan: request.arguments.first == "orphan")
            return session
        } catch is CancellationError {
            throw CancellationError() // contract: only before actual spawn
        } catch { markAmbiguousLaunch(); throw error }
    }
    func registerOrphanBeforeParentExit(_ session: ProcessSession) async throws {
        try await waitFor("descendant.pid")
        let text = try String(contentsOf: root.appendingPathComponent("descendant.pid"), encoding: .utf8)
        guard let pid = Int32(text), pid > 0 else { throw FixtureError.observationIncomplete }
        let parent = try #require(session.identity)
        let watch = try FixtureExitWatch(pid: pid, executable: binary, parent: parent)
        retain(watch)
        try Data("observing".utf8).write(to: root.appendingPathComponent("descendant-observed"))
    }
    func dispose() async throws {
        let (owned, descendants, incomplete) = tracked()
        var proven = !incomplete
        for session in owned {
            do { _ = try await requireOwnedStatus(session) }
            catch { proven = false }
        }
        for watch in descendants {
            let exited = (try? await watch.observeExit(within: .seconds(6))) ?? false
            proven = proven && exited
        }
        guard proven else {
            Issue.record("Fixture exit not proven; preserved run scratch: \(root.path)")
            throw FixtureError.observationIncomplete
        }
        try FileManager.default.removeItem(at: root)
    }
```

Identity-less owned reaping permits nonforking fixture teardown only; original unobservedDescendants/ambiguousLaunch flags and registered NOTE_EXIT requirements remain. Other precise original edits:

- mutatingTimeoutLeavesActualChildRunning: replace matches(session.identity) with `let identity = try #require(session.identity)` then `#expect(ProcessIdentity.matches(identity))`.
- abandonmentBeforeReleaseDoesNotPerformFixtureEffect: replace observe/guard block with `expectNormalExit(try await requireOwnedStatus(session), code: 96)`; preserve absent-effect assertion.
- realSurvivingChildKeepsReopenedCoordinatorBlocked: replace child binding with `let child = try #require(session.identity)`; keep all journal/unknown-adapter blocking assertions.
- reusedPIDShapeCannotMatchActualIdentity: use `let actual = try #require(session.identity)`; no real PID-reuse claim.

All other original B tests remain, including flood, surviving mutation/orphan, both abandonment windows, queued cancellation, FIFO/cancel-transfer stress and aggregate public gate. The following complete additions go inside the original serialized suite.

```swift
    @Test(arguments: [("exit-zero", Int32(0)), ("exit-seven", Int32(7))])
    func identityCaptureFailureStillReapsActualFastChild(_ item: (String, Int32)) async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request(item.0, .readOnly),
                gate: ProcessJobGate(limit: 1), identityCapture: .failClosed)
            #expect(session.identity == nil)
            let output = await session.collect()
            #expect(output.identity == nil && output.end == .exited(item.1))
            let first = await session.observeOwnedExit(within: .seconds(6))
            guard case .reapedWithoutIdentity(let pid, let raw) = first else {
                throw FixtureError.observationIncomplete
            }
            #expect(pid > 0)
            expectNormalExit(raw, code: item.1)
            #expect(await session.observeOwnedExit(within: .zero) == first)
            #expect(session.observationSnapshot().consumingReapCount == 1)
            #expect(session.observationSnapshot().signalAttempts == 0)
        }
    }
    @Test func identityCaptureFailureCannotSignalAtDeadline() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("slow", .readOnly, seconds: 0.2),
                gate: ProcessJobGate(limit: 1), identityCapture: .failClosed)
            let output = await session.collect()
            #expect(output.end == .readOnlyTimedOut && output.identity == nil)
            #expect(session.observationSnapshot().signalAttempts == 0)
            try await s.waitFor("done")
            expectNormalExit(try await requireOwnedStatus(session), code: 0)
            #expect(session.observationSnapshot().signalAttempts == 0)
            #expect(session.observationSnapshot().consumingReapCount == 1)
        }
    }
    @Test(arguments: [("exit-zero", Int32(0)), ("exit-seven", Int32(7))])
    func actualFastExitIsCached(_ item: (String, Int32)) async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request(item.0, .readOnly), gate: ProcessJobGate(limit: 1))
            let output = await session.collect()
            #expect(output.end == .exited(item.1))
            #expect(output.identity == session.identity)
            #expect(output.stdout.eofObserved && output.stderr.eofObserved)
            #expect(output.stdout.bytes.isEmpty && output.stderr.bytes.isEmpty)
            #expect(!output.stdout.truncated && !output.stderr.truncated)
            let first = await session.observeOwnedExit(within: .seconds(6))
            expectNormalExit(try await requireOwnedStatus(session), code: item.1)
            #expect(await session.observeOwnedExit(within: .zero) == first)
            let snapshot = session.observationSnapshot()
            #expect(snapshot.ownedExit == first && snapshot.consumingReapCount == 1)
            #expect(snapshot.signalAttempts == 0)
            let legacy = ProcessRunner.legacyOutput(output)
            #expect(legacy.exitCode == item.1 && legacy.outputComplete && !legacy.timedOut)
            #expect(legacy.succeeded == (item.1 == 0))
        }
    }
    @Test func reapedChildCannotSignalAtLaterDeadline() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("exit-zero", .readOnly, seconds: 0.5),
                                             gate: ProcessJobGate(limit: 1))
            #expect(await session.collect().end == .exited(0))
            _ = try await requireOwnedStatus(session)
            let before = session.observationSnapshot()
            try #require(before.consumingReapCount == 1)
            session.abandonWithoutSignal()
            try await Task.sleep(for: .milliseconds(600))
            #expect(await session.observeOwnedExit(within: .zero) == before.ownedExit)
            let after = session.observationSnapshot()
            #expect(after.consumingReapCount == 1 && after.signalAttempts == 0)
            #expect(await session.collect().end == .exited(0))
        }
    }
    @Test(arguments: ["text", "invalid-stdout", "invalid-stderr", "flood"])
    func realOutputIsBoundedAndTruthful(_ mode: String) async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request(mode, .readOnly, seconds: 15),
                                             gate: ProcessJobGate(limit: 1))
            let captured = await session.collect()
            #expect(captured.end == .exited(0))
            #expect(captured.stdout.eofObserved && captured.stderr.eofObserved)
            #expect(captured.stdout.bytes.count <= 1_048_576 && captured.stderr.bytes.count <= 1_048_576)
            let output = ProcessRunner.legacyOutput(captured)
            #expect(output.exitCode == 0 && !output.timedOut)
            if mode == "text" {
                #expect(output.outputComplete && output.succeeded)
                #expect(output.standardOutput == "out\n" && output.standardError == "err\n")
            } else {
                #expect(!output.outputComplete && !output.succeeded)
                #expect(output.standardOutput.isEmpty && output.standardError.isEmpty)
            }
            if mode == "flood" {
                #expect(captured.stdout.bytes.count == 1_048_576 && captured.stderr.bytes.count == 1_048_576)
                #expect(captured.stdout.truncated && captured.stderr.truncated)
            } else { #expect(!captured.stdout.truncated && !captured.stderr.truncated) }
            if mode == "invalid-stdout" { #expect(captured.stdout.bytes == Data([0xC3, 0x28])) }
            if mode == "invalid-stderr" { #expect(captured.stderr.bytes == Data([0xFF])) }
            expectNormalExit(try await requireOwnedStatus(session), code: 0)
        }
    }
    @Test func inheritedPipeDeadlineIsNotCommandTimeout() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("orphan", .readOnly, seconds: 8),
                                             gate: ProcessJobGate(limit: 1))
            try await s.registerOrphanBeforeParentExit(session)
            let start = ContinuousClock.now
            let captured = await session.collect()
            #expect(start.duration(to: .now) < .seconds(1))
            #expect(captured.end == .exited(0))
            #expect(!captured.stdout.eofObserved || !captured.stderr.eofObserved)
            let output = ProcessRunner.legacyOutput(captured)
            #expect(!output.outputComplete && !output.succeeded && !output.timedOut)
            #expect(output.standardOutput.isEmpty && output.standardError.isEmpty)
            try await s.waitFor("done") // dispose still requires registered NOTE_EXIT
        }
    }
    @Test(arguments: ["exit-zero", "exit-seven", "text", "flood", "invalid-stdout", "invalid-stderr"])
    func publicRunnerUsesTruthfulMapping(_ mode: String) async throws {
        let s = try await ProcessScratch()
        defer { print("Retained public mapping evidence: \(s.root.path)") }
        let output = try await ProcessRunner.run(executableURL: s.binary,
            arguments: [mode, s.root.path], environment: ["HOME": s.root.path, "PATH": "/usr/bin:/bin"], timeout: 15)
        #expect(!output.timedOut && output.exitCode == (mode == "exit-seven" ? 7 : 0))
        let complete = ["exit-zero", "exit-seven", "text"].contains(mode)
        #expect(output.outputComplete == complete)
        #expect(output.succeeded == (complete && mode != "exit-seven"))
        if mode == "text" {
            #expect(output.standardOutput == "out\n" && output.standardError == "err\n")
        } else { #expect(output.standardOutput.isEmpty && output.standardError.isEmpty) }
    }
    @Test func actualCommandDeadlineIsTimedOut() async throws {
        let s = try await ProcessScratch()
        defer { print("Retained public deadline evidence: \(s.root.path)") }
        let start = ContinuousClock.now
        let output = try await ProcessRunner.run(executableURL: s.binary,
            arguments: ["slow", s.root.path], environment: ["HOME": s.root.path, "PATH": "/usr/bin:/bin"], timeout: 0.2)
        #expect(start.duration(to: .now) < .seconds(1))
        #expect(output.timedOut && !output.succeeded)
        // No assertion that timeout kills a process tree or implies missing EOF.
    }
    @Test func foundationAndPOSIXChildrenKeepDistinctExitOwnership() async throws {
        let s = try await ProcessScratch()
        defer { print("Retained Foundation coexistence evidence: \(s.root.path)") }
        try ProcessSession.validateChildWaitDisposition()
        let foundation = try FoundationExitWitness(executable: s.binary, root: s.root)
        try ProcessSession.validateChildWaitDisposition()
        let session = try await s.launch(s.request("slow", .readOnly, seconds: 8),
                                         gate: ProcessJobGate(limit: 1))
        #expect(await session.collect().end == .exited(0))
        expectNormalExit(try await requireOwnedStatus(session), code: 0)
        #expect(try await foundation.exit(within: .seconds(6)) == 7)
        let snapshot = session.observationSnapshot()
        #expect(snapshot.consumingReapCount == 1 && snapshot.signalAttempts == 0)
        try ProcessSession.validateChildWaitDisposition()
        // No wait-any, no direct consuming wait outside the production owner.
    }
    @Test func incompleteMappingNeverFabricatesTimeout() {
        // Pure representation test: NOT executed-child or recovery evidence.
        let empty = CapturedStream(bytes: Data(), truncated: false, eofObserved: true)
        let cases = [
            CapturedStream(bytes: Data("prefix".utf8), truncated: false, eofObserved: false),
            CapturedStream(bytes: Data("prefix".utf8), truncated: true, eofObserved: true),
            CapturedStream(bytes: Data([0xFF]), truncated: false, eofObserved: true)
        ]
        for stream in cases {
            for stdout in [true, false] {
                let output = ProcessRunner.legacyOutput(BoundedProcessOutput(end: .exited(0),
                    stdout: stdout ? stream : empty, stderr: stdout ? empty : stream, identity: nil))
                #expect(!output.outputComplete && !output.timedOut && !output.succeeded)
                #expect(output.standardOutput.isEmpty && output.standardError.isEmpty)
            }
        }
        let timed = ProcessRunner.legacyOutput(BoundedProcessOutput(end: .readOnlyTimedOut,
            stdout: empty, stderr: empty, identity: nil))
        #expect(timed.timedOut && !timed.succeeded && timed.outputComplete)
    }
```

System-probe fast tests permit identity present or absent; scheduler speed cannot guarantee capture failure. The separate fail-only dependency tests deterministically exercise the production unavailable-identity path using actual children and actual reaping, not seeded exits. Source review must verify identity failure never authorizes signals or loses ownership. Counter tests require independent source review of the sole actual kill site; counters alone cannot prove absence of an uninstrumented kill path.

## Inspected boundaries and unexecuted gates

### Implementation-time fixture sequencing clarification

The controller's actual source audit precedes child execution. During the first run, `mutatingTimeoutLeavesActualChildRunning` returned uncertainty at its unchanged0.2s deadline before the cold fixture reached its alive marker. A diagnostic-only repeat observed launch0.003528s, collection0.215808s with no marker and zero signals, then actual normal reaping after done1.923769s. Keep launch→collect→uncertain assertion first, then add the existing bounded `waitFor("alive")` before the original alive/not-done/identity assertions. Keep every original deadline/assertion and require zero signal attempts before and after the actual normal-exit proof. This is post-timeout readiness observation, not marker-based teardown or a raised command deadline. Original done/exact reap/descendant teardown requirements stand.

The Foundation coexistence method now runs exactly two parameterized cases, Foundation-first and POSIX-first, with one shared assertion body and separate retained roots; no repeated stress loop. Current-host success is not all-runtime compatibility. For complete package coverage run the entire B suite in isolation, then all non-B tests; unrelated discovery launches must not affect the prescribed global-gate counts. Record both exact counts/commands and never describe this partition as a single default-parallel run.

Current ProcessRunner has detached blocking readers, Process.isRunning polling, PID-only SIGKILL and a four-slot gate; replace them rather than wrap them. Async ContainerSpaceInfo, ProcessSurvey, SnapshotLister and both SimctlClient methods check succeeded before parsing, so truthful outputComplete closes their partial-success path. Synchronous discovery remains T08.

MemoryReclaimer, SimulatorPruner, SnapshotDeleter and GitHousekeeper remain fixed-denied before calling injected transports. SystemCleanupCommandRunner itself is a public executable transport, not a fixed-denial implementation; preserve its callers' quarantine and do not misdescribe it as intrinsically incapable of executing commands. B adds no mutation selector/capability.

Public/Foundation tests intentionally retain run roots because they are not handled by per-session teardown. Original compiler build artifacts remain retained. Original host-command ProcessRunnerTests require a separate execution audit; their “timeout is killed” wording is obsolete, not an acceptance requirement. No tests/builds/processes/signals ran while preparing this file. Controller review/source assignment, Darwin API validation, actual supported OS/architecture evidence, compile-negative access checks and full-program integration remain outstanding.
