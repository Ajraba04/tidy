import Foundation
import Darwin

/// One installation-wide, fail-closed ledger. No reconciliation/reset API exists here.
final class MutationAdmissionStore {
    private struct Bootstrap: Codable { let schema: Int; let storeID: UUID; let state: String }
    private struct Envelope: Codable { let schema: Int; let storeID: UUID; var unfinished: [PendingEffectIntent] }
    private let directoryFD: Int32
    private let directoryPath: String
    private let lockFD: Int32
    private var held = false
    private var failed = false
    private let io: any JournalPOSIXIO

    let scanLimits: JournalScanLimits
    init(directory: URL, io: any JournalPOSIXIO = DarwinJournalIO(), scanLimits: JournalScanLimits = .production) throws {
        self.scanLimits = scanLimits
        self.io = io
        directoryPath = directory.path
        let dir = try Self.openDirectory(directory.path, create: true)
        do { try Self.validate(dir, directory: true) } catch { close(dir); throw error }
        directoryFD = dir
        let scan: JournalDirectoryScan
        do { scan = try JournalDirectoryScan.read(directoryFD: dir, limits: scanLimits) }
        catch { close(dir); throw ConfirmationError.storageUnavailable }
        var created = false
        var fd: Int32 = -1
        if scan.entryCount == 0 {
            fd = openat(dir, "mutation.lock", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            created = fd >= 0
        }
        if fd < 0 {
            fd = openat(dir, "mutation.lock", O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else { close(dir); throw ConfirmationError.storageUnavailable }
        do { try Self.validate(fd, directory: false) } catch { close(fd); close(dir); throw error }
        lockFD = fd
        if created {
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                failed = true
                return
            }
            held = true
            do {
                let bootstrapScan = try JournalDirectoryScan.read(directoryFD: dir, limits: scanLimits)
                guard bootstrapScan.entryCount == 1, bootstrapScan.containsStableLock else {
                    throw ConfirmationError.storageUnavailable
                }
                let id = UUID()
                try publish(Bootstrap(schema: 1, storeID: id, state: "initializing"), name: "bootstrap.json")
                try publish(Envelope(schema: 1, storeID: id, unfinished: []), name: "unfinished-effects.json")
                try publish(Bootstrap(schema: 1, storeID: id, state: "initialized"), name: "bootstrap.json")
            } catch { failed = true }
            release()
        }
    }

    deinit { release(); close(lockFD); close(directoryFD) }

    func acquire() -> MutationAdmission {
        if held { return readAdmissionWhileLocked() }
        guard !failed else { return .storageUnavailable }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            return errno == EWOULDBLOCK ? .busy : .storageUnavailable
        }
        held = true
        return readAdmissionWhileLocked()
    }

    func release() {
        if held { _ = flock(lockFD, LOCK_UN); held = false }
    }

    func readAdmissionWhileLocked() -> MutationAdmission {
        guard held, !failed else { return .storageUnavailable }
        do {
            try validateStableLock()
            let ledger = try readLedger()
            let scan = try JournalDirectoryScan.read(directoryFD: directoryFD, limits: scanLimits)
            return ledger.unfinished.isEmpty && !scan.containsEffectStage
                ? .ready : .uncertainAndPossiblyRunning
        } catch { return .storageUnavailable }
    }

    func requireJournalLock() throws {
        guard held, !failed else { throw JournalError.unavailable }
        do {
            try validateStableLock()
            _ = try readLedger()
        } catch {
            failed = true
            throw JournalError.unavailable
        }
    }

    func latchJournalStorageFailure() { failed = true }
    func journalDirectoryIdentityWhileLocked() throws -> JournalDirectoryIdentity {
        try requireJournalLock()
        return try JournalFiles.identity(directoryFD)
    }
    func unfinishedIntentsWhileLocked() throws -> [PendingEffectIntent] {
        try requireJournalLock()
        return try readLedger().unfinished
    }
    func withLockedStorage<T>(_ body: (Int32, any JournalPOSIXIO, JournalScanLimits) throws -> T)
        throws -> T {
        try requireJournalLock()
        return try body(directoryFD, io, scanLimits)
    }
    func persistIntentWhileLocked(_ intent: PendingEffectIntent, update: IntentPersistence = .append) throws {
        try requireJournalLock()
        var ledger = try readLedger()
        switch update {
        case .append:
            guard !ledger.unfinished.contains(where: { $0.operationID == intent.operationID }),
                  Self.validIntent(intent),
                  intent.schemaVersion != 3 || Self.serviceChildFieldsAbsent(intent),
                  Self.validChildTuple(intent, allowAbsent: true) else {
                throw JournalError.invalidTransition
            }
            ledger.unfinished.append(intent)
        case .capturedChild:
            guard ledger.unfinished.filter({ $0.operationID == intent.operationID }).count == 1,
                  let index = ledger.unfinished.firstIndex(where: {
                $0.operationID == intent.operationID && $0.runID == intent.runID
            }) else { throw JournalError.invalidTransition }
            let prior = ledger.unfinished[index]
            guard prior.schemaVersion == 1, intent.schemaVersion == 1,
                  Self.validIntent(intent), Self.validChildTuple(intent, allowAbsent: false),
                  prior.adapterID == intent.adapterID, prior.bootID == intent.bootID,
                  prior.executablePath == intent.executablePath,
                  prior.executableDevice == intent.executableDevice, prior.executableInode == intent.executableInode,
                  prior.phase == intent.phase else { throw JournalError.invalidTransition }
            if prior == intent { return }
            guard prior.childPID == nil, prior.childStartSeconds == nil,
                  prior.childStartMicroseconds == nil else { throw JournalError.invalidTransition }
            ledger.unfinished[index] = intent
        case .serviceChildCapture:
            // A syntactically valid tuple is data, not an owned observation.
            throw JournalError.invalidTransition
        case .ownedServiceChildCapture(let receipt):
            try receipt.requireStore(self)
            guard intent == receipt.intent(phase: intent.phase) else { throw JournalError.invalidTransition }
            guard ledger.unfinished.filter({ $0.operationID == intent.operationID }).count == 1,
                  let index = ledger.unfinished.firstIndex(where: {
                      $0.operationID == intent.operationID && $0.runID == intent.runID
                  }) else { throw JournalError.invalidTransition }
            let prior = ledger.unfinished[index]
            guard prior.schemaVersion == 3, intent.schemaVersion == 3,
                  prior.binding == intent.binding, prior.adapterID == intent.adapterID,
                  [.submitted, .uncertainAndPossiblyRunning].contains(prior.phase), prior.phase == intent.phase,
                  Self.validIntent(intent), Self.validChildTuple(intent, allowAbsent: false) else {
                throw JournalError.invalidTransition
            }
            if prior == intent { return }
            guard Self.serviceChildFieldsAbsent(prior) else { throw JournalError.invalidTransition }
            ledger.unfinished[index] = intent
        case .serviceSubmission:
            guard let index = ledger.unfinished.firstIndex(where: {
                $0.operationID == intent.operationID && $0.runID == intent.runID
            }) else { throw JournalError.invalidTransition }
            let prior = ledger.unfinished[index]
            guard prior.schemaVersion == 3, intent.schemaVersion == 3,
                  prior.phase == .prepared, intent.phase == .submitted,
                  Self.serviceChildFieldsAbsent(prior), Self.serviceChildFieldsAbsent(intent),
                  prior.binding == intent.binding, prior.adapterID == intent.adapterID,
                  Self.validIntent(intent), Self.validChildTuple(intent, allowAbsent: true) else {
                throw JournalError.invalidTransition
            }
            ledger.unfinished[index] = intent
        }
        try publishLedger(ledger)
    }

    @discardableResult
    func retireIntentWhileLocked(operationID: UUID, proof: EffectProofReference,
                                 artifacts: ReviewedManifestStore) throws -> PendingEffectIntent {
        try requireJournalLock()
        var ledger = try readLedger()
        guard ledger.unfinished.filter({ $0.operationID == operationID }).count == 1,
              let index = ledger.unfinished.firstIndex(where: { $0.operationID == operationID }) else {
            throw JournalError.invalidTransition
        }
        let intent = ledger.unfinished[index]
        _ = try artifacts.proof(proof, for: intent)
        ledger.unfinished.remove(at: index)
        try publishLedger(ledger)
        return intent
    }

    private func publishLedger(_ ledger: Envelope) throws {
        let bytes = try JSONEncoder().encode(ledger)
        guard bytes.count <= JournalFiles.maximumBytes else { throw JournalError.capacity }
        do {
            try JournalFilePublication.replace(directoryFD: directoryFD,
                name: "unfinished-effects.json", bytes: bytes, io: io, scanLimits: scanLimits)
        } catch JournalError.capacity { throw JournalError.capacity }
        catch {
            failed = true
            throw ConfirmationError.storageUnavailable
        }
    }

    private static func validChildTuple(_ intent: PendingEffectIntent, allowAbsent: Bool) -> Bool {
        if intent.childPID == nil && intent.childStartSeconds == nil && intent.childStartMicroseconds == nil {
            return allowAbsent
        }
        guard let pid = intent.childPID, let seconds = intent.childStartSeconds,
              let micros = intent.childStartMicroseconds else { return false }
        return pid > 0 && seconds >= 0 && (0..<1_000_000).contains(micros)
    }

    private static func serviceChildFieldsAbsent(_ intent: PendingEffectIntent) -> Bool {
        intent.bootID == nil && intent.executablePath == nil && intent.executableDevice == nil
            && intent.executableInode == nil && intent.childPID == nil
            && intent.childStartSeconds == nil && intent.childStartMicroseconds == nil
    }

    private static func validIntent(_ intent: PendingEffectIntent) -> Bool {
        guard !intent.adapterID.isEmpty else { return false }
        switch intent.schemaVersion {
        case 1:
            return intent.binding == nil && intent.bootID != nil
                && intent.executablePath?.isEmpty == false
                && intent.executableDevice != nil && intent.executableInode != nil
        case 2:
            guard case .filesystem(let binding)? = intent.binding else { return false }
            return binding.schema == FilesystemEffectBinding.schemaVersion
                && binding.adapterID == intent.adapterID
                && intent.bootID == nil && intent.executablePath == nil
                && intent.executableDevice == nil && intent.executableInode == nil
                && intent.childPID == nil && intent.childStartSeconds == nil
                && intent.childStartMicroseconds == nil
        case 3:
            guard case .service(let binding)? = intent.binding,
                  (try? binding.validate()) != nil,
                  [.prepared, .submitted, .uncertainAndPossiblyRunning].contains(intent.phase) else { return false }
            guard intent.adapterID == binding.operation.adapter.rawValue else { return false }
            if serviceChildFieldsAbsent(intent) { return true }
            guard binding.operation.adapter == .appleSimulatorShutdownV1,
                  case .appleSimulator(let producer) = binding.operation.producer,
                  [.submitted, .uncertainAndPossiblyRunning].contains(intent.phase),
                  intent.bootID != nil, validChildTuple(intent, allowAbsent: false),
                  intent.executablePath == producer.simctl.canonicalPath,
                  intent.executableDevice == producer.simctl.device,
                  intent.executableInode == producer.simctl.inode else { return false }
            return true
        default:
            return false
        }
    }

    private func validateStableLock() throws {
        let scan = try JournalDirectoryScan.read(directoryFD: directoryFD, limits: scanLimits)
        guard !scan.containsPendingStage else { throw ConfirmationError.storageUnavailable }
        try Self.validate(directoryFD, directory: true)
        try Self.validate(lockFD, directory: false)
        let namedFD = try Self.openDirectory(directoryPath, create: false)
        defer { close(namedFD) }
        var namedDirectory = stat(); var openedDirectory = stat()
        guard fstat(namedFD, &namedDirectory) == 0, fstat(directoryFD, &openedDirectory) == 0,
              namedDirectory.st_mode & S_IFMT == S_IFDIR,
              namedDirectory.st_dev == openedDirectory.st_dev,
              namedDirectory.st_ino == openedDirectory.st_ino else { throw ConfirmationError.storageUnavailable }
        var current = stat(); var opened = stat()
        guard fstatat(directoryFD, "mutation.lock", &current, AT_SYMLINK_NOFOLLOW) == 0,
              fstat(lockFD, &opened) == 0,
              current.st_dev == opened.st_dev, current.st_ino == opened.st_ino,
              current.st_mode & S_IFMT == S_IFREG else { throw ConfirmationError.storageUnavailable }
    }

    private static func validate(_ fd: Int32, directory: Bool) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              info.st_mode & 0o777 == (directory ? 0o700 : 0o600),
              directory || info.st_nlink == 1 else { throw ConfirmationError.storageUnavailable }
    }

    /// Component-wise open prevents an ancestor symlink from redirecting bootstrap writes.
    private static func openDirectory(_ path: String, create: Bool) throws -> Int32 {
        let components = path.split(separator: "/").map(String.init)
        guard path.hasPrefix("/"), !path.utf8.contains(0), !components.isEmpty,
              !components.contains("."), !components.contains("..") else {
            throw ConfirmationError.storageUnavailable
        }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ConfirmationError.storageUnavailable }
        for component in components {
            var next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT, create {
                guard mkdirat(fd, component, 0o700) == 0 || errno == EEXIST else {
                    close(fd); throw ConfirmationError.storageUnavailable
                }
                guard fsync(fd) == 0 else { close(fd); throw ConfirmationError.storageUnavailable }
                next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            close(fd)
            guard next >= 0 else { throw ConfirmationError.storageUnavailable }
            fd = next
        }
        return fd
    }

    private func read<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        try JSONDecoder().decode(type, from: JournalFiles.read(directoryFD, name: name))
    }

    private func readLedger() throws -> Envelope {
        let marker = try read(Bootstrap.self, name: "bootstrap.json")
        let ledger = try read(Envelope.self, name: "unfinished-effects.json")
        guard marker.schema == 1, marker.state == "initialized",
              ledger.schema == 1, ledger.storeID == marker.storeID,
              ledger.unfinished.allSatisfy(Self.validIntent) else {
            throw ConfirmationError.storageUnavailable
        }
        return ledger
    }

    private func publish<T: Encodable>(_ value: T, name: String) throws {
        let bytes = try JSONEncoder().encode(value)
        try JournalFilePublication.replace(directoryFD: directoryFD, name: name, bytes: bytes,
                                           io: io, scanLimits: scanLimits)
    }
}
struct PendingEffectIntent: Codable, Equatable, Sendable {
    let schemaVersion: UInt32
    let runID: UUID
    let operationID: UUID
    let adapterID: String
    let binding: PersistedEffectBinding?
    let bootID: UUID?
    let executablePath: String?
    let executableDevice: UInt64?
    let executableInode: UInt64?
    let childPID: Int32?
    let childStartSeconds: Int64?
    let childStartMicroseconds: Int32?
    let phase: SubmissionPhase

    init(runID: UUID, operationID: UUID, adapterID: String, bootID: UUID,
         executablePath: String, executableDevice: UInt64, executableInode: UInt64,
         childPID: Int32?, childStartSeconds: Int64?, childStartMicroseconds: Int32?,
         phase: SubmissionPhase) {
        schemaVersion = 1
        self.runID = runID
        self.operationID = operationID
        self.adapterID = adapterID
        binding = nil
        self.bootID = bootID
        self.executablePath = executablePath
        self.executableDevice = executableDevice
        self.executableInode = executableInode
        self.childPID = childPID
        self.childStartSeconds = childStartSeconds
        self.childStartMicroseconds = childStartMicroseconds
        self.phase = phase
    }

    init(runID: UUID, operationID: UUID, filesystem binding: FilesystemEffectBinding,
         phase: SubmissionPhase = .prepared) {
        schemaVersion = 2
        self.runID = runID
        self.operationID = operationID
        adapterID = binding.adapterID
        self.binding = .filesystem(binding)
        bootID = nil
        executablePath = nil
        executableDevice = nil
        executableInode = nil
        childPID = nil
        childStartSeconds = nil
        childStartMicroseconds = nil
        self.phase = phase
    }

    init(runID: UUID, operationID: UUID, service binding: ManualServiceEffectBinding,
         phase: SubmissionPhase = .prepared, child: ProcessInstanceIdentity? = nil) {
        schemaVersion = 3
        self.runID = runID; self.operationID = operationID
        adapterID = binding.operation.adapter.rawValue
        self.binding = .service(binding)
        bootID = child?.bootID; executablePath = child?.executablePath
        executableDevice = child?.executableDevice; executableInode = child?.executableInode
        childPID = child?.pid; childStartSeconds = child?.startSeconds; childStartMicroseconds = child?.startMicroseconds
        self.phase = phase
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, runID, operationID, adapterID, binding, bootID
        case executablePath, executableDevice, executableInode
        case childPID, childStartSeconds, childStartMicroseconds, phase
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(UInt32.self, forKey: .schemaVersion) ?? 1
        runID = try values.decode(UUID.self, forKey: .runID)
        operationID = try values.decode(UUID.self, forKey: .operationID)
        adapterID = try values.decode(String.self, forKey: .adapterID)
        binding = try values.decodeIfPresent(PersistedEffectBinding.self, forKey: .binding)
        bootID = try values.decodeIfPresent(UUID.self, forKey: .bootID)
        executablePath = try values.decodeIfPresent(String.self, forKey: .executablePath)
        executableDevice = try values.decodeIfPresent(UInt64.self, forKey: .executableDevice)
        executableInode = try values.decodeIfPresent(UInt64.self, forKey: .executableInode)
        childPID = try values.decodeIfPresent(Int32.self, forKey: .childPID)
        childStartSeconds = try values.decodeIfPresent(Int64.self, forKey: .childStartSeconds)
        childStartMicroseconds = try values.decodeIfPresent(Int32.self, forKey: .childStartMicroseconds)
        phase = try values.decode(SubmissionPhase.self, forKey: .phase)
    }
}
enum SubmissionPhase: String, Codable, Sendable {
    case prepared, releaseArmed, submitted, uncertainAndPossiblyRunning
}

enum IntentPersistence: Sendable {
    case append, capturedChild, serviceSubmission
    case serviceChildCapture // Retired raw route: always rejected.
    case ownedServiceChildCapture(OwnedServiceChildCaptureReceipt)
}
