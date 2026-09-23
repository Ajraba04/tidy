import AppKit
import Foundation

/// Production app-lifetime owner for execution shutdown. The delegate never
/// claims that timeout means cancellation; Core's durable intent remains
/// unresolved and blocks the next launch until positive reconciliation.
@MainActor
final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    private weak var services: AppExecutionServices?
    private var terminationTask: Task<Void, Never>?

    func bind(services: AppExecutionServices) {
        self.services = services
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let services, services.hasActiveConfirmedExecution else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task { @MainActor [weak self, weak sender] in
            _ = await services.cancelAndDrainExecutionForTermination()
            sender?.reply(toApplicationShouldTerminate: true)
            self?.terminationTask = nil
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        services?.cancelConfirmedExecution()
    }
}
