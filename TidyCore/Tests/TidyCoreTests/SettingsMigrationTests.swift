import Foundation
import Darwin
import Dispatch
import Testing
@testable import TidyCore

private func canonicalSettingsScratchBase() throws -> URL {
    var path = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath("/private/tmp", &path) != nil else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return URL(fileURLWithPath: String(cString: path), isDirectory: true)
}

private struct SettingsScratch {
    let root: URL
    var file: URL { root.appendingPathComponent("config.json") }
    var backup: URL { root.appendingPathComponent("config.backup.json") }
    init() throws {
        root = try canonicalSettingsScratchBase()
            .appendingPathComponent("T05-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
    }
    func seed(_ bytes: Data) throws {
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json",
                                             subdirectory: "Config"))
    return try Data(contentsOf: url)
}
private func expectStoreError(_ expected: SettingsStoreError,
                             _ body: () async throws -> Void) async {
    do { try await body(); Issue.record("Expected \(expected)") }
    catch let error as SettingsStoreError { #expect(error == expected) }
    catch { Issue.record("Unexpected error: \(error)") }
}
private func mode(_ url: URL) throws -> Int {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attrs[.posixPermissions] as? NSNumber).intValue & 0o777
}

@Suite("Settings migration")
struct SettingsMigrationTests {
    @Test func missingOnlyCreatesInMemoryDefaults() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .newDefaults)
        let value = try #require(result.envelope)
        #expect(value.schemaVersion == 2 && value.revision == 0)
        #expect(value.config.gitRoots.isEmpty && value.config.presets.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: s.file.path))
    }

    @Test(arguments: ["v1-original", "v1-memory"])
    func bothHistoricalShapes(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture(name); try s.seed(original)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .migrated && result.recoveryReason == nil)
        let envelope = try #require(result.envelope)
        #expect(envelope.schemaVersion == 2 && envelope.revision == 0)
        let c = envelope.config
        #expect(c.schemaVersion == 2 && c.hasCompletedOnboarding)
        #expect(c.gitRoots == ["/fixture/Developer", "/fixture/Other"])
        #expect(c.keepCookieDomains == ["example.invalid", "keep.invalid"])
        #expect(c.simulatorsApprovedForDeletion == ["Old simulator name"])
        #expect(c.staleNodeModulesThresholdDays == 90 && c.transcriptAgeThresholdDays == 120)
        #expect(c.presets == [CustomPreset(name: "Weekly", itemIDs: [
            "safe.tool.npm-cache-clean", "unknown.preset.id", "deep.simulator.erase-all"])])
        #expect(c.appsApprovedForQuit == (name == "v1-memory" ? ["Old application name"] : []))
        #expect(c.allowRestartToReclaimSwap == (name == "v1-memory"))
        #expect(try Data(contentsOf: s.file) == original)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
    }


    @Test(arguments: ["corrupt", "v999"])
    func recoveryPreservesBytes(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture(name); try s.seed(bytes)
        let store = SettingsStore(url: s.file); let result = await store.load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(result.recoveryReason == (name == "v999" ? .unsupportedSchema(999) : .malformed))
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        await expectStoreError(.readOnlyRecovery) { _ = try await store.previewRollback() }
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
    }

    @Test(arguments: [Data(), Data("{\"schemaVersion\":1,\"hasCompletedOnboarding\":false}".utf8),
                       Data("{\"schemaVersion\":1,\"schemaVersion\":2}".utf8),
                       Data(repeating: 0x20, count: 1_048_577), Data([0xff, 0xfe])])
    func existingInvalidIsNeverNewDefaults(bytes: Data) async throws {
        let s = try SettingsScratch(); defer { s.remove() }; try s.seed(bytes)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(try Data(contentsOf: s.file) == bytes)
    }

    @Test func symlinkDoesNotAuthorizeReadingOrReplacingDestination() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let target = s.root.appendingPathComponent("other.json")
        let bytes = try fixture("v1-original"); try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: s.file, withDestinationURL: target)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly)
        #expect(try Data(contentsOf: target) == bytes)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: s.file.path) == target.path)
    }
    @Test func oldReportsHaveUnavailableMemoryNotMeasuredZero() throws {
        let report = try JSONDecoder().decode(RunReport.self, from: fixture("old-report"))
        #expect(report.totalFreedBytes == 13)
        #expect(report.results[0].measuredReclaimedMemoryBytes == nil)
        #expect(report.measuredTotalReclaimedMemoryBytes == nil)
        let roundTrip = try JSONDecoder().decode(RunReport.self, from: JSONEncoder().encode(report))
        #expect(roundTrip.measuredTotalReclaimedMemoryBytes == nil)
        #expect(roundTrip.results[0].measuredReclaimedMemoryBytes == nil)
    }

    @Test func emptyHistoricalAndCoordinatorReportsHaveUnavailableMemoryNotMeasuredZero() throws {
        let historical = try JSONDecoder().decode(RunReport.self, from: Data(#"{"tier":"safe","results":[],"startedAt":0,"finishedAt":1,"freeSpaceBeforeBytes":0,"freeSpaceAfterBytes":0}"#.utf8))
        #expect(historical.measuredTotalReclaimedMemoryBytes == nil)
        let historicalRoundTrip = try JSONDecoder().decode(RunReport.self,
            from: JSONEncoder().encode(historical))
        #expect(historicalRoundTrip.measuredTotalReclaimedMemoryBytes == nil)
        for disposition in [RunDisposition.invalidToken, .noWork] {
            let report = RunReport(tier: .safe, results: [],
                startedAt: Date(timeIntervalSince1970: 100), finishedAt: Date(timeIntervalSince1970: 101),
                freeSpaceBeforeBytes: 0, freeSpaceAfterBytes: 0,
                disposition: disposition, coordinatorMeasurementsAvailable: false)
            #expect(report.measuredTotalReclaimedMemoryBytes == nil)
            let roundTrip = try JSONDecoder().decode(RunReport.self, from: JSONEncoder().encode(report))
            #expect(roundTrip.measuredTotalReclaimedMemoryBytes == nil)
            #expect(roundTrip.disposition == disposition)
        }
    }
}

extension SettingsMigrationTests {
    @Test(arguments: ["config.backup.json", "config.lock"])
    func missingConfigWithHistoricalAuxiliaryIsRecovery(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let auxiliary = s.root.appendingPathComponent(name)
        let bytes = name == "config.backup.json" ? try fixture("v1-original")
            : Data(#"{"schema":1,"storeID":"11111111-1111-1111-1111-111111111111"}"#.utf8)
        try bytes.write(to: auxiliary)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: auxiliary.path)
        let store = SettingsStore(url: s.file)
        let result = await store.load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(result.recoveryReason == .unavailable)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        #expect(try Data(contentsOf: auxiliary) == bytes && mode(auxiliary) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == [name])
    }

    @Test func directoryAndUnreadableExistingFilesNeverBecomeDefaults() async throws {
        let directory = try SettingsScratch(); defer { directory.remove() }
        try FileManager.default.createDirectory(at: directory.file, withIntermediateDirectories: false)
        let directoryResult = await SettingsStore(url: directory.file).load()
        #expect(directoryResult.disposition == .recoveryReadOnly && directoryResult.envelope == nil)
        #expect(directoryResult.recoveryReason == .unsafeLocation)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.file.path).isEmpty)
        guard geteuid() != 0 else { Issue.record("Requires ordinary unprivileged test user"); return }
        let unreadable = try SettingsScratch(); defer { unreadable.remove() }
        let bytes = try fixture("v1-original"); try unreadable.seed(bytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.file.path) }
        let result = await SettingsStore(url: unreadable.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(result.recoveryReason == .unavailable)
        #expect(try mode(unreadable.file) == 0)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.file.path)
        #expect(try Data(contentsOf: unreadable.file) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: unreadable.root.path) == ["config.json"])
    }

    @Test func validStatePersistenceRemainsUnavailableAndRecoveryRejectsRollback() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        let store = SettingsStore(url: s.file)
        let loaded = await store.load()
        let config = try #require(loaded.envelope).config
        // Internal construction is possible only under @testable; it grants no production write path.
        let preview = SettingsRollbackPreview(config: config, identity: UUID())
        await expectStoreError(.unavailable) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        await expectStoreError(.unavailable) { _ = try await store.previewRollback() }
        await expectStoreError(.unavailable) { _ = try await store.rollback(expectedRevision: 0, preview: preview) }
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
        let corrupt = try fixture("corrupt"); try s.seed(corrupt)
        #expect(await store.load().disposition == .recoveryReadOnly)
        await expectStoreError(.readOnlyRecovery) { _ = try await store.rollback(expectedRevision: 0, preview: preview) }
        #expect(try Data(contentsOf: s.file) == corrupt)
    }

    @Test func strictBoundsAndTypesRejectOtherwiseValidSettings() async throws {
        let original = String(decoding: try fixture("v1-original"), as: UTF8.self)
        let invalid = [
            original.replacingOccurrences(of: "\"schemaVersion\":1", with: #""schemaVersion":1,"schema\u0056ersion":1"#),
            original.replacingOccurrences(of: "\"staleNodeModulesThresholdDays\":90", with: "\"staleNodeModulesThresholdDays\":9223372036854775808"),
            original.replacingOccurrences(of: "\"staleNodeModulesThresholdDays\":90", with: "\"staleNodeModulesThresholdDays\":true"),
            original.replacingOccurrences(of: "\"staleNodeModulesThresholdDays\":90", with: "\"staleNodeModulesThresholdDays\":90.5"),
            original.replacingOccurrences(of: "\"hasCompletedOnboarding\":true", with: "\"hasCompletedOnboarding\":1"),
            original.replacingOccurrences(of: "\"staleNodeModulesThresholdDays\":90", with: "\"staleNodeModulesThresholdDays\":6"),
            original.replacingOccurrences(of: "\"transcriptAgeThresholdDays\":120", with: "\"transcriptAgeThresholdDays\":366")
        ]
        var tooManyProfiles = try #require(JSONSerialization.jsonObject(with: fixture("v1-original")) as? [String: Any])
        tooManyProfiles["presets"] = Array(repeating: ["name": "Profile", "itemIDs": [String]()] as [String: Any], count: 51)
        for bytes in invalid.map({ Data($0.utf8) }) + [try JSONSerialization.data(withJSONObject: tooManyProfiles)] {
            let s = try SettingsScratch(); defer { s.remove() }; try s.seed(bytes)
            let result = await SettingsStore(url: s.file).load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            #expect(try Data(contentsOf: s.file) == bytes)
        }
    }

    @Test func exactCollectionStringAndByteBoundsRemainReadable() async throws {
        var object = try #require(JSONSerialization.jsonObject(with: fixture("v1-original")) as? [String: Any])
        object["gitRoots"] = Array(repeating: "/fixture/root", count: 1000)
        object["presets"] = Array(repeating: ["name": String(repeating: "x", count: 4096), "itemIDs": [String]()] as [String: Any], count: 50)
        var bytes = try JSONSerialization.data(withJSONObject: object)
        bytes.append(Data(repeating: 0x20, count: 1_048_576 - bytes.count))
        let s = try SettingsScratch(); defer { s.remove() }; try s.seed(bytes)
        #expect(await SettingsStore(url: s.file).load().disposition == .migrated)
        #expect(try Data(contentsOf: s.file) == bytes)
    }

    @Test func explicitZeroMixedUnknownAndOverflowMemoryStayTruthful() throws {
        func report(_ items: [ItemResult]) -> RunReport {
            RunReport(tier: .safe, results: items, startedAt: Date(), finishedAt: Date(),
                freeSpaceBeforeBytes: 0, freeSpaceAfterBytes: 0)
        }
        let zero = ItemResult(id: "zero", title: "Zero", freedBytes: 0, reclaimedMemoryBytes: 0, succeeded: true)
        let unknown = ItemResult(id: "unknown", title: "Unknown", freedBytes: 0, succeeded: true)
        #expect(zero.measuredReclaimedMemoryBytes == 0)
        #expect(unknown.measuredReclaimedMemoryBytes == nil)
        #expect(report([zero]).measuredTotalReclaimedMemoryBytes == 0)
        #expect(report([zero, unknown]).measuredTotalReclaimedMemoryBytes == nil)
        let largest = ItemResult(id: "large", title: "Large", freedBytes: 0, reclaimedMemoryBytes: .max, succeeded: true)
        #expect(report([largest, largest]).measuredTotalReclaimedMemoryBytes == nil)
        let encoded = try JSONEncoder().encode(report([zero, unknown]))
        let decoded = try JSONDecoder().decode(RunReport.self, from: encoded)
        #expect(decoded.results[0].measuredReclaimedMemoryBytes == 0)
        #expect(decoded.results[1].measuredReclaimedMemoryBytes == nil)
        #expect(decoded.measuredTotalReclaimedMemoryBytes == nil)
        let legacyExplicit = try JSONDecoder().decode(ItemResult.self,
            from: Data(#"{"id":"x","title":"X","freedBytes":0,"reclaimedMemoryBytes":0,"succeeded":true}"#.utf8))
        #expect(legacyExplicit.measuredReclaimedMemoryBytes == 0)
    }

    private func schema2(nestedVersion: Int = 2, revision: UInt64 = 0,
                         extra: [String: Any] = [:]) throws -> Data {
        var config = try #require(JSONSerialization.jsonObject(with: fixture("v1-original")) as? [String: Any])
        config["schemaVersion"] = nestedVersion
        config["appsApprovedForQuit"] = [String]()
        config["allowRestartToReclaimSwap"] = false
        var envelope: [String: Any] = ["schemaVersion": 2, "revision": NSNumber(value: revision), "config": config]
        for (key, value) in extra { envelope[key] = value }
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    @Test func knownSchema2LoadsNonzeroRevisionWithoutWriting() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try schema2(revision: 41); try s.seed(bytes)
        let expected = TidyConfig(schemaVersion: 2, hasCompletedOnboarding: true,
            keepCookieDomains: ["example.invalid", "keep.invalid"],
            simulatorsApprovedForDeletion: ["Old simulator name"],
            gitRoots: ["/fixture/Developer", "/fixture/Other"],
            staleNodeModulesThresholdDays: 90, transcriptAgeThresholdDays: 120,
            appsApprovedForQuit: [], allowRestartToReclaimSwap: false,
            presets: [CustomPreset(name: "Weekly", itemIDs: [
                "safe.tool.npm-cache-clean", "unknown.preset.id", "deep.simulator.erase-all"])])
        let store = SettingsStore(url: s.file)
        let result = await store.load()
        #expect(result.disposition == .loaded && result.recoveryReason == nil)
        let envelope = try #require(result.envelope)
        #expect(envelope.schemaVersion == 2 && envelope.revision == 41)
        #expect(envelope.config == expected)
        #expect(await store.load() == result)
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
    }

    @Test func unknownSchema2ExtensionAndNestedMismatchAreReadOnly() async throws {
        var nestedUnknown = try #require(JSONSerialization.jsonObject(with: schema2()) as? [String: Any])
        var config = try #require(nestedUnknown["config"] as? [String: Any])
        config["registryPreferences"] = ["feature.rescue": true]
        nestedUnknown["config"] = config
        var presetUnknown = try #require(JSONSerialization.jsonObject(with: schema2()) as? [String: Any])
        config.removeValue(forKey: "registryPreferences")
        config["presets"] = [["name": "Weekly", "itemIDs": ["unknown.preset.id"], "future": true] as [String: Any]]
        presetUnknown["config"] = config
        for bytes in [try schema2(extra: ["registryPreferences": ["feature.rescue": true]]),
                      try schema2(nestedVersion: 1),
                      try JSONSerialization.data(withJSONObject: nestedUnknown),
                      try JSONSerialization.data(withJSONObject: presetUnknown)] {
            let s = try SettingsScratch(); defer { s.remove() }; try s.seed(bytes)
            let store = SettingsStore(url: s.file); let result = await store.load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            await expectStoreError(.readOnlyRecovery) {
                _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
            }
            await expectStoreError(.readOnlyRecovery) { _ = try await store.previewRollback() }
            #expect(try Data(contentsOf: s.file) == bytes)
            #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        }
    }


    @Test func depthListAndStringBoundsRejectWithoutRewrite() async throws {
        var base = try #require(JSONSerialization.jsonObject(with: fixture("v1-original")) as? [String: Any])
        var largeList = base; largeList["gitRoots"] = Array(repeating: "/fixture/root", count: 1001)
        var longString = base; longString["gitRoots"] = [String(repeating: "x", count: 4097)]
        var nested: Any = "leaf"
        for _ in 0..<17 { nested = ["next": nested] }
        base["unknownNested"] = nested
        for object in [largeList, longString, base] {
            let s = try SettingsScratch(); defer { s.remove() }
            let bytes = try JSONSerialization.data(withJSONObject: object); try s.seed(bytes)
            let result = await SettingsStore(url: s.file).load()
            #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
            #expect(try Data(contentsOf: s.file) == bytes)
        }
    }

    @Test func ownedLegacy755DirectoryAnd644FileMigrateWithoutSilentChmod() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: s.file.path)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .migrated && result.recoveryReason == nil)
        let envelope = try #require(result.envelope)
        #expect(envelope.schemaVersion == 2 && envelope.revision == 0)
        #expect(envelope.config.gitRoots == ["/fixture/Developer", "/fixture/Other"])
        #expect(try mode(s.root) == 0o755 && mode(s.file) == 0o644)
        #expect(try Data(contentsOf: s.file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.root.path) == ["config.json"])
    }
    @Test(arguments: [true, false])
    func groupWritableLegacyLocationIsReadOnly(directory: Bool) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        let changed = directory ? s.root : s.file
        let permissions = directory ? 0o770 : 0o660
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: changed.path)
        let result = await SettingsStore(url: s.file).load()
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        #expect(try mode(changed) == permissions)
        #expect(try Data(contentsOf: s.file) == bytes)
    }

    @Test(arguments: ["config.lock", "config.backup.json"])
    func unsafeExistingAuxiliaryFilesAreNotRepaired(name: String) async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let bytes = try fixture("v1-original"); try s.seed(bytes)
        let auxiliary = s.root.appendingPathComponent(name)
        let sentinel = Data("preserve unsafe auxiliary".utf8)
        try sentinel.write(to: auxiliary)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: auxiliary.path)
        let store = SettingsStore(url: s.file)
        #expect(await store.load().disposition == .recoveryReadOnly)
        await expectStoreError(.readOnlyRecovery) {
            _ = try await store.update(expectedRevision: 0, change: .transcriptAgeDays(90))
        }
        #expect(try Data(contentsOf: auxiliary) == sentinel && mode(auxiliary) == 0o666)
        #expect(try Data(contentsOf: s.file) == bytes)
    }
}

private final class SettingsFIFOReadWatchdog {
    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        func markFired() { lock.lock(); fired = true; lock.unlock() }
        func didFire() -> Bool { lock.lock(); defer { lock.unlock() }; return fired }
    }
    private let completed = DispatchSemaphore(value: 0)
    private let drained = DispatchSemaphore(value: 0)
    private let outcome = Outcome()
    private let worker: Thread

    init(fifo: URL) throws {
        let reader = open(fifo.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard reader >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        // Prove rescue is possible, then leave NO writer alive during the call.
        let probe = open(fifo.path, O_WRONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard probe >= 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(reader); throw error
        }
        close(probe)
        let completed = self.completed, drained = self.drained, outcome = self.outcome
        let path = fifo.path
        worker = Thread {
            var writer: Int32 = -1
            if completed.wait(timeout: .now() + .seconds(5)) == .timedOut {
                outcome.markFired()
                writer = open(path, O_WRONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                guard writer >= 0 else {
                    fatalError("Settings FIFO rescue failed (errno \(errno)); retaining scratch at \(path) because settings I/O may still be active")
                }
                completed.wait()
            }
            if writer >= 0 { close(writer) }
            close(reader) // ownership transferred after successful initialization
            drained.signal()
        }
        worker.start()
    }
    func finishAndDrain() -> Bool {
        completed.signal()
        drained.wait()
        while !worker.isFinished { Thread.sleep(forTimeInterval: 0.001) }
        return outcome.didFire()
    }
}

private func withSettingsFIFORescue<Value>(
    _ fifo: URL, operation: () async throws -> Value
) async throws -> Result<Value, Error> {
    let watchdog = try SettingsFIFOReadWatchdog(fifo: fifo)
    let result: Result<Value, Error>
    do { result = .success(try await operation()) }
    catch { result = .failure(error) }
    let fired = watchdog.finishAndDrain() // before any assertion can throw/return
    #expect(!fired, "Settings I/O needed the FIFO rescue writer after five seconds")
    return result
}

private func expectFIFOStoreError<Value>(_ expected: SettingsStoreError,
                                         result: Result<Value, Error>) {
    switch result {
    case .success: Issue.record("Expected settings error \(expected)")
    case .failure(let error):
        guard let error = error as? SettingsStoreError else {
            Issue.record("Wrong settings error: \(error)"); return
        }
        #expect(error == expected)
    }
}

private struct SettingsFIFOImage {
    let fifo: URL
    let before: stat
    let names: [String]
    let regularBytes: [String: Data]
    let regularModes: [String: mode_t]
    let regularDevices: [String: dev_t]
    let regularInodes: [String: ino_t]
    let directoryMode: mode_t

    init(scratch: SettingsScratch, name: String) throws {
        fifo = scratch.root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: fifo.path) {
            // Only an exact existing disposable regular fixture is moved aside.
            let retained = scratch.root.appendingPathComponent("retained-original-" + name)
            try FileManager.default.moveItem(at: fifo, to: retained)
        }
        try #require(mkfifo(fifo.path, 0o600) == 0)
        var info = stat(), directory = stat()
        try #require(lstat(fifo.path, &info) == 0)
        try #require(info.st_mode & S_IFMT == S_IFIFO)
        try #require(info.st_mode & 0o777 == 0o600)
        try #require(lstat(scratch.root.path, &directory) == 0)
        before = info; directoryMode = directory.st_mode
        names = try FileManager.default.contentsOfDirectory(atPath: scratch.root.path).sorted()
        var bytes: [String: Data] = [:], modes: [String: mode_t] = [:]
        var devices: [String: dev_t] = [:], inodes: [String: ino_t] = [:]
        for other in names where other != name {
            let url = scratch.root.appendingPathComponent(other)
            var regular = stat()
            try #require(lstat(url.path, &regular) == 0 && regular.st_mode & S_IFMT == S_IFREG)
            bytes[other] = try Data(contentsOf: url)
            modes[other] = regular.st_mode
            devices[other] = regular.st_dev
            inodes[other] = regular.st_ino
        }
        regularBytes = bytes; regularModes = modes
        regularDevices = devices; regularInodes = inodes
    }
    func expectPreserved(in scratch: SettingsScratch) throws {
        var after = stat(), directory = stat()
        try #require(lstat(fifo.path, &after) == 0)
        #expect(after.st_mode & S_IFMT == S_IFIFO)
        #expect(after.st_dev == before.st_dev && after.st_ino == before.st_ino)
        #expect(after.st_mode == before.st_mode)
        try #require(lstat(scratch.root.path, &directory) == 0)
        #expect(directory.st_mode == directoryMode)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.root.path).sorted() == names)
        for (name, bytes) in regularBytes {
            let url = scratch.root.appendingPathComponent(name)
            var info = stat()
            try #require(lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG)
            #expect(try Data(contentsOf: url) == bytes)
            #expect(info.st_mode == regularModes[name])
            #expect(info.st_dev == regularDevices[name] && info.st_ino == regularInodes[name])
        }
    }
}

extension SettingsMigrationTests {
    @Test func fifoConfigReadRejectsPromptlyWithoutBootstrap() async throws {
        let s = try SettingsScratch(); defer { s.remove() }
        let original = try fixture("v1-original"); try s.seed(original)
        let image = try SettingsFIFOImage(scratch: s, name: "config.json")
        let store = SettingsStore(url: s.file)
        let load = try await withSettingsFIFORescue(image.fifo) { await store.load() }
        let result = try load.get() // watchdog already drained
        #expect(result.disposition == .recoveryReadOnly && result.envelope == nil)
        let edit = try await withSettingsFIFORescue(image.fifo) {
            try await store.update(expectedRevision: 0, change: .transcriptAgeDays(60))
        }
        expectFIFOStoreError(.readOnlyRecovery, result: edit)
        try image.expectPreserved(in: s)
        #expect(try Data(contentsOf: s.root.appendingPathComponent("retained-original-config.json")) == original)
        #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.lock").path))
        #expect(!FileManager.default.fileExists(atPath: s.root.appendingPathComponent("config.store.json").path))
        #expect(!FileManager.default.fileExists(atPath: s.backup.path))
        withExtendedLifetime(store) {}
    }
}
