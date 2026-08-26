# T05 A.3 Atomic App Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans after Controller assignment and independent entry review. Steps use checkbox (`- [ ]`) syntax for tracking. This is a documentation-only entry proposal, not source-entry approval or test evidence.

**Goal:** Replace every legacy app settings reader/writer atomically with the accepted SettingsStore, preserve the existing coordinator ticket barrier across off-main persistence, and present historical measurement availability truthfully.

**Architecture:** One app-lifetime bootstrap loads the actual SettingsStore and constructs the actual ExecutionCoordinator off MainActor. Its one MainActor AppExecutionServices owns the real bridge and shared AppConfigStore; per-window review lifetimes never own persistence. Tests use the existing unhosted XCTest target and existing internal JournalPOSIXIO injection, observing/pausing real I/O rather than substituting success or authority.

**Tech Stack:** Native Swift/SwiftUI/Observation, XCTest and the existing Swift Testing package suites, Foundation/Darwin, macOS 14+, local TidyCore only.

## Global Constraints

- Native Swift/SwiftUI, macOS 14+, local TidyCore package, zero third-party runtime dependencies.
- Intel x86_64 and Apple Silicon arm64 supported; both require build and device evidence.
- No internet requests, telemetry, remote updates, repository fetches, model downloads, or remote package dependencies at runtime.
- Local IPC to an explicitly identified local tool service is allowed. No remote Docker contexts, TCP endpoints, SSH endpoints, or daemon auto-start during discovery.
- No repository deletion, database deletion, Docker volume deletion, local-model deletion, generic duplicate-file deletion, arbitrary scripts, or automatic force-quitting.
- No kernel tuning, swap-file manipulation, launch-agent disabling, privileged persistent helper, or changes to other tools' settings.
- No full-home scans on popover open or timers. No repository-supplied executable/config evaluation merely to discover a project.
- No change to signing, publishing, deployment, or remote Git state is authorized by this document.

PRODUCT.md, design S01–S16, the registry/adapter appendix, the entire T02 sealed-execution contract, its accepted app-confirmation card, and T05's original requirements remain binding. This card closes the **entry-design gap** identified in T05 lines1518–1613; it does not waive A.2P, native-dialog, supported-OS/device or accepted-adapter gates. Import limits remain1MiB/depth16/profiles50/list1000/string4096, rejecting invalid UTF-8, duplicate keys and overflow. Unknown IDs/names/paths remain inert; no registry resolver, consent, local authorization or execution capability is added.

## Prerequisites and precise delivery boundary

1. A.1/A.2F and their correction are accepted through `63dc0f4`; read the current accepted source again before source entry. Actual A.2P process tests remain dependent on the in-progress T04.B owner/reaper and then A.2P acceptance. The reviewed A.2P card is not actual A.2P evidence.
2. **A.3 source remains blocked until accepted A.2P and independent T02 integration/entry review.** Controller must also serialize source ownership and compiler jobs; this document authorizes no concurrent edits to T04.B process files.
3. This A.3 unit is off-main settings/bootstrap, shared app-model wiring and pure report presentation. It does **not** require B.1's stable-OS AX run or B.2's first accepted `.M` adapter merely to implement/test this unit. Those remain separate acceptance gates, not completed or waived by A.3. No positive cleanup, successful mutation, native-dialog callback ordering, Intel/macOS14 device or full T05 claim follows.
4. No production app launch, live settings write, fake HOME/environment rewrite, disposable home chosen by a production default, signed artifact, Git write or source/test/build execution occurred while preparing this card. Commands below are **NOT EXECUTED**.

## Actual source findings and atomic file ownership

Inspection found `ExecutionPolicyBridge.submit` currently calls synchronous `ConfigStore.save` in a MainActor-inheriting Task; TidyApp synchronously loads fallback settings and constructs the journal; ScanViewModel independently calls `ConfigStore.load().makeEnvironment`; ScanView automatically calls that scan in `.task`; CleanResultsView reads compatibility `totalReclaimedMemoryBytes > 0`. All join this cutover. The existing unhosted model target is XCTest, with six explicit production/test source entries, empty TEST_HOST/BUNDLE_LOADER and no TidyApp import/launch.

Future A.3 ownership is exactly this allowlist; source changes require a separate assignment:

| File | Change/responsibility |
|---|---|
| `TidyCore/Sources/TidyCore/Execution/ExecutionPolicyBridge.swift` | Replace URL/ConfigStore dependency with sole loaded SettingsStore; bounded ordered submissions, durable revision observation and drain; preserve original opaque coordinator tickets |
| `TidyCore/Sources/TidyCore/Engine/ConfigStore.swift` | Delete legacy fallback loader, writer, default-path API and ConfigSaveError together; no public/raw compatibility bypass remains |
| `TidyCore/Sources/TidyCore/Model/TidyConfig.swift` | Change `currentSchemaVersion` from1 to2 **only in this atomic cutover**; preserve pure projection and historical explicit schema1 fixtures |
| `Tidy/Execution/AppExecutionServices.swift` | Actual off-main factory, explicit paths, app-lifetime bootstrap state, read-only recovery/journal state, shared services; retain actual AppReviewSession |
| `Tidy/Settings/AppConfigStore.swift` | Keep actual `config.didSet { bridge.submit(config: config) }`; no I/O/projection/discovery in setter or its argument evaluation |
| `Tidy/TidyApp.swift` | Resolve production paths explicitly once, own one bootstrap state, show loading/recovery and pass identical services to all scenes |
| `Tidy/MenuBar/MenuBarContentView.swift` | Remove `hasCheckedOnboarding`, `checkOnboardingOnce()` and its `.onAppear` call; when onboarding is unfinished show an explicit `Set up Tidy…` button that opens the existing `WindowID.onboarding` only on that button's click |
| `Tidy/Scan/ScanViewModel.swift`, `Tidy/Scan/ScanView.swift` | Consume shared service config/path rather than fallback loader; remove auto-scan `.task`; explicit scan only and unknown tools `[]`, no `makeEnvironment` detector call |
| `Tidy/Clean/RunReportPresentation.swift` (new) | Pure availability/text projection actually consumed by CleanResultsView; no authority or I/O |
| `Tidy/Clean/CleanResultsView.swift` | Consume the projection, preserve T02 no-op/denial text and distinct disk/memory accounting |
| `TidyAppModelTests/SharedSettingsWiringTests.swift` (new) | Complete XCTest RED below, including real publication pause, bootstrap, failure, queue and shared-window tests |
| `TidyAppModelTests/RunReportPresentationTests.swift` (new) | Complete presentation RED below |
| `TidyAppModelTests/ConfirmationLifecycleTests.swift` | Migrate existing scratch service helper/calls and saved-value assertion; retain every accepted lifecycle/denial assertion |
| `TidyCore/Tests/TidyCoreTests/ConfigStoreTests.swift` | Replace the four obsolete loader/writer tests with recoverable SettingsStore tests, retain both TidyConfig tests |
| `TidyCore/Tests/TidyCoreTests/ConfirmedExecutionTests.swift` | Migrate `persistPolicy`, `settingsSaveFailureBlocksBridge`, `settingsSubmissionHasNoDiscoveryPhase`, `overlappingPolicyUpdates` together; retain token/error/revision/denial assertions |
| `project.yml`, generated `Tidy.xcodeproj/project.pbxproj`, generated `Tidy.xcodeproj/xcshareddata/xcschemes/TidyAppModelTests.xcscheme` | Add only the three named new test/presentation source entries to the existing unhosted target; preserve all unrelated generated content |

SettingsStore, SettingsPublication, SettingsEnvelope, JournalPOSIXIO, coordinator/token/barrier implementation, manual host, SafetyHost, process files, package dependencies/resources and T06 policy are **not A.3 write ownership**. If accepted source needs a change there, stop for a narrow Controller amendment. Existing internal SettingsStore initializer is sufficient; do not make JournalPOSIXIO or its initializer public, add a shipping test flag, or copy core source into an alternate test module.

### Exact interfaces consumed and produced

Consumed, as currently present:

```swift
// TidyCore; ordinary production entry, no I/O in initializer.
public actor SettingsStore {
    public init(url: URL)
    internal init(url: URL, io: any JournalPOSIXIO)
    public func load() -> SettingsLoadResult
    public func update(expectedRevision: UInt64, change: SettingsChange) throws -> SettingsEnvelope
    internal func lastPublicationFailure() -> SettingsPublicationFailure?
}
// Actor calls above require await. JournalPOSIXIO/DarwinJournalIO stay internal.
// SettingsStore has no policy authority; a returned SettingsEnvelope is storage data.
ExecutionCoordinator.beginPolicyUpdate() throws -> PolicyUpdateTicket // nonisolated
ExecutionCoordinator.policyAdmission() -> PolicyAdmission // nonisolated
ExecutionCoordinator.commitPolicyUpdate(_:environment:) throws -> PolicyCommit // internal, actor-isolated
ExecutionCoordinator.mutationAdmission() -> MutationAdmission // actor-isolated
ExecutionPolicyBridge.submit(config: TidyConfig) -> Task<Void, Never> // synchronous
```

Produced (declarations specify the implementation contract, not landed source):

```swift
// Same public core bridge, never a second coordinator/resolver.
ExecutionPolicyBridge.init(coordinator: ExecutionCoordinator, settings: SettingsStore,
    loaded: SettingsLoadResult, homeDirectory: String, detectedTools: Set<ToolchainID>)
ExecutionPolicyBridge.durableSettingsRevision: UInt64? // public private(set)
ExecutionPolicyBridge.drain() async
ExecutionPolicyBridge.pendingSnapshotCount: Int // internal private(set), active included
ExecutionPolicyBridge.pendingSnapshotBytes: Int // internal private(set), validated JSON bytes
// Keep public updateGeneration, isExecutionEnabled, policyUpdatePending, persistenceError.

// App-internal; explicit values, no default paths, filesystem work or discovery.
struct AppStoragePaths: Sendable {
    let home: URL
    let settings: URL // SettingsStore requires leaf exactly config.json
    let journal: URL
}
enum AppBootstrapStage: String, Sendable {
    case beforeSettingsLoad, afterSettingsLoad
    case beforeCoordinatorConstruction, afterCoordinatorConstruction
}
@MainActor final class AppExecutionServices {
    static func bootstrap(paths: AppStoragePaths) async -> AppExecutionServices
    // App-internal overload for the existing real store and observation only.
    static func bootstrap(paths: AppStoragePaths, settings: SettingsStore,
        observe: @escaping @Sendable (AppBootstrapStage) -> Void) async -> AppExecutionServices
    let paths: AppStoragePaths
    let settings: SettingsStore
    let settingsLoad: SettingsLoadResult
    let initialJournalAdmission: MutationAdmission
    let coordinator: ExecutionCoordinator
    let policyBridge: ExecutionPolicyBridge
    let configStore: AppConfigStore
    let engine: CleanEngine
    let runLogURL: URL
}
@MainActor final class AppBootstrapState {
    enum Status: Equatable { case notStarted, loading, ready, recovery, unavailable }
    private(set) var status: Status
    private(set) var services: AppExecutionServices?
    func start(paths: AppStoragePaths) -> Task<Void, Never>
    func start(paths: AppStoragePaths, settings: SettingsStore,
        observe: @escaping @Sendable (AppBootstrapStage) -> Void) -> Task<Void, Never>
    func storagePathUnavailable() // no service or Task is created
}
struct RunReportPresentation {
    init(report: RunReport)
    let measurementsAvailable: Bool
    let memoryText: String
    let admissionMessage: String?
}
```

All app classes retain/add Observation as required by actual SwiftUI state. The injectable overload is app-internal and uses the supplied **actual** SettingsStore; it accepts neither loaded-success data nor a factory returning fake services/coordinator. Production calls the paths-only overload, constructs exactly one `SettingsStore(url: paths.settings)`, and never supplies an observer. Tests use `@testable import TidyCore` in the Debug unhosted target to access the **existing** internal `SettingsStore(url:io:)`, `JournalPOSIXIO`, `DarwinJournalIO` and diagnostic. Verify the local package is actually compiled with testability before behavioral RED; a missing module/testability error is a build-configuration gate, not a reason to publicize APIs or claim behavior. Do not change Release settings to enable testability.

### Bootstrap and path contract

- AppBootstrapState begins `.notStarted` with nil services. Its first `start` synchronously sets `.loading`, retains its completion task and calls the actual factory. Later starts, including those caused by another scene or reopening the popover, join that same task/instance, never construct another store. No service/default-enabled interval exists before completion.
- The factory performs its storage work in `Task.detached` (or a separately reviewed non-MainActor worker with equivalent evidence), **not** `Task {}` inheriting MainActor. Place observer callbacks immediately before/after `await settings.load()` and immediately before/after the real synchronous `ExecutionCoordinator(environment:journalDirectory:)` construction inside that off-main operation. Observer has Void return, cannot replace inputs/results, and does nothing in production. The actor load executes on its own executor; persistence instrumentation below additionally observes actual POSIX publication.
- Construct the coordinator using only the successfully loaded envelope's pure `makePolicyEnvironment(homeDirectory: paths.home.path, detectedTools: [])`. Recovery has no usable envelope: a conservative schema2 display-only projection may populate disabled controls, but the bridge must synchronously begin an uncommittable update before services are published. Recovery edits remain rejected/read-only; a placeholder value never becomes persisted or policy authority. `durableSettingsRevision == nil` in recovery.
- Await the real coordinator's `mutationAdmission()` in the off-main factory, store its result, and expose service `isExecutionEnabled` only when settings are usable, bridge enabled and journal admission was `.ready`. Journal unavailable/recovery must produce visible `.recovery`, never successful startup. Existing coordinator checks remain authoritative against later journal changes. A settings save cannot repair/clear the journal or make a service with failed initial journal admission enabled.
- Settings load creates no parents/config/metadata. Missing file plus absent auxiliary state is genuine `.newDefaults`/revision0, not recovery; known schema2 with no store metadata remains a read-only valid load. The **real journal constructor** may create its explicit no-follow owner-only journal path/parents off-main. This is the sole bootstrap path creation, not generic `FileManager.createDirectory` recovery. Production settings and journal share application-support ancestry; verify the real missing-common-parent case below. Settings metadata/config are first created only by an explicit validated edit. Corrupt/future/partial initialized settings are preserved and never repaired.
- Production TidyApp resolves `NSHomeDirectory()` and `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first` once in its explicit production path factory. Pass `base/Tidy/config.json` and `base/Tidy/execution`; absence of a valid absolute home/support URL shows unavailable with no bootstrap. No ConfigStore.defaultURL, environment mutation, fake-home fallback, scratch path, directory creation or settings read belongs to TidyApp init. All injected paths are explicit and production has no test arguments.
- Every scene uses the same State-owned bootstrap object. Loading shows only loading; recovery shows explanation/read-only data, no actionable settings/reset or review/confirmation. No onboarding, suggestions, scan, detector, locator, Process, makeEnvironment or auto-discovery Task runs during startup/setters. Remove ScanView's automatic `.task`; only its explicit button uses shared config and `makePolicyEnvironment(... detectedTools: [])`. T08 remains responsible for accepted discovery, not this patch.
- `MenuBarContentView` is also part of this startup boundary. Its `.onAppear` may refresh the existing local stats only; it must not open onboarding, inspect onboarding completion or call any helper that can do so. Delete `hasCheckedOnboarding` and `checkOnboardingOnce()` rather than retaining a latent automatic route. If `configStore.config.hasCompletedOnboarding == false`, render an explicit `Set up Tidy…` button whose action alone calls the existing `open(WindowID.onboarding)`. That click preserves reachability of the existing Welcome window; its user-initiated `OnboardingView.onAppear` → `OnboardingViewModel.start()` → `ToolchainDetector.detect()` route remains T08-bound manual onboarding/detection work and is neither startup behavior nor an A.3 discovery fix.

### Bridge ordering, capacity and error contract

1. Every submit, including identical/invalid/overflow/recovery edits, synchronously sets disabled, changes observable updateGeneration and calls **the existing** `beginPolicyUpdate()` before projection, validation/encoding, Task creation or await. Its original ticket is retained; no caller-provided policy revision or success callback exists.
2. Bound admitted outstanding snapshots, **including the active write**, to32. Validate each complete settings snapshot with the existing bounded SettingsDecoding encoder, using revision UInt64.max for worst-case envelope digit overhead, before retaining it in the chain; each snapshot is at most1,048,576 encoded bytes, total logical snapshot bytes at most33,554,432. This is an encoded-data bound, not a universal heap/RSS or synchronous filesystem latency bound. Do not capture rejected configs in a returned Task or accumulate rejected task-chain nodes.
3. The synchronous validation/projection is pure bounded CPU work. Queue admission must not bypass the store's own authoritative validation. Invalid/oversized requests show a failure and leave admission updating without disk writes. Overflow returns a completion handle joined to the admitted tail, shows exactly `Settings changes are pending; wait and save again.`, and retains no snapshot. It invalidates the latest ticket/generation even while prior32 drain; their actual success cannot re-enable it. There is no acknowledgment that the rejected33rd edit was saved, automatic retry/coalescing, silent drop of admitted edits or automatic error clearing.
4. Each admitted Task awaits the preceding admitted Task, then calls `await settings.update(expectedRevision: lastSuccessfullyPersistedRevision, change: .legacyPreferences(snapshot))`. Only returned success advances durableSettingsRevision. Derive the environment from the **returned saved config** and commit the original ticket on the same coordinator. An older save can advance storage revision and return `.superseded`; never reopen the latest admission. Latest actual success may enable only when commit is `.applied` and current admission matches it.
5. Any write failure, `.durabilityUncertain` or `.finalizationBlocked` does not advance the bridge's successful durable revision or commit. Preserve disabled/error state and any retained journal evidence. A subsequent explicit valid edit uses the last successful revision; if the store has latched recovery it still rejects. No retry/load/default/rollback/reset in the failure path. A validation-only failure may be followed by a valid explicit edit.
6. `drain()` joins the admitted tail without manufacturing a new submit/revision. Once submissions stop it returns only after their storage work and coordinator callbacks complete; closing one view never cancels it. Tail handles must not retain completed configs indefinitely. AppConfigStore remains one shared actual setter; AppReviewSession remains the existing lifetime owner with existing synchronous confirmation capture.

## Task 1: Add complete unhosted wiring RED

**Files:** new `TidyAppModelTests/SharedSettingsWiringTests.swift`; narrow project membership above.

- [ ] Add the complete file below. The first compile RED names proposed app/bridge APIs only; instrumentation uses existing internal production I/O. Do not report compile-only failure as behavior proof.

```swift
import Foundation
import Darwin
import XCTest
@testable import TidyCore

private enum A3Failure: Error { case timeout, setup }

private struct A3Scratch {
    let root: URL
    var home: URL { root.appendingPathComponent("home", isDirectory: true) }
    var support: URL { root.appendingPathComponent("support/Tidy", isDirectory: true) }
    var paths: AppStoragePaths {
        AppStoragePaths(home: home, settings: support.appendingPathComponent("config.json"),
            journal: support.appendingPathComponent("execution", isDirectory: true))
    }
    init() throws {
        var chars = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath("/private/tmp", &chars) != nil else { throw A3Failure.setup }
        root = URL(fileURLWithPath: String(cString: chars), isDirectory: true)
            .appendingPathComponent("T05-A3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try Data("preserve".utf8).write(to: home.appendingPathComponent("sentinel"))
    }
    func seed(_ bytes: Data) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try bytes.write(to: paths.settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
            ofItemAtPath: paths.settings.path)
    }
    func intact() throws {
        XCTAssertEqual(try Data(contentsOf: home.appendingPathComponent("sentinel")), Data("preserve".utf8))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

// Observation/pause only. The finite watchdog releases this fixture's wait;
// it never closes an FD, signals a process, invents success or cancels storage.
private final class A3Probe: @unchecked Sendable {
    private let condition = NSCondition()
    private let stops: Set<String>
    private var released: Set<String> = []
    private var open = false
    private var events: [(String, Bool)] = []
    private var timeout = false
    init(stops: Set<String> = []) { self.stops = stops }
    func hit(_ name: String) {
        condition.lock(); defer { condition.unlock() }
        events.append((name, Thread.isMainThread))
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        while stops.contains(name), !released.contains(name), !open {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                timeout = true
                break
            }
            _ = condition.wait(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
    func release(_ name: String) {
        condition.lock(); released.insert(name); condition.broadcast(); condition.unlock()
    }
    func releaseAll() {
        condition.lock(); open = true; condition.broadcast(); condition.unlock()
    }
    func seen(_ name: String) -> Bool {
        condition.lock(); defer { condition.unlock() }
        return events.contains { $0.0 == name }
    }
    var names: [String] {
        condition.lock(); defer { condition.unlock() }; return events.map { $0.0 }
    }
    var allOffMain: Bool {
        condition.lock(); defer { condition.unlock() }; return !events.isEmpty && events.allSatisfy { !$0.1 }
    }
    var watchdogFired: Bool {
        condition.lock(); defer { condition.unlock() }; return timeout
    }
    func waitFor(_ name: String) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        while !seen(name) {
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw A3Failure.timeout }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

private final class A3RealIO: JournalPOSIXIO, @unchecked Sendable {
    enum Fault { case none, configReplace, configDirectorySync }
    private let real = DarwinJournalIO()
    private let lock = NSLock()
    let probe: A3Probe
    private let fault: Fault
    private var replacements = 0
    private var awaitingConfigSync = false
    private var observedErrno: Int32?
    init(probe: A3Probe, fault: Fault = .none) { self.probe = probe; self.fault = fault }
    var configAttempts: Int { lock.lock(); defer { lock.unlock() }; return replacements }
    var failureErrno: Int32? { lock.lock(); defer { lock.unlock() }; return observedErrno }
    private func record(_ error: Error) {
        lock.lock(); observedErrno = (error as? POSIXError)?.code.rawValue; lock.unlock()
    }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        probe.hit("write")
        return try real.write(fd: fd, bytes: bytes, offset: offset)
    }
    func syncFile(fd: Int32) throws { probe.hit("syncFile"); try real.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        guard destination == "config.json" else {
            try real.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
            return
        }
        lock.lock(); replacements += 1; let number = replacements; lock.unlock()
        probe.hit("config.\(number)") // immediately BEFORE actual config publication
        do {
            // EBADF comes from actual renameat(-1,...), not a synthesized error/success.
            try real.replace(directoryFD: fault == .configReplace ? -1 : directoryFD,
                temporary: temporary, destination: destination)
        } catch { record(error); throw error }
        lock.lock(); awaitingConfigSync = true; lock.unlock()
        probe.hit("config.done.\(number)")
    }
    func syncDirectory(fd: Int32) throws {
        lock.lock(); let fail = awaitingConfigSync && fault == .configDirectorySync
        awaitingConfigSync = false; lock.unlock()
        probe.hit("syncDirectory")
        do { try real.syncDirectory(fd: fail ? -1 : fd) }
        catch { record(error); throw error }
    }
}

@MainActor
final class SharedSettingsWiringTests: XCTestCase {
    private func run(stops: Set<String> = [], seed: Data? = nil,
                     fault: A3RealIO.Fault = .none,
                     _ body: (A3Scratch, AppExecutionServices, A3RealIO) async throws -> Void) async throws {
        let s = try A3Scratch()
        defer { s.remove() }
        if let seed { try s.seed(seed) }
        let probe = A3Probe(stops: stops)
        let io = A3RealIO(probe: probe, fault: fault)
        let store = SettingsStore(url: s.paths.settings, io: io)
        let services = await AppExecutionServices.bootstrap(paths: s.paths, settings: store,
            observe: { probe.hit($0.rawValue) })
        do { try await body(s, services, io) }
        catch {
            probe.releaseAll()
            await services.policyBridge.drain() // no cleanup until actual chain finished
            throw error
        }
        probe.releaseAll()
        await services.policyBridge.drain()
        XCTAssertFalse(probe.watchdogFired)
        try s.intact()
    }

    private func noOpReview(_ services: AppExecutionServices) async throws -> RegisteredReview {
        try await services.coordinator.prepareReview(engine: services.engine, tier: .safe,
            selectDefaults: false) // real catalog, scratch paths, unknown tools; no fake rows
    }

    func testRealPublicationOffMainAndOldSaveCannotEnableNewerEdit() async throws {
        try await run(stops: ["config.1", "config.2"]) { s, services, io in
            let bridge = services.policyBridge, c = services.coordinator
            let review = try await self.noOpReview(services)
            let token = try await c.confirm(binding: review.binding)
            let a = services.configStore, b = services.configStore
            XCTAssertTrue(a === b)
            a.config.transcriptAgeThresholdDays = 60
            XCTAssertEqual(c.policyAdmission(), .updating(revision: 2)) // no await
            XCTAssertFalse(services.isExecutionEnabled)
            try await io.probe.waitFor("config.1")
            XCTAssertTrue(io.probe.allOffMain)
            XCTAssertFalse(io.probe.seen("config.done.1"))
            var eventProcessed = false
            await Task { @MainActor in
                XCTAssertTrue(Thread.isMainThread)
                eventProcessed = true
            }.value
            XCTAssertTrue(eventProcessed)
            XCTAssertFalse(io.probe.watchdogFired)
            b.config.transcriptAgeThresholdDays = 90 // while first real publication suspended
            XCTAssertEqual(c.policyAdmission(), .updating(revision: 3))
            XCTAssertEqual(a.config.transcriptAgeThresholdDays, 90)
            XCTAssertFalse(services.isExecutionEnabled)
            let stale = await c.execute(token, currentPolicyRevision: 1)
            XCTAssertEqual(stale.disposition, .stalePolicy)
            do { _ = try await c.confirm(binding: review.binding); XCTFail("Old binding survived") }
            catch let error as ConfirmationError { XCTAssertEqual(error, .stalePolicy) }
            io.probe.release("config.1")
            try await io.probe.waitFor("config.2")
            // First update returned actual success, second has not published.
            let firstDisk = try JSONDecoder().decode(SettingsEnvelope.self,
                from: Data(contentsOf: s.paths.settings))
            XCTAssertEqual(firstDisk.revision, 1)
            XCTAssertEqual(firstDisk.config.transcriptAgeThresholdDays, 60)
            XCTAssertEqual(bridge.durableSettingsRevision, 1)
            XCTAssertEqual(c.policyAdmission(), .updating(revision: 3))
            XCTAssertFalse(services.isExecutionEnabled)
            XCTAssertFalse(io.probe.seen("config.done.2"))
            io.probe.release("config.2")
            await bridge.drain()
            let saved = await services.settings.load()
            XCTAssertEqual(saved.envelope?.revision, 2)
            XCTAssertEqual(saved.envelope?.config.transcriptAgeThresholdDays, 90)
            XCTAssertEqual(bridge.durableSettingsRevision, 2)
            XCTAssertEqual(c.policyAdmission(), .ready(revision: 3))
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertNil(bridge.persistenceError)
            let fresh = try await self.noOpReview(services)
            XCTAssertEqual(fresh.binding.policyRevision, 3)
            let freshToken = try await c.confirm(binding: fresh.binding)
            let report = await c.execute(freshToken, currentPolicyRevision: 3)
            XCTAssertEqual(report.disposition, .noWork)
            XCTAssertEqual(report.coordinatorMeasurementsAvailable, false)
            XCTAssertEqual(bridge.pendingSnapshotCount, 0)
            XCTAssertEqual(bridge.pendingSnapshotBytes, 0)
        }
    }

    func testBootstrapIsOffMainSharedAndHasNoEnabledDefaultInterval() async throws {
        let s = try A3Scratch(); defer { s.remove() }
        let probe = A3Probe(stops: ["beforeSettingsLoad", "beforeCoordinatorConstruction"])
        let store = SettingsStore(url: s.paths.settings)
        let state = AppBootstrapState()
        XCTAssertEqual(state.status, .notStarted); XCTAssertNil(state.services)
        let started = state.start(paths: s.paths, settings: store, observe: { probe.hit($0.rawValue) })
        XCTAssertEqual(state.status, .loading); XCTAssertNil(state.services)
        let secondWindow = state.start(paths: s.paths, settings: store, observe: { probe.hit($0.rawValue) })
        do {
            try await probe.waitFor("beforeSettingsLoad")
            XCTAssertNil(state.services)
            XCTAssertFalse(FileManager.default.fileExists(atPath: s.support.path))
            var handled = false
            await Task { @MainActor in handled = true }.value
            XCTAssertTrue(handled)
            probe.release("beforeSettingsLoad")
            try await probe.waitFor("beforeCoordinatorConstruction")
            XCTAssertNil(state.services)
            XCTAssertFalse(FileManager.default.fileExists(atPath: s.support.path))
            XCTAssertFalse(probe.watchdogFired)
            probe.release("beforeCoordinatorConstruction")
            await started.value; await secondWindow.value
            let services = try XCTUnwrap(state.services)
            XCTAssertEqual(state.status, .ready)
            XCTAssertEqual(services.settingsLoad.disposition, .newDefaults)
            XCTAssertEqual(services.initialJournalAdmission, .ready)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 0)
            XCTAssertEqual(probe.names, ["beforeSettingsLoad", "afterSettingsLoad",
                "beforeCoordinatorConstruction", "afterCoordinatorConstruction"])
            XCTAssertTrue(probe.allOffMain)
            XCTAssertFalse(FileManager.default.fileExists(atPath: s.paths.settings.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath:
                s.paths.journal.appendingPathComponent("unfinished-effects.json").path))
            let reopened = state.start(paths: s.paths)
            await reopened.value
            XCTAssertTrue(state.services === services)
            services.configStore.config.transcriptAgeThresholdDays = 61
            await services.policyBridge.drain()
            let saved = await services.settings.load()
            XCTAssertEqual(saved.envelope?.revision, 1)
            XCTAssertEqual(saved.envelope?.config.transcriptAgeThresholdDays, 61)
        } catch {
            probe.releaseAll(); await started.value; await secondWindow.value
            if let services = state.services { await services.policyBridge.drain() }
            throw error
        }
        probe.releaseAll(); await started.value; await secondWindow.value
        if let services = state.services { await services.policyBridge.drain() }
        XCTAssertFalse(probe.watchdogFired)
        try s.intact()
    }

    func testCorruptAndFutureBootstrapRemainReadOnlyAfterActualSetter() async throws {
        for bytes in [Data("{broken".utf8), Data(#"{"schemaVersion":999,"keep":"future"}"#.utf8)] {
            try await run(seed: bytes) { s, services, io in
                XCTAssertEqual(services.settingsLoad.disposition, .recoveryReadOnly)
                XCTAssertNil(services.settingsLoad.envelope)
                XCTAssertNil(services.policyBridge.durableSettingsRevision)
                XCTAssertFalse(services.isExecutionEnabled)
                services.configStore.config.transcriptAgeThresholdDays = 75
                XCTAssertFalse(services.isExecutionEnabled)
                await services.policyBridge.drain()
                XCTAssertFalse(services.isExecutionEnabled)
                XCTAssertNotNil(services.persistenceError)
                XCTAssertEqual(io.configAttempts, 0)
                XCTAssertEqual(try Data(contentsOf: s.paths.settings), bytes)
                XCTAssertFalse(FileManager.default.fileExists(atPath:
                    s.support.appendingPathComponent("config.lock").path))
                do { _ = try await self.noOpReview(services); XCTFail("Recovery admitted review") }
                catch let error as ConfirmationError { XCTAssertEqual(error, .stalePolicy) }
            }
        }
    }

    func testKnownSchema2WithoutMetadataLoadsWithoutSettingsWrite() async throws {
        let config = TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: 88)
        let bytes = try JSONEncoder().encode(SettingsEnvelope(schemaVersion: 2, revision: 41, config: config))
        try await run(seed: bytes) { s, services, io in
            XCTAssertEqual(services.settingsLoad.disposition, .loaded)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 41)
            XCTAssertEqual(services.configStore.config, config)
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertEqual(io.configAttempts, 0)
            XCTAssertEqual(try Data(contentsOf: s.paths.settings), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath:
                s.support.appendingPathComponent("config.lock").path))
            services.configStore.config.transcriptAgeThresholdDays = 89
            await services.policyBridge.drain()
            let saved = await services.settings.load()
            XCTAssertEqual(saved.envelope?.revision, 42)
            XCTAssertEqual(try Data(contentsOf: s.support.appendingPathComponent("config.backup.json")), bytes)
        }
    }

    func testSchema1BootstrapMigratesSharedControlsWithoutWritingUntilExplicitEdit() async throws {
        let legacy = Data(#"""
        {"schemaVersion":1,"hasCompletedOnboarding":true,"keepCookieDomains":["example.invalid","keep.invalid"],"simulatorsApprovedForDeletion":["Old simulator name"],"gitRoots":["/fixture/Developer","/fixture/Other"],"staleNodeModulesThresholdDays":90,"transcriptAgeThresholdDays":120,"appsApprovedForQuit":["Old application name"],"allowRestartToReclaimSwap":true,"presets":[{"name":"Weekly","itemIDs":["safe.tool.npm-cache-clean","unknown.preset.id","deep.simulator.erase-all"]}]}
        """#.utf8)
        let migrated = TidyConfig(schemaVersion: 2, hasCompletedOnboarding: true,
            keepCookieDomains: ["example.invalid", "keep.invalid"],
            simulatorsApprovedForDeletion: ["Old simulator name"],
            gitRoots: ["/fixture/Developer", "/fixture/Other"],
            staleNodeModulesThresholdDays: 90, transcriptAgeThresholdDays: 120,
            appsApprovedForQuit: ["Old application name"], allowRestartToReclaimSwap: true,
            presets: [CustomPreset(name: "Weekly", itemIDs: [
                "safe.tool.npm-cache-clean", "unknown.preset.id", "deep.simulator.erase-all"
            ])])
        try await run(seed: legacy) { s, services, io in
            XCTAssertEqual(services.settingsLoad.disposition, .migrated)
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            XCTAssertEqual(services.settingsLoad.envelope?.schemaVersion, 2)
            XCTAssertEqual(services.settingsLoad.envelope?.revision, 0)
            XCTAssertEqual(services.settingsLoad.envelope?.config, migrated)
            XCTAssertEqual(services.configStore.config, migrated) // shared app controls preserve every migrated field
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 0)
            XCTAssertEqual(io.configAttempts, 0)
            XCTAssertEqual(try Data(contentsOf: s.paths.settings), legacy)
            XCTAssertFalse(FileManager.default.fileExists(atPath:
                s.support.appendingPathComponent("config.backup.json").path))

            services.configStore.config.transcriptAgeThresholdDays = 121
            await services.policyBridge.drain()
            let saved = await services.settings.load()
            var expected = migrated; expected.transcriptAgeThresholdDays = 121
            XCTAssertEqual(saved.disposition, .loaded)
            XCTAssertEqual(saved.envelope?.schemaVersion, 2)
            XCTAssertEqual(saved.envelope?.revision, 1)
            XCTAssertEqual(saved.envelope?.config, expected)
            XCTAssertEqual(services.configStore.config, expected)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 1)
            XCTAssertEqual(io.configAttempts, 1)
            XCTAssertEqual(try Data(contentsOf:
                s.support.appendingPathComponent("config.backup.json")), legacy)
        }
    }

    func testPartialSettingsBootstrapAndUninitializedJournalDoNotBecomeReady() async throws {
        for partialSettings in [true, false] {
            let s = try A3Scratch(); defer { s.remove() }
            try s.seed(try JSONEncoder().encode(SettingsEnvelope(schemaVersion: 2,
                revision: 7, config: TidyConfig(schemaVersion: 2))))
            let target: URL
            if partialSettings { target = s.support.appendingPathComponent("config.lock") }
            else {
                try FileManager.default.createDirectory(at: s.paths.journal,
                    withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                target = s.paths.journal.appendingPathComponent("mutation.lock")
            }
            let bytes = Data("incomplete initialized state".utf8)
            try bytes.write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            let state = AppBootstrapState()
            await state.start(paths: s.paths).value
            let services = try XCTUnwrap(state.services)
            XCTAssertEqual(state.status, .recovery)
            XCTAssertFalse(services.isExecutionEnabled)
            if partialSettings { XCTAssertNil(services.settingsLoad.envelope) }
            else { XCTAssertEqual(services.initialJournalAdmission, .storageUnavailable) }
            XCTAssertEqual(try Data(contentsOf: target), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: partialSettings
                ? s.support.appendingPathComponent("config.store.json").path
                : s.paths.journal.appendingPathComponent("unfinished-effects.json").path))
            services.configStore.config.transcriptAgeThresholdDays = 77
            await services.policyBridge.drain()
            XCTAssertFalse(services.isExecutionEnabled) // a saved setting cannot repair journal admission
            XCTAssertEqual(try Data(contentsOf: target), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: partialSettings
                ? s.support.appendingPathComponent("config.store.json").path
                : s.paths.journal.appendingPathComponent("unfinished-effects.json").path))
            try s.intact()
        }
    }

    func testActualReplaceAndPostRenameSyncFailuresNeverCommit() async throws {
        let initial = try JSONEncoder().encode(SettingsEnvelope(schemaVersion: 2,
            revision: 7, config: TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: 45)))
        for fault in [A3RealIO.Fault.configReplace, .configDirectorySync] {
            try await run(seed: initial, fault: fault) { s, services, io in
                let c = services.coordinator, bridge = services.policyBridge
                let old = try await self.noOpReview(services)
                let token = try await c.confirm(binding: old.binding)
                services.configStore.config.transcriptAgeThresholdDays = 90
                XCTAssertEqual(c.policyAdmission(), .updating(revision: 2))
                await bridge.drain()
                XCTAssertEqual(io.failureErrno, EBADF)
                XCTAssertEqual(io.configAttempts, 1)
                let diagnostic = await services.settings.lastPublicationFailure()
                XCTAssertEqual(diagnostic?.stage, fault == .configReplace ? "config.replace" : "config.syncDirectory")
                XCTAssertEqual(diagnostic?.errno, EBADF)
                XCTAssertEqual(bridge.durableSettingsRevision, 7)
                XCTAssertEqual(c.policyAdmission(), .updating(revision: 2))
                XCTAssertFalse(services.isExecutionEnabled)
                XCTAssertNotNil(services.persistenceError)
                let rejected = await c.execute(token, currentPolicyRevision: 1)
                XCTAssertEqual(rejected.disposition, .stalePolicy)
                if fault == .configReplace {
                    XCTAssertEqual(try Data(contentsOf: s.paths.settings), initial)
                } else {
                    let actual = try JSONDecoder().decode(SettingsEnvelope.self,
                        from: Data(contentsOf: s.paths.settings))
                    XCTAssertEqual(actual.revision, 8) // readable bytes != durable success
                    XCTAssertEqual(actual.config.transcriptAgeThresholdDays, 90)
                }
                XCTAssertTrue(FileManager.default.fileExists(atPath:
                    s.support.appendingPathComponent("config.pending.json").path))
                let loaded = await services.settings.load()
                XCTAssertEqual(loaded.disposition, .recoveryReadOnly)
                services.configStore.config.transcriptAgeThresholdDays = 91
                await bridge.drain()
                XCTAssertEqual(io.configAttempts, 1) // no automatic or implicit recovery retry
                XCTAssertEqual(bridge.durableSettingsRevision, 7)
                XCTAssertFalse(services.isExecutionEnabled)
            }
        }
    }

    func testBounded32SnapshotQueueOverflowStaysDisabledUntilExplicitResave() async throws {
        try await run(stops: ["config.1"]) { s, services, io in
            let bridge = services.policyBridge, c = services.coordinator
            services.configStore.config.transcriptAgeThresholdDays = 60
            try await io.probe.waitFor("config.1")
            for day in 61...91 { services.configStore.config.transcriptAgeThresholdDays = day }
            XCTAssertEqual(bridge.pendingSnapshotCount, 32)
            XCTAssertGreaterThan(bridge.pendingSnapshotBytes, 0)
            XCTAssertLessThanOrEqual(bridge.pendingSnapshotBytes, 32 * 1_048_576)
            services.configStore.config.transcriptAgeThresholdDays = 92
            XCTAssertEqual(c.policyAdmission(), .updating(revision: 34))
            XCTAssertEqual(bridge.pendingSnapshotCount, 32)
            XCTAssertEqual(bridge.persistenceError, "Settings changes are pending; wait and save again.")
            io.probe.releaseAll(); await bridge.drain()
            let saved = await services.settings.load()
            XCTAssertEqual(saved.envelope?.revision, 32)
            XCTAssertEqual(saved.envelope?.config.transcriptAgeThresholdDays, 91)
            XCTAssertEqual(io.configAttempts, 32)
            XCTAssertEqual(bridge.durableSettingsRevision, 32)
            XCTAssertEqual(c.policyAdmission(), .updating(revision: 34))
            XCTAssertFalse(services.isExecutionEnabled)
            XCTAssertEqual(bridge.persistenceError, "Settings changes are pending; wait and save again.")
            XCTAssertEqual(bridge.pendingSnapshotCount, 0)
            XCTAssertEqual(bridge.pendingSnapshotBytes, 0)
            services.configStore.config.transcriptAgeThresholdDays = 92 // explicit user resave
            await bridge.drain()
            let retry = await services.settings.load()
            XCTAssertEqual(retry.envelope?.revision, 33)
            XCTAssertEqual(retry.envelope?.config.transcriptAgeThresholdDays, 92)
            XCTAssertEqual(c.policyAdmission(), .ready(revision: 35))
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertNil(bridge.persistenceError)
        }
    }

    func testOversizedAndInvalidSnapshotsAreNotRetainedOrPersistedThenValidEditWorks() async throws {
        try await run { s, services, io in
            var oversized = services.configStore.config
            oversized.keepCookieDomains = Array(repeating: String(repeating: "a", count: 4096), count: 257)
            services.configStore.config = oversized
            XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 2))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            await services.policyBridge.drain()
            XCTAssertEqual(io.configAttempts, 0)
            XCTAssertFalse(services.isExecutionEnabled)
            XCTAssertNotNil(services.persistenceError)
            XCTAssertFalse(FileManager.default.fileExists(atPath: s.paths.settings.path))
            var invalid = TidyConfig(schemaVersion: 2); invalid.transcriptAgeThresholdDays = 366
            services.configStore.config = invalid
            await services.policyBridge.drain()
            XCTAssertEqual(io.configAttempts, 0)
            XCTAssertFalse(services.isExecutionEnabled)
            services.configStore.config = TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: 75)
            await services.policyBridge.drain()
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 1)
            XCTAssertTrue(services.isExecutionEnabled)
        }
    }

    func testClosingOneActualWindowDoesNotCancelSharedPendingSaveOrOtherWindow() async throws {
        try await run(stops: ["config.1"]) { s, services, io in
            let clean = CleanViewModel(tier: .safe, services: services)
            let custom = CustomViewModel(services: services)
            await clean.requestLoad().value; await custom.requestLoad().value
            XCTAssertNotNil(clean.registeredReview); XCTAssertNotNil(custom.registeredReview)
            services.configStore.config.transcriptAgeThresholdDays = 74
            clean.policyDidChange(); custom.policyDidChange() // real view notification handlers
            try await io.probe.waitFor("config.1")
            let closed = clean.teardown()
            await closed.value
            XCTAssertNil(clean.selection)
            XCTAssertFalse(services.isExecutionEnabled)
            XCTAssertFalse(custom.selection?.canConfirm ?? false)
            custom.confirm() // denied while actual save suspended; no mutation/log effect
            io.probe.releaseAll(); await services.policyBridge.drain()
            await custom.requestLoad().value
            XCTAssertNotNil(custom.registeredReview)
            XCTAssertNotNil(custom.selection)
            XCTAssertFalse(custom.selection?.canConfirm ?? true) // all denied, not positive cleanup
            await clean.requestLoad().value
            XCTAssertNil(clean.selection) // closed lifetime never reopens
            await custom.teardown().value
            let saved = await services.settings.load()
            XCTAssertEqual(saved.envelope?.config.transcriptAgeThresholdDays, 74)
            XCTAssertEqual(saved.envelope?.revision, 1)
        }
    }

    func testUnavailableProductionPathStateCreatesNoServices() {
        let state = AppBootstrapState()
        state.storagePathUnavailable()
        XCTAssertEqual(state.status, .unavailable)
        XCTAssertNil(state.services)
    }
}
```

The real-I/O pause is before config rename, after candidate/backup work. Both old and latest transactions run the actual settings publisher and finalization; the test does not call coordinator.commit itself. The first update must return success and advance durable revision before the second paused boundary is reached. The two real EBADF tests identify exact stages and do not claim media-error simulation or physical durability. Runner timeouts below are still required for malformed implementation deadlocks; an actor task cannot be joined by cancellation. All expected-path exits release pauses and await actual tasks before exact UUID scratch deletion. A killed/hung runner retains its scratch roots; never broad-clean them.

## Task 2: Exact legacy-caller migration and cutover

- [ ] Change the existing AppModelScratch helper to this implementation, then change **all six currently inspected** `scratch.services()` call sites to `await scratch.services()` (recount at entry). Keep their async XCTest methods and assertions; do not remove accepted tests.

```swift
@MainActor func services() async -> AppExecutionServices {
    await AppExecutionServices.bootstrap(paths: AppStoragePaths(home: home,
        settings: configURL, journal: journal))
}
```

- [ ] Replace the existing final ConfigStore.load assertion in `testActualConfigStoreSettersInvalidateSynchronouslyAndPersistInOrder` with actual actor reload and revision3 (that test intentionally submits three edits, ending policy revision4):

```swift
let persisted = await services.settings.load()
XCTAssertEqual(persisted.envelope?.config.transcriptAgeThresholdDays, 90)
XCTAssertEqual(persisted.envelope?.revision, 3)
```

- [ ] Migrate core helper `persistPolicy` to one genuine load/update, then original ticket commit. Test-only ephemeral stores may share scratch URLs only sequentially after reloading actual disk; no new public raw writer. Exact replacement:

```swift
private func persistPolicy(_ coordinator: ExecutionCoordinator,
                           scratch: ExecutionScratch) async throws -> UInt64 {
    let ticket = try coordinator.beginPolicyUpdate()
    let settings = SettingsStore(url: scratch.home.appendingPathComponent("config.json"))
    let loaded = await settings.load()
    let envelope = try #require(loaded.envelope)
    let saved = try await settings.update(expectedRevision: envelope.revision,
        change: .legacyPreferences(TidyConfig(schemaVersion: 2)))
    let environment = saved.config.makePolicyEnvironment(homeDirectory: scratch.home.path, detectedTools: [])
    let commit = try await coordinator.commitPolicyUpdate(ticket, environment: environment)
    guard case .applied(let revision) = commit else { throw ConfirmationError.stalePolicy }
    return revision
}
```

The three complete core method replacements below preserve their existing names. The failure starts with a valid real load **before** obstructing its exact scratch parent; starting already in recovery would lose the original valid-policy1 → actual failed save → no commit regression. The overlapping test keeps storage revision2 separate from policy revision3. Keep the more specific actual-publication failure tests in Task1 as separate evidence.

```swift
@Test("Real settings persistence error leaves production app bridge disabled with error")
@MainActor
func settingsSaveFailureBlocksBridge() async throws {
    let s = try ExecutionScratch(); defer { s.cleanup() }
    let parent = s.home.appendingPathComponent("settings", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
    let url = parent.appendingPathComponent("config.json")
    let settings = SettingsStore(url: url), loaded = await settings.load()
    #expect(loaded.disposition == .newDefaults)
    try FileManager.default.moveItem(at: parent, to: s.home.appendingPathComponent("retained-settings"))
    let blockerBytes = Data("preserve blocking file".utf8)
    try blockerBytes.write(to: parent)
    let c = s.coordinator(), r = try await review(c)
    let token = try await c.confirm(binding: r.binding)
    let bridge = ExecutionPolicyBridge(coordinator: c, settings: settings, loaded: loaded,
        homeDirectory: s.home.path, detectedTools: [])
    var config = TidyConfig(schemaVersion: 2); config.transcriptAgeThresholdDays = 90
    let update = bridge.submit(config: config)
    #expect(!bridge.isExecutionEnabled && bridge.policyUpdatePending)
    #expect(c.policyAdmission() == .updating(revision: 2))
    #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
    await update.value
    #expect(!bridge.isExecutionEnabled && !bridge.policyUpdatePending)
    #expect(bridge.durableSettingsRevision == 0)
    #expect(bridge.persistenceError == "Settings could not be saved. Cleanup remains disabled. Fix the settings storage location and save again.")
    #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .invalidToken)
    await expectConfirmationError(.stalePolicy) { _ = try await review(c) }
    #expect(try Data(contentsOf: parent) == blockerBytes)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    try s.intact()
}

@Test("Two synchronous settings submissions invalidate before queued persistence runs")
@MainActor
func settingsSubmissionHasNoDiscoveryPhase() async throws {
    let s = try ExecutionScratch(); defer { s.cleanup() }
    let c = s.coordinator(), r = try await review(c)
    let token = try await c.confirm(binding: r.binding)
    let url = s.home.appendingPathComponent("config.json"), settings = SettingsStore(url: url)
    let loaded = await settings.load()
    let bridge = ExecutionPolicyBridge(coordinator: c, settings: settings, loaded: loaded,
        homeDirectory: s.home.path, detectedTools: [])
    var first = TidyConfig(schemaVersion: 2); first.transcriptAgeThresholdDays = 60
    var second = first; second.transcriptAgeThresholdDays = 90
    let a = bridge.submit(config: first)
    #expect(c.policyAdmission() == .updating(revision: 2))
    let b = bridge.submit(config: second)
    #expect(c.policyAdmission() == .updating(revision: 3))
    #expect(!bridge.isExecutionEnabled && bridge.policyUpdatePending)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
    await a.value; await b.value
    let actual = await settings.load()
    #expect(actual.envelope?.config == second && actual.envelope?.revision == 2)
    #expect(bridge.durableSettingsRevision == 2)
    #expect(c.policyAdmission() == .ready(revision: 3))
    #expect(bridge.isExecutionEnabled && !bridge.policyUpdatePending)
    #expect(bridge.persistenceError == nil)
    let fresh = try await review(c)
    #expect(fresh.binding.policyRevision == 3)
    let denied = try #require(fresh.plan.reviewItems.first { $0.id == "deep.simulator.erase-all" })
    #expect(!denied.review.isSelectable)
    await expectConfirmationError(.unavailableSelection) {
        _ = try await c.setSelection(planID: fresh.binding.planID, selectedIDs: [denied.id])
    }
    try s.intact()
}

@Test("Older persisted update cannot reopen admission while a newer ticket is pending")
func overlappingPolicyUpdates() async throws {
    let s = try ExecutionScratch(); defer { s.cleanup() }
    let c = s.coordinator(), old = try await review(c)
    let token = try await c.confirm(binding: old.binding)
    let first = try c.beginPolicyUpdate(), second = try c.beginPolicyUpdate()
    #expect(c.policyAdmission() == .updating(revision: 3))
    let configURL = s.home.appendingPathComponent("config.json")
    let settings = SettingsStore(url: configURL); _ = await settings.load()
    var firstConfig = TidyConfig(schemaVersion: 2); firstConfig.transcriptAgeThresholdDays = 60
    let firstSaved = try await settings.update(expectedRevision: 0, change: .legacyPreferences(firstConfig))
    let firstEnvironment = firstSaved.config.makePolicyEnvironment(homeDirectory: s.home.path, detectedTools: [])
    #expect(try await c.commitPolicyUpdate(first, environment: firstEnvironment) == .superseded)
    #expect(c.policyAdmission() == .updating(revision: 3))
    await expectConfirmationError(.stalePolicy) { _ = try await review(c) }
    #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
    var secondConfig = TidyConfig(schemaVersion: 2); secondConfig.transcriptAgeThresholdDays = 90
    let secondSaved = try await settings.update(expectedRevision: 1, change: .legacyPreferences(secondConfig))
    let secondEnvironment = secondSaved.config.makePolicyEnvironment(homeDirectory: s.home.path, detectedTools: [])
    #expect(try await c.commitPolicyUpdate(second, environment: secondEnvironment) == .applied(revision: 3))
    #expect(c.policyAdmission() == .ready(revision: 3))
    let actual = await settings.load()
    #expect(actual.envelope?.config == secondConfig && actual.envelope?.revision == 2)
    #expect(try await c.commitPolicyUpdate(first, environment: firstEnvironment) == .superseded)
    #expect(c.policyAdmission() == .ready(revision: 3))
    let fresh = try await review(c)
    #expect(fresh.binding.policyRevision == 3)
    let freshToken = try await c.confirm(binding: fresh.binding)
    #expect(await c.execute(freshToken, currentPolicyRevision: 3).disposition == .noWork)
    try s.intact()
}
```

- [ ] Replace the obsolete four ConfigStore tests with this complete suite in the same file; retain `TidyConfigTests` unchanged, including its pure projection test. The names deliberately describe new recovery semantics rather than making corruption appear successful defaults.

```swift
@Suite("SettingsStore cutover")
struct SettingsStoreCutoverTests {
    private func scratch() throws -> URL {
        var chars = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath("/private/tmp", &chars) != nil else { throw SettingsStoreError.unavailable }
        let root = URL(fileURLWithPath: String(cString: chars), isDirectory: true)
            .appendingPathComponent("T05-Cutover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        return root
    }
    @Test func missingLoadIsInMemoryOnlyAndDefaultSchemaIsTwo() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("missing/config.json")
        let store = SettingsStore(url: url), loaded = await store.load()
        #expect(TidyConfig.currentSchemaVersion == 2)
        #expect(loaded.disposition == .newDefaults)
        #expect(loaded.envelope?.config == TidyConfig())
        #expect(loaded.envelope?.revision == 0)
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }
    @Test func explicitSaveRoundTripsEnvelopeAndUnknownPresetAsInertData() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.json"), store = SettingsStore(url: url)
        _ = await store.load()
        var config = TidyConfig(); config.hasCompletedOnboarding = true
        config.keepCookieDomains = ["example.invalid"]
        config.simulatorsApprovedForDeletion = ["Old iPhone"]
        config.gitRoots = [root.appendingPathComponent("Developer").path]
        config.staleNodeModulesThresholdDays = 90
        config.presets = [CustomPreset(name: "Saved", itemIDs: ["unknown.preset.id"])]
        let saved = try await store.update(expectedRevision: 0, change: .legacyPreferences(config))
        let actual = await SettingsStore(url: url).load()
        #expect(actual.disposition == .loaded && actual.envelope == saved)
        #expect(saved.schemaVersion == 2 && saved.revision == 1 && saved.config == config)
        #expect(actual.envelope?.config.simulatorsApprovedForDeletion == ["Old iPhone"])
        #expect(actual.envelope?.config.gitRoots == [root.appendingPathComponent("Developer").path])
        #expect(actual.envelope?.config.staleNodeModulesThresholdDays == 90)
    }
    @Test func firstExplicitSaveCreatesParents() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("missing/parents/config.json")
        let store = SettingsStore(url: url); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .legacyPreferences(TidyConfig()))
        #expect(FileManager.default.fileExists(atPath: url.path))
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }
    @Test func corruptSettingsStayReadOnlyAndBytePreserved() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.json"), bytes = Data("not json at all".utf8)
        try bytes.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let store = SettingsStore(url: url), loaded = await store.load()
        #expect(loaded.disposition == .recoveryReadOnly && loaded.envelope == nil)
        do {
            _ = try await store.update(expectedRevision: 0, change: .legacyPreferences(TidyConfig()))
            Issue.record("Recovery wrote defaults")
        } catch let error as SettingsStoreError { #expect(error == .readOnlyRecovery) }
        #expect(try Data(contentsOf: url) == bytes)
    }
}
```

Add `import Darwin` alongside the current Foundation/Testing/@testable imports in that core file.

- [ ] Implement only the declared app factory/bridge/state contract, migrate the listed app consumers, delete ConfigStore and change schema default in one non-deployable work batch. Keep TidyConfig's historical schema1 decoder fixtures explicit; do not globally rewrite fixture versions. Trace every default initializer/lazy call so a remaining raw writer cannot publish flat schema2.
- [ ] Review whole app transitive startup/settings call paths against no-discovery contract, then run the RED/GREEN commands below under Controller scheduling. A mismatch in file ownership or inability to get testable internal I/O is a stop/review condition, not permission to widen APIs.
- [ ] Perform this focused **actual-source adoption inspection** in addition to the unhosted wiring tests: inspect `Tidy/MenuBar/MenuBarContentView.swift` after the cutover and verify `hasCheckedOnboarding` and `checkOnboardingOnce` are absent; its popover `.onAppear` contains only the existing stats refresh and does not open a window or inspect onboarding completion; and the only retained `WindowID.onboarding` route in that file is an explicit `Button("Set up Tidy…")` action guarded by unfinished onboarding. Then trace that click to the existing Welcome scene and record that `OnboardingView.onAppear` invokes `model.start()`, which invokes `ToolchainDetector.detect()`. This is a manual, click-initiated T08 route, not A.3 startup discovery. The unhosted XCTest target cannot prove SwiftUI `.onAppear` adoption or the absence of this transitive UI route; source/signature inspection is required and must not be reported as executed source-test evidence.

## Task 3: Historical-memory presentation RED and actual view adoption

`RunReportPresentation` is a small pure projection in its new app file. It defines `measurementsAvailable = report.coordinatorMeasurementsAvailable != false`; `memoryText` is `Not measured` if measurements are unavailable or measuredTotalReclaimedMemoryBytes is nil, otherwise `ByteFormat.human(actual)` including explicit0. Its optional admissionMessage is nil when measurementsAvailable; otherwise copy the existing complete CleanResultsView disposition switch verbatim. CleanResultsView consumes these exact properties for its availability branch, memory row and admission text; it must not fall back to compatibility numeric memory fields or hide a measured zero. Disk and memory remain separate; this unit does not change T03 accounting. This pure projection unit is not a native-rendering/device/AX claim.

- [ ] Add the complete XCTest file before the projection/view implementation:

```swift
import Foundation
import XCTest
import TidyCore

final class RunReportPresentationTests: XCTestCase {
    private func report(_ items: [ItemResult], disposition: RunDisposition = .completed,
                        available: Bool? = nil) -> RunReport {
        RunReport(tier: .safe, results: items, startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2), freeSpaceBeforeBytes: 100,
            freeSpaceAfterBytes: 110, disposition: disposition,
            coordinatorMeasurementsAvailable: available)
    }
    func testHistoricalAbsentMemoryIsNotMeasuredNotZero() throws {
        let old = try JSONDecoder().decode(RunReport.self, from: Data(#"{"tier":"safe","results":[{"id":"old","title":"Old","freedBytes":10,"succeeded":true}],"startedAt":0,"finishedAt":1,"freeSpaceBeforeBytes":100,"freeSpaceAfterBytes":110}"#.utf8))
        let presentation = RunReportPresentation(report: old)
        XCTAssertTrue(presentation.measurementsAvailable)
        XCTAssertEqual(presentation.memoryText, "Not measured")
        XCTAssertNil(presentation.admissionMessage)
    }
    func testExplicitZeroIsMeasuredAndMixedUnknownIsNot() {
        let zero = ItemResult(id: "zero", title: "Zero", freedBytes: 0,
            reclaimedMemoryBytes: 0, succeeded: true)
        let known = ItemResult(id: "known", title: "Known", freedBytes: 0,
            reclaimedMemoryBytes: 2048, succeeded: true)
        let unknown = ItemResult(id: "unknown", title: "Unknown", freedBytes: 0, succeeded: true)
        XCTAssertEqual(RunReportPresentation(report: report([zero])).memoryText, ByteFormat.human(0))
        XCTAssertEqual(RunReportPresentation(report: report([known])).memoryText, ByteFormat.human(2048))
        XCTAssertEqual(RunReportPresentation(report: report([unknown, known])).memoryText, "Not measured")
        XCTAssertEqual(RunReportPresentation(report: report([])).memoryText, "Not measured")
    }
    func testT02NoOpAndEveryDenialRemainUnmeasuredWithTheirOwnMessage() {
        let cases: [(RunDisposition, String)] = [
            (.noWork, "No items selected; nothing was run."),
            (.busy, "Another cleanup is running. Wait for it to finish, then try again."),
            (.recoveryBlocked, "An earlier operation may still be running. Cleanup is blocked pending reconciliation."),
            (.storageUnavailable, "Execution records could not be validated. Cleanup remains blocked."),
            (.stalePolicy, "Settings changed. Review the items again before confirming."),
            (.staleReview, "This confirmation is no longer valid. Review the items again."),
            (.invalidToken, "This confirmation is no longer valid. Review the items again."),
            (.unavailableSelection, "The selected action is unavailable. Nothing was run."),
            (.completed, "The operation finished, but measurements are unavailable.")
        ]
        let zero = ItemResult(id: "zero", title: "Zero", freedBytes: 0,
            reclaimedMemoryBytes: 0, succeeded: true)
        for (disposition, message) in cases {
            let presentation = RunReportPresentation(report: report([zero],
                disposition: disposition, available: false))
            XCTAssertFalse(presentation.measurementsAvailable)
            XCTAssertEqual(presentation.memoryText, "Not measured")
            XCTAssertEqual(presentation.admissionMessage, message)
        }
    }
}
```

- [ ] Implement the specified pure projection and make the actual CleanResultsView use it. Add only `RunReportPresentation.swift`, `SharedSettingsWiringTests.swift`, and `RunReportPresentationTests.swift` to the existing six-entry unhosted target (nine total). Do not add CleanResultsView/SwiftUI scene files, ScanView, TidyApp, a host dependency, package fixtures or blanket `path: Tidy` to that target. The normal Tidy target already includes the new pure app file via its existing source directory.

## Controller-scheduled commands — NOT EXECUTED

Entry-only diagnostics (read-only) and source inspection:

```sh
cd /private/tmp/tidy-headroom.wUbV9h
rg -n 'ConfigStore|ConfigSaveError|ExecutionPolicyBridge\(|AppExecutionServices\(' Tidy TidyCore/Sources TidyCore/Tests TidyAppModelTests
rg -n 'makeEnvironment|ToolchainDetector|ToolLocator|Process|NSHomeDirectory|defaultURL|\.task' Tidy/Execution Tidy/Settings/AppConfigStore.swift Tidy/TidyApp.swift Tidy/Scan
rg -n 'totalReclaimedMemoryBytes|reclaimedMemoryBytes|RunReportPresentation' Tidy
```

Expected after cutover: no old ConfigStore/ConfigSaveError production/test references (test filename may remain); one real coordinator constructor in off-main app factory; only explicit production home resolution in TidyApp; no bootstrap/setter discovery; no ScanView automatic scan; actual result view uses measured availability. Review transitive callees, not merely grep counts.

After A.2P + entry approval and source assignment, with no other compiler job:

```sh
cd /private/tmp/tidy-headroom.wUbV9h
xcodegen generate --spec project.yml
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build-for-testing CODE_SIGNING_ALLOWED=NO
```

Inspect generated nine-source membership, no TEST_HOST/BUNDLE_LOADER, only local TidyCore dependency, Debug testability and exact selected bundle before running. Expected initial compile RED for proposed APIs; once declarations exist, the original synchronous implementation must fail off-main/pause/queue/bootstrap/presentation assertions. Do not implement a known unsafe fake saver to manufacture RED; use natural missing/old behavior and record scaffold-only failures separately.

```sh
cd /private/tmp/tidy-headroom.wUbV9h
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 test-without-building -parallel-testing-enabled NO -only-testing:TidyAppModelTests/SharedSettingsWiringTests -only-testing:TidyAppModelTests/RunReportPresentationTests -only-testing:TidyAppModelTests/ConfirmationLifecycleTests -test-timeouts-enabled YES -default-test-execution-time-allowance 30 -maximum-test-execution-time-allowance 60 CODE_SIGNING_ALLOWED=NO
cd /private/tmp/tidy-headroom.wUbV9h/TidyCore
swift test --filter 'SettingsStoreCutoverTests|TidyConfigTests|ConfirmedExecutionTests|SettingsMigrationTests|SettingsPublicationTests' --jobs 2
```

Expected GREEN: all named new scenarios and preserved existing assertions, actual saved revisions/bytes, no timeout/watchdog, no app launch or unscheduled executable. Queue test32 real fsync transactions must finish within runner allowance on tested machine; a timeout fails and requires investigation, not raised bounds or removed assertions without review. Use accepted A.2P focused command from its card and the Controller-approved full package suite afterward; do not overlap T04.B or its independent process audit jobs.

```sh
cd /private/tmp/tidy-headroom.wUbV9h
xcodebuild -quiet -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build CODE_SIGNING_ALLOWED=NO
```

Unsigned compile is not launch/native UI/Intel/macOS14 evidence. No commit command is supplied: Controller decides the exact final allowlist after independent source/spec review of the **whole atomic cutover**; no intermediate schema2/old-writer commit is deployable.

## Self-review and remaining gates

- [ ] Verify every owned path and callsite against accepted source at entry; Core internal injection stays internal and app state is the actual production state, not a copied harness.
- [ ] Check RED observes a suspended actual publication, non-main thread, live MainActor event, second edit during suspension, first real success without enabling, then latest real success committing existing coordinator ticket.
- [ ] Check both real failure stages, sticky recovery, no revision/authority conflation, complete32 snapshot persistence and observable overflow, rejected oversized data, valid explicit retry, one shared service and closed-window persistence independence.
- [ ] Inspect bootstrap journal/settings off-main ordering and missing shared parent behavior; reject live-path defaults, corrupt/future reset, default-enabled interval, discovery, automatic scan, fallback loader/writer or flat schema2 writer.
- [ ] Independently perform the focused `MenuBarContentView` source-adoption inspection above: verify no popover appearance can transitively reach `OnboardingView.onAppear` → `OnboardingViewModel.start()` → `ToolchainDetector.detect()`, while the explicit `Set up Tidy…` button remains the sole unfinished-onboarding route. Do not substitute unhosted XCTest results for this SwiftUI source/appearance check.
- [ ] Confirm actual CleanResultsView consumes tested availability and preserves T02 text; do not call pure projection tests a rendered native-view pass.
- [ ] Independent review must approve this entry before source. Source/test review and actual commands then remain separate evidence. A.2P acceptance is mandatory before A.3 entry; B.1 stable-OS AX, B.2 accepted-adapter positive effect/dialog/in-flight tests, T06 registry integration, T08 discovery and full useful cleanup remain open at this scoped unit's completion.
