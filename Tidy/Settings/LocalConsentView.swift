import AppKit
import Dispatch
import SwiftUI
import TidyCore

struct LocalConsentView: View {
    private let authority: LocalAuthorityStore?
    private let inputSnapshot: LocalAuthoritySnapshot?
    private let policy: EffectivePolicy?
    private let onAuthorityChange: @MainActor (LocalAuthoritySnapshot) -> Void

    @State private var owner = LocalAuthorityOwner()
    @State private var currentSnapshot: LocalAuthoritySnapshot?
    @State private var pending: PendingLocalConsent?
    @State private var socketPath = ""
    @State private var confirmsRevokeAll = false
    @State private var message: String?
    @State private var busy = false

    init(authority: LocalAuthorityStore?, snapshot: LocalAuthoritySnapshot?,
         policy: EffectivePolicy?,
         onAuthorityChange: @escaping @MainActor (LocalAuthoritySnapshot) -> Void) {
        self.authority = authority
        inputSnapshot = snapshot
        self.policy = policy
        self.onAuthorityChange = onAuthorityChange
        _currentSnapshot = State(initialValue: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local consent").font(.headline)
            Text("These grants stay in Tidy's private local authority ledger. Settings imports and profiles cannot create them.")
                .font(.caption).foregroundStyle(.secondary)

            consentRow(title: "Background signals",
                       detail: "Allows bounded signal sampling while Tidy is hidden.",
                       scope: .backgroundSignals)
            consentRow(title: "Notifications",
                       detail: "Allows Tidy to consider notifications. macOS permission is requested separately.",
                       scope: .notifications)

            Divider()
            HStack {
                Button("Review local root…") { chooseRoot() }
                Button("Review external volume…") { chooseExternalVolume() }
                Button("Review local executable…") { chooseExecutable() }
            }
            .disabled(busy || authority == nil)
            HStack {
                TextField("/path/to/local.sock", text: $socketPath)
                    .textFieldStyle(.roundedBorder)
                Button("Review Unix socket") { reviewSocket() }
                    .disabled(socketPath.isEmpty || busy || authority == nil)
            }

            if let snapshot = currentSnapshot {
                let current = localPathScopes(snapshot.scopes)
                if !current.isEmpty {
                    Text("Current local identities").font(.subheadline.bold())
                    ForEach(current, id: \.self) { scope in
                        identityRow(scope: scope, stale: false)
                    }
                }
                let stale = localPathScopes(snapshot.staleScopes)
                if !stale.isEmpty {
                    Text("Reassociation required").font(.subheadline.bold())
                    ForEach(stale, id: \.self) { scope in
                        identityRow(scope: scope, stale: true)
                    }
                }
            }

            if let pending {
                GroupBox("Review local grant") {
                    Text(pending.summary).font(.caption)
                    Text("Confirming changes only the machine-local authority ledger.")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button("Confirm grant") { confirm(pending) }
                        Button("Cancel", role: .cancel) { cancelPendingReview() }
                    }
                }
            }

            if authority == nil {
                Label("Local authority storage is unavailable. All grants remain denied.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if policy == nil {
                Text("Effective policy is unavailable; consumers remain disabled even if a local grant exists.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("localConsent.status")
            }
            Button("Revoke all local consent…", role: .destructive) {
                confirmsRevokeAll = true
            }
            .disabled(busy || authority == nil
                      || currentSnapshot?.recordedScopes.isEmpty != false)
        }
        .onChange(of: inputSnapshot) { _, updated in
            guard currentSnapshot != updated else { return }
            cancelPendingReview()
            currentSnapshot = updated
            message = "Local authority changed; any open review was cancelled."
        }
        .onDisappear(perform: cancelPendingReview)
        .confirmationDialog("Revoke every local grant?",
            isPresented: $confirmsRevokeAll, titleVisibility: .visible) {
                Button("Revoke all local consent", role: .destructive,
                       action: revokeAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This stops background signals and removes notification, rescue, maintenance, login-item, root, volume, executable, and socket authority. It does not edit portable settings or change macOS Login Items registration.")
            }
    }

    @ViewBuilder
    private func consentRow(title: String, detail: String,
                            scope: LocalAuthorityScope) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if currentSnapshot?.permits(scope) == true {
                Button("Revoke", role: .destructive) { revoke(scope) }
                    .disabled(busy)
            } else {
                Button("Review…") { begin(scope: scope, summary: detail) }
                    .disabled(busy || authority == nil)
            }
        }
    }

    @ViewBuilder
    private func identityRow(scope: LocalAuthorityScope, stale: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(scopeTitle(scope)).font(.caption)
                if stale {
                    Text("The recorded inode/device no longer matches. This grant has no effect.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if stale {
                Button("Reassociate…") { reassociate(scope) }.disabled(busy)
            }
            Button("Revoke", role: .destructive) { revoke(scope) }.disabled(busy)
        }
    }

    private func begin(scope: LocalAuthorityScope, summary: String,
                       replacing: LocalAuthorityScope? = nil) {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                let token = try await authority.beginReview(scope: scope, owner: owner,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                pending = PendingLocalConsent(token: token, scope: scope,
                    replacing: replacing, summary: summary)
            } catch { message = "Grant review denied: \(String(describing: error))" }
            busy = false
        }
    }

    private func confirm(_ pending: PendingLocalConsent) {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                let confirmed = try await authority.confirm(pending.token, owner: owner,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                currentSnapshot = confirmed
                onAuthorityChange(confirmed)
                if let replacing = pending.replacing {
                    do {
                        let final = try await authority.revoke(replacing)
                        currentSnapshot = final
                        onAuthorityChange(final)
                    } catch {
                        self.pending = nil
                        message = "New local identity was approved, but the stale record could not be revoked: \(String(describing: error))"
                        busy = false
                        return
                    }
                }
                self.pending = nil
                message = "Local grant saved."
            } catch { message = "Grant confirmation failed; authority remains denied: \(String(describing: error))" }
            busy = false
        }
    }

    private func revoke(_ scope: LocalAuthorityScope) {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                let snapshot = try await authority.revoke(scope)
                currentSnapshot = snapshot
                onAuthorityChange(snapshot)
                if pending?.scope == scope { pending = nil }
                message = "Local grant revoked."
            } catch { message = "Revoke failed; consumers remain fail-closed: \(String(describing: error))" }
            busy = false
        }
    }

    private func cancelPendingReview() {
        guard let pending else { return }
        self.pending = nil
        guard let authority else { return }
        Task { try? await authority.cancel(pending.token, owner: owner) }
    }

    private func revokeAll() {
        guard let authority else { return }
        cancelPendingReview()
        busy = true; message = nil
        Task { @MainActor in
            do {
                let snapshot = try await authority.revokeAll()
                currentSnapshot = snapshot
                onAuthorityChange(snapshot)
                message = "All local consent was revoked."
            } catch {
                currentSnapshot = nil
                message = "The ledger could not publish revocation; runtime authority remains fail-closed: \(String(describing: error))"
            }
            busy = false
        }
    }

    private func chooseRoot(replacing: LocalAuthorityScope? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let approval = try LocalRootApproval.verify(directory: url)
            begin(scope: .localRoot(approval),
                  summary: "Local root: \(approval.canonicalPath)\nVolume: \(approval.volumeID.uuidString)",
                  replacing: replacing)
        } catch { message = "That directory cannot be approved: \(String(describing: error))" }
    }

    private func chooseExecutable(replacing: LocalAuthorityScope? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let approval = try LocalExecutableApproval.verify(executable: url)
            begin(scope: .localExecutable(approval),
                  summary: "Local executable: \(approval.canonicalPath)\nDevice/inode: \(approval.device)/\(approval.inode)",
                  replacing: replacing)
        } catch { message = "That executable cannot be approved: \(String(describing: error))" }
    }

    private func reassociate(_ scope: LocalAuthorityScope) {
        switch scope {
        case .localRoot: chooseRoot(replacing: scope)
        case .externalVolume: chooseExternalVolume(replacing: scope)
        case .localExecutable: chooseExecutable(replacing: scope)
        case .localSocket(let socket):
            socketPath = socket.canonicalPath
            reviewSocket(replacing: scope)
        default: break
        }
    }

    private func localPathScopes(_ scopes: Set<LocalAuthorityScope>) -> [LocalAuthorityScope] {
        scopes.filter {
            if case .localRoot = $0 { return true }
            if case .externalVolume = $0 { return true }
            if case .localExecutable = $0 { return true }
            if case .localSocket = $0 { return true }
            return false
        }.sorted { scopeTitle($0) < scopeTitle($1) }
    }

    private func scopeTitle(_ scope: LocalAuthorityScope) -> String {
        switch scope {
        case .backgroundSignals: return "Background signals"
        case .notifications: return "Notifications"
        case .launchAtLogin: return "Launch at login"
        case .rescueApplication(let approval): return "App: \(approval.bundleIdentifier)"
        case .maintenanceNotifyOnly(let grant): return "Maintenance notice: \(grant.capabilityID.rawValue)"
        case .maintenanceCaches(let grant): return "Maintenance cache: \(grant.capabilityID.rawValue)"
        case .localRoot(let root): return root.canonicalPath
        case .externalVolume(let root): return "External volume: \(root.canonicalPath)"
        case .localExecutable(let executable): return executable.canonicalPath
        case .localSocket(let socket): return "Unix socket: \(socket.canonicalPath)"
        }
    }

    private func chooseExternalVolume(replacing: LocalAuthorityScope? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let approval = try LocalRootApproval.verifyExternalVolumeRoot(directory: url)
            begin(scope: .externalVolume(approval),
                  summary: "External volume root: \(approval.canonicalPath)\nVolume: \(approval.volumeID.uuidString)",
                  replacing: replacing)
        } catch { message = "That selection is not a live local volume root: \(String(describing: error))" }
    }

    private func reviewSocket(replacing: LocalAuthorityScope? = nil) {
        do {
            let approval = try LocalSocketApproval.verify(
                socket: URL(fileURLWithPath: socketPath))
            begin(scope: .localSocket(approval),
                  summary: "Local Unix socket: \(approval.canonicalPath)\nOwner: \(approval.ownerUID) · device/inode: \(approval.device)/\(approval.inode)\nReviewing this endpoint does not connect to it or start a daemon.",
                  replacing: replacing)
        } catch { message = "That local socket cannot be approved: \(String(describing: error))" }
    }
}

private struct PendingLocalConsent {
    let token: LocalAuthorityReviewToken
    let scope: LocalAuthorityScope
    let replacing: LocalAuthorityScope?
    let summary: String
}
