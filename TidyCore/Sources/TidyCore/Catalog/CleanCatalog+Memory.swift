import Foundation

extension CleanCatalog {
    /// RAM and swap, as first-class actions rather than a read-only gauge.
    ///
    /// Every item here is deep-tier and opt-in. Two reasons: none of them
    /// delete anything, so they don't belong in a tier framed around
    /// regeneratable files; and each has a real cost that the user should
    /// be choosing deliberately rather than inheriting from a disk cleanup.
    ///
    /// Targets are opaque identifiers, not paths, so `isFilesystemPath` is
    /// false throughout and `PathGuard` never sees them -- the same shape
    /// the simulator-deletion item uses for device UDIDs.
    static var memory: CleanCategory {
        var items: [CleanItem] = []

        items.append(CleanItem(
            id: "deep.memory.purge-inactive",
            title: "Purge inactive memory",
            tier: .deep,
            dangerNote: "Evicts cached file data the machine was about to reuse, so the next few minutes are slower",
            costNote: "Moves pages from inactive to free. Improves the number in Activity Monitor more reliably than it improves performance",
            declaredRoot: { env in env.homeDirectory },
            locate: { _ in
                [TargetPath(path: "purge", label: "Inactive memory", isFilesystemPath: false)]
            },
            action: .custom(.purgeInactiveMemory)
        ))

        items.append(CleanItem(
            id: "deep.memory.quit-approved-apps",
            title: "Quit applications you've approved for quitting",
            tier: .deep,
            dangerNote: "Asks each app to quit; an app with unsaved work can prompt or refuse",
            costNote: "The only memory action with an unambiguous benefit: an app's resident memory returns the moment it exits",
            declaredRoot: { env in env.homeDirectory },
            locate: { env in
                env.appsApprovedForQuit.map { name in
                    TargetPath(path: name, label: name, isFilesystemPath: false)
                }
            },
            action: .custom(.quitMemoryHog)
        ))

        items.append(CleanItem(
            id: "deep.memory.restart-for-swap",
            title: "Restart to reclaim swap",
            tier: .deep,
            dangerNote: "Restarts this Mac. Save your work first",
            costNote: "The only way to return swap: macOS grows swapfiles on demand and never shrinks them while booted",
            declaredRoot: { env in env.homeDirectory },
            locate: { env in
                // Ships off. Requires an explicit opt-in in Settings on top
                // of selecting the item, because a cleanup tool that can
                // reboot the machine as a side effect of a checkbox is not
                // something anyone should discover by accident.
                guard env.allowRestartToReclaimSwap else { return [] }
                return [TargetPath(path: "restart", label: "Restart this Mac", isFilesystemPath: false)]
            },
            action: .custom(.restartToReclaimSwap)
        ))

        return CleanCategory(id: "memory", title: "Memory & Swap", items: items)
    }
}
