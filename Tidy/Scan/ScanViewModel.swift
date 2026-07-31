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
    private let sizeScanner = SizeScanner()

    func runScan() async {
        phase = .running

        let home = NSHomeDirectory()
        let environment = ConfigStore.load().makeEnvironment(homeDirectory: home)

        let report = await ScanEngine.run(environment: environment, sizeScanner: sizeScanner)
        phase = .complete(report)
    }
}
