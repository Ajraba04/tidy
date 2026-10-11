import SwiftUI
import TidyCore

struct ManualServiceReviewView: View {
    @Bindable var model: ManualServiceReviewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Manual producer operations").font(.title2.bold())
                    Spacer()
                    Button("Refresh Candidates") { model.refreshCandidates() }
                        .disabled(!model.canRefreshCandidates)
                        .accessibilityIdentifier("manualService.refresh")
                }
                Text("Refresh reads explicitly approved producer inventory. Review an exact candidate to see its scope and consequences.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.isRefreshing { ProgressView("Reading explicit candidate inventory…") }
                if !model.candidates.isEmpty {
                    GroupBox("Inventory candidates") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.candidates.indices, id: \.self) { index in
                                let binding = model.candidates[index]
                                Button(candidateTitle(binding)) { model.inspect(binding) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("manualService.candidate.\(index)")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let binding = model.candidate {
                    candidateDetails(binding)
                    GroupBox("Consequences") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(consequences(binding))
                            Toggle("Select this candidate for manual review", isOn: $model.isSelected)
                                .accessibilityIdentifier("manualService.selected")
                            Toggle("I understand the consequences shown above", isOn: $model.consequencesAcknowledged)
                                .accessibilityIdentifier("manualService.acknowledged")
                            Text("Every newly chosen candidate starts unselected. Execution requires confirmed current permissions and an accepted producer.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(model.isPreparing || model.isRefreshing || model.isExecuting)
                    if let reason = model.unavailableReason {
                        Label(reason, systemImage: "lock")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("manualService.unavailable")
                    }
                    HStack {
                        Button("Prepare Review") { model.prepareReview() }
                            .disabled(!model.canPrepareReview)
                            .accessibilityIdentifier("manualService.prepare")
                        if binding.executionUnavailableReason == nil {
                            Button("Execute") { model.execute() }
                                .disabled(!model.canExecute)
                                .accessibilityIdentifier("manualService.execute")
                        }
                        if model.reviewSummary != nil {
                            Button("Cancel Review", role: .cancel) { model.cancelReview() }
                                .accessibilityIdentifier("manualService.cancel")
                        }
                        Button("Dismiss") { model.dismiss() }
                            .accessibilityIdentifier("manualService.dismiss")
                    }
                    if model.isPreparing { ProgressView("Preparing a local review…") }
                    if model.isExecuting { ProgressView("Waiting for the app-owned operation…") }
                    if let summary = model.reviewSummary {
                        GroupBox("Prepared review") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Review: \(summary.reviewID.uuidString)").font(.caption.monospaced())
                                Text("A review expires within 60 seconds of preparation. Freshness and ownership are checked before use.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(binding.executionUnavailableReason == nil
                                    ? "Execution confirms current permissions and verifies the exact producer state."
                                    : "Current producer state still requires verification. Execution remains unavailable.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    ContentUnavailableView("No manual candidate selected", systemImage: "checklist",
                        description: Text("Choose an exact candidate from explicit producer inventory to inspect its identity and consequences."))
                }
                if let message = model.operationMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("manualService.status")
                }
            }.padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Manual producer operation review")
    }

    @ViewBuilder private func candidateDetails(_ binding: ManualServiceOperationBinding) -> some View {
        GroupBox("Exact candidate identity") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                detail("Operation", binding.adapter == .appleSimulatorShutdownV1 ? "Simulator shutdown" : "Stopped container removal")
                switch binding.object {
                case .simulator(let object):
                    detail("UDID", object.udid.uuidString)
                    detail("Runtime", object.runtimeIdentifier)
                    detail("Device type", object.deviceTypeIdentifier)
                    detail("Display name", object.name)
                    detail("Candidate state", object.state.rawValue)
                case .container(let object):
                    detail("Container ID", object.id)
                    detail("Display name", object.name)
                    detail("Candidate state", object.observedState)
                    detail("Image identity", object.imageID)
                    detail("Created", object.created)
                }
                switch binding.producer {
                case .appleSimulator(let producer):
                    detail("Resolver", producer.resolver.canonicalPath)
                    detail("simctl", producer.simctl.canonicalPath)
                    detail("Developer directory", producer.developerDirectory.canonicalPath)
                    detail("Device set", producer.deviceSet.canonicalPath)
                    detail("Xcode", "\(producer.xcodeVersion) (\(producer.xcodeBuild))")
                    detail("CoreSimulator", producer.coreSimulatorVersion)
                case .docker(let producer):
                    detail("Local socket", producer.socket.canonicalPath)
                    detail("Provider", producer.providerIdentifier)
                    detail("Daemon ID", producer.daemonID)
                    detail("Engine / API", "\(producer.version.engineVersion) / \(producer.version.apiVersion)")
                    detail("Connected peer executable", producer.peerExecutable.canonicalPath)
                    detail("Peer PID / UID", "\(producer.peerPID) / \(producer.peerUID)")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        Text("Names are display metadata. The exact identity and approved producer scope determine the target. This pane does not establish current native state from a description alone.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
        }
    }

    private func candidateTitle(_ binding: ManualServiceOperationBinding) -> String {
        switch binding.object {
        case .simulator(let value): return "Shutdown review · \(value.name) · \(value.udid.uuidString)"
        case .container(let value): return "Container removal review · \(value.id)"
        }
    }

    private func consequences(_ binding: ManualServiceOperationBinding) -> String {
        switch binding.object {
        case .simulator:
            return "Shutdown ends this exact simulator's running session. Unsaved in-simulator work may be lost. It does not delete the device, its installed apps or its stored data, and it makes no promise of reclaimed physical space."
        case .container(let value): return value.consequenceDescription
        }
    }
}
