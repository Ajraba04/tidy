import CryptoKit
import Foundation

/// Immutable command metadata, not a launch capability. Only the separate
/// process owner can combine one with an actually owned session.
struct ManualSimulatorShutdownInvocation: Sendable {
    enum Origin: String, Codable, Sendable { case nativeShutdown, cooperativeFixture }
    let origin: Origin
    let binding: ManualServiceEffectBinding
    let runID: UUID
    let operationID: UUID
    let executable: LocalExecutableApproval
    let arguments: [String]
    let environment: [String: String]
    let operationBindingDigest: Data
    let invocationDigest: Data

    private struct Encoding: Codable {
        let schema: Int
        let origin: Origin
        let binding: ManualServiceEffectBinding
        let runID: UUID
        let operationID: UUID
        let executable: LocalExecutableApproval
        let arguments: [String]
        let environment: [String: String]
    }

    private init(origin: Origin, binding: ManualServiceEffectBinding, runID: UUID,
                 operationID: UUID, executable: LocalExecutableApproval,
                 arguments: [String], environment: [String: String]) throws {
        try binding.validate()
        self.origin = origin; self.binding = binding; self.runID = runID; self.operationID = operationID
        self.executable = executable; self.arguments = arguments; self.environment = environment
        operationBindingDigest = try binding.operation.canonicalDigest()
        let value = Encoding(schema: 1, origin: origin, binding: binding, runID: runID,
            operationID: operationID, executable: executable, arguments: arguments, environment: environment)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard bytes.count <= 131_072 else { throw ManualServiceInventoryError.capacity }
        invocationDigest = Data(SHA256.hash(data: bytes))
    }

    static func describe(binding: ManualServiceEffectBinding,
                         runID: UUID, operationID: UUID) throws -> Self {
        let (object, producer) = try simulatorBinding(binding)
        guard producer.isInspectedCandidateVersion,
              producer.resolver.canonicalPath == "/usr/bin/xcrun",
              producer.developerDirectory.canonicalPath.hasSuffix(".app/Contents/Developer"),
              producer.simctl.canonicalPath == producer.developerDirectory.canonicalPath + "/usr/bin/simctl" else {
            throw ManualServiceInventoryError.unsupportedProducer
        }
        return try Self(origin: .nativeShutdown, binding: binding, runID: runID, operationID: operationID,
            executable: producer.simctl,
            arguments: ["--set", producer.deviceSet.canonicalPath, "shutdown", object.udid.uuidString],
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty",
                          "DEVELOPER_DIR": producer.developerDirectory.canonicalPath])
    }

    /// Pure metadata for a separately declared harmless cooperative child.
    /// This origin is digest-bound and can never describe a native shutdown.
    static func cooperativeFixture(binding: ManualServiceEffectBinding, runID: UUID,
                                   operationID: UUID, executable: LocalExecutableApproval) throws -> Self {
        let (_, producer) = try simulatorBinding(binding)
        guard executable.canonicalPath == "/bin/cat", producer.simctl == executable else {
            throw ManualServiceInventoryError.identityMismatch
        }
        return try Self(origin: .cooperativeFixture, binding: binding, runID: runID,
            operationID: operationID, executable: executable, arguments: [],
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty"])
    }

    static func simulatorBinding(_ binding: ManualServiceEffectBinding) throws
        -> (ManualSimulatorObject, AppleSimulatorProducerIdentity) {
        try binding.validate()
        guard binding.operation.adapter == .appleSimulatorShutdownV1,
              case .simulator(let object) = binding.operation.object,
              case .appleSimulator(let producer) = binding.operation.producer else {
            throw ManualServiceInventoryError.identityMismatch
        }
        guard object.isAvailable, object.state == .booted else {
            throw ManualServiceInventoryError.ineligibleState
        }
        return (object, producer)
    }
}
