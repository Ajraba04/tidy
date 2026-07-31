import SwiftUI
import TidyCore

struct OnboardingView: View {
    @Environment(AppConfigStore.self) private var configStore
    @Environment(\.dismiss) private var dismiss
    @State private var model = OnboardingViewModel()

    var body: some View {
        @Bindable var configStore = configStore
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case .welcome:
                    welcomeStep
                case .tools:
                    toolsStep
                case .projectRoots:
                    Form { ProjectRootsSection(roots: $configStore.config.gitRoots) }
                        .formStyle(.grouped)
                case .cookieDomains:
                    Form { CookieDomainsSection(domains: $configStore.config.keepCookieDomains) }
                        .formStyle(.grouped)
                case .simulators:
                    Form { SimulatorApprovalSection(approvedForDeletion: $configStore.config.simulatorsApprovedForDeletion) }
                        .formStyle(.grouped)
                case .finish:
                    finishStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                if model.step != .welcome {
                    Button("Back") { model.goBack() }
                }
                Spacer()
                Text("\(model.step.rawValue + 1) of \(OnboardingViewModel.Step.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.step == .finish {
                    Button("Done") {
                        configStore.config.hasCompletedOnboarding = true
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { model.advance() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 480, idealHeight: 560)
        .onAppear { model.start() }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome to Tidy")
                .font(.title.bold())
            Text("Tidy reclaims disk space and memory: caches, browser data, Xcode and simulator files, and more. Nothing is ever deleted without a plan you review and confirm first, and Tidy makes zero network calls, ever.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .padding()
    }

    private var toolsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detected on this Mac")
                .font(.headline)
            Text("Tidy only shows cleanup items for tools it finds installed.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ToolchainID.allCases.filter { model.detectedTools.contains($0) }, id: \.self) { tool in
                        Label(tool.displayName, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding()
    }

    private var finishStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("You're all set")
                .font(.title.bold())
            Text("Change any of this later from Settings. Every clean still shows you exactly what it will do before anything is deleted.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .padding()
    }
}
