import Foundation
import Observation
import TidyCore

/// Loads `TidyConfig` once at launch and saves it back to disk on every
/// change. Shared across Settings, Onboarding, and Custom via the SwiftUI
/// environment so they all read and write the same in-memory copy.
@Observable
@MainActor
final class AppConfigStore {
    var config: TidyConfig {
        didSet { ConfigStore.save(config) }
    }

    init() {
        self.config = ConfigStore.load()
    }
}
