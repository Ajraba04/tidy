import SwiftUI
import TidyCore

struct DeveloperWorkspaceView: View {
    @Bindable private var model: DeveloperWorkspaceModel
    private let localAuthority: LocalAuthoritySnapshot?
    private let policy: EffectivePolicy?

    init(model: DeveloperWorkspaceModel, localAuthority: LocalAuthoritySnapshot?,
         policy: EffectivePolicy?) {
        self.model = model
        self.localAuthority = localAuthority
        self.policy = policy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Developer Workspace").font(.title2.bold())
                Spacer()
                if model.isScanning {
                    Button("Cancel") { model.cancel() }
                } else {
                    Button("Refresh Inventory") {
                        model.scan(localAuthority: localAuthority)
                    }
                    .disabled(policy?.allowedFeatures.contains("projects") != true)
                }
            }
            Text("Tool-backed inventory runs only when the executable and local socket have explicit local approval. Refresh uses fixed read-only probes and never runs project scripts.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            if let message = model.projectActionMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            TabView {
                projectsTab.tabItem { Text("Projects") }
                ecosystemsTab.tabItem { Text("Ecosystems") }
                buildPrepTab.tabItem { Text("Build Prep") }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 480)
    }

    private var projectsTab: some View {
        List {
            Section("Project protection") {
                if !model.projectControlsEnabled {
                    Text("Project controls are disabled by the acknowledged policy.")
                        .foregroundStyle(.secondary)
                }
                if model.projectSettingsWritePending {
                    Text("A settings change is pending.")
                        .foregroundStyle(.secondary)
                }
                if let current = model.globalCurrentProjectID {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.projectDisplayName(current))
                            Text("Global current project").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Clear Current") { model.clearGlobalCurrentProject() }
                            .disabled(!model.canEditProjectSettings)
                    }
                }
                if model.activeProfileOverridesCurrentProject {
                    if let profileCurrent = model.activeProfileCurrentProjectID {
                        Text(profileCurrent == model.globalCurrentProjectID
                            ? "The active profile also selects this global current project."
                            : "The active profile selects \(model.projectDisplayName(profileCurrent)) as current.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("The active profile clears the current-project selection.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(model.globalPinnedProjectIDs.sorted(), id: \.self) { id in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.projectDisplayName(id))
                            Text(model.isProfilePinned(id)
                                ? "Pinned globally and by the active profile"
                                : "Pinned globally")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove Global Pin") { model.unpinGlobally(id) }
                            .disabled(!model.canEditProjectSettings)
                    }
                }
                ForEach(model.profileOnlyPinnedProjectIDs.sorted(), id: \.self) { id in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.projectDisplayName(id))
                        Text("Pinned by the active profile; edit the profile to remove it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.globalPinnedProjectIDs.isEmpty,
                   model.profilePinnedProjectIDs.isEmpty,
                   model.globalCurrentProjectID == nil,
                   model.effectiveCurrentProjectID == nil {
                    Text("No project protection is configured.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Discovered projects") {
                ForEach(model.snapshot?.inventory.projects.records ?? [], id: \.id) { project in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(URL(fileURLWithPath: project.canonicalRoot).lastPathComponent)
                            .font(.headline)
                        Text(project.canonicalRoot).font(.caption).textSelection(.enabled)
                        Text("\(project.activity.rawValue) · "
                            + (project.toolchains.map(\.rawValue).sorted().joined(separator: ", ")
                                .nonempty ?? "toolchain unknown"))
                            .font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Button("Reveal in Finder") { model.revealProject(project.id) }
                            if model.isGloballyPinned(project.id) {
                                Button("Remove Global Pin") { model.unpinGlobally(project.id) }
                                    .disabled(!model.canEditProjectSettings)
                            } else if model.isProfilePinned(project.id) {
                                Text("Pinned by active profile")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("Pin Globally") { model.pinGlobally(project.id) }
                                    .disabled(!model.canEditProjectSettings)
                            }
                            Button("Set Global Current") {
                                model.setGlobalCurrentProject(project.id)
                            }
                            .disabled(!model.canEditProjectSettings
                                || model.globalCurrentProjectID == project.id)
                        }
                    }
                }
                if model.snapshot?.inventory.projects.records.isEmpty != false {
                    Text("Choose Refresh Inventory to scan approved project roots.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var ecosystemsTab: some View {
        List {
            ForEach(model.snapshot?.inventory.entries ?? [], id: \.record.id) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.record.kind).font(.headline)
                    Text(entry.record.adapterID + " · " + entry.record.activity.rawValue)
                        .font(.caption)
                    if case .filesystem(let file) = entry.record.resource {
                        Text(file.canonicalPath).font(.caption).textSelection(.enabled)
                        Text("Allocation: " + (entry.record.allocatedBytes.map {
                            ByteFormat.human($0)
                        } ?? "unknown or shared"))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("Volume: \(file.volumeID.uuidString) · confidence: "
                            + entry.record.confidence.rawValue)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(entry.record.reason).font(.caption2).foregroundStyle(.secondary)
                    if case .filesystem = entry.record.resource {
                        Button("Reveal in Finder") {
                            model.revealInventoryEntry(entry.record.id)
                        }
                    }
                }
            }
            if model.snapshot?.inventory.entries.isEmpty != false {
                Text("Disabled ecosystems and unapproved tools are not queried.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var buildPrepTab: some View {
        List {
            Section("Headroom target") {
                Text(headroomStatus)
                if let plan = model.snapshot?.headroomPlan {
                    Text("Target: \(ByteFormat.human(plan.targetBytes)); strictly available: "
                        + "\(plan.availableBytes.map { ByteFormat.human($0) } ?? "unavailable"); "
                        + "deficit: \(plan.deficitBytes.map { ByteFormat.human($0) } ?? "unavailable").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Reviewed selection: \(ByteFormat.human(plan.selectedBytes)) across "
                        + "\(plan.selected.count) item(s).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Section("Candidates") {
                if model.snapshot?.buildPrep.rows.isEmpty != false {
                    Text("No ranked candidates are available from the current inventory.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.snapshot?.buildPrep.rows ?? [], id: \.candidate.record.id) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(row.candidate.record.kind).font(.headline)
                                Spacer()
                                Text(row.eligible ? "Eligible" : "Unavailable")
                                    .foregroundStyle(row.eligible ? .primary : .secondary)
                            }
                            Text(row.reason).font(.caption).foregroundStyle(.secondary)
                            if model.snapshot?.headroomPlan?.selected.contains(where: {
                                $0.candidate.record.id == row.candidate.record.id
                            }) == true {
                                Button("Remove from plan") {
                                    model.removeFromBuildPrep(row.candidate.record.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var headroomStatus: String {
        if let reason = model.snapshot?.headroomUnavailableReason { return reason }
        guard let plan = model.snapshot?.headroomPlan else {
            return "Choose Refresh Inventory to measure strict available capacity and prepare a plan."
        }
        switch plan.status {
        case .targetMet: return "The configured headroom target is currently met."
        case .ready: return "The reviewed selection covers the current deficit."
        case .insufficient: return "The available reviewed selection does not cover the deficit."
        case .unavailable(let reason): return reason
        }
    }
}

private extension String {
    var nonempty: String? { isEmpty ? nil : self }
}
