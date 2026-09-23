import AppKit
import Foundation
import TidyCore

final class ApplicationTerminator: GracefulApplicationTerminating, @unchecked Sendable {
    func requestGracefulTermination(of workload: WorkloadIdentity,
                                    timeoutSeconds: Int,
                                    authorization: GracefulTerminationAuthorization) async
        -> GracefulTerminationObservation {
        guard (5...60).contains(timeoutSeconds) else { return .unavailable }
        let accepted = await MainActor.run { () -> GracefulTerminationObservation? in
            guard let application = NSRunningApplication(processIdentifier: workload.pid) else {
                return .alreadyExited
            }
            guard Self.matches(application, workload: workload),
                  workload.matchesCurrentProcess(),
                  authorization.permitsTermination(of: workload) else {
                return .unavailable
            }
            return application.terminate() ? nil : .refused
        }
        if let accepted { return accepted }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        while clock.now < deadline {
            let exited = await MainActor.run { () -> Bool in
                guard let application = NSRunningApplication(
                    processIdentifier: workload.pid) else { return true }
                if application.isTerminated { return true }
                // A reused PID is not the reviewed instance. Observing that
                // replacement means the original instance has exited; never
                // send another request to the replacement.
                return !Self.matches(application, workload: workload)
                    || !workload.matchesCurrentProcess()
            }
            if exited { return .exited }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return .unavailable }
        }
        return .timedOut
    }

    @MainActor
    private static func matches(_ application: NSRunningApplication,
                                workload: WorkloadIdentity) -> Bool {
        guard application.processIdentifier == workload.pid,
              application.bundleIdentifier == workload.bundleIdentifier,
              let bundleURL = application.bundleURL else { return false }
        return bundleURL.standardizedFileURL == workload.bundleURL
    }
}

struct VisibleApplicationWorkload: Identifiable, Hashable {
    let workload: WorkloadIdentity
    let displayName: String
    var id: WorkloadIdentity { workload }
}

@MainActor
enum ApplicationWorkloadInventory {
    static func refresh() -> [VisibleApplicationWorkload] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard application.activationPolicy == .regular,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  !application.isTerminated,
                  let bundleURL = application.bundleURL,
                  let bundleIdentifier = application.bundleIdentifier,
                  let workload = try? WorkloadIdentity.capture(
                    bundleURL: bundleURL, bundleIdentifier: bundleIdentifier,
                    pid: application.processIdentifier) else { return nil }
            return VisibleApplicationWorkload(workload: workload,
                displayName: application.localizedName ?? bundleIdentifier)
        }
        .sorted {
            let order = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if order == .orderedSame { return $0.workload.pid < $1.workload.pid }
            return order == .orderedAscending
        }
    }

    static func recapture(_ workload: WorkloadIdentity) -> WorkloadIdentity? {
        guard let application = NSRunningApplication(processIdentifier: workload.pid),
              !application.isTerminated,
              application.bundleIdentifier == workload.bundleIdentifier,
              let bundleURL = application.bundleURL,
              bundleURL.standardizedFileURL == workload.bundleURL else { return nil }
        return try? WorkloadIdentity.capture(bundleURL: bundleURL,
            bundleIdentifier: workload.bundleIdentifier, pid: workload.pid)
    }
}
