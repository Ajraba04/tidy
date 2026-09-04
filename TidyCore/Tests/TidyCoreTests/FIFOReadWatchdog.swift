import Foundation
import Darwin
import Dispatch

/// Bounds a pre-fix blocking FIFO open without cancelling work or deleting an active fixture.
final class FIFOReadWatchdog {
    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        func markFired() { lock.lock(); fired = true; lock.unlock() }
        func didFire() -> Bool { lock.lock(); defer { lock.unlock() }; return fired }
    }

    private let completed = DispatchSemaphore(value: 0)
    private let drained = DispatchSemaphore(value: 0)
    private let outcome = Outcome()
    private let worker: Thread

    init(fifo: URL) throws {
        // A reader alone does not satisfy a blocking read-only open's need for a writer.
        let reader = open(fifo.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard reader >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        // Prove rescue can open a writer while this exact reader stays alive. Close it
        // before admission starts, leaving no writer to mask the production defect.
        let probe = open(fifo.path, O_WRONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard probe >= 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(reader)
            throw error
        }
        close(probe)
        let completed = self.completed
        let drained = self.drained
        let outcome = self.outcome
        let path = fifo.path
        worker = Thread {
            var writer: Int32 = -1
            if completed.wait(timeout: .now() + .seconds(5)) == .timedOut {
                outcome.markFired()
                writer = open(path, O_WRONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                guard writer >= 0 else {
                    fatalError("FIFO rescue open failed (errno \(errno)); retaining scratch containing \(path) because active I/O may still be in progress")
                }
                // Keep the actual writer FD alive until admission has really returned.
                completed.wait()
            }
            if writer >= 0 { close(writer) }
            close(reader) // Ownership transferred to this thread after successful setup.
            drained.signal()
        }
        worker.start()
    }

    /// Must run immediately after admission, before any throwing assertion or scratch cleanup.
    func finishAndDrain() -> Bool {
        completed.signal()
        drained.wait()
        // Thread has closed every FD; also wait for its closure to return completely.
        while !worker.isFinished { Thread.sleep(forTimeInterval: 0.001) }
        return outcome.didFire()
    }
}
