import SwiftUI
import TidyCore

@main
@MainActor
struct TestHostApp: App {
    var body: some Scene {
        WindowGroup("Tidy: Manual Review Fixtures") {
            GeometryReader { geometry in
                FixtureChooser(observedContentSize: geometry.size)
            }
            .frame(width: 620, height: 620)
        }
        .defaultSize(width: 620, height: 620)
        .windowResizability(.contentSize)
    }
}

private enum FixtureSurface: String, CaseIterable, Identifiable {
    case safe = "Safe", normal = "Normal", deep = "Deep", custom = "Custom"
    case settings = "Settings"
    var id: String { rawValue }
    var cleanupTier: Tier? {
        switch self {
        case .safe: .safe
        case .normal: .normal
        case .deep, .custom: .deep
        case .settings: nil
        }
    }
}

@MainActor
private enum ReviewFixtures {
    static let marker = "TIDY_MANUAL_FIXTURE_HOST_ONLY"
    static let presets = [
        CustomPreset(name: "Fixture: unavailable + unknown IDs", itemIDs: [
            "safe.tool.npm-cache-clean", "deep.memory.purge-inactive",
            "deep.simulator.erase-all", "unknown.preset.id",
        ])
    ]
    static func plan(for surface: FixtureSurface) -> CleanPlan {
        guard let tier = surface.cleanupTier else {
            return CleanPlan(tier: .safe, plannedItems: [],
                             generatedAt: Date(timeIntervalSince1970: 0))
        }
        var rows = CleanCatalog.allItems.filter { $0.tier <= tier }.map { item -> PlannedItem in
            let status: ReviewStatus
            let reason: String
            if case .unavailable(let tombstoneReason) = item.action {
                status = .unavailable
                reason = tombstoneReason
            } else {
                switch item.id {
                case "safe.cache.swiftpm-cache":
                    status = .noWork
                    reason = "No matching path exists."
                case "safe.cache.swiftpm-clones":
                    status = .blocked
                    reason = "One or more targets failed path protection checks."
                case "safe.cache.pip-cache":
                    status = .unavailable
                    reason = "Required toolchain is not available."
                default:
                    status = .unavailable
                    reason = CapabilityRegistry.quarantineReason
                }
            }
            return PlannedItem(
                id: item.id, title: item.title, tier: item.tier,
                dangerNote: item.dangerNote, costNote: item.costNote,
                targets: [], estimatedBytes: 0, action: item.action,
                review: ActionDescriptor(
                    id: item.id, status: status, reason: reason,
                    requiresPerRunOptIn: item.action.requiresPerRunOptIn)
            )
        }
        if surface == .custom {
            let reason = "Fixture-only uncategorized row; no operation exists."
            rows.append(PlannedItem(
                id: "fixture.presentation.other", title: "Fixture: uncategorized unavailable row", tier: .deep,
                dangerNote: "Fixture warning: no change will run.",
                costNote: "Fixture cost note: no savings have been measured.",
                targets: [], estimatedBytes: 0, action: .unavailable(reason: reason),
                review: ActionDescriptor(id: "fixture.presentation.other", status: .unavailable,
                    reason: reason, requiresPerRunOptIn: false)
            ))
        }
        return CleanPlan(tier: tier, plannedItems: rows, generatedAt: Date(timeIntervalSince1970: 0))
    }

    static let settingsRows = SettingsSurfaceModel.fixtureRows(bundle: .main)
}

@MainActor
private struct FixtureChooser: View {
    let observedContentSize: CGSize
    @State private var surface: FixtureSurface = .safe
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual fixtures: no discovery, persistence, settings write or cleanup.")
                .font(.headline)
            Text("Descriptive data, not findings about this Mac. All actions are unavailable, blocked or no-work.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Review surface", selection: $surface) {
                ForEach(FixtureSurface.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.segmented)
            if surface == .settings {
                SettingsFixtureSurface()
            } else {
                FixtureReviewSurface(surface: surface).id(surface)
            }
            Text("\(ReviewFixtures.marker) · \(Int(observedContentSize.width.rounded())) × \(Int(observedContentSize.height.rounded())) pt")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 620, minHeight: 620)
    }
}

@MainActor
private struct FixtureReviewSurface: View {
    let surface: FixtureSurface
    @State private var selection: PlanSelectionModel
    init(surface: FixtureSurface) {
        self.surface = surface
        _selection = State(initialValue: PlanSelectionModel(
            plan: ReviewFixtures.plan(for: surface), selectDefaults: surface != .custom))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(surface.rawValue): \(selection.value.reviewItems.count) fixture rows · \(selection.value.selectedCount) selected · \(ByteFormat.human(selection.value.selectedEstimatedBytes)) selected")
                .font(.caption).monospacedDigit()
            if surface == .custom {
                DisclosureGroup("Fixture input preset IDs (immutable)") {
                    Text(ReviewFixtures.presets[0].itemIDs.sorted().joined(separator: "\n"))
                        .font(.caption).textSelection(.enabled)
                }
                CustomPlanView(selection: selection, presets: ReviewFixtures.presets,
                               onSavePreset: { _ in }, onConfirm: {})
            } else {
                CleanPlanView(selection: selection, onConfirm: {})
            }
        }
    }
}

@MainActor
private struct SettingsFixtureSurface: View {
    @State private var dark = false
    @State private var compactWidth = false
    @State private var accessibilityText = false
    @State private var submissions = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Scheme", selection: $dark) {
                    Text("Light").tag(false); Text("Dark").tag(true)
                }.accessibilityIdentifier("fixture.settings.scheme")
                Picker("Width", selection: $compactWidth) {
                    Text("620").tag(false); Text("480").tag(true)
                }.accessibilityIdentifier("fixture.settings.width")
                Picker("Text size", selection: $accessibilityText) {
                    Text("Default").tag(false); Text("Accessibility 3").tag(true)
                }.accessibilityIdentifier("fixture.settings.textSize")
            }
            Text("Fixture submissions: \(submissions)")
                .accessibilityIdentifier("fixture.settings.submissions")
            RegistrySettingsSurface(rows: ReviewFixtures.settingsRows) { _, _ in
                submissions += 1
            }
            .frame(width: compactWidth ? 480 : 620)
            .environment(\.dynamicTypeSize, accessibilityText ? .accessibility3 : .large)
            .preferredColorScheme(dark ? .dark : .light)
            .accessibilityIdentifier("fixture.settings.surface")
        }
    }
}
