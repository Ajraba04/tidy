import ServiceManagement
import Dispatch
import SwiftUI
import TidyCore

enum LoginItemStatus: String, Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LoginItemManaging: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor
final class SMLoginItemManager: LoginItemManaging {
    private let service: SMAppService

    init(service: SMAppService? = nil) {
        self.service = service ?? .mainApp
    }

    var status: LoginItemStatus {
        switch service.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
}

struct LaunchAtLoginView: View {
    private let authority: LocalAuthorityStore?
    private let inputSnapshot: LocalAuthoritySnapshot?
    private let manager: any LoginItemManaging
    private let onAuthorityChange: @MainActor (LocalAuthoritySnapshot) -> Void

    @State private var owner = LocalAuthorityOwner()
    @State private var currentSnapshot: LocalAuthoritySnapshot?
    @State private var pendingToken: LocalAuthorityReviewToken?
    @State private var actualStatus: LoginItemStatus = .unavailable
    @State private var message: String?
    @State private var busy = false

    init(authority: LocalAuthorityStore?, snapshot: LocalAuthoritySnapshot?,
         manager: any LoginItemManaging,
         onAuthorityChange: @escaping @MainActor (LocalAuthoritySnapshot) -> Void) {
        self.authority = authority
        inputSnapshot = snapshot
        self.manager = manager
        self.onAuthorityChange = onAuthorityChange
        _currentSnapshot = State(initialValue: snapshot)
    }

    var body: some View {
        GroupBox("Launch at login") {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusText).font(.caption)
                Text("Login launch starts Tidy only. It grants no scan, inventory, maintenance, rescue, or cleanup authority.")
                    .font(.caption2).foregroundStyle(.secondary)

                if let pendingToken {
                    Text("Review: allow this installation to ask macOS to register Tidy as a login item. macOS may still require approval in System Settings.")
                        .font(.caption)
                    HStack {
                        Button("Confirm and register") { confirmAndRegister(pendingToken) }
                        Button("Cancel", role: .cancel, action: cancelReview)
                    }
                } else if actualStatus == .enabled || hasLocalGrant {
                    Button("Disable and revoke launch at login", role: .destructive,
                           action: disable)
                        .disabled(busy)
                } else {
                    Button("Review launch at login…", action: beginReview)
                        .disabled(busy || authority == nil)
                }

                HStack {
                    Button("Refresh status", action: refreshStatus).disabled(busy)
                    if actualStatus == .requiresApproval {
                        Text("Approval is required in Login Items settings. Tidy will not retry automatically.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("launchAtLogin.status")
                }
            }
        }
        .onAppear(perform: refreshStatus)
        .onChange(of: inputSnapshot) { _, updated in
            guard currentSnapshot != updated else { return }
            cancelReview()
            currentSnapshot = updated
            message = "Local authority changed; any open login-item review was cancelled."
        }
        .onDisappear(perform: cancelReview)
    }

    private var hasLocalGrant: Bool {
        currentSnapshot?.permits(.launchAtLogin) == true
    }

    private var statusText: String {
        let system: String
        switch actualStatus {
        case .notRegistered: system = "Not registered with macOS"
        case .enabled: system = "Enabled by macOS"
        case .requiresApproval: system = "Waiting for approval in System Settings"
        case .unavailable: system = "Status unavailable"
        }
        return system + " · local grant " + (hasLocalGrant ? "approved" : "off")
    }

    private func refreshStatus() {
        actualStatus = manager.status
        if actualStatus != .enabled, hasLocalGrant {
            message = "The local grant exists, but macOS is not currently launching Tidy at login. No automatic registration was attempted."
        }
    }

    private func beginReview() {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                pendingToken = try await authority.beginReview(
                    scope: .launchAtLogin, owner: owner,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
            } catch { message = "Login-item review denied: \(String(describing: error))" }
            busy = false
        }
    }

    private func confirmAndRegister(_ token: LocalAuthorityReviewToken) {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            do {
                let snapshot = try await authority.confirm(token, owner: owner,
                    nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                currentSnapshot = snapshot
                onAuthorityChange(snapshot)
                pendingToken = nil
                do {
                    try manager.register()
                    actualStatus = manager.status
                    message = actualStatus == .enabled
                        ? "Launch at login is enabled."
                        : "Registration was requested; macOS reports \(actualStatus.rawValue). No automatic retry will run."
                } catch {
                    do {
                        let revoked = try await authority.revoke(.launchAtLogin)
                        currentSnapshot = revoked
                        onAuthorityChange(revoked)
                    } catch {
                        currentSnapshot = nil
                        onAuthorityChangeInvalidation()
                    }
                    actualStatus = manager.status
                    message = "Registration failed and local authority was denied: \(String(describing: error))"
                }
            } catch {
                message = "Local grant failed; registration was not attempted: \(String(describing: error))"
            }
            busy = false
        }
    }

    private func disable() {
        guard let authority else { return }
        busy = true; message = nil
        Task { @MainActor in
            if actualStatus == .enabled || actualStatus == .requiresApproval {
                do {
                    try manager.unregister()
                    actualStatus = manager.status
                } catch {
                    actualStatus = manager.status
                    message = "macOS did not unregister the login item; local authority was retained: \(String(describing: error))"
                    busy = false
                    return
                }
            } else if actualStatus == .unavailable {
                message = "macOS login-item status is unavailable, so Tidy retained local authority rather than claiming disablement."
                busy = false
                return
            }
            do {
                let snapshot = try await authority.revoke(.launchAtLogin)
                currentSnapshot = snapshot
                onAuthorityChange(snapshot)
                message = "Launch at login is disabled and its local grant was revoked."
            } catch {
                currentSnapshot = nil
                onAuthorityChangeInvalidation()
                message = "macOS disabled the login item, but the ledger could not publish revocation. Runtime authority remains fail-closed."
            }
            busy = false
        }
    }

    private func cancelReview() {
        guard let token = pendingToken else { return }
        pendingToken = nil
        guard let authority else { return }
        Task { try? await authority.cancel(token, owner: owner) }
    }

    /// The store update stream publishes nil on durability failure. This view
    /// cannot manufacture a replacement snapshot, so it clears local state and
    /// waits for the app-owned model to propagate that nil.
    private func onAuthorityChangeInvalidation() {
        message = "Local authority is unavailable."
    }
}
