import Foundation

/// The three things that genuinely move RAM and swap on macOS, and nothing
/// that doesn't.
///
/// Worth stating plainly, because "memory cleaner" is a category full of
/// software that pretends otherwise:
///
/// - **Swap cannot be shrunk while the machine is booted.** macOS grows
///   swapfiles on demand and never returns them until boot. There is no
///   API, no supported command, and no privilege level that changes this.
///   The only honest "free swap" action is a restart, so that is what
///   `restartToReclaimSwap` does -- it does not pretend to be anything else.
/// - **Purging inactive memory is real but usually not a win.** `purge(8)`
///   evicts the file-backed page cache, which moves pages from "inactive"
///   to "free". Those pages were caching data the machine was about to want
///   again, so the number in Activity Monitor improves while real
///   performance briefly gets worse. Offered, never on by default, and
///   labelled with that trade-off.
/// - **Quitting an application returns its resident memory immediately.**
///   The only mechanism here with an unambiguous benefit. Graceful quit
///   only, opt-in per application by name, never a signal.
public enum MemoryReclaimer: Sendable {
    public struct Outcome: Sendable, Equatable {
        public let succeeded: Bool
        /// RAM returned, measured before and after. Deliberately never
        /// added to a disk figure: they are different resources and a
        /// combined "freed" number would be a lie in both directions.
        public let reclaimedMemoryBytes: Int64
        public let message: String?

        public init(succeeded: Bool, reclaimedMemoryBytes: Int64, message: String?) {
            self.succeeded = succeeded
            self.reclaimedMemoryBytes = reclaimedMemoryBytes
            self.message = message
        }
    }

    /// Runs `/usr/sbin/purge`, measuring used memory either side so the
    /// reported figure is observed rather than claimed.
    public static func purgeInactiveMemory() async -> Outcome {
        guard let purgePath = ToolLocator.locate("purge") else {
            return Outcome(succeeded: false, reclaimedMemoryBytes: 0, message: "purge not found")
        }

        let before = MemoryStats.current().usedBytes
        let succeeded = await ProcessRunner.runDiscardingOutput(
            executableURL: URL(fileURLWithPath: purgePath),
            arguments: []
        )
        guard succeeded else {
            return Outcome(
                succeeded: false,
                reclaimedMemoryBytes: 0,
                message: "purge failed (it may require administrator rights on this system)"
            )
        }

        let after = MemoryStats.current().usedBytes
        let reclaimed = max(0, before - after)
        return Outcome(
            succeeded: true,
            reclaimedMemoryBytes: reclaimed,
            message: reclaimed == 0 ? "no inactive memory to purge" : nil
        )
    }

    /// Asks an application to quit, the way choosing Quit from its menu
    /// would: it can present unsaved-changes dialogs and refuse. Never
    /// sends a signal -- SIGKILL would return the same memory while losing
    /// the user's work, which is not a trade a cleanup tool gets to make.
    public static func quitApplication(named name: String) async -> Outcome {
        guard let osascriptPath = ToolLocator.locate("osascript") else {
            return Outcome(succeeded: false, reclaimedMemoryBytes: 0, message: "osascript not found")
        }

        let before = MemoryStats.current().usedBytes
        let script = "tell application \"\(name)\" to quit"
        let result = try? await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: osascriptPath),
            arguments: ["-e", script]
        )

        guard let result, result.succeeded else {
            return Outcome(
                succeeded: false,
                reclaimedMemoryBytes: 0,
                message: "\(name) did not quit (it may have a dialog open)"
            )
        }

        // Quitting is asynchronous; give the app a moment to actually exit
        // before measuring, or the delta reads as zero.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let after = MemoryStats.current().usedBytes
        return Outcome(
            succeeded: true,
            reclaimedMemoryBytes: max(0, before - after),
            message: "quit \(name)"
        )
    }

    /// Asks macOS to restart. This is the *only* mechanism that returns
    /// swap, which is why it exists as an action rather than as advice.
    ///
    /// Reports zero reclaimed bytes on purpose: the process does not
    /// survive to measure anything, and a number invented here could not be
    /// verified by the user or by the app.
    public static func restartToReclaimSwap() async -> Outcome {
        guard let osascriptPath = ToolLocator.locate("osascript") else {
            return Outcome(succeeded: false, reclaimedMemoryBytes: 0, message: "osascript not found")
        }

        let succeeded = await ProcessRunner.runDiscardingOutput(
            executableURL: URL(fileURLWithPath: osascriptPath),
            arguments: ["-e", "tell application \"System Events\" to restart"]
        )
        return Outcome(
            succeeded: succeeded,
            reclaimedMemoryBytes: 0,
            message: succeeded ? "restart requested" : "restart request was refused or cancelled"
        )
    }
}
