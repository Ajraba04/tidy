import AppKit
import Dispatch
import SwiftUI
import TidyCore

struct MaintenanceSettingsView: View {
    private let authority: LocalAuthorityStore?
    private let inputSnapshot: LocalAuthoritySnapshot?
    private let policy: EffectivePolicy?
    private let policyRevision: UInt64
    private let ruleStatuses: [MaintenanceRuleStatus]
    private let onAuthorityChange: @MainActor (LocalAuthoritySnapshot) -> Void

    @State private var owner = LocalAuthorityOwner()
    @State private var currentSnapshot: LocalAuthoritySnapshot?
    @State private var pending: PendingMaintenanceConsent?
    @State private var message: String?
    @State private var busy = false

    init(authority: LocalAuthorityStore?, snapshot: LocalAuthoritySnapshot?,
         policy: EffectivePolicy?, policyRevision: UInt64,
         ruleStatuses: [MaintenanceRuleStatus] = [],
         onAuthorityChange: @escaping @MainActor (LocalAuthoritySnapshot) -> Void) {
        self.authority = authority
        inputSnapshot = snapshot
        self.policy = policy
        self.policyRevision = policyRevision
        self.ruleStatuses = ruleStatuses
        self.onAuthorityChange = onAuthorityChange
        _currentSnapshot = State(initialValue: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Maintenance").font(.headline)
            Text("Off by default. Notify-only rules open review; they never run cleanup.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("Mode")
                Spacer()
                Text(activeNotifyGrants.isEmpty ? "Off" : "Notify only")
                    .foregroundStyle(.secondary)
            }

            if !featureEnabled {
                Label("Maintenance is disabled by the effective policy.", systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(activeNotifyGrants, id: \.self) { grant in
                ruleRow(grant, stale: false)
            }
            ForEach(staleNotifyGrants, id: \.self) { grant in
                ruleRow(grant, stale: true)
            }

            Button("Review notify-only DerivedData rule…", action: chooseRoot)
                .disabled(busy || authority == nil || !featureEnabled)
                .accessibilityIdentifier("maintenance.reviewNotifyOnly")

            GroupBox("Authorized cache maintenance") {
                Label("Unavailable: the source-reviewed unattended capability allowlist is empty.",
                      systemImage: "nosign")
                    .font(.caption)
                Text("No Safe-tier item, imported setting, or profile can enable automatic cleanup.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if let pending {
                GroupBox("Review notify-only rule") {
                    Text(ruleSummary(pending.grant)).font(.caption)
                    Text("Confirming permits a review notification only. It grants no cleanup execution.")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button("Confirm notify-only rule") { confirm(pending) }
                        Button("Cancel", role: .cancel) { cancelPendingReview() }
                    }
                }
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("maintenance.status")
            }
        }
        .onChange(of: inputSnapshot) { _, updated in
            guard currentSnapshot != updated else { return }
            cancelPendingReview()
            currentSnapshot = updated
            message = "Local authority changed; any open maintenance review was cancelled."
        }
        .onDisappear(perform: cancelPendingReview)
    }

    private var featureEnabled: Bool {
        policy?.allowedFeatures.contains("maintenance") == true
    }

    private var activeNotifyGrants: [MaintenanceGrant] {
        grants(in: currentSnapshot?.scopes ?? [])
    }

    private var staleNotifyGrants: [MaintenanceGrant] {
        grants(in: currentSnapshot?.staleScopes ?? [])
    }

    private func grants(in scopes: Set<LocalAuthorityScope>) -> [MaintenanceGrant] {
        scopes.compactMap {
            if case .maintenanceNotifyOnly(let grant) = $0 { return grant }
            return nil
        }.sorted { $0.ruleID.uuidString < $1.ruleID.uuidString }
    }

    @ViewBuilder
    private func ruleRow(_ grant: MaintenanceGrant, stale: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(grant.root.canonicalPath).font(.caption)
                Text(stale ? "Identity changed; this rule has no authority."
                            : "Notify only · up to \(ByteFormat.human(grant.maxBytes)) / \(grant.maxItems) items")
                    .font(.caption2).foregroundStyle(.secondary)
                if !stale, let status = ruleStatuses.first(where: { $0.id == grant.ruleID }) {
                    Text(statusLabel(status))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("maintenance.ruleStatus.\(grant.ruleID.uuidString)")
                }
            }
            Spacer()
            Button("Revoke", role: .destructive) { revoke(grant) }.disabled(busy)
        }
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let root = try LocalRootApproval.verify(directory: url)
            let grant = try MaintenanceGrant.registryDefaultNotifyOnly(
                capabilityID: .appleDerivedData, root: root,
                policyRevision: policyRevision)
            begin(grant)
        } catch { message = "Rule review denied: \(String(describing: error))" }
    }

    private func begin(_ grant: MaintenanceGrant) {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                let token = try await authority.beginReview(
                    scope: .maintenanceNotifyOnly(grant), owner: owner,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                pending = PendingMaintenanceConsent(token: token, grant: grant)
            } catch { message = "Rule review denied: \(String(describing: error))" }
            busy = false
        }
    }

    private func confirm(_ pending: PendingMaintenanceConsent) {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                let snapshot = try await authority.confirm(pending.token, owner: owner,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                currentSnapshot = snapshot
                onAuthorityChange(snapshot)
                self.pending = nil
                message = "Notify-only rule saved. No cleanup was run."
            } catch { message = "Rule confirmation failed; maintenance remains denied: \(String(describing: error))" }
            busy = false
        }
    }

    private func revoke(_ grant: MaintenanceGrant) {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                let snapshot = try await authority.revoke(.maintenanceNotifyOnly(grant))
                currentSnapshot = snapshot
                onAuthorityChange(snapshot)
                message = "Notify-only rule revoked."
            } catch { message = "Revoke failed; the rule remains fail-closed: \(String(describing: error))" }
            busy = false
        }
    }

    private func cancelPendingReview() {
        guard let pending else { return }
        self.pending = nil
        guard let authority else { return }
        Task { try? await authority.cancel(pending.token, owner: owner) }
    }

    private func ruleSummary(_ grant: MaintenanceGrant) -> String {
        "Capability: \(grant.capabilityID.rawValue)\n"
        + "Root: \(grant.root.canonicalPath)\n"
        + "Volume: \(grant.root.volumeID.uuidString)\n"
        + "Maximum: \(ByteFormat.human(grant.maxBytes)), \(grant.maxItems) items\n"
        + "Minimum age: \(grant.minimumAgeDays) days · interval: \(grant.minimumIntervalHours) hours"
    }

    private func statusLabel(_ status: MaintenanceRuleStatus) -> String {
        let prefix: String
        switch status.state {
        case .denied: prefix = "Denied"
        case .eligible: prefix = "Eligible"
        case .delivered: prefix = "Notification accepted"
        }
        return "\(prefix): \(status.detail)"
    }
}

private struct PendingMaintenanceConsent {
    let token: LocalAuthorityReviewToken
    let grant: MaintenanceGrant
}
