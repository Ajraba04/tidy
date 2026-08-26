import Foundation
import Observation
import TidyCore

@Observable @MainActor
final class AppConfigStore {
    var config: TidyConfig {
        didSet { bridge.submit(config: config) }
    }
    private let bridge: ExecutionPolicyBridge
    init(config: TidyConfig, bridge: ExecutionPolicyBridge) {
        self.config = config
        self.bridge = bridge
    }
}
