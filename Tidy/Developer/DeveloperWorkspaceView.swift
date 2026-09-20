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
        List(model.snapshot?.inventory.projects.records ?? [], id: \.id) { project in
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: project.canonicalRoot).lastPathComponent)
                    .font(.headline)
                Text(project.canonicalRoot).font(.caption).textSelection(.enabled)
                Text("\(project.activity.rawValue) · "
                    + (project.toolchains.map(\.rawValue).sorted().joined(separator: ", ")
                        .nonempty ?? "toolchain unknown"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .overlay { if model.snapshot?.inventory.projects.records.isEmpty != false {
            ContentUnavailableView("No project inventory", systemImage: "folder.badge.questionmark",
                description: Text("Choose Refresh Inventory to scan approved project roots."))
        }}
    }

    private var ecosystemsTab: some View {
        List(model.snapshot?.inventory.entries ?? [], id: \.record.id) { entry in
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.record.kind).font(.headline)
                Text(entry.record.adapterID + " · " + entry.record.activity.rawValue)
                    .font(.caption)
                Text(entry.record.reason).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .overlay { if model.snapshot?.inventory.entries.isEmpty != false {
            ContentUnavailableView("No ecosystem inventory", systemImage: "shippingbox",
                description: Text("Disabled ecosystems and unapproved tools are not queried."))
        }}
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
        .overlay { if model.snapshot?.buildPrep.rows.isEmpty != false {
            ContentUnavailableView("No Build Prep plan", systemImage: "hammer",
                description: Text("Inventory-only and manual-risk resources never become executable Build Prep actions."))
        }}
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
