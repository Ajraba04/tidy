import Foundation
import Security

enum ManualSimulatorNativeLaunchOutcome: Sendable {
    case launched(ManualSimulatorOwnedLaunch)
    case notSpawned(ManualSimulatorNeverSpawnedReceipt)
}

extension AppleSimulatorOperation {
    /// Native acceptance is checked before gate admission, durable submission,
    /// tool discovery or any possible spawn. Both providers remain denied.
    static func requireAcceptedProducer(for binding: ManualServiceOperationBinding) throws {
        guard binding.adapter == .appleSimulatorShutdownV1,
              ManualServiceAcceptanceRegistry.denial(for: binding) == nil else {
            throw ManualServiceReviewError.providerUnavailable
        }
    }

    static func launch(submission: ManualServiceSubmission, grant: ManualServicePolicyGrant,
                       deadline: ContinuousClock.Instant,
                       cancellation: EffectCancellationToken) async throws -> ManualSimulatorNativeLaunchOutcome {
        try requireAcceptedProducer(for: submission.effectBinding.operation)
        return try await ProcessRunner.launchManualSimulatorShutdown(submission: submission,
            grant: grant, deadline: deadline, cancellation: cancellation)
    }

    static func validateGrant(_ grant: ManualServicePolicyGrant,
                              binding: ManualServiceEffectBinding) throws {
        guard binding.coordinatorID == grant.coordinatorID,
              binding.policyRevision == grant.policyRevision,
              binding.authorityRevision == grant.authority.revision,
              binding.installation == grant.authority.installation else {
            throw ManualServiceReviewError.bindingMismatch
        }
        try grant.validateScope(for: binding.operation)
    }

    static func requireAppleSignature(_ executable: LocalExecutableApproval) throws {
        let url = URL(fileURLWithPath: executable.canonicalPath)
        guard try LocalExecutableApproval.verify(executable: url) == executable else {
            throw ManualServiceInventoryError.identityMismatch
        }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
              let code, let requirement else { throw ManualServiceReviewError.providerUnavailable }
        // Network access is opt-in for this API; kSecCSAllowNetworkAccess is
        // deliberately absent. This is signature evidence, not acceptance.
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess,
              try LocalExecutableApproval.verify(executable: url) == executable else {
            throw ManualServiceReviewError.providerUnavailable
        }
    }
}
