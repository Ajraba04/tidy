#if TIDY_RUNTIME_TEST_HOST
import Darwin
import Foundation
import SwiftUI
import TidyCore

private enum RuntimeObservationError: Error, CustomStringConvertible {
    case invalidScenario
    case invalidFixtureRoot
    case invalidSettings(String)
    case invalidRuntimeState(String)
    case counterOverflow
    case publication(String)

    var description: String {
        switch self {
        case .invalidScenario: return "The runtime observation scenario is unsupported."
        case .invalidFixtureRoot: return "The runtime observation fixture root is unsafe."
        case .invalidSettings(let detail): return "Runtime observation settings are invalid: \(detail)"
        case .invalidRuntimeState(let detail): return "Runtime observation state is invalid: \(detail)"
        case .counterOverflow: return "The runtime observation counter overflowed."
        case .publication(let detail): return "Runtime observation publication failed: \(detail)"
        }
    }
}

private enum RuntimeObservationScenario: String, Sendable {
    case hiddenOff = "hidden-off"
    case hiddenNoAuthority = "hidden-no-authority"

    var duration: Duration {
        switch self {
        case .hiddenOff: return .seconds(120)
        case .hiddenNoAuthority: return .seconds(600)
        }
    }

    var durationNanoseconds: UInt64 {
        switch self {
        case .hiddenOff: return 120_000_000_000
        case .hiddenNoAuthority: return 600_000_000_000
        }
    }
}

private struct RuntimeObservationDocument: Codable, Equatable, Sendable {
    let schema: Int
    let scenario: String
    let pid: Int
    let settingsRevision: UInt64
    let backgroundAuthority: String
    let applicationHidden: Bool
    let timerRunning: Bool
    let sceneLeases: Int
    let explicitWorkLeases: Int
    let scanSessions: Int
    let scanActiveWork: Int
    let allMutationsDenied: Bool
    let timerScheduledCount: Int
    let timerCancelledCount: Int
    let observedMonotonicNanoseconds: UInt64
}

private final class RuntimeObservationInstrumentation: MonitorInstrumentation, @unchecked Sendable {
    struct Snapshot: Sendable {
        let scheduled: Int
        let cancelled: Int
        let overflowed: Bool
    }

    private let lock = NSLock()
    private var scheduled = 0
    private var cancelled = 0
    private var overflowed = false
    func timerScheduled() {
        lock.lock()
        let (next, didOverflow) = scheduled.addingReportingOverflow(1)
        if didOverflow { overflowed = true } else { scheduled = next }
        lock.unlock()
    }

    func timerCancelled() {
        lock.lock()
        let (next, didOverflow) = cancelled.addingReportingOverflow(1)
        if didOverflow { overflowed = true } else { cancelled = next }
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(scheduled: scheduled, cancelled: cancelled, overflowed: overflowed)
        }
    }

}

@MainActor
struct RuntimeObservationControl: View {
    let services: AppExecutionServices
    let scenario: RuntimeTestScenario
    @State private var readyState = "pending"
    @State private var finalState = "pending"
    @State private var diagnostic = "none"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            attestation("Observation ready", value: readyState,
                        identifier: "runtime.observation.ready")
            attestation("Observation final", value: finalState,
                        identifier: "runtime.observation.final")
            attestation("Observation diagnostic", value: diagnostic,
                        identifier: "runtime.observation.diagnostic")
        }
        .task {
            guard RuntimeObservationCoordinator.supports(scenario) else { return }
            await RuntimeObservationCoordinator.startIfNeeded(
                services: services, scenario: scenario
            ) { update in
                switch update {
                case .ready: readyState = "published"
                case .final: finalState = "published"
                case .failed(let message): diagnostic = message
                }
            }
        }
    }

    private func attestation(_ label: String, value: String, identifier: String) -> some View {
        Text(value)
            .font(.caption)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }
}

enum RuntimeObservationCoordinator {
    enum Update: Sendable {
        case ready
        case final
        case failed(String)
    }

    private static let instrumentation = RuntimeObservationInstrumentation()
    static var monitorInstrumentation: any MonitorInstrumentation { instrumentation }

    static func supports(_ scenario: RuntimeTestScenario) -> Bool {
        RuntimeObservationScenario(rawValue: scenario.rawValue) != nil
    }

    @MainActor private static var activeTask: Task<Void, Never>?
    @MainActor private static var latestUpdate: Update?

    @MainActor
    static func startIfNeeded(services: AppExecutionServices, scenario: RuntimeTestScenario,
                              onUpdate: @escaping @MainActor (Update) -> Void) async {
        if let latestUpdate { onUpdate(latestUpdate) }
        if let activeTask {
            await activeTask.value
            if let latestUpdate { onUpdate(latestUpdate) }
            return
        }
        let task = Task { @MainActor in
            await run(services: services, scenario: scenario) { update in
                latestUpdate = update
                onUpdate(update)
            }
        }
        activeTask = task
        await task.value
    }

    @MainActor
    static func stopIfActive() async {
        let task = activeTask
        activeTask = nil
        task?.cancel()
        await task?.value
    }

    @MainActor
    private static func run(services: AppExecutionServices, scenario runtimeScenario: RuntimeTestScenario,
                            onUpdate: @escaping @MainActor (Update) -> Void) async {
        do {
            guard let scenario = RuntimeObservationScenario(rawValue: runtimeScenario.rawValue) else {
                throw RuntimeObservationError.invalidScenario
            }
            let root = try validatedRoot(for: services.paths)
            Swift.print("TIDY_RUNTIME_ROOT=\(root.path)")
            fflush(stdout)
            NSApp.hide(nil)
            await Task.yield()
            guard NSApp.isHidden else {
                throw RuntimeObservationError.invalidRuntimeState("application did not become hidden")
            }

            try validateSettings(services: services, scenario: scenario)
            try Task.checkCancellation()
            let clock = ContinuousClock()
            let monotonicOrigin = clock.now
            let ready = try await capture(services: services, scenario: scenario,
                                          origin: monotonicOrigin)
            try validateReady(ready, scenario: scenario)
            try publish(ready, named: "runtime-ready.json", under: services.paths.settings
                .deletingLastPathComponent())
            onUpdate(.ready)

            try await clock.sleep(for: scenario.duration)
            try Task.checkCancellation()
            let final = try await capture(services: services, scenario: scenario,
                                          origin: monotonicOrigin)
            try validateFinal(final, after: ready, scenario: scenario)
            try publish(final, named: "runtime-final.json", under: services.paths.settings
                .deletingLastPathComponent())
            onUpdate(.final)
        } catch is CancellationError {
            onUpdate(.failed("cancelled"))
        } catch {
            onUpdate(.failed(String(describing: error)))
        }
    }

    @MainActor
    private static func validateSettings(services: AppExecutionServices,
                                         scenario: RuntimeObservationScenario) throws {
        let store = services.configStore
        guard store.acknowledgedSettingsRevision == 1, !store.hasPendingSettingsWrites,
              let policy = store.acknowledgedEffectivePolicy else {
            throw RuntimeObservationError.invalidSettings("revision 1 is not settled")
        }
        let enabled = policy.allowedFeatures.contains("headroom")
        let backgroundUnavailable = authorityUnavailable(policy, "monitor.backgroundEnabled")
        let suppressHidden = bool(policy, "monitor.suppressHiddenSampling")
        let hiddenInterval = integer(policy, "monitor.hiddenIntervalSeconds")
        let expected: (enabled: Bool, suppressHidden: Bool)
        switch scenario {
        case .hiddenOff: expected = (false, true)
        case .hiddenNoAuthority: expected = (true, false)
        }
        guard enabled == expected.enabled, backgroundUnavailable,
              suppressHidden == expected.suppressHidden, hiddenInterval == 60 else {
            throw RuntimeObservationError.invalidSettings("fixed hidden policy does not match")
        }
    }

    private static func authorityUnavailable(_ policy: EffectivePolicy, _ rawID: String) -> Bool {
        guard let field = policy.fields[SettingID(rawValue: rawID)] else { return false }
        return field.value == .unavailable(.authorityUnavailable)
            && field.reason == .authorityUnavailable
            && field.sources == [.localAuthority]
    }

    private static func bool(_ policy: EffectivePolicy, _ rawID: String) -> Bool? {
        guard case .stored(.bool(let value))? = policy.fields[SettingID(rawValue: rawID)]?.value else {
            return nil
        }
        return value
    }

    private static func integer(_ policy: EffectivePolicy, _ rawID: String) -> Int64? {
        guard case .stored(.integer(let value))? = policy.fields[SettingID(rawValue: rawID)]?.value else {
            return nil
        }
        return value
    }

    @MainActor
    private static func capture(services: AppExecutionServices, scenario: RuntimeObservationScenario,
                                origin: ContinuousClock.Instant) async throws
      -> RuntimeObservationDocument {
        let monitor = services.systemMonitor
        let timerRunning = await monitor.isTimerRunningForTesting()
        let sceneLeases = await monitor.activeSceneLeaseCountForTesting()
        let explicitWorkLeases = await monitor.activeExplicitWorkLeaseCountForTesting()
        let monitorRevision = await monitor.appliedConfigurationRevisionForTesting()
        let scan = await services.scanRegistry.snapshot()
        let scheduler = await services.explicitSessions.snapshot()
        let indexWatchActive = await services.activeScanIndexWatchIsActiveForTesting()
        let counters = instrumentation.snapshot()
        guard !counters.overflowed else { throw RuntimeObservationError.counterOverflow }
        guard monitorRevision == 1, scheduler.settingsRevision == 1,
              scheduler.active == 0, scheduler.queued == 0, scheduler.liveSessions == 0,
              services.activeScanSessionID == nil, !indexWatchActive,
              scan.liveSubscribers == 0 else {
            throw RuntimeObservationError.invalidRuntimeState("hidden work ownership is not idle")
        }
        let allDenied = CleanCatalog.allItems.allSatisfy {
            CapabilityRegistry.denialReason(for: $0.action, itemID: $0.id) != nil
        }
        let backgroundUnavailable = services.configStore.acknowledgedEffectivePolicy.map {
            authorityUnavailable($0, "monitor.backgroundEnabled")
        } ?? false
        return RuntimeObservationDocument(schema: 1, scenario: scenario.rawValue,
            pid: Int(getpid()), settingsRevision: services.configStore.acknowledgedSettingsRevision,
            backgroundAuthority: backgroundUnavailable ? "unavailable" : "unexpected",
            applicationHidden: NSApp.isHidden, timerRunning: timerRunning, sceneLeases: sceneLeases,
            explicitWorkLeases: explicitWorkLeases, scanSessions: scan.sessions,
            scanActiveWork: scan.activeWork, allMutationsDenied: allDenied,
            timerScheduledCount: counters.scheduled, timerCancelledCount: counters.cancelled,
            observedMonotonicNanoseconds: try monotonicNanoseconds(since: origin))
    }

    private static func validateReady(_ value: RuntimeObservationDocument,
                                      scenario: RuntimeObservationScenario) throws {
        guard value.schema == 1, value.scenario == scenario.rawValue, value.pid == Int(getpid()),
              value.settingsRevision == 1, value.backgroundAuthority == "unavailable",
              value.applicationHidden, value.sceneLeases == 0,
              value.explicitWorkLeases == 0, value.scanSessions == 0,
              value.scanActiveWork == 0, value.allMutationsDenied else {
            throw RuntimeObservationError.invalidRuntimeState("ready ownership state is not idle")
        }
        switch scenario {
        case .hiddenOff, .hiddenNoAuthority:
            guard !value.timerRunning, value.timerScheduledCount == 0,
                  value.timerCancelledCount == 0 else {
                throw RuntimeObservationError.invalidRuntimeState("hidden timer started without authority")
            }
        }
    }

    private static func validateFinal(_ value: RuntimeObservationDocument,
                                      after ready: RuntimeObservationDocument,
                                      scenario: RuntimeObservationScenario) throws {
        let (minimumFinalObservation, durationOverflow) = ready.observedMonotonicNanoseconds
            .addingReportingOverflow(scenario.durationNanoseconds)
        guard value.schema == ready.schema, value.scenario == ready.scenario,
              value.pid == ready.pid, value.settingsRevision == ready.settingsRevision,
              value.backgroundAuthority == "unavailable",
              value.backgroundAuthority == ready.backgroundAuthority,
              value.applicationHidden, value.applicationHidden == ready.applicationHidden,
              value.sceneLeases == ready.sceneLeases,
              value.explicitWorkLeases == ready.explicitWorkLeases,
              value.scanSessions == ready.scanSessions,
              value.scanActiveWork == ready.scanActiveWork,
              value.allMutationsDenied == ready.allMutationsDenied, !durationOverflow,
              value.observedMonotonicNanoseconds >= minimumFinalObservation else {
            throw RuntimeObservationError.invalidRuntimeState("final ownership state changed")
        }
        switch scenario {
        case .hiddenOff, .hiddenNoAuthority:
            guard !value.timerRunning, value.timerScheduledCount == 0,
                  value.timerCancelledCount == 0 else {
                throw RuntimeObservationError.invalidRuntimeState("hidden timer changed without authority")
            }
        }
    }

    private static func monotonicNanoseconds(since origin: ContinuousClock.Instant) throws -> UInt64 {
        let components = origin.duration(to: ContinuousClock().now).components
        guard components.seconds >= 0, components.attoseconds >= 0 else {
            throw RuntimeObservationError.invalidRuntimeState("monotonic clock moved backwards")
        }
        let (seconds, secondsOverflow) = UInt64(components.seconds)
            .multipliedReportingOverflow(by: 1_000_000_000)
        let (result, additionOverflow) = seconds.addingReportingOverflow(
            UInt64(components.attoseconds) / 1_000_000_000)
        guard !secondsOverflow, !additionOverflow else { throw RuntimeObservationError.counterOverflow }
        return result
    }

    private static func validatedRoot(for paths: AppStoragePaths) throws -> URL {
        let root = paths.home.deletingLastPathComponent()
        let path = root.path
        guard root.lastPathComponent.hasPrefix("tidy-production-runtime-"),
              path.hasPrefix("/private/var/folders/") || path.hasPrefix("/private/tmp/"),
              !path.hasPrefix(NSHomeDirectory() + "/"),
              paths.settings.path.hasPrefix(path + "/state/"),
              paths.journal.path.hasPrefix(path + "/state/") else {
            throw RuntimeObservationError.invalidFixtureRoot
        }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700 else {
            throw RuntimeObservationError.invalidFixtureRoot
        }
        return root
    }

    private static func publish(_ value: RuntimeObservationDocument, named name: String,
                                under directoryURL: URL) throws {
        guard name == "runtime-ready.json" || name == "runtime-final.json" else {
            throw RuntimeObservationError.publication("invalid destination")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard bytes.count <= 16_384 else {
            throw RuntimeObservationError.publication("document exceeds bound")
        }
        let directory = open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw RuntimeObservationError.publication("state directory open") }
        defer { close(directory) }
        var directoryInfo = stat()
        guard fstat(directory, &directoryInfo) == 0, directoryInfo.st_mode & S_IFMT == S_IFDIR,
              directoryInfo.st_uid == geteuid(), directoryInfo.st_mode & 0o777 == 0o700 else {
            throw RuntimeObservationError.publication("unsafe state directory")
        }
        let temporary = ".runtime-observation-\(UUID().uuidString)"
        let fd = openat(directory, temporary,
                        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw RuntimeObservationError.publication("staging open") }
        var fileOpen = true
        defer {
            if fileOpen { close(fd) }
            _ = unlinkat(directory, temporary, 0)
        }
        guard fchmod(fd, 0o600) == 0 else {
            throw RuntimeObservationError.publication("staging mode")
        }
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeBytes {
                Darwin.write(fd, $0.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw RuntimeObservationError.publication("staging write") }
            offset += count
        }
        guard fsync(fd) == 0 else { throw RuntimeObservationError.publication("staging sync") }
        var fileInfo = stat()
        guard fstat(fd, &fileInfo) == 0, fileInfo.st_mode & S_IFMT == S_IFREG,
              fileInfo.st_uid == geteuid(), fileInfo.st_size == off_t(bytes.count),
              fileInfo.st_mode & 0o777 == 0o600 else {
            throw RuntimeObservationError.publication("staging validation")
        }
        let closeResult = close(fd)
        fileOpen = false
        guard closeResult == 0 else { throw RuntimeObservationError.publication("staging close") }
        guard renameatx_np(directory, temporary, directory, name, UInt32(RENAME_EXCL)) == 0 else {
            throw RuntimeObservationError.publication("exclusive publish")
        }
    }
}
#endif
