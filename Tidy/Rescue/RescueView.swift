import Dispatch
import SwiftUI
import TidyCore

struct RescueView: View {
    private let authority: LocalAuthorityStore?
    private let inputSnapshot: LocalAuthoritySnapshot?
    private let policy: EffectivePolicy?
    private let inputPolicyRevision: UInt64
    private let onAuthorityChange: @MainActor (LocalAuthoritySnapshot) -> Void
    private let observeAvailableBytes: (@Sendable () async -> Int64?)?

    @State private var planner: RescuePlanner
    @State private var owner = UUID()
    @State private var authorityOwner = LocalAuthorityOwner()
    @State private var currentSnapshot: LocalAuthoritySnapshot?
    @State private var workloads: [VisibleApplicationWorkload] = []
    @State private var selected: Set<WorkloadIdentity> = []
    @State private var pendingAuthority: PendingRescueAuthority?
    @State private var pendingReview: RescueReview?
    @State private var message: String?
    @State private var busy = false

    init(authority: LocalAuthorityStore?, snapshot: LocalAuthoritySnapshot?,
         policy: EffectivePolicy?, policyRevision: UInt64,
         terminator: any GracefulApplicationTerminating = ApplicationTerminator(),
         livePolicy: @escaping @MainActor @Sendable () -> RescueLivePolicy,
         observeAvailableBytes: (@Sendable () async -> Int64?)? = nil,
         onAuthorityChange: @escaping @MainActor (LocalAuthoritySnapshot) -> Void) {
        self.authority = authority
        inputSnapshot = snapshot
        self.policy = policy
        inputPolicyRevision = policyRevision
        self.onAuthorityChange = onAuthorityChange
        self.observeAvailableBytes = observeAvailableBytes
        _planner = State(initialValue: RescuePlanner(
            terminator: terminator, livePolicy: livePolicy))
        _currentSnapshot = State(initialValue: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Pressure Rescue").font(.title2.bold())
                    Text("Gracefully ask one exact app instance to quit. Nothing is selected automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh running apps", action: refresh)
                    .disabled(busy || !featureEnabled || pendingReview != nil
                              || pendingAuthority != nil)
                    .accessibilityIdentifier("rescue.refresh")
            }

            if !featureEnabled {
                Label("Rescue is unavailable in the effective policy.",
                      systemImage: "lock")
                    .foregroundStyle(.secondary)
            } else if workloads.isEmpty {
                ContentUnavailableView("No reviewed app list", systemImage: "app.dashed",
                    description: Text("Choose Refresh running apps to take a fresh, visible snapshot."))
            } else {
                List(workloads) { item in
                    Toggle(isOn: selectionBinding(item.workload)) {
                        VStack(alignment: .leading) {
                            Text(item.displayName)
                            Text("PID \(item.workload.pid) · \(item.workload.bundleIdentifier)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(busy || pendingReview != nil || pendingAuthority != nil)
                }
                .frame(minHeight: 220)
            }

            if let pendingAuthority {
                GroupBox("Local approval review") {
                    Text("Approve graceful rescue for \(pendingAuthority.workload.bundleIdentifier) at \(pendingAuthority.workload.bundleURL.path). This does not quit it.")
                        .font(.caption)
                    HStack {
                        Button("Confirm local approval") { confirmAuthority(pendingAuthority) }
                        Button("Cancel", role: .cancel) { cancelAuthorityReview() }
                    }
                }
            } else if let pendingReview {
                GroupBox("Graceful quit review") {
                    Text("PID \(pendingReview.workload.pid) at \(pendingReview.workload.bundleURL.path). The app may refuse, time out, or already have exited. No force quit is available.")
                        .font(.caption)
                    HStack {
                        Button("Confirm graceful quit") { confirmRescue(pendingReview) }
                        Button("Cancel", role: .cancel) { cancelReview(pendingReview) }
                    }
                }
            } else {
                Button("Review selected app") { beginReview() }
                    .disabled(busy || selected.count != 1 || authority == nil)
                    .accessibilityIdentifier("rescue.review")
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("rescue.status")
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
        .onChange(of: inputSnapshot) { _, updated in
            guard currentSnapshot != updated else { return }
            let review = pendingReview
            cancelAuthorityReview()
            currentSnapshot = updated
            pendingReview = nil
            selected = []
            message = "Local authority changed; any open rescue review was cancelled."
            if let review {
                Task { try? await planner.cancel(review.token, owner: owner) }
            }
        }
        .onChange(of: inputPolicyRevision) { _, _ in
            invalidatePendingReviewsForPolicyChange()
        }
        .onDisappear {
            cancelAuthorityReview()
            if let review = pendingReview {
                pendingReview = nil
                Task { try? await planner.cancel(review.token, owner: owner) }
            }
        }
    }

    private var featureEnabled: Bool {
        policy?.allowedFeatures.contains("rescue") == true
    }

    private var timeoutSeconds: Int {
        guard case .stored(.integer(let value))? = policy?.fields[
            SettingID(rawValue: "rescue.quitTimeoutSeconds")]?.value,
              let seconds = Int(exactly: value), (5...60).contains(seconds) else { return 15 }
        return seconds
    }

    private func selectionBinding(_ workload: WorkloadIdentity) -> Binding<Bool> {
        Binding(get: { selected.contains(workload) }, set: { enabled in
            if enabled {
                selected = [workload]
            } else {
                selected.remove(workload)
            }
        })
    }

    private func refresh() {
        workloads = ApplicationWorkloadInventory.refresh()
        selected = []
        pendingAuthority = nil
        pendingReview = nil
        message = workloads.isEmpty ? "No visible regular applications were captured." : nil
    }

    private func beginReview() {
        guard let workload = selected.first, let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                let approval = try RescueApplicationApproval(
                    bundleURL: workload.bundleURL,
                    bundleIdentifier: workload.bundleIdentifier)
                let snapshot = try await authority.snapshot()
                currentSnapshot = snapshot
                if snapshot.permits(.rescueApplication(approval)) {
                    try await prepareRescue(workload: workload,
                                            approval: approval, snapshot: snapshot)
                } else {
                    let token = try await authority.beginReview(
                        scope: .rescueApplication(approval), owner: authorityOwner,
                        nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                    pendingAuthority = PendingRescueAuthority(token: token,
                        approval: approval, workload: workload)
                }
            } catch { message = "Rescue review denied: \(String(describing: error))" }
            busy = false
        }
    }

    private func confirmAuthority(_ pending: PendingRescueAuthority) {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                let snapshot = try await authority.confirm(pending.token,
                    owner: authorityOwner,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                currentSnapshot = snapshot
                onAuthorityChange(snapshot)
                pendingAuthority = nil
                try await prepareRescue(workload: pending.workload,
                                        approval: pending.approval, snapshot: snapshot)
            } catch { message = "Local approval denied: \(String(describing: error))" }
            busy = false
        }
    }

    private func prepareRescue(workload: WorkloadIdentity,
                               approval: RescueApplicationApproval,
                               snapshot: LocalAuthoritySnapshot) async throws {
        pendingReview = try await planner.beginReview(workload: workload,
            approval: approval, authority: snapshot, owner: owner,
            nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
        selected = []
    }

    private func confirmRescue(_ review: RescueReview) {
        busy = true; message = nil
        Task { @MainActor in
            do {
                _ = try await planner.select(review.token, owner: owner,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                let current = ApplicationWorkloadInventory.recapture(review.workload)
                let before = await observedAvailableBytes()
                var result = try await planner.requestGracefulTermination(review.token,
                    owner: owner, currentIdentity: current,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
                    timeoutSeconds: timeoutSeconds)
                let after = await observedAvailableBytes()
                result = result.recordingSystemObservation(
                    beforeAvailableBytes: before, afterAvailableBytes: after)
                message = resultMessage(result)
                pendingReview = nil
            } catch { message = "Graceful quit denied: \(String(describing: error))" }
            busy = false
        }
    }

    private func cancelReview(_ review: RescueReview) {
        Task { @MainActor in
            try? await planner.cancel(review.token, owner: owner)
            pendingReview = nil
            message = "Review cancelled; no request was sent."
        }
    }

    private func cancelAuthorityReview() {
        guard let pendingAuthority else { return }
        self.pendingAuthority = nil
        guard let authority else { return }
        Task {
            try? await authority.cancel(pendingAuthority.token,
                                        owner: authorityOwner)
        }
    }

    private func invalidatePendingReviewsForPolicyChange() {
        cancelAuthorityReview()
        if let review = pendingReview {
            pendingReview = nil
            Task { try? await planner.cancel(review.token, owner: owner) }
        }
        selected = []
        message = "Effective policy changed; any open rescue review was cancelled."
    }

    private func resultMessage(_ result: RescueOutcome) -> String {
        let outcome: String
        switch result.termination {
        case .exited: outcome = "The reviewed app instance exited after the graceful request."
        case .alreadyExited: outcome = "The reviewed app instance had already exited; no request was sent."
        case .refused: outcome = "The app refused the graceful quit request."
        case .timedOut: outcome = "The app did not exit before the timeout. It was not force-quit."
        case .unavailable: outcome = "The exact app identity could not be confirmed. No request was sent."
        }
        guard let delta = result.memory.noisyAvailableByteDelta else { return outcome }
        let prefix = delta >= 0 ? "+" : ""
        return outcome + " Observed system-wide available-memory change: "
            + prefix + ByteFormat.human(delta.magnitude > UInt64(Int64.max)
                ? Int64.max : Int64(delta.magnitude))
            + (delta < 0 ? " decrease" : " increase")
            + ". This noisy delta is not attributed to the app."
    }

    private func observedAvailableBytes() async -> Int64? {
        guard let observeAvailableBytes else { return nil }
        return await observeAvailableBytes()
    }
}

private struct PendingRescueAuthority {
    let token: LocalAuthorityReviewToken
    let approval: RescueApplicationApproval
    let workload: WorkloadIdentity
}
