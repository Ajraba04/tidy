import Foundation
import Darwin
import TidyCore
final class Counters: MonitorInstrumentation, @unchecked Sendable {
    private let lock = NSLock(); private var scheduled = 0; private var cancelled = 0
    func timerScheduled() { lock.lock(); scheduled += 1; lock.unlock() }
    func timerCancelled() { lock.lock(); cancelled += 1; lock.unlock() }
    func values() -> [Int] { lock.lock(); defer { lock.unlock() }; return [scheduled,cancelled] }
}
@main struct MonitorAudit {
    static func usage() -> (Double, UInt64, UInt64) {
        var r = rusage(); getrusage(RUSAGE_SELF, &r)
        let cpu = Double(r.ru_utime.tv_sec+r.ru_stime.tv_sec) + Double(r.ru_utime.tv_usec+r.ru_stime.tv_usec)/1e6
        var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size/MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in ptr.withMemoryRebound(to: integer_t.self, capacity:Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return (cpu, result == KERN_SUCCESS ? info.resident_size : 0, UInt64(r.ru_maxrss))
    }
    static func main() async throws {
        let counters = Counters()
        let monitor = SystemMonitor(configuration: .init(featureEnabled:true,backgroundEnabled:false,suppressHiddenSampling:false,visibleIntervalSeconds:5,hiddenIntervalSeconds:60,historyEnabled:false,historyHours:0),volumes:[URL(fileURLWithPath:"/private/tmp")],instrumentation:counters)
        let idleStart=usage(); let start=ContinuousClock.now
        for _ in 0..<6 { try await Task.sleep(for:.seconds(5)) }
        let idleEnd=usage()
        print("AUDIT hidden-off duration=\(start.duration(to:.now)) cpuSeconds=\(idleEnd.0-idleStart.0) rssBytes=\(idleEnd.1) timerCounts=\(counters.values()) timerRunning=\(await monitor.isTimerRunningForTesting())")
        await monitor.applyConfiguration(.init(featureEnabled:true,backgroundEnabled:true,suppressHiddenSampling:false,visibleIntervalSeconds:5,hiddenIntervalSeconds:60,historyEnabled:false,historyHours:0))
        try await Task.sleep(for:.seconds(5))
        let base=usage(); let timed=ContinuousClock.now
        for sample in 1...120 { try await Task.sleep(for:.seconds(5)); if sample % 12 == 0 { let u=usage(); print("AUDIT monitoring seconds=\(sample*5) cpuSeconds=\(u.0-base.0) rssBytes=\(u.1) peakRSSBytes=\(u.2)"); fflush(stdout) } }
        let end=usage(); let elapsed=timed.duration(to:.now); print("AUDIT monitoring completed duration=\(elapsed) cpuSeconds=\(end.0-base.0) rssBytes=\(end.1) timerCounts=\(counters.values())")
        await monitor.stop()
    }
}
