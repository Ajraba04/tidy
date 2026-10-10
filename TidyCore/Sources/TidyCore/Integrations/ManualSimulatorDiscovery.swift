import CoreFoundation
import Darwin
import Foundation

/// Read-only discovery supplies full review metadata, never effect acceptance.
public enum ManualSimulatorCandidateService {
    /// Presentation options only. Inspect at most the ledger's bounded grant
    /// count, entirely off the UI actor, without launching a tool or reading
    /// marker contents. Every later inventory request revalidates independently.
    public static func approvedExistingDeviceSets(authority: LocalAuthoritySnapshot) async -> [LocalRootApproval] {
        guard authority.isCurrent else { return [] }
        let worker = Task.detached(priority: .utility) { () -> [LocalRootApproval] in
            let roots = authority.scopes.compactMap { scope -> LocalRootApproval? in
                guard case .localRoot(let root) = scope else { return nil }
                return root
            }.sorted { $0.canonicalPath < $1.canonicalPath }
            guard roots.count <= 256 else { return [] }
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            var result: [LocalRootApproval] = []
            for root in roots {
                guard !Task.isCancelled, authority.isCurrent, ContinuousClock.now < deadline else { return [] }
                if (try? ManualSimulatorDiscovery.hasExistingMarker(root, deadline: deadline)) == true {
                    result.append(root)
                }
            }
            guard !Task.isCancelled, authority.isCurrent, ContinuousClock.now < deadline else { return [] }
            return result
        }
        return await withTaskCancellationHandler {
            let result = await worker.value
            return Task.isCancelled || !authority.isCurrent ? [] : result
        } onCancel: { worker.cancel() }
    }

    public static func read(deviceSet: LocalRootApproval,
                            authority: LocalAuthoritySnapshot) async throws -> [ManualServiceOperationBinding] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        guard authority.isCurrent, authority.permits(.localRoot(deviceSet)),
              let resolver = authority.scopes.compactMap({ scope -> LocalExecutableApproval? in
                  guard case .localExecutable(let value) = scope,
                        value.canonicalPath == "/usr/bin/xcrun" else { return nil }
                  return value
              }).first else { throw ManualServiceReviewError.authorityDenied }
        try await Task.detached {
            try ManualSimulatorDiscovery.requireInitialAuthority(resolver: resolver,
                deviceSet: deviceSet, authority: authority)
            try ManualSimulatorDiscovery.requireExistingDeviceSet(deviceSet, deadline: deadline)
        }.value
        let resolved = try await ProcessRunner.runManualSimulatorResolver(resolver: resolver,
            deviceSet: deviceSet, authority: authority, deadline: deadline)
        let simctlURL = try ManualSimulatorDiscovery.parseResolvedSimctl(resolved)
        let developerURL = simctlURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let roots = try await Task.detached {
            (try LocalExecutableApproval.verify(executable: simctlURL),
             try LocalRootApproval.verify(directory: developerURL))
        }.value
        let bootstrap = ManualSimulatorReadBootstrap(resolver: resolver, simctl: roots.0,
            developerDirectory: roots.1, deviceSet: deviceSet, authority: authority)
        let metadata = try await Task.detached {
            try bootstrap.checkCurrent(deadline: deadline)
            return try ManualSimulatorDiscovery.readVersionMetadata(developerDirectory: roots.1, deadline: deadline)
        }.value
        let rawVersion = try await ProcessRunner.runManualSimctlVersion(bootstrap, deadline: deadline)
        let producer = AppleSimulatorProducerIdentity(resolver: resolver, simctl: roots.0,
            developerDirectory: roots.1, deviceSet: deviceSet, xcodeVersion: metadata.version,
            xcodeBuild: metadata.build,
            coreSimulatorVersion: try ManualSimulatorDiscovery.parseCoreSimulatorVersion(rawVersion))
        guard producer.isInspectedCandidateVersion else { throw ManualServiceInventoryError.unsupportedProducer }
        try await requireSameSelection(bootstrap, deadline: deadline)
        let reader = ManualSimulatorNativeReader(authority: authority, deadline: deadline)
        let client = try ManualSimulatorClient.inventoryOnly(producer: producer, reader: reader, authority: authority)
        let result = try await client.candidates()
        try await requireSameSelection(bootstrap, deadline: deadline)
        return result
    }

    private static func requireSameSelection(_ binding: ManualSimulatorReadBootstrap,
                                             deadline: ContinuousClock.Instant) async throws {
        let value = try await ProcessRunner.runManualSimulatorResolver(resolver: binding.resolver,
            deviceSet: binding.deviceSet, authority: binding.authority, deadline: deadline)
        guard try ManualSimulatorDiscovery.parseResolvedSimctl(value).path == binding.simctl.canonicalPath else {
            throw ManualServiceInventoryError.identityMismatch
        }
        try await Task.detached { try binding.checkCurrent(deadline: deadline) }.value
    }
}

struct ManualSimulatorReadBootstrap: Sendable {
    let resolver: LocalExecutableApproval
    let simctl: LocalExecutableApproval
    let developerDirectory: LocalRootApproval
    let deviceSet: LocalRootApproval
    let authority: LocalAuthoritySnapshot

    func checkCurrent(deadline: ContinuousClock.Instant) throws {
        try ManualSimulatorDiscovery.requireInitialAuthority(resolver: resolver, deviceSet: deviceSet, authority: authority)
        guard authority.permits(.localExecutable(simctl)),
              authority.permits(.localRoot(developerDirectory)) else { throw ManualServiceReviewError.authorityDenied }
        guard simctl.canonicalPath == developerDirectory.canonicalPath + "/usr/bin/simctl",
              try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: simctl.canonicalPath)) == simctl,
              try LocalRootApproval.verify(directory: URL(fileURLWithPath: developerDirectory.canonicalPath)) == developerDirectory else {
            throw ManualServiceInventoryError.identityMismatch
        }
        try ManualSimulatorDiscovery.requireExistingDeviceSet(deviceSet, deadline: deadline)
        guard ContinuousClock.now < deadline, authority.isCurrent else { throw ManualServiceReviewError.authorityDenied }
    }
}

struct ManualSimulatorNativeReader: ManualSimulatorReading {
    let authority: LocalAuthoritySnapshot
    let deadline: ContinuousClock.Instant
    func read(_ request: ManualSimulatorReadRequest,
              terminalLease: ProcessTerminalVerificationLease?) async throws -> Data {
        try await ProcessRunner.runManualSimulatorInventory(request, authority: authority,
            deadline: deadline, terminalLease: terminalLease)
    }
}

enum ManualSimulatorDiscovery {
    private static let metadataLimit = 65_536
    // sys/stat.h defines SF_DATALESS, but Darwin does not import this macro.
    private static let systemDatalessFlag: UInt32 = 0x40000000

    static func metadataIsLocallyPresent(flags: UInt32) -> Bool {
        flags & systemDatalessFlag == 0
    }

    static func hasExistingMarker(_ approval: LocalRootApproval,
                                   deadline: ContinuousClock.Instant) throws -> Bool {
        let root = try openApprovedDirectory(approval, deadline: deadline)
        defer { close(root) }
        var marker = stat()
        guard fstatat(root, "device_set.plist", &marker, AT_SYMLINK_NOFOLLOW) == 0,
              readableMetadata(marker, onDevice: approval.device) else { return false }
        guard try LocalRootApproval.verify(directory: URL(fileURLWithPath: approval.canonicalPath)) == approval,
              ContinuousClock.now < deadline else { return false }
        return true
    }

    /// Walk canonical components from an anchored / descriptor. O_NOFOLLOW on
    /// only the last directory would still traverse a replaced ancestor alias.
    private static func openApprovedDirectory(_ approval: LocalRootApproval,
                                               deadline: ContinuousClock.Instant) throws -> Int32 {
        try ManualServiceValueBounds.root(approval)
        guard URL(fileURLWithPath: approval.canonicalPath).standardizedFileURL.path == approval.canonicalPath else {
            throw ManualServiceInventoryError.invalidIdentity
        }
        // Foundation can retain /tmp or /var in an otherwise canonical grant
        // even though the kernel namespace uses /private/tmp or /private/var.
        // Validate the complete grant before resolving that spelling. A moved
        // root or replaced ancestor alias must not become a fresh approval.
        guard try LocalRootApproval.verify(directory: URL(fileURLWithPath: approval.canonicalPath)) == approval,
              let resolved = realpath(approval.canonicalPath, nil) else {
            throw ManualServiceInventoryError.identityMismatch
        }
        defer { free(resolved) }
        let traversalPath = String(cString: resolved)
        guard try LocalRootApproval.verify(directory: URL(fileURLWithPath: traversalPath)) == approval else {
            throw ManualServiceInventoryError.identityMismatch
        }
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw ManualServiceInventoryError.invalidIdentity }
        var returned = false
        defer { if !returned { close(descriptor) } }
        for component in traversalPath.split(separator: "/") {
            guard !Task.isCancelled, ContinuousClock.now < deadline else { throw ManualSimulatorClientError.expired }
            var named = stat()
            guard fstatat(descriptor, String(component), &named, AT_SYMLINK_NOFOLLOW) == 0,
                  named.st_mode & S_IFMT == S_IFDIR, metadataIsLocallyPresent(flags: named.st_flags) else {
                throw ManualServiceInventoryError.invalidIdentity
            }
            let next = openat(descriptor, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard next >= 0 else { throw ManualServiceInventoryError.invalidIdentity }
            var opened = stat()
            guard fstat(next, &opened) == 0, opened.st_dev == named.st_dev, opened.st_ino == named.st_ino,
                  metadataIsLocallyPresent(flags: opened.st_flags) else {
                close(next); throw ManualServiceInventoryError.identityMismatch
            }
            close(descriptor); descriptor = next
        }
        var root = stat(), filesystem = statfs()
        guard fstat(descriptor, &root) == 0, UInt64(root.st_dev) == approval.device,
              UInt64(root.st_ino) == approval.inode, root.st_mode & S_IFMT == S_IFDIR,
              metadataIsLocallyPresent(flags: root.st_flags), fstatfs(descriptor, &filesystem) == 0,
              filesystem.f_flags & UInt32(MNT_LOCAL) != 0,
              try LocalRootApproval.verify(directory: URL(fileURLWithPath: approval.canonicalPath)) == approval else {
            throw ManualServiceInventoryError.identityMismatch
        }
        returned = true
        return descriptor
    }

    private static func readableMetadata(_ info: stat, onDevice device: UInt64) -> Bool {
        info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1 && UInt64(info.st_dev) == device
            && (info.st_uid == 0 || info.st_uid == geteuid()) && info.st_mode & 0o022 == 0
            && info.st_size > 0 && info.st_size <= metadataLimit && metadataIsLocallyPresent(flags: info.st_flags)
    }
    static func requireInitialAuthority(resolver: LocalExecutableApproval, deviceSet: LocalRootApproval,
                                        authority: LocalAuthoritySnapshot) throws {
        guard resolver.canonicalPath == "/usr/bin/xcrun", authority.isCurrent,
              authority.permits(.localExecutable(resolver)), authority.permits(.localRoot(deviceSet)) else {
            throw ManualServiceReviewError.authorityDenied
        }
        guard try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: resolver.canonicalPath)) == resolver,
              try LocalRootApproval.verify(directory: URL(fileURLWithPath: deviceSet.canonicalPath)) == deviceSet else {
            throw ManualServiceInventoryError.identityMismatch
        }
    }

    static func parseResolvedSimctl(_ bytes: Data) throws -> URL {
        guard bytes.count <= 4_096, let text = String(data: bytes, encoding: .utf8) else {
            throw ManualServiceInventoryError.malformed
        }
        let path = text.hasSuffix("\n") ? String(text.dropLast()) : text
        guard !path.contains("\n"), !path.contains("\r"), path.hasPrefix("/"),
              path.hasSuffix(".app/Contents/Developer/usr/bin/simctl"),
              URL(fileURLWithPath: path).standardizedFileURL.path == path else {
            throw ManualServiceInventoryError.invalidIdentity
        }
        try ManualServiceValueBounds.path(path)
        return URL(fileURLWithPath: path)
    }

    static func parseVersionMetadata(_ bytes: Data) throws -> (version: String, build: String) {
        let root = try plist(bytes)
        guard let version = root["CFBundleShortVersionString"] as? String,
              let build = root["ProductBuildVersion"] as? String else { throw ManualServiceInventoryError.malformed }
        try ManualServiceValueBounds.string(version, maximum: 128)
        try ManualServiceValueBounds.string(build, maximum: 128)
        return (version, build)
    }

    static func parseCoreSimulatorVersion(_ bytes: Data) throws -> String {
        guard bytes.count <= 256, let text = String(data: bytes, encoding: .utf8) else {
            throw ManualServiceInventoryError.malformed
        }
        let expression = try NSRegularExpression(pattern: "\\A@\\(#\\)PROGRAM:simctl +PROJECT:CoreSimulator-([0-9]+(?:\\.[0-9]+){1,3})\\n?\\z")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              let value = Range(match.range(at: 1), in: text) else { throw ManualServiceInventoryError.malformed }
        return String(text[value])
    }

    static func requireExistingDeviceSet(_ root: LocalRootApproval,
                                         deadline: ContinuousClock.Instant) throws {
        let data = try readMetadata(directory: root, name: "device_set.plist", deadline: deadline)
        try validateDeviceSetMetadata(data)
    }

    static func validateDeviceSetMetadata(_ bytes: Data) throws {
        let root = try plist(bytes)
        guard let version = root["Version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
              let value = Int64(version.stringValue), value >= 0,
              root["DefaultDevices"] is [String: Any], root["DevicePairs"] is [String: Any] else {
            throw ManualServiceInventoryError.malformed
        }
    }

    static func readVersionMetadata(developerDirectory: LocalRootApproval,
                                     deadline: ContinuousClock.Instant) throws -> (version: String, build: String) {
        let contents = URL(fileURLWithPath: developerDirectory.canonicalPath).deletingLastPathComponent()
        let directory = try LocalRootApproval.verify(directory: contents)
        return try parseVersionMetadata(readMetadata(directory: directory, name: "version.plist", deadline: deadline))
    }

    private static func plist(_ bytes: Data) throws -> [String: Any] {
        guard !bytes.isEmpty, bytes.count <= metadataLimit,
              let root = try PropertyListSerialization.propertyList(from: bytes, options: [], format: nil) as? [String: Any] else {
            throw ManualServiceInventoryError.malformed
        }
        return root
    }

    private static func readMetadata(directory: LocalRootApproval, name: String,
                                     deadline: ContinuousClock.Instant) throws -> Data {
        guard ContinuousClock.now < deadline else { throw ManualSimulatorClientError.expired }
        let root = try openApprovedDirectory(directory, deadline: deadline)
        defer { close(root) }
        // Refuse dataless/type/link metadata before opening the leaf, so a
        // purported local marker cannot cause provider hydration on open/read.
        var namedBefore = stat()
        guard fstatat(root, name, &namedBefore, AT_SYMLINK_NOFOLLOW) == 0,
              readableMetadata(namedBefore, onDevice: directory.device) else { throw ManualServiceInventoryError.malformed }
        let fd = openat(root, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw ManualServiceInventoryError.malformed }
        defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_dev == namedBefore.st_dev,
              before.st_ino == namedBefore.st_ino, readableMetadata(before, onDevice: directory.device) else {
            throw ManualServiceInventoryError.malformed
        }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            guard !Task.isCancelled, ContinuousClock.now < deadline else { throw ManualSimulatorClientError.expired }
            let count = Darwin.read(fd, &buffer, min(buffer.count, metadataLimit + 1 - bytes.count))
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw ManualServiceInventoryError.malformed }
            if count == 0 { break }
            guard bytes.count + count <= metadataLimit else { throw ManualServiceInventoryError.capacity }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        var after = stat(), named = stat()
        guard fstat(fd, &after) == 0, fstatat(root, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_dev == before.st_dev, named.st_ino == before.st_ino,
              named.st_mode & S_IFMT == S_IFREG, after.st_nlink == 1,
              before.st_size == after.st_size, bytes.count == before.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              readableMetadata(after, onDevice: directory.device),
              try LocalRootApproval.verify(directory: URL(fileURLWithPath: directory.canonicalPath)) == directory else {
            throw ManualServiceInventoryError.identityMismatch
        }
        return bytes
    }
}
