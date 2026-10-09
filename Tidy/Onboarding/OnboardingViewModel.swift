import Foundation
import Observation
import TidyCore

@Observable
@MainActor
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case welcome
        case tools
        case projectRoots
        case cookieDomains
        case simulators
        case finish

        var title: String {
            switch self {
            case .welcome: return "Welcome to Tidy"
            case .tools: return "Detected Tools"
            case .projectRoots: return "Project Roots"
            case .cookieDomains: return "Cookie Domains"
            case .simulators: return "Simulator Devices"
            case .finish: return "All Set"
            }
        }
    }

    private(set) var step: Step = .welcome
    let detectedTools: Set<ToolchainID>

    init(detectedTools: Set<ToolchainID>) {
        self.detectedTools = detectedTools
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }
}
