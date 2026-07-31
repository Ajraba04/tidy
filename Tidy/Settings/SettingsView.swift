import SwiftUI
import TidyCore

struct SettingsView: View {
    @Environment(AppConfigStore.self) private var configStore

    var body: some View {
        @Bindable var configStore = configStore
        Form {
            CookieDomainsSection(domains: $configStore.config.keepCookieDomains)
            ProjectRootsSection(roots: $configStore.config.gitRoots)
            SimulatorApprovalSection(approvedForDeletion: $configStore.config.simulatorsApprovedForDeletion)
            ThresholdsSection(
                staleNodeModulesDays: $configStore.config.staleNodeModulesThresholdDays,
                transcriptAgeDays: $configStore.config.transcriptAgeThresholdDays
            )
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 520, idealHeight: 600)
        .navigationTitle("Settings")
    }
}

struct CookieDomainsSection: View {
    @Binding var domains: [String]
    @State private var newDomain = ""
    @State private var suggestions: [String] = []

    var body: some View {
        Section {
            ForEach(domains, id: \.self) { domain in
                Text(domain)
            }
            .onDelete { indices in domains.remove(atOffsets: indices) }

            HStack {
                TextField("example.com", text: $newDomain)
                    .onSubmit(addTypedDomain)
                Button("Add", action: addTypedDomain)
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !suggestions.isEmpty {
                DisclosureGroup("Suggestions from your Chrome cookies (\(suggestions.count))") {
                    ForEach(suggestions, id: \.self) { domain in
                        Button {
                            add(domain)
                            suggestions.removeAll { $0 == domain }
                        } label: {
                            Label(domain, systemImage: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Button("Suggest domains from Chrome…") {
                    let found = CookieDomainSuggester.suggestDomains()
                    suggestions = found.filter { !domains.contains($0) }
                }
            }
        } header: {
            Text("Cookie domains to keep")
        } footer: {
            Text("Chrome cookies for these domains (and their subdomains) survive Normal and Deep cleans. Empty means nothing is kept — Chrome cookie cleaning is skipped entirely until you add at least one.")
        }
    }

    private func addTypedDomain() {
        add(newDomain)
        newDomain = ""
    }

    private func add(_ domain: String) {
        let trimmed = domain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, !domains.contains(trimmed) else { return }
        domains.append(trimmed)
    }
}

struct ProjectRootsSection: View {
    @Binding var roots: [String]
    @State private var candidates: [GitRootDiscovery.Candidate] = []
    @State private var showingFolderPicker = false

    var body: some View {
        Section {
            ForEach(roots, id: \.self) { root in
                Text(PathDisplay.tilde(root))
            }
            .onDelete { indices in roots.remove(atOffsets: indices) }

            Button("Add Folder…") { showingFolderPicker = true }
                .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result, !roots.contains(url.path) {
                        roots.append(url.path)
                    }
                }

            if candidates.isEmpty {
                Button("Discover common project folders…") {
                    candidates = GitRootDiscovery.discoverCandidates().filter { !roots.contains($0.path) }
                }
            } else {
                ForEach(candidates, id: \.path) { candidate in
                    Button {
                        roots.append(candidate.path)
                        candidates.removeAll { $0.path == candidate.path }
                    } label: {
                        Label("\(PathDisplay.tilde(candidate.path)) (\(candidate.repositoryCount) repos)", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Project roots")
        } footer: {
            Text("Folders that contain your projects, e.g. ~/Developer. Used to find git repositories, stale node_modules, and build output directories to clean.")
        }
    }
}

struct SimulatorApprovalSection: View {
    @Binding var approvedForDeletion: [String]
    @State private var devices: [SimulatorDevice] = []
    @State private var loaded = false

    var body: some View {
        Section {
            if !loaded {
                Button("Load simulator devices…") {
                    Task { devices = await SimctlClient.listDevices() }
                    loaded = true
                }
            } else if devices.isEmpty {
                Text("No simulator devices found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices) { device in
                    Toggle(isOn: approvalBinding(for: device.name)) {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text(device.runtimeIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Simulator devices")
        } footer: {
            Text("Every device is kept by default. Check a device to allow Deep Clean to delete it. This never runs on its own — Deep Clean still shows a confirmation first.")
        }
    }

    private func approvalBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { approvedForDeletion.contains(name) },
            set: { isApproved in
                if isApproved {
                    if !approvedForDeletion.contains(name) { approvedForDeletion.append(name) }
                } else {
                    approvedForDeletion.removeAll { $0 == name }
                }
            }
        )
    }
}

struct ThresholdsSection: View {
    @Binding var staleNodeModulesDays: Int
    @Binding var transcriptAgeDays: Int

    var body: some View {
        Section("Thresholds") {
            Stepper("Stale node_modules after \(staleNodeModulesDays) days", value: $staleNodeModulesDays, in: 7...365, step: 1)
            Stepper("Old session transcripts after \(transcriptAgeDays) days", value: $transcriptAgeDays, in: 7...365, step: 1)
        }
    }
}
