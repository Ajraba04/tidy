import SwiftUI
import TidyCore

private enum AssistanceTab: Hashable {
    case consent
    case maintenance
    case budgets
    case rescue
}

struct AssistanceView: View {
    @Bindable private var model: AssistanceModel
    private let loginItemManager: any LoginItemManaging
    @State private var tab: AssistanceTab = .consent
    @Environment(\.openWindow) private var openWindow

    @MainActor init(model: AssistanceModel,
         loginItemManager: (any LoginItemManaging)? = nil) {
        self.model = model
        self.loginItemManager = loginItemManager ?? SMLoginItemManager()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            TabView(selection: $tab) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        LocalConsentView(authority: model.authority,
                            snapshot: model.authoritySnapshot,
                            policy: model.effectivePolicy,
                            onAuthorityChange: model.acceptAuthoritySnapshot)
                        LaunchAtLoginView(authority: model.authority,
                            snapshot: model.authoritySnapshot,
                            manager: loginItemManager,
                            onAuthorityChange: model.acceptAuthoritySnapshot)
                    }
                    .padding(20)
                }
                .tabItem { Label("Consent", systemImage: "checkmark.shield") }
                .tag(AssistanceTab.consent)

                ScrollView {
                    MaintenanceSettingsView(authority: model.authority,
                        snapshot: model.authoritySnapshot,
                        policy: model.effectivePolicy,
                        policyRevision: model.policyRevision,
                        ruleStatuses: model.maintenanceStatuses,
                        onAuthorityChange: model.acceptAuthoritySnapshot)
                        .padding(20)
                }
                .tabItem { Label("Maintenance", systemImage: "wrench.and.screwdriver") }
                .tag(AssistanceTab.maintenance)

                VStack(spacing: 8) {
                    if model.budgetVolumeIDs.count > 1 {
                        Picker("Volume", selection: Binding(
                            get: { model.budgetVolumeID },
                            set: { value in
                                if let value { model.selectBudgetVolume(value) }
                            })) {
                                ForEach(model.budgetVolumeIDs, id: \.self) { volumeID in
                                    Text(volumeID.uuidString).tag(Optional(volumeID))
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.horizontal, 20)
                    }
                    if model.notificationBroker == nil {
                        Button("Prepare notification controls") {
                            model.prepareNotificationControls()
                        }
                        .help("Loads private deduplication state. This does not request macOS permission.")
                    }
                    BudgetsView(authority: model.authority,
                        snapshot: model.authoritySnapshot,
                        policy: model.effectivePolicy,
                        volumeID: model.budgetVolumeID,
                        measurements: model.budgetMeasurements,
                        broker: model.notificationBroker,
                        onAuthorityChange: model.acceptAuthoritySnapshot)
                }
                .tabItem { Label("Budgets", systemImage: "gauge.with.dots.needle.50percent") }
                .tag(AssistanceTab.budgets)

                RescueView(authority: model.authority,
                    snapshot: model.authoritySnapshot,
                    policy: model.effectivePolicy,
                    policyRevision: model.policyRevision,
                    livePolicy: { [weak model] in
                        RescueLivePolicy(revision: model?.policyRevision ?? 0,
                                         policy: model?.effectivePolicy)
                    },
                    observeAvailableBytes: { [weak model] in
                        guard let model else { return nil }
                        return await MainActor.run { model.availableMemoryBytes }
                    },
                    onAuthorityChange: model.acceptAuthoritySnapshot)
                    .tabItem { Label("Rescue", systemImage: "lifepreserver") }
                    .tag(AssistanceTab.rescue)
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .onAppear { model.setVisible(true) }
        .onDisappear { model.setVisible(false) }
        .onChange(of: model.requestedNavigation) { _, navigation in
            guard let navigation else { return }
            switch navigation {
            case .headroomReview:
                openWindow(id: WindowID.headroom)
            case .budgetReview:
                tab = .budgets
            case .maintenance(.reviewCache):
                openWindow(id: WindowID.developer)
            }
            model.consumeNavigation()
        }
    }
}
