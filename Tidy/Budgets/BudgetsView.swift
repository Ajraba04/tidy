import Dispatch
import SwiftUI
import TidyCore

struct BudgetsView: View {
    private let authority: LocalAuthorityStore?
    private let inputSnapshot: LocalAuthoritySnapshot?
    private let policy: EffectivePolicy?
    private let volumeID: UUID?
    private let measurements: [BudgetMeasurement]
    private let broker: NotificationBroker?
    private let onAuthorityChange: @MainActor (LocalAuthoritySnapshot) -> Void

    @State private var authorityOwner = LocalAuthorityOwner()
    @State private var currentSnapshot: LocalAuthoritySnapshot?
    @State private var priorEvaluation: BudgetEvaluation?
    @State private var permission: NotificationPermission = .notDetermined
    @State private var pendingNotificationToken: LocalAuthorityReviewToken?
    @State private var message: String?
    @State private var busy = false

    init(authority: LocalAuthorityStore?, snapshot: LocalAuthoritySnapshot?,
         policy: EffectivePolicy?, volumeID: UUID?,
         measurements: [BudgetMeasurement], broker: NotificationBroker?,
         onAuthorityChange: @escaping @MainActor (LocalAuthoritySnapshot) -> Void) {
        self.authority = authority
        inputSnapshot = snapshot
        self.policy = policy
        self.volumeID = volumeID
        self.measurements = measurements
        self.broker = broker
        self.onAuthorityChange = onAuthorityChange
        _currentSnapshot = State(initialValue: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budgets").font(.title2.bold())
            Text("Suggestions are disabled until configured. Measurements are evaluated per volume and never summed across overlapping categories.")
                .font(.caption).foregroundStyle(.secondary)

            if !featureEnabled {
                Label("Budgets are unavailable in the effective policy.", systemImage: "lock")
                    .foregroundStyle(.secondary)
            } else if let evaluation {
                List(BudgetID.allCases, id: \.self) { id in
                    budgetRow(evaluation.statuses[id])
                }
                .frame(minHeight: 260)
            } else {
                ContentUnavailableView("No selected volume", systemImage: "externaldrive.badge.questionmark",
                    description: Text("Budget evaluation requires an approved volume and effective policy."))
            }

            GroupBox("Notifications") {
                Text("Local grant: \(notificationGrantLabel) · macOS: \(permission.rawValue)")
                    .font(.caption)
                HStack {
                    if currentSnapshot?.permits(.notifications) == true {
                        Button("Revoke local notification grant", role: .destructive,
                               action: revokeNotificationGrant)
                    } else if pendingNotificationToken == nil {
                        Button("Review local notification grant…", action: reviewNotificationGrant)
                    } else {
                        Button("Confirm local notification grant", action: confirmNotificationGrant)
                        Button("Cancel", role: .cancel) { cancelNotificationReview() }
                    }
                    Button("Refresh macOS permission", action: refreshPermission)
                    Button("Request macOS permission", action: requestPermission)
                        .disabled(currentSnapshot?.permits(.notifications) != true || broker == nil)
                }
                .disabled(busy)
                Text("Opening a notification only navigates to review. It never runs cleanup.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("budgets.status")
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 480)
        .task { await refreshPermissionValue() }
        .onChange(of: inputSnapshot) { _, updated in
            guard currentSnapshot != updated else { return }
            cancelNotificationReview()
            currentSnapshot = updated
            message = "Local authority changed; any open notification review was cancelled."
        }
        .onAppear { priorEvaluation = evaluation }
        .onChange(of: measurements) { _, _ in priorEvaluation = evaluation }
        .onDisappear(perform: cancelNotificationReview)
    }

    private var featureEnabled: Bool {
        policy?.allowedFeatures.contains("budgets") == true
    }

    private var evaluation: BudgetEvaluation? {
        guard let policy, let volumeID else { return nil }
        return BudgetEvaluator.evaluate(policy: policy, volumeID: volumeID,
                                        measurements: measurements,
                                        previous: priorEvaluation)
    }

    private var notificationGrantLabel: String {
        currentSnapshot?.permits(.notifications) == true ? "approved" : "off"
    }

    @ViewBuilder
    private func budgetRow(_ status: BudgetStatus?) -> some View {
        if let status {
            HStack {
                VStack(alignment: .leading) {
                    Text(status.budgetID.rawValue)
                    Text(statusDetail(status)).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(status.state.rawValue).font(.caption)
            }
        }
    }

    private func statusDetail(_ status: BudgetStatus) -> String {
        guard let used = status.usedBytes, let high = status.highBytes,
              let low = status.lowBytes else {
            return status.alertLatched
                ? "Measurement unavailable; the prior warning is retained."
                : "Disabled or measurement unavailable."
        }
        return "\(ByteFormat.human(used)) used · warn at \(ByteFormat.human(high)) · clear at \(ByteFormat.human(low))"
    }

    private func reviewNotificationGrant() {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                pendingNotificationToken = try await authority.beginReview(
                    scope: .notifications, owner: authorityOwner,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
            } catch { message = "Notification review denied: \(String(describing: error))" }
            busy = false
        }
    }

    private func confirmNotificationGrant() {
        guard let authority, let token = pendingNotificationToken else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                let snapshot = try await authority.confirm(token, owner: authorityOwner,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                currentSnapshot = snapshot
                onAuthorityChange(snapshot)
                pendingNotificationToken = nil
                message = "Local notification grant saved. macOS permission is still separate."
            } catch { message = "Notification grant failed: \(String(describing: error))" }
            busy = false
        }
    }

    private func revokeNotificationGrant() {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                let snapshot = try await authority.revoke(.notifications)
                currentSnapshot = snapshot
                onAuthorityChange(snapshot)
                message = "Local notification grant revoked."
            } catch { message = "Revoke failed; notification delivery remains denied: \(String(describing: error))" }
            busy = false
        }
    }

    private func cancelNotificationReview() {
        guard let token = pendingNotificationToken else { return }
        pendingNotificationToken = nil
        guard let authority else { return }
        Task { try? await authority.cancel(token, owner: authorityOwner) }
    }

    private func refreshPermission() {
        Task { @MainActor in await refreshPermissionValue() }
    }

    private func refreshPermissionValue() async {
        guard let broker else { permission = .denied; return }
        permission = await broker.permission()
    }

    private func requestPermission() {
        guard let broker, currentSnapshot?.permits(.notifications) == true else { return }
        busy = true
        Task { @MainActor in
            permission = await broker.requestAuthorizationFromExplicitUserAction()
            message = permission == .authorized
                ? "macOS notification permission is available."
                : "macOS notification permission was not granted."
            busy = false
        }
    }
}
