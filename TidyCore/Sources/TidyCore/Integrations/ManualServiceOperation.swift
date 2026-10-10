import CryptoKit
import Foundation

/// These values describe reviewed objects. They confer no execution authority.
public enum ManualServiceAdapterID: String, Codable, CaseIterable, Sendable {
    case appleSimulatorShutdownV1
    case dockerStoppedContainerRemovalV1
}

public enum ManualSimulatorState: String, Codable, Sendable {
    case booted = "Booted"
    case shutdown = "Shutdown"
    case creating = "Creating"
    case booting = "Booting"
    case shuttingDown = "Shutting Down"
}

public struct ManualSimulatorObject: Codable, Equatable, Sendable {
    /// UDID/runtime/device type select the object. The mutable display name is
    /// retained in the review digest but never used as a target selector.
    public let udid: UUID
    public let runtimeIdentifier: String
    public let deviceTypeIdentifier: String
    public let name: String
    public let state: ManualSimulatorState
    public let isAvailable: Bool

    func validate() throws {
        try ManualServiceValueBounds.string(runtimeIdentifier, maximum: 512)
        try ManualServiceValueBounds.string(deviceTypeIdentifier, maximum: 512)
        try ManualServiceValueBounds.string(name, maximum: 512)
    }
}

extension ManualSimulatorObject {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(udid: try c.decode(UUID.self, forKey: .udid),
            runtimeIdentifier: try c.decode(String.self, forKey: .runtimeIdentifier),
            deviceTypeIdentifier: try c.decode(String.self, forKey: .deviceTypeIdentifier),
            name: try c.decode(String.self, forKey: .name),
            state: try c.decode(ManualSimulatorState.self, forKey: .state),
            isAvailable: try c.decode(Bool.self, forKey: .isAvailable))
        try validate()
    }
}

public struct AppleSimulatorProducerIdentity: Codable, Equatable, Sendable {
    public let resolver: LocalExecutableApproval
    public let simctl: LocalExecutableApproval
    public let developerDirectory: LocalRootApproval
    public let deviceSet: LocalRootApproval
    public let xcodeVersion: String
    public let xcodeBuild: String
    public let coreSimulatorVersion: String

    var isInspectedCandidateVersion: Bool {
        xcodeVersion == "27.0" && xcodeBuild == "27A266a" && coreSimulatorVersion == "1171.7"
    }

    func validate() throws {
        try ManualServiceValueBounds.executable(resolver)
        try ManualServiceValueBounds.executable(simctl)
        try ManualServiceValueBounds.root(developerDirectory)
        try ManualServiceValueBounds.root(deviceSet)
        for value in [xcodeVersion, xcodeBuild, coreSimulatorVersion] {
            try ManualServiceValueBounds.string(value, maximum: 128)
        }
    }
}

extension AppleSimulatorProducerIdentity {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(resolver: try c.decode(LocalExecutableApproval.self, forKey: .resolver),
            simctl: try c.decode(LocalExecutableApproval.self, forKey: .simctl),
            developerDirectory: try c.decode(LocalRootApproval.self, forKey: .developerDirectory),
            deviceSet: try c.decode(LocalRootApproval.self, forKey: .deviceSet),
            xcodeVersion: try c.decode(String.self, forKey: .xcodeVersion),
            xcodeBuild: try c.decode(String.self, forKey: .xcodeBuild),
            coreSimulatorVersion: try c.decode(String.self, forKey: .coreSimulatorVersion))
        try validate()
    }
}

public struct ManualDockerVersion: Codable, Equatable, Sendable {
    public let engineVersion: String
    public let apiVersion: String
    public let minimumAPIVersion: String
    public let operatingSystem: String
    public let architecture: String

    func validate() throws {
        try ManualServiceValueBounds.string(engineVersion, maximum: 128)
        let api = try ManualServiceValueBounds.apiVersion(apiVersion)
        let minimum = try ManualServiceValueBounds.apiVersion(minimumAPIVersion)
        guard minimum <= api, operatingSystem == "linux",
              ["amd64", "arm64"].contains(architecture) else {
            throw ManualServiceInventoryError.unsupportedProducer
        }
    }
}

extension ManualDockerVersion {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(engineVersion: try c.decode(String.self, forKey: .engineVersion),
            apiVersion: try c.decode(String.self, forKey: .apiVersion),
            minimumAPIVersion: try c.decode(String.self, forKey: .minimumAPIVersion),
            operatingSystem: try c.decode(String.self, forKey: .operatingSystem),
            architecture: try c.decode(String.self, forKey: .architecture))
        try validate()
    }
}

public struct DockerProducerIdentity: Codable, Equatable, Sendable {
    public let socket: LocalSocketApproval
    public let peerPID: Int32
    public let peerUID: UInt32
    public let peerBootID: UUID
    public let peerStartSeconds: Int64
    public let peerStartMicroseconds: Int32
    public let peerExecutable: LocalExecutableApproval
    public let providerIdentifier: String
    public let daemonID: String
    public let version: ManualDockerVersion

    func validate() throws {
        try ManualServiceValueBounds.path(socket.canonicalPath)
        guard socket.inode > 0, peerPID > 0, peerStartSeconds >= 0,
              (0..<1_000_000).contains(peerStartMicroseconds) else { throw ManualServiceInventoryError.invalidIdentity }
        try ManualServiceValueBounds.executable(peerExecutable)
        try ManualServiceValueBounds.string(providerIdentifier, maximum: 128)
        try ManualServiceValueBounds.string(daemonID, maximum: 128)
        try version.validate()
    }
}

extension DockerProducerIdentity {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(socket: try c.decode(LocalSocketApproval.self, forKey: .socket),
            peerPID: try c.decode(Int32.self, forKey: .peerPID),
            peerUID: try c.decode(UInt32.self, forKey: .peerUID),
            peerBootID: try c.decode(UUID.self, forKey: .peerBootID),
            peerStartSeconds: try c.decode(Int64.self, forKey: .peerStartSeconds),
            peerStartMicroseconds: try c.decode(Int32.self, forKey: .peerStartMicroseconds),
            peerExecutable: try c.decode(LocalExecutableApproval.self, forKey: .peerExecutable),
            providerIdentifier: try c.decode(String.self, forKey: .providerIdentifier),
            daemonID: try c.decode(String.self, forKey: .daemonID),
            version: try c.decode(ManualDockerVersion.self, forKey: .version))
        try validate()
    }
}

public struct ManualDockerContainerObject: Codable, Equatable, Sendable {
    /// The target is this ID only. Names and configuration are review metadata;
    /// they contribute to the full binding digest and never select an object.
    public let id: String
    public let name: String
    public let created: String
    public let imageID: String
    public let writableLayerBytes: Int64?
    public let configurationDigest: Data
    public let labelKeys: [String]

    public var observedState: String { "exited" }

    /// Applies even when writable size is zero or unknown. This is a consequence,
    /// not consent, and never asserts stopped contents are immutable.
    public var requiresWholeContainerDataLossConfirmation: Bool { true }
    public var consequenceDescription: String {
        "Remove this entire exact container and its mutable contents when Docker accepts removal, including its writable layer, logs and configuration. Contents may change after review. Mounted data and volumes are not removed."
    }

    func validate() throws {
        try ManualServiceValueBounds.containerID(id)
        try ManualServiceValueBounds.string(name, maximum: 512)
        try ManualServiceValueBounds.string(created, maximum: 128)
        guard imageID.hasPrefix("sha256:") else { throw ManualServiceInventoryError.invalidIdentity }
        try ManualServiceValueBounds.containerID(String(imageID.dropFirst(7)))
        guard writableLayerBytes.map({ $0 >= 0 }) ?? true,
              configurationDigest.count == SHA256.Digest.byteCount,
              labelKeys.count <= 128, Set(labelKeys).count == labelKeys.count,
              labelKeys == labelKeys.sorted() else { throw ManualServiceInventoryError.invalidIdentity }
        for key in labelKeys {
            try ManualServiceValueBounds.string(key, maximum: 256)
            guard !ManualServiceValueBounds.isManagedLabel(key) else { throw ManualServiceInventoryError.managedContainer }
        }
    }
}

extension ManualDockerContainerObject {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
            created: try c.decode(String.self, forKey: .created), imageID: try c.decode(String.self, forKey: .imageID),
            writableLayerBytes: try c.decodeIfPresent(Int64.self, forKey: .writableLayerBytes),
            configurationDigest: try c.decode(Data.self, forKey: .configurationDigest),
            labelKeys: try c.decode([String].self, forKey: .labelKeys))
        try validate()
    }
}

public enum ManualServiceObject: Codable, Equatable, Sendable {
    case simulator(ManualSimulatorObject)
    case container(ManualDockerContainerObject)
}

public enum ManualProducerIdentity: Codable, Equatable, Sendable {
    case appleSimulator(AppleSimulatorProducerIdentity)
    case docker(DockerProducerIdentity)
}

public struct ManualServiceOperationBinding: Codable, Equatable, Sendable {
    public static let currentSchemaVersion: UInt32 = 1
    public let schemaVersion: UInt32
    public let adapter: ManualServiceAdapterID
    public let object: ManualServiceObject
    public let producer: ManualProducerIdentity

    init(adapter: ManualServiceAdapterID, object: ManualServiceObject, producer: ManualProducerIdentity) throws {
        schemaVersion = Self.currentSchemaVersion
        self.adapter = adapter; self.object = object; self.producer = producer
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw ManualServiceInventoryError.unsupportedSchema }
        switch (adapter, object, producer) {
        case (.appleSimulatorShutdownV1, .simulator(let object), .appleSimulator(let producer)):
            try object.validate(); try producer.validate()
            guard object.isAvailable, [.booted, .shutdown].contains(object.state) else {
                throw ManualServiceInventoryError.ineligibleState
            }
        case (.dockerStoppedContainerRemovalV1, .container(let object), .docker(let producer)):
            try object.validate(); try producer.validate()
        default: throw ManualServiceInventoryError.identityMismatch
        }
    }

    public func canonicalDigest() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 65_536 else { throw ManualServiceInventoryError.capacity }
        return Data(SHA256.hash(data: data))
    }
}

extension ManualServiceOperationBinding {
    /// A compiled availability description, never a setting or effect permit.
    public var executionUnavailableReason: String? {
        switch ManualServiceAcceptanceRegistry.denial(for: self) {
        case .invalidBinding: return "The producer or object identity is invalid. Refresh its complete inventory."
        case .unsupportedVersion: return "This producer version has not been accepted for manual operations."
        case .producerAcceptanceMissing:
            switch adapter {
            case .appleSimulatorShutdownV1:
                return "Simulator shutdown is unavailable until this producer's disposable-device acceptance is complete."
            case .dockerStoppedContainerRemovalV1:
                return "Container removal is unavailable until this local Docker provider's disposable-container acceptance is complete."
            }
        case nil: return nil
        }
    }
}

extension ManualServiceOperationBinding {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(UInt32.self, forKey: .schemaVersion)
        adapter = try c.decode(ManualServiceAdapterID.self, forKey: .adapter)
        object = try c.decode(ManualServiceObject.self, forKey: .object)
        producer = try c.decode(ManualProducerIdentity.self, forKey: .producer)
        try validate()
    }
}

public struct ManualServiceReviewSummary: Codable, Equatable, Sendable {
    public static let maximumPendingReviewCount = 32
    public static let maximumLifetimeNanoseconds: UInt64 = 60_000_000_000
    public let reviewID: UUID
    public let binding: ManualServiceOperationBinding
    public let bindingDigest: Data
    public let issuedAtMonotonicNanoseconds: UInt64
    public let expiresAtMonotonicNanoseconds: UInt64

    init(reviewID: UUID, binding: ManualServiceOperationBinding,
         issuedAtMonotonicNanoseconds: UInt64, expiresAtMonotonicNanoseconds: UInt64) throws {
        self.reviewID = reviewID; self.binding = binding
        bindingDigest = try binding.canonicalDigest()
        self.issuedAtMonotonicNanoseconds = issuedAtMonotonicNanoseconds
        self.expiresAtMonotonicNanoseconds = expiresAtMonotonicNanoseconds
        try validate()
    }

    func validate() throws {
        guard expiresAtMonotonicNanoseconds > issuedAtMonotonicNanoseconds,
              expiresAtMonotonicNanoseconds - issuedAtMonotonicNanoseconds <= Self.maximumLifetimeNanoseconds,
              try binding.canonicalDigest() == bindingDigest else { throw ManualServiceInventoryError.invalidReview }
    }
}

extension ManualServiceReviewSummary {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reviewID = try c.decode(UUID.self, forKey: .reviewID)
        binding = try c.decode(ManualServiceOperationBinding.self, forKey: .binding)
        bindingDigest = try c.decode(Data.self, forKey: .bindingDigest)
        issuedAtMonotonicNanoseconds = try c.decode(UInt64.self, forKey: .issuedAtMonotonicNanoseconds)
        expiresAtMonotonicNanoseconds = try c.decode(UInt64.self, forKey: .expiresAtMonotonicNanoseconds)
        try validate()
    }
}

enum ManualServiceAcceptanceDenial: String, Equatable, Sendable {
    case invalidBinding, unsupportedVersion, producerAcceptanceMissing
}

/// No dynamic registration, caller flags, fixture provider or portable setting
/// can alter this compiled decision. Qualifying production evidence is still
/// missing for both adapter/provider/version combinations.
enum ManualServiceAcceptanceRegistry {
    static func denial(for binding: ManualServiceOperationBinding) -> ManualServiceAcceptanceDenial? {
        guard (try? binding.validate()) != nil else { return .invalidBinding }
        if case .appleSimulator(let producer) = binding.producer,
           !producer.isInspectedCandidateVersion { return .unsupportedVersion }
        return .producerAcceptanceMissing
    }
}

enum ManualServiceInventoryError: Error, Equatable, Sendable {
    case malformed, capacity, invalidIdentity, identityMismatch, duplicateIdentity
    case unsupportedSchema, unsupportedProducer, ineligibleState, unavailableRuntime
    case pairedSimulator, managedContainer, mountedContainer, invalidReview
}

enum ManualServiceValueBounds {
    static func string(_ value: String, maximum: Int) throws {
        guard !value.isEmpty, value.utf8.count <= maximum, !value.utf8.contains(0),
              !value.contains("\r"), !value.contains("\n") else { throw ManualServiceInventoryError.capacity }
    }
    static func path(_ value: String) throws {
        try string(value, maximum: 4_096)
        guard value.hasPrefix("/"), !value.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw ManualServiceInventoryError.invalidIdentity
        }
    }
    static func executable(_ value: LocalExecutableApproval) throws {
        try path(value.canonicalPath)
        guard value.inode > 0 else { throw ManualServiceInventoryError.invalidIdentity }
    }
    static func root(_ value: LocalRootApproval) throws {
        try path(value.canonicalPath)
        guard value.inode > 0 else { throw ManualServiceInventoryError.invalidIdentity }
    }
    static func containerID(_ value: String) throws {
        guard value.utf8.count == 64, value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw ManualServiceInventoryError.invalidIdentity
        }
    }
    static func apiVersion(_ value: String) throws -> Int {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "1", parts[1].count <= 3,
              !parts[1].isEmpty, parts[1].utf8.allSatisfy({ (48...57).contains($0) }),
              let minor = Int(parts[1]), String(minor) == parts[1] else {
            throw ManualServiceInventoryError.unsupportedProducer
        }
        return minor
    }
    static func isManagedLabel(_ key: String) -> Bool {
        ["com.docker.compose.", "com.docker.stack.", "com.docker.swarm.", "io.kubernetes."]
            .contains(where: { key.lowercased().hasPrefix($0) })
    }
}
