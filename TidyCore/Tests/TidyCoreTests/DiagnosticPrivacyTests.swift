import Darwin
import Foundation
import Testing
@testable import TidyCore

@Suite("Diagnostic privacy")
struct DiagnosticPrivacyTests {
    private struct NodeIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
        let mode: UInt32
        let links: UInt64
        let size: Int64
    }

    private func withArtifactDirectory(_ body: (URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("Tidy-Diagnostic-Privacy-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        try body(directory)
    }

    private func privacyInput(cosmeticRedactionEnabled: Bool)
        -> (input: DiagnosticExportInput, forbidden: [String]) {
        let forbidden = [
            "credential-WRITER-SENTINEL", "cookie-WRITER-SENTINEL",
            "environment-WRITER-SENTINEL", "argv-WRITER-SENTINEL",
            "remote-WRITER-SENTINEL", "/Users/personal-WRITER-SENTINEL",
            "setting-value-WRITER-SENTINEL", "profile-name-WRITER-SENTINEL"
        ]
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 89,
            config: TidyConfig(schemaVersion: 2, gitRoots: [forbidden[5]]),
            preferences: .init(global: .init(fields: [
                SettingID(rawValue: "ui.units"): .choice(forbidden[6])
            ]), profiles: [SavedProfile(id: UUID(), name: forbidden[7], values: .init())]))
        return (.init(settings: envelope,
            cosmeticRedactionEnabled: cosmeticRedactionEnabled,
            credentials: [forbidden[0]], cookies: [forbidden[1]],
            environment: ["TOKEN": forbidden[2]], argv: [forbidden[3]],
            remotes: [forbidden[4]], personalPaths: [forbidden[5]]), forbidden)
    }

    private func identity(of url: URL) throws -> NodeIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return NodeIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino),
            mode: UInt32(info.st_mode), links: UInt64(info.st_nlink),
            size: Int64(info.st_size))
    }

    private func stagingNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".tidy-diagnostic-") && $0.hasSuffix(".staging") }
    }

    private func addACLEntry(_ entry: String, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", entry, url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw POSIXError(.EINVAL)
        }
    }

    private func clearACL(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["-N", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw POSIXError(.EINVAL)
        }
    }

    private func extendedACLTags(of url: URL) throws -> [acl_tag_t] {
        let descriptor = Darwin.open(url.path,
            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT { return [] }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var tags: [acl_tag_t] = []
        var selector = ACL_FIRST_ENTRY
        while true {
            var entry: acl_entry_t?
            errno = 0
            let status = acl_get_entry(acl, Int32(selector.rawValue), &entry)
            if status == -1, errno == EINVAL { break }
            guard status == 0, let entry, tags.count < Int(ACL_MAX_ENTRIES) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            tags.append(tag)
            selector = ACL_NEXT_ENTRY
        }
        return tags
    }

    @Test("every rendered artifact candidate excludes immutable sensitive classes even with cosmetic redaction off")
    func immutableExclusionsApplyToEveryArtifact() throws {
        let sentinels = [
            "credential-SENTINEL", "cookie-SENTINEL", "environment-SENTINEL",
            "argv-SENTINEL", "remote-SENTINEL", "/Users/personal-SENTINEL"
        ]
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 41,
            config: TidyConfig(schemaVersion: 2, gitRoots: [sentinels[5]]),
            preferences: .init(profiles: [SavedProfile(id: UUID(),
                name: "Safe profile label", values: .init())]))
        let artifacts = try DiagnosticExportRenderer.render(.init(settings: envelope,
            cosmeticRedactionEnabled: false, credentials: [sentinels[0]],
            cookies: [sentinels[1]], environment: ["TOKEN": sentinels[2]],
            argv: [sentinels[3]], remotes: [sentinels[4]],
            personalPaths: [sentinels[5]]))

        for bytes in [artifacts.primaryCandidate, artifacts.temporaryCandidate,
                      artifacts.backupCandidate] {
            let text = String(decoding: bytes, as: UTF8.self)
            for sentinel in sentinels { #expect(!text.contains(sentinel)) }
            let object = try #require(JSONSerialization.jsonObject(with: bytes)
                as? [String: Any])
            #expect((object["settingsRevision"] as? NSNumber)?.uint64Value == 41)
        }
    }

    @Test("primary temporary and backup renderer outputs remain private after disk materialization")
    func diskMaterializedArtifactCandidatesExcludeEveryForbiddenSentinel() throws {
        let sentinels = [
            "credential-DISK-SENTINEL", "cookie-DISK-SENTINEL",
            "environment-DISK-SENTINEL", "argv-DISK-SENTINEL",
            "remote-DISK-SENTINEL", "/Users/personal-DISK-SENTINEL"
        ]
        let settingsValue = "setting-value-DISK-SENTINEL"
        let profileName = "profile-name-DISK-SENTINEL"
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 73,
            config: TidyConfig(schemaVersion: 2, gitRoots: [sentinels[5]]),
            preferences: .init(global: .init(fields: [
                SettingID(rawValue: "ui.units"): .choice(settingsValue)
            ]), profiles: [SavedProfile(id: UUID(), name: profileName, values: .init())]))
        let rendered = try DiagnosticExportRenderer.render(.init(settings: envelope,
            cosmeticRedactionEnabled: false, credentials: [sentinels[0]],
            cookies: [sentinels[1]], environment: ["TOKEN": sentinels[2]],
            argv: [sentinels[3]], remotes: [sentinels[4]], personalPaths: [sentinels[5]]))

        try withArtifactDirectory { directory in
            let candidates = [
                ("tidy-diagnostic.json", rendered.primaryCandidate),
                (".tidy-diagnostic.json.temporary", rendered.temporaryCandidate),
                ("tidy-diagnostic.json.backup", rendered.backupCandidate)
            ]
            for (name, candidate) in candidates {
                let url = directory.appendingPathComponent(name)
                try candidate.write(to: url, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                      ofItemAtPath: url.path)
                let diskBytes = try Data(contentsOf: url)
                #expect(diskBytes == candidate)
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
                let text = String(decoding: diskBytes, as: UTF8.self)
                for forbidden in sentinels + [settingsValue, profileName] {
                    #expect(!text.contains(forbidden))
                }
            }
        }
    }

    @Test("diagnostic artifacts never serialize portable setting values or profile names")
    func valuesAndNamesAreStructurallyExcluded() throws {
        let secret = "profile-name-SENTINEL"
        let id = SettingID(rawValue: "future.fixture")
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 2,
            config: TidyConfig(schemaVersion: 2),
            preferences: .init(global: .init(fields: [id: .choice(secret)]),
                profiles: [SavedProfile(id: UUID(), name: secret, values: .init())]))
        let bytes = try DiagnosticExportRenderer.render(.init(settings: envelope,
            cosmeticRedactionEnabled: false)).primaryCandidate
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains(secret))
        let object = try #require(JSONSerialization.jsonObject(with: bytes)
            as? [String: Any])
        #expect((object["profileCount"] as? NSNumber)?.intValue == 1)
    }

    @Test("writer creates one private export with renderer bytes for both cosmetic flag states")
    func writerCreatesPrivateRendererPayloadForBothFlagStates() throws {
        try withArtifactDirectory { directory in
            for flag in [false, true] {
                let fixture = privacyInput(cosmeticRedactionEnabled: flag)
                let destination = directory.appendingPathComponent("diagnostic-\(flag).json")
                let expected = try DiagnosticExportRenderer.render(fixture.input).primaryCandidate

                let receipt = try DiagnosticExportWriter.write(fixture.input, to: destination)

                let bytes = try Data(contentsOf: destination)
                #expect(receipt.bytesWritten == bytes.count)
                #expect(bytes == expected)
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: destination.path)
                #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
                let text = String(decoding: bytes, as: UTF8.self)
                for forbidden in fixture.forbidden { #expect(!text.contains(forbidden)) }
                let object = try #require(JSONSerialization.jsonObject(with: bytes)
                    as? [String: Any])
                #expect((object["cosmeticRedactionEnabled"] as? Bool) == flag)
            }
            #expect(try stagingNames(in: directory).isEmpty)
        }
    }

    @Test("writer never replaces existing regular symlink FIFO directory or hard-linked destinations")
    func writerPreservesEveryExistingDestinationKind() throws {
        try withArtifactDirectory { directory in
            let fixture = privacyInput(cosmeticRedactionEnabled: false)
            let regular = directory.appendingPathComponent("existing.json")
            let symlink = directory.appendingPathComponent("existing-link.json")
            let fifo = directory.appendingPathComponent("existing.fifo")
            let existingDirectory = directory.appendingPathComponent("existing-directory")
            let hardSource = directory.appendingPathComponent("hard-source.json")
            let hardDestination = directory.appendingPathComponent("hard-destination.json")
            let regularWitness = Data("regular-witness".utf8)
            let hardWitness = Data("hard-link-witness".utf8)
            try regularWitness.write(to: regular)
            try FileManager.default.createSymbolicLink(at: symlink,
                                                        withDestinationURL: regular)
            try #require(mkfifo(fifo.path, 0o600) == 0)
            try FileManager.default.createDirectory(at: existingDirectory,
                withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let directoryMarker = existingDirectory.appendingPathComponent("marker")
            try Data("directory-witness".utf8).write(to: directoryMarker)
            try hardWitness.write(to: hardSource)
            try #require(link(hardSource.path, hardDestination.path) == 0)

            let destinations = [regular, symlink, fifo, existingDirectory, hardDestination]
            let before = try destinations.map(identity(of:))
            for destination in destinations {
                do {
                    _ = try DiagnosticExportWriter.write(fixture.input, to: destination)
                    Issue.record("Writer replaced an existing destination")
                } catch let error as DiagnosticExportWriteError {
                    #expect(error == .failure(stage: .publication, code: EEXIST))
                }
            }

            #expect(try destinations.map(identity(of:)) == before)
            #expect(try Data(contentsOf: regular) == regularWitness)
            #expect(try FileManager.default.destinationOfSymbolicLink(
                atPath: symlink.path) == regular.path)
            #expect(try Data(contentsOf: directoryMarker) == Data("directory-witness".utf8))
            #expect(try Data(contentsOf: hardSource) == hardWitness)
            #expect(try Data(contentsOf: hardDestination) == hardWitness)
            #expect(try stagingNames(in: directory).isEmpty)
        }
    }

    @Test("writer rejects a symlinked parent without changing its target")
    func writerPreservesSymlinkedParent() throws {
        try withArtifactDirectory { directory in
            let fixture = privacyInput(cosmeticRedactionEnabled: true)
            let realParent = directory.appendingPathComponent("real-parent", isDirectory: true)
            let linkedParent = directory.appendingPathComponent("linked-parent", isDirectory: true)
            try FileManager.default.createDirectory(at: realParent,
                withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createSymbolicLink(at: linkedParent,
                                                        withDestinationURL: realParent)
            let before = try identity(of: linkedParent)

            do {
                _ = try DiagnosticExportWriter.write(fixture.input,
                    to: linkedParent.appendingPathComponent("diagnostic.json"))
                Issue.record("Writer followed a symlinked parent")
            } catch let error as DiagnosticExportWriteError {
                guard case .failure(stage: .parentOpen, code: let code) = error else {
                    Issue.record("Unexpected symlink-parent error: \(error)")
                    return
                }
                #expect(code == ENOTDIR || code == ELOOP)
            }

            #expect(try identity(of: linkedParent) == before)
            #expect(!FileManager.default.fileExists(
                atPath: realParent.appendingPathComponent("diagnostic.json").path))
        }
    }

    @Test("prepublication failure removes only its exact staging file")
    func prepublicationFailureCleansStagingAndPreservesWitness() throws {
        try withArtifactDirectory { directory in
            let fixture = privacyInput(cosmeticRedactionEnabled: false)
            let destination = directory.appendingPathComponent("diagnostic.json")
            let witness = directory.appendingPathComponent("witness")
            let witnessBytes = Data("unrelated-witness".utf8)
            try witnessBytes.write(to: witness)
            let before = try identity(of: witness)

            do {
                _ = try DiagnosticExportWriter.write(fixture.input, to: destination,
                    injecting: .beforePublication(code: EIO))
                Issue.record("Injected prepublication failure did not fail")
            } catch let error as DiagnosticExportWriteError {
                #expect(error == .failure(stage: .publication, code: EIO))
            }

            #expect(!FileManager.default.fileExists(atPath: destination.path))
            #expect(try identity(of: witness) == before)
            #expect(try Data(contentsOf: witness) == witnessBytes)
            #expect(try stagingNames(in: directory).isEmpty)
        }
    }

    @Test("postpublication directory sync failure reports uncertainty and retains private payload")
    func postpublicationFailureLeavesPublishedPayload() throws {
        try withArtifactDirectory { directory in
            let fixture = privacyInput(cosmeticRedactionEnabled: true)
            let destination = directory.appendingPathComponent("diagnostic.json")
            let expected = try DiagnosticExportRenderer.render(fixture.input).primaryCandidate

            do {
                _ = try DiagnosticExportWriter.write(fixture.input, to: destination,
                    injecting: .afterPublication(code: EIO))
                Issue.record("Injected postpublication failure did not fail")
            } catch let error as DiagnosticExportWriteError {
                #expect(error == .publicationUncertain(code: EIO))
            }

            #expect(try Data(contentsOf: destination) == expected)
            let attributes = try FileManager.default.attributesOfItem(
                atPath: destination.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            #expect(try stagingNames(in: directory).isEmpty)
        }
    }

    @Test("writer rejects allow ACL parents and clears inherited deny ACLs from exports")
    func writerEnforcesExtendedACLBoundary() throws {
        try withArtifactDirectory { directory in
            let fixture = privacyInput(cosmeticRedactionEnabled: false)
            let allowParent = directory.appendingPathComponent("allow-parent", isDirectory: true)
            let denyParent = directory.appendingPathComponent("deny-parent", isDirectory: true)
            try FileManager.default.createDirectory(at: allowParent,
                withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: denyParent,
                withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
            try addACLEntry("everyone allow add_file,file_inherit", to: allowParent)
            try addACLEntry("everyone deny delete,file_inherit", to: denyParent)
            defer {
                try? clearACL(at: allowParent)
                try? clearACL(at: denyParent)
            }
            let allowTags = try extendedACLTags(of: allowParent)
            let denyTags = try extendedACLTags(of: denyParent)
            #expect(allowTags.contains(ACL_EXTENDED_ALLOW))
            #expect(!denyTags.isEmpty && denyTags.allSatisfy { $0 == ACL_EXTENDED_DENY })

            let allowDestination = allowParent.appendingPathComponent("diagnostic.json")
            do {
                _ = try DiagnosticExportWriter.write(fixture.input, to: allowDestination)
                Issue.record("Writer accepted an allow ACL on its parent")
            } catch let error as DiagnosticExportWriteError {
                #expect(error == .failure(stage: .parentValidation, code: EPERM))
            }
            #expect(!FileManager.default.fileExists(atPath: allowDestination.path))
            #expect(try extendedACLTags(of: allowParent) == allowTags)

            let denyDestination = denyParent.appendingPathComponent("diagnostic.json")
            let receipt = try DiagnosticExportWriter.write(fixture.input, to: denyDestination)
            let bytes = try Data(contentsOf: denyDestination)
            #expect(receipt.bytesWritten == bytes.count)
            #expect(try extendedACLTags(of: denyDestination).isEmpty)
            #expect(try extendedACLTags(of: denyParent) == denyTags)
            let attributes = try FileManager.default.attributesOfItem(
                atPath: denyDestination.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            #expect(try stagingNames(in: denyParent).isEmpty)
        }
    }
}
