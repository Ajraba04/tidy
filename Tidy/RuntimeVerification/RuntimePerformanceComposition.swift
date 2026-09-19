#if TIDY_RUNTIME_TEST_HOST
import Darwin
import Foundation
import SwiftUI
import TidyCore

private enum RuntimePerformanceScenario: String {
    case performance50k = "performance-50k"
    case activeCancel20 = "active-cancel-20"
}

private enum RuntimePerformanceError: Error, CustomStringConvertible {
    case invalidScenario
    case invalidRoot
    case invalidFixture(String)
    case missingUsefulProgress
    case missingTerminal
    case missingResult
    case terminalTimeout
    case didNotSettle(String)
    case counterOverflow
    case publication(String)

    var description: String {
        switch self {
        case .invalidScenario: return "unsupported performance scenario"
        case .invalidRoot: return "unsafe performance fixture root"
        case .invalidFixture(let detail): return "invalid performance fixture: \(detail)"
        case .missingUsefulProgress: return "scan produced no useful progress"
        case .missingTerminal: return "scan produced no terminal"
        case .missingResult: return "scan terminal has no retained result"
        case .terminalTimeout: return "scan terminal deadline expired"
        case .didNotSettle(let detail): return "scan ownership did not settle: \(detail)"
        case .counterOverflow: return "performance counter overflow"
        case .publication(let detail): return "performance publication failed: \(detail)"
        }
    }
}

private struct Runtime50kDocument: Codable, Sendable {
    let schema: Int
    let scenario: String
    let pid: Int
    let fixtureDirectories: Int
    let fixtureFiles: Int
    let fixtureLogicalBytes: Int64
    let fixtureAllocatedBytes: Int64
    let requestNanoseconds: UInt64
    let firstRegistryProgressNanoseconds: UInt64
    let firstRenderableUsefulResultNanoseconds: UInt64
    let terminalNanoseconds: UInt64
    let workersSettledNanoseconds: UInt64
    let terminal: String
    let completeCoverage: Bool
    let processedEntries: Int
    let metadataVisits: Int
    let schedulerWorkers: Int
    let registrySessions: Int
    let registryActiveWork: Int
    let retainedTerminalStates: Int
    let allMutationsDenied: Bool
    let witnessUnchanged: Bool
    let settled: Bool
    let passed: Bool
}

private struct RuntimePerformanceReadyDocument: Codable, Sendable {
    let schema: Int
    let scenario: String
    let pid: Int
    let fixtureFiles: Int
    let fixtureLogicalBytes: Int64
    let fixtureAllocatedBytes: Int64
    let registrySessions: Int
    let registryActiveWork: Int
    let schedulerActive: Int
    let schedulerQueued: Int
    let schedulerLiveSessions: Int
    let explicitLeases: Int
    let indexWatchActive: Bool
    let allMutationsDenied: Bool
    let witnessUnchanged: Bool
    let settled: Bool
}

private struct RuntimePerformanceErrorDocument: Codable, Sendable {
    let schema: Int
    let scenario: String
    let pid: Int
    let message: String
}

private struct RuntimeCycleDocument: Codable, Sendable {
    let schema: Int
    let scenario: String
    let pid: Int
    let cycleCount: Int
    let cancelRequested: Int
    let terminalCancelled: Int
    let completedBeforeCancel: Int
    let otherTerminal: Int
    let maxCancelToTerminalNanoseconds: UInt64
    let maxCancelToSettledNanoseconds: UInt64
    let registrySessions: Int
    let registryActiveWork: Int
    let retainedTerminalStates: Int
    let schedulerActive: Int
    let schedulerQueued: Int
    let schedulerLiveSessions: Int
    let explicitLeases: Int
    let indexWatchActive: Bool
    let allMutationsDenied: Bool
    let witnessUnchanged: Bool
    let settled: Bool
    let passed: Bool
}

private struct RuntimeFixtureMeasurement {
    let directories: Int
    let files: Int
    let logicalBytes: Int64
    let allocatedBytes: Int64
}

private final class RuntimeTimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var expired = false
    func markExpired() { lock.withLock { expired = true } }
    var isExpired: Bool { lock.withLock { expired } }
}

private struct RuntimeSettledState {
    let registry: ScanSessionRegistrySnapshot
    let scheduler: WorkSchedulerSnapshot
    let explicitLeases: Int
    let indexWatchActive: Bool
    let serviceActive: Bool

    var isSettled: Bool {
        !serviceActive && registry.activeWork == 0 && scheduler.active == 0
            && scheduler.queued == 0 && scheduler.liveSessions == 0
            && explicitLeases == 0 && !indexWatchActive
    }

    var diagnostic: String {
        "serviceActive:\(serviceActive) registry:\(registry.sessions)/\(registry.activeWork)/"
            + "\(registry.retainedTerminalStates) scheduler:\(scheduler.active)/"
            + "\(scheduler.queued)/\(scheduler.liveSessions) leases:\(explicitLeases) "
            + "watch:\(indexWatchActive)"
    }
}

@MainActor
struct RuntimePerformanceControl: View {
    let services: AppExecutionServices
    let scenario: RuntimeTestScenario
    @State private var state = "not-required"

    var body: some View {
        Text(state)
            .font(.caption)
            .accessibilityLabel("Runtime performance state")
            .accessibilityValue(state)
            .accessibilityIdentifier("runtime.performance.state")
            .task {
                guard RuntimePerformanceCoordinator.supports(scenario) else { return }
                state = "running"
                state = await RuntimePerformanceCoordinator.startIfNeeded(
                    services: services, scenario: scenario)
            }
    }
}

enum RuntimePerformanceCoordinator {
    @MainActor private static var activeTask: Task<String, Never>?

    static func supports(_ scenario: RuntimeTestScenario) -> Bool {
        RuntimePerformanceScenario(rawValue: scenario.rawValue) != nil
    }

    @MainActor
    static func startIfNeeded(services: AppExecutionServices,
                              scenario: RuntimeTestScenario) async -> String {
        if let activeTask { return await activeTask.value }
        let task = Task { @MainActor in
            var fixedScenario: RuntimePerformanceScenario?
            var stateDirectory: URL?
            do {
                guard let fixed = RuntimePerformanceScenario(rawValue: scenario.rawValue) else {
                    throw RuntimePerformanceError.invalidScenario
                }
                fixedScenario = fixed
                let root = try validatedRoot(for: services.paths)
                let state = services.paths.settings.deletingLastPathComponent()
                stateDirectory = state
                Swift.print("TIDY_RUNTIME_ROOT=\(root.path)")
                fflush(stdout)
                let ready = try await makeReadyDocument(services: services, scenario: fixed)
                try publish(ready, named: "runtime-performance-ready.json", under: state)
                Swift.print("TIDY_RUNTIME_PERFORMANCE_READY=runtime-performance-ready.json")
                fflush(stdout)
                try await waitForProceed(under: state)
                switch fixed {
                case .performance50k:
                    let document = try await run50k(services: services)
                    try publish(document, named: "runtime-performance.json",
                                under: state)
                    Swift.print("TIDY_RUNTIME_PERFORMANCE_FINAL=runtime-performance.json")
                    fflush(stdout)
                    return "published passed:\(document.passed)"
                case .activeCancel20:
                    let document = try await runCycles(services: services)
                    try publish(document, named: "runtime-cycles.json",
                                under: state)
                    Swift.print("TIDY_RUNTIME_PERFORMANCE_FINAL=runtime-cycles.json")
                    fflush(stdout)
                    return "published passed:\(document.passed)"
                }
            } catch is CancellationError {
                return "failed cancelled"
            } catch {
                let message = String(String(describing: error).prefix(1_024))
                if let fixedScenario, let stateDirectory {
                    let document = RuntimePerformanceErrorDocument(schema: 1,
                        scenario: fixedScenario.rawValue, pid: Int(getpid()), message: message)
                    try? publish(document, named: "runtime-performance-error.json",
                                 under: stateDirectory)
                    Swift.print("TIDY_RUNTIME_PERFORMANCE_ERROR=runtime-performance-error.json")
                    fflush(stdout)
                }
                return "failed \(message)"
            }
        }
        activeTask = task
        return await task.value
    }

    @MainActor
    private static func makeReadyDocument(services: AppExecutionServices,
                                          scenario: RuntimePerformanceScenario) async throws
      -> RuntimePerformanceReadyDocument {
        let settled = try await currentState(services: services)
        guard settled.isSettled else {
            throw RuntimePerformanceError.didNotSettle(settled.diagnostic)
        }
        let fixture: RuntimeFixtureMeasurement
        switch scenario {
        case .performance50k, .activeCancel20:
            fixture = try measure50kFixture(home: services.paths.home)
            guard fixture.directories == 500, fixture.files == 50_000,
                  fixture.logicalBytes == 0 else {
                throw RuntimePerformanceError.invalidFixture("ready fixture mismatch")
            }
        }
        return RuntimePerformanceReadyDocument(schema: 1, scenario: scenario.rawValue,
            pid: Int(getpid()), fixtureFiles: fixture.files,
            fixtureLogicalBytes: fixture.logicalBytes,
            fixtureAllocatedBytes: fixture.allocatedBytes,
            registrySessions: settled.registry.sessions,
            registryActiveWork: settled.registry.activeWork,
            schedulerActive: settled.scheduler.active,
            schedulerQueued: settled.scheduler.queued,
            schedulerLiveSessions: settled.scheduler.liveSessions,
            explicitLeases: settled.explicitLeases,
            indexWatchActive: settled.indexWatchActive,
            allMutationsDenied: RuntimeTestComposition.authorizationState == "all-denied",
            witnessUnchanged: witnessUnchanged(paths: services.paths),
            settled: settled.isSettled)
    }

    private static func waitForProceed(under directory: URL) async throws {
        let signal = directory.appendingPathComponent("runtime-performance-proceed")
        let expected = Data("TIDY_RUNTIME_PROCEED_V1\n".utf8)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(60))
        while clock.now < deadline {
            try Task.checkCancellation()
            var info = stat()
            if lstat(signal.path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
                      info.st_mode & 0o777 == 0o600, info.st_nlink == 1,
                      info.st_size == expected.count,
                      (try? Data(contentsOf: signal)) == expected else {
                    throw RuntimePerformanceError.publication("invalid proceed signal")
                }
                return
            }
            guard errno == ENOENT else {
                throw RuntimePerformanceError.publication("proceed signal lstat")
            }
            try await clock.sleep(for: .milliseconds(50))
        }
        throw RuntimePerformanceError.publication("proceed signal timeout")
    }

    @MainActor
    static func stopIfActive() async {
        let task = activeTask
        activeTask = nil
        task?.cancel()
        _ = await task?.value
    }

    @MainActor
    private static func run50k(services: AppExecutionServices) async throws
      -> Runtime50kDocument {
        let fixture = try measure50kFixture(home: services.paths.home)
        guard fixture.directories == 500, fixture.files == 50_000,
              fixture.logicalBytes == 0 else {
            throw RuntimePerformanceError.invalidFixture(
                "dirs=\(fixture.directories) files=\(fixture.files) logical=\(fixture.logicalBytes)")
        }
        let schedulerAtRequest = await services.explicitSessions.snapshot()
        guard schedulerAtRequest.effectiveWorkers > 0 else {
            throw RuntimePerformanceError.invalidFixture("scheduler has no workers")
        }
        let clock = ContinuousClock()
        let origin = clock.now
        let request = try nanoseconds(since: origin)
        let ownerID = UUID()
        let consent = try services.issueFullHomeScanConsent(ownerID: ownerID)
        let environment = services.configStore.config.makePolicyEnvironment(
            homeDirectory: services.paths.home.path, detectedTools: [])
        let handle = try await services.beginScan(environment: environment,
            request: .fullHome(consent), ownerID: ownerID)
        let subscription = try await services.scanRegistry.subscribe(sessionID: handle.sessionID)
        let timeout = RuntimeTimeoutFlag()
        let watchdog = Task { @MainActor in
            do { try await clock.sleep(for: .seconds(120)) }
            catch { return }
            timeout.markExpired()
            await services.cancelActiveScan()
            await subscription.cancel()
        }
        defer { watchdog.cancel() }
        let fixtureName = services.paths.home.deletingLastPathComponent().lastPathComponent
        var firstRegistryProgress: UInt64?
        var firstRenderableUsefulResult: UInt64?
        var terminalTime: UInt64?
        var terminal: ScanSessionTerminal?
        for await event in subscription.stream {
            if firstRegistryProgress == nil, event.terminal == nil,
               (event.snapshot.processedEntries > 0 || !event.snapshot.items.isEmpty) {
                firstRegistryProgress = try nanoseconds(since: origin)
            }
            if firstRenderableUsefulResult == nil,
               let current = await services.latestScanResult(sessionID: handle.sessionID),
               hasUsefulFixtureRow(current, fixtureName: fixtureName) {
                firstRenderableUsefulResult = try nanoseconds(since: origin)
            }
            if let value = event.terminal {
                terminal = value
                terminalTime = try nanoseconds(since: origin)
                break
            }
        }
        await subscription.cancel()
        if timeout.isExpired { throw RuntimePerformanceError.terminalTimeout }
        guard let firstRegistryProgress, let firstRenderableUsefulResult else {
            throw RuntimePerformanceError.missingUsefulProgress
        }
        guard let terminal, let terminalTime else { throw RuntimePerformanceError.missingTerminal }
        guard let result = await services.latestScanResult(sessionID: handle.sessionID) else {
            throw RuntimePerformanceError.missingResult
        }
        let settled = try await waitForSettled(services: services)
        let workersSettled = try nanoseconds(since: origin)
        guard request <= firstRegistryProgress,
              firstRegistryProgress <= firstRenderableUsefulResult,
              firstRenderableUsefulResult <= terminalTime,
              terminalTime <= workersSettled else {
            throw RuntimePerformanceError.counterOverflow
        }
        let usefulPath = hasUsefulFixtureRow(result, fixtureName: fixtureName)
        let allDenied = RuntimeTestComposition.authorizationState == "all-denied"
        let witness = witnessUnchanged(paths: services.paths)
        let usefulLatency = firstRenderableUsefulResult - request
        let totalLatency = workersSettled - request
        let passed = terminal == .complete && result.coverage.isComplete
            && result.metadataVisits >= 50_000 && usefulPath && settled.isSettled
            && settled.registry.sessions == 1 && settled.registry.retainedTerminalStates == 1
            && usefulLatency <= 1_000_000_000 && totalLatency <= 10_000_000_000
            && allDenied && witness
        return Runtime50kDocument(schema: 1, scenario: RuntimePerformanceScenario.performance50k.rawValue,
            pid: Int(getpid()), fixtureDirectories: fixture.directories,
            fixtureFiles: fixture.files, fixtureLogicalBytes: fixture.logicalBytes,
            fixtureAllocatedBytes: fixture.allocatedBytes, requestNanoseconds: request,
            firstRegistryProgressNanoseconds: firstRegistryProgress,
            firstRenderableUsefulResultNanoseconds: firstRenderableUsefulResult,
            terminalNanoseconds: terminalTime,
            workersSettledNanoseconds: workersSettled, terminal: terminal.rawValue,
            completeCoverage: result.coverage.isComplete,
            processedEntries: (try await services.scanRegistry.state(
                sessionID: handle.sessionID)).snapshot.processedEntries,
            metadataVisits: result.metadataVisits,
            schedulerWorkers: schedulerAtRequest.effectiveWorkers,
            registrySessions: settled.registry.sessions,
            registryActiveWork: settled.registry.activeWork,
            retainedTerminalStates: settled.registry.retainedTerminalStates,
            allMutationsDenied: allDenied, witnessUnchanged: witness,
            settled: settled.isSettled, passed: passed)
    }

    @MainActor
    private static func runCycles(services: AppExecutionServices) async throws
      -> RuntimeCycleDocument {
        let cycleTarget = 20
        var cancelRequested = 0
        var terminalCancelled = 0
        var completedBeforeCancel = 0
        var otherTerminal = 0
        var maxCancelToTerminal: UInt64 = 0
        var maxCancelToSettled: UInt64 = 0

        for _ in 0..<cycleTarget {
            try Task.checkCancellation()
            let ownerID = UUID()
            let consent = try services.issueFullHomeScanConsent(ownerID: ownerID)
            let environment = services.configStore.config.makePolicyEnvironment(
                homeDirectory: services.paths.home.path, detectedTools: [])
            let handle = try await services.beginScan(environment: environment,
                request: .fullHome(consent), ownerID: ownerID)
            let subscription = try await services.scanRegistry.subscribe(sessionID: handle.sessionID)
            let clock = ContinuousClock()
            let timeout = RuntimeTimeoutFlag()
            let watchdog = Task { @MainActor in
                do { try await clock.sleep(for: .seconds(30)) }
                catch { return }
                timeout.markExpired()
                await services.cancelActiveScan()
                await subscription.cancel()
            }
            var cancelOrigin: ContinuousClock.Instant?
            var terminalValue: ScanSessionTerminal?
            var terminalAfterCancel: UInt64?
            for await event in subscription.stream {
                if cancelOrigin == nil, event.terminal == nil,
                   event.snapshot.processedEntries > 0 || !event.snapshot.items.isEmpty {
                    cancelOrigin = clock.now
                    cancelRequested += 1
                    await services.cancelActiveScan()
                }
                if let terminal = event.terminal {
                    terminalValue = terminal
                    if let cancelOrigin {
                        terminalAfterCancel = try nanoseconds(since: cancelOrigin)
                    }
                    break
                }
            }
            watchdog.cancel()
            await subscription.cancel()
            if timeout.isExpired { throw RuntimePerformanceError.terminalTimeout }
            guard let terminalValue else { throw RuntimePerformanceError.missingTerminal }
            if cancelOrigin == nil, terminalValue == .complete {
                completedBeforeCancel += 1
            } else if terminalValue == .cancelled {
                terminalCancelled += 1
            } else {
                otherTerminal += 1
            }
            if let terminalAfterCancel {
                maxCancelToTerminal = max(maxCancelToTerminal, terminalAfterCancel)
            }
            let settled = try await waitForSettled(services: services)
            if let cancelOrigin {
                maxCancelToSettled = max(maxCancelToSettled,
                    try nanoseconds(since: cancelOrigin))
            }
            guard settled.isSettled else {
                throw RuntimePerformanceError.didNotSettle(settled.diagnostic)
            }
        }

        let final = try await currentState(services: services)
        let allDenied = RuntimeTestComposition.authorizationState == "all-denied"
        let witness = witnessUnchanged(paths: services.paths)
        let passed = cancelRequested == cycleTarget && terminalCancelled == cycleTarget
            && completedBeforeCancel == 0 && otherTerminal == 0 && final.isSettled
            && final.registry.sessions == cycleTarget
            && final.registry.retainedTerminalStates == cycleTarget
            && maxCancelToTerminal <= 500_000_000
            && maxCancelToSettled <= 500_000_000
            && allDenied && witness
        return RuntimeCycleDocument(schema: 1,
            scenario: RuntimePerformanceScenario.activeCancel20.rawValue,
            pid: Int(getpid()), cycleCount: cycleTarget, cancelRequested: cancelRequested,
            terminalCancelled: terminalCancelled, completedBeforeCancel: completedBeforeCancel,
            otherTerminal: otherTerminal,
            maxCancelToTerminalNanoseconds: maxCancelToTerminal,
            maxCancelToSettledNanoseconds: maxCancelToSettled,
            registrySessions: final.registry.sessions,
            registryActiveWork: final.registry.activeWork,
            retainedTerminalStates: final.registry.retainedTerminalStates,
            schedulerActive: final.scheduler.active, schedulerQueued: final.scheduler.queued,
            schedulerLiveSessions: final.scheduler.liveSessions,
            explicitLeases: final.explicitLeases, indexWatchActive: final.indexWatchActive,
            allMutationsDenied: allDenied, witnessUnchanged: witness,
            settled: final.isSettled, passed: passed)
    }

    @MainActor
    private static func waitForSettled(services: AppExecutionServices) async throws
      -> RuntimeSettledState {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        var state = try await currentState(services: services)
        while !state.isSettled, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
            state = try await currentState(services: services)
        }
        guard state.isSettled else {
            throw RuntimePerformanceError.didNotSettle(state.diagnostic)
        }
        return state
    }

    @MainActor
    private static func currentState(services: AppExecutionServices) async throws
      -> RuntimeSettledState {
        RuntimeSettledState(registry: await services.scanRegistry.snapshot(),
            scheduler: await services.explicitSessions.snapshot(),
            explicitLeases: await services.systemMonitor.activeExplicitWorkLeaseCountForTesting(),
            indexWatchActive: await services.activeScanIndexWatchIsActiveForTesting(),
            serviceActive: services.activeScanSessionID != nil)
    }

    private static func measure50kFixture(home: URL) throws -> RuntimeFixtureMeasurement {
        let workspace = home.appendingPathComponent("SyntheticWorkspace", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: workspace,
            includingPropertiesForKeys: nil, options: []) else {
            throw RuntimePerformanceError.invalidFixture("enumerator unavailable")
        }
        var directories = 0
        var files = 0
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var witnessSeen = false
        var seenDirectories = Set<String>()
        let expectedDirectories = Set((0..<500).map { String(format: "batch-%03d", $0) })
        let expectedEntries = Set((0..<100).map { String(format: "entry-%03d.bin", $0) })
        for case let url as URL in enumerator {
            let relative = String(url.path.dropFirst(workspace.path.count + 1))
            let components = relative.split(separator: "/").map(String.init)
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                throw RuntimePerformanceError.invalidFixture("lstat \(url.lastPathComponent)")
            }
            if components.count == 1, components[0] == "runtime-witness.txt" {
                guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
                      info.st_nlink == 1,
                      (try? Data(contentsOf: url)) == Data("runtime-witness\n".utf8) else {
                    throw RuntimePerformanceError.invalidFixture("invalid witness")
                }
                witnessSeen = true
            } else if components.count == 1,
                      expectedDirectories.contains(components[0]) {
                guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
                      info.st_mode & 0o777 == 0o700,
                      seenDirectories.insert(components[0]).inserted else {
                    throw RuntimePerformanceError.invalidFixture("invalid batch \(relative)")
                }
                directories += 1
            } else if components.count == 2,
                      expectedDirectories.contains(components[0]),
                      expectedEntries.contains(components[1]) {
                guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
                      info.st_nlink == 1, info.st_size == 0 else {
                    throw RuntimePerformanceError.invalidFixture("invalid entry \(relative)")
                }
                files += 1
                let (nextLogical, logicalOverflow) = logical.addingReportingOverflow(info.st_size)
                let (fileAllocated, allocationOverflow) = Int64(info.st_blocks)
                    .multipliedReportingOverflow(by: 512)
                let (nextAllocated, totalOverflow) = allocated.addingReportingOverflow(fileAllocated)
                guard !logicalOverflow, !allocationOverflow, !totalOverflow else {
                    throw RuntimePerformanceError.counterOverflow
                }
                logical = nextLogical
                allocated = nextAllocated
            } else {
                throw RuntimePerformanceError.invalidFixture("unexpected entry \(relative)")
            }
        }
        guard witnessSeen, seenDirectories == expectedDirectories else {
            throw RuntimePerformanceError.invalidFixture("incomplete directory graph")
        }
        return RuntimeFixtureMeasurement(directories: directories, files: files,
            logicalBytes: logical, allocatedBytes: allocated)
    }

    private static func witnessUnchanged(paths: AppStoragePaths) -> Bool {
        (try? Data(contentsOf: RuntimeTestComposition.witnessURL(home: paths.home)))
            == Data("runtime-witness\n".utf8)
    }

    private static func hasUsefulFixtureRow(_ result: CoreScanResult,
                                            fixtureName: String) -> Bool {
        result.report.topLevelHomeRanking.contains {
            $0.path.contains("/\(fixtureName)/home/SyntheticWorkspace")
        }
    }

    private static func nanoseconds(since origin: ContinuousClock.Instant) throws -> UInt64 {
        let components = origin.duration(to: ContinuousClock().now).components
        guard components.seconds >= 0, components.attoseconds >= 0 else {
            throw RuntimePerformanceError.counterOverflow
        }
        let (seconds, secondsOverflow) = UInt64(components.seconds)
            .multipliedReportingOverflow(by: 1_000_000_000)
        let (total, additionOverflow) = seconds.addingReportingOverflow(
            UInt64(components.attoseconds) / 1_000_000_000)
        guard !secondsOverflow, !additionOverflow else {
            throw RuntimePerformanceError.counterOverflow
        }
        return total
    }

    private static func validatedRoot(for paths: AppStoragePaths) throws -> URL {
        let root = paths.home.deletingLastPathComponent()
        let path = root.path
        guard root.lastPathComponent.hasPrefix("tidy-production-runtime-"),
              path.hasPrefix("/private/var/folders/") || path.hasPrefix("/private/tmp/"),
              !path.hasPrefix(NSHomeDirectory() + "/"),
              paths.settings.path.hasPrefix(path + "/state/"),
              paths.journal.path.hasPrefix(path + "/state/") else {
            throw RuntimePerformanceError.invalidRoot
        }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700 else {
            throw RuntimePerformanceError.invalidRoot
        }
        return root
    }

    private static func publish<T: Encodable>(_ value: T, named name: String,
                                               under directoryURL: URL) throws {
        let allowed = Set(["runtime-performance-ready.json", "runtime-performance.json",
                           "runtime-cycles.json", "runtime-performance-error.json"])
        guard allowed.contains(name) else {
            throw RuntimePerformanceError.publication("invalid name")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard bytes.count <= 32_768 else {
            throw RuntimePerformanceError.publication("oversized document")
        }
        let directory = open(directoryURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw RuntimePerformanceError.publication("directory open") }
        defer { close(directory) }
        var directoryInfo = stat()
        guard fstat(directory, &directoryInfo) == 0,
              directoryInfo.st_mode & S_IFMT == S_IFDIR,
              directoryInfo.st_uid == geteuid(),
              directoryInfo.st_mode & 0o777 == 0o700 else {
            throw RuntimePerformanceError.publication("unsafe directory")
        }
        let temporary = ".runtime-performance-\(UUID().uuidString)"
        let fd = openat(directory, temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw RuntimePerformanceError.publication("staging open") }
        var stagingOpen = true
        defer {
            if stagingOpen { close(fd) }
            _ = unlinkat(directory, temporary, 0)
        }
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw RuntimePerformanceError.publication("write")
                }
                offset += count
            }
        }
        guard fsync(fd) == 0 else {
            throw RuntimePerformanceError.publication("file durability")
        }
        let closeResult = close(fd)
        stagingOpen = false
        guard closeResult == 0, fsync(directory) == 0 else {
            throw RuntimePerformanceError.publication("staging durability")
        }
        guard renameatx_np(directory, temporary, directory, name,
                           UInt32(RENAME_EXCL)) == 0 else {
            throw RuntimePerformanceError.publication("exclusive rename")
        }
    }
}
#endif
