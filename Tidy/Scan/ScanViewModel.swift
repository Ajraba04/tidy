import Foundation
import Observation
import TidyCore

@Observable
@MainActor
final class ScanViewModel {
    enum Phase {
        case idle
        case running
        case complete(ScanReport)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private let services: AppExecutionServices

    init(services: AppExecutionServices) {
        self.services = services
    }

    func runScan() async {
        phase = .running
        let environment = services.configStore.config.makePolicyEnvironment(
            homeDirectory: services.paths.home.path, detectedTools: [])
        let report = await ScanEngine.run(environment: environment)
        phase = .complete(report)
    }
}
