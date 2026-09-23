import Foundation

public extension LocalAuthoritySnapshot {
    var approvedRoots: [LocalRootApproval] {
        guard isCurrent else { return [] }
        return scopes.compactMap { if case .localRoot(let root) = $0 { return root }; return nil }
            .sorted { $0.canonicalPath < $1.canonicalPath }
    }

    var approvedExternalVolumes: [LocalRootApproval] {
        guard isCurrent else { return [] }
        return scopes.compactMap { if case .externalVolume(let root) = $0 { return root }; return nil }
            .sorted { $0.canonicalPath < $1.canonicalPath }
    }

    var approvedExecutables: [LocalExecutableApproval] {
        guard isCurrent else { return [] }
        return scopes.compactMap { if case .localExecutable(let tool) = $0 { return tool }; return nil }
            .sorted { $0.canonicalPath < $1.canonicalPath }
    }

    var approvedSockets: [LocalSocketApproval] {
        guard isCurrent else { return [] }
        return scopes.compactMap { if case .localSocket(let socket) = $0 { return socket }; return nil }
            .sorted { $0.canonicalPath < $1.canonicalPath }
    }

    /// This projection is read-only. Portable policy layers still cannot hold
    /// authority fields, and stale store-issued snapshots grant nothing.
    func policyValue(for id: SettingID) -> SettingValue? {
        guard isCurrent else { return nil }
        switch id.rawValue {
        case "monitor.backgroundEnabled": return .bool(permits(.backgroundSignals))
        case "notifications.enabled": return .bool(permits(.notifications))
        case "app.launchAtLogin": return .bool(permits(.launchAtLogin))
        case "scope.projectRoots": return .strings(approvedRoots.map(\.canonicalPath))
        case "scope.externalVolumes": return .strings(approvedExternalVolumes.map { $0.volumeID.uuidString })
        case "tools.approvedExecutables": return .strings(approvedExecutables.map(\.canonicalPath))
        case "docker.approvedEndpoints": return .strings(approvedSockets.map { "unix://" + $0.canonicalPath })
        case "rescue.approvedApplications":
            return .strings(scopes.compactMap {
                if case .rescueApplication(let value) = $0 { return value.bundleURL.path }
                return nil
            }.sorted())
        case "maintenance.mode":
            if scopes.contains(where: { if case .maintenanceCaches = $0 { return true }; return false }) {
                return .choice("authorizedCaches")
            }
            return .choice(scopes.contains(where: {
                if case .maintenanceNotifyOnly = $0 { return true }; return false
            }) ? "notifyOnly" : "off")
        default: return nil
        }
    }
}
