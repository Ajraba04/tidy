import SwiftUI
import TidyCore

struct AssistanceView: View {
    @Bindable private var model: AssistanceModel
    private let loginItemManager: any LoginItemManaging

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
            TabView(selection: Binding(
                get: { model.selectedSection }, set: model.selectSection)) {
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
                .tag(AssistanceSection.consent)

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
                .tag(AssistanceSection.maintenance)

                VStack(spacing: 8) {
                    if let budgetID = model.reviewedBudgetID,
                       let volumeID = model.budgetVolumeID {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notification review: \(budgetID.rawValue)")
                                .font(.headline)
                            Text("Volume: \(volumeID.uuidString)")
                                .font(.caption).foregroundStyle(.secondary)
                            if !model.budgetVolumeIDs.contains(volumeID) {
                                Text("This volume has no current inventory. Measurements remain unavailable until you explicitly collect inventory.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("assistance.notificationBudgetReview")
                    }
                    if model.budgetVolumeIDs.count > 1
                        || (model.budgetVolumeIDs.count == 1
                            && model.budgetVolumeID != model.budgetVolumeIDs.first) {
                        Picker("Volume", selection: Binding(
                            get: { model.budgetVolumeID },
                            set: { value in
                                if let value { model.selectBudgetVolume(value) }
                            })) {
                                if let volumeID = model.budgetVolumeID,
                                   !model.budgetVolumeIDs.contains(volumeID) {
                                    Text("\(volumeID.uuidString) (inventory unavailable)")
                                        .tag(Optional(volumeID))
                                }
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
                .tag(AssistanceSection.budgets)

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
                    .tag(AssistanceSection.rescue)
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .onAppear { model.setVisible(true) }
        .onDisappear { model.setVisible(false) }
    }
}
