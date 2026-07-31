import Foundation

extension CleanCatalog {
    /// Section 2 of the shell script: browser caches and Chrome cookies.
    /// Every item here is gated on the relevant browser not running —
    /// checked at `locate` time, right before the plan is built, and the
    /// cookie cleaner re-checks again immediately before it opens a
    /// database. Safari cookies are never touched: its binarycookies store
    /// has no safe per-domain delete.
    static var browsers: CleanCategory {
        var items: [CleanItem] = []

        items.append(CleanItem(
            id: "normal.chrome.http-cache",
            title: "Chrome HTTP cache",
            tier: .normal,
            requires: .chrome,
            declaredRoot: { env in env.homeDirectory + "/Library/Caches/Google/Chrome" },
            locate: { env in
                guard !ChromiumCookieCleaner.isChromeRunning() else { return [] }
                let path = env.homeDirectory + "/Library/Caches/Google/Chrome"
                guard FileManager.default.fileExists(atPath: path) else { return [] }
                return [TargetPath(path: path, label: "Chrome HTTP cache")]
            },
            action: .deleteContents
        ))

        items.append(CleanItem(
            id: "normal.chrome.profile-caches",
            title: "Chrome per-profile caches",
            tier: .normal,
            requires: .chrome,
            declaredRoot: { env in ChromiumCookieCleaner.chromeRoot(homeDirectory: env.homeDirectory) },
            locate: { env in
                guard !ChromiumCookieCleaner.isChromeRunning() else { return [] }
                let fm = FileManager.default
                var targets: [TargetPath] = []
                for profile in ChromiumCookieCleaner.profiles(homeDirectory: env.homeDirectory) {
                    for subpath in Self.chromePerProfileCacheSubpaths {
                        let path = profile.path + "/" + subpath
                        if fm.fileExists(atPath: path) {
                            targets.append(TargetPath(path: path, label: "Chrome [\(profile.name)] \(subpath)"))
                        }
                    }
                }
                return targets
            },
            action: .deletePath
        ))

        items.append(CleanItem(
            id: "normal.chrome.cookies",
            title: "Chrome cookies (keeps your configured domains)",
            tier: .normal,
            requires: .chrome,
            dangerNote: "Signs you out of every site not in your keep-list",
            declaredRoot: { env in ChromiumCookieCleaner.chromeRoot(homeDirectory: env.homeDirectory) },
            locate: { env in
                guard !env.keepCookieDomains.isEmpty else { return [] }
                guard !ChromiumCookieCleaner.isChromeRunning(),
                      !ChromiumCookieCleaner.hasSingletonLock(homeDirectory: env.homeDirectory)
                else { return [] }
                return ChromiumCookieCleaner.profiles(homeDirectory: env.homeDirectory).map { profile in
                    TargetPath(path: profile.path, label: "Chrome [\(profile.name)] cookies")
                }
            },
            action: .custom(.chromeCookies)
        ))

        let safariItems: [(id: String, title: String, relativePath: String, declaredRootRelativePath: String, action: CleanAction)] = [
            (
                "normal.safari.cache", "Safari cache",
                "Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari",
                "Library/Containers/com.apple.Safari/Data/Library/Caches", .deleteContents
            ),
            (
                "normal.safari.webkit-cache", "Safari WebKit cache",
                "Library/Containers/com.apple.Safari/Data/Library/Caches/WebKit",
                "Library/Containers/com.apple.Safari/Data/Library/Caches", .deleteContents
            ),
            (
                "normal.safari.legacy-cache", "Safari cache (legacy path)",
                "Library/Caches/com.apple.Safari", "Library/Caches", .deleteContents
            ),
            (
                "normal.safari.webkit-global", "~/Library/WebKit",
                "Library/WebKit", "Library", .deleteContents
            ),
            (
                "normal.safari.favicon-cache", "Safari favicon cache",
                "Library/Containers/com.apple.Safari/Data/Library/Safari/Favicon Cache",
                "Library/Containers/com.apple.Safari/Data/Library/Safari", .deletePath
            ),
            (
                "normal.safari.touch-icons", "Safari touch-icon cache",
                "Library/Containers/com.apple.Safari/Data/Library/Safari/Touch Icons Cache",
                "Library/Containers/com.apple.Safari/Data/Library/Safari", .deletePath
            )
        ]

        for entry in safariItems {
            items.append(CleanItem(
                id: entry.id,
                title: entry.title,
                tier: .normal,
                declaredRoot: { env in env.homeDirectory + "/" + entry.declaredRootRelativePath },
                locate: { env in
                    guard !AppRunningCheck.isSafariRunning else { return [] }
                    let path = env.homeDirectory + "/" + entry.relativePath
                    guard PermissionBroker.canRead(path: (path as NSString).deletingLastPathComponent) else { return [] }
                    guard FileManager.default.fileExists(atPath: path) else { return [] }
                    return [TargetPath(path: path, label: entry.title)]
                },
                action: entry.action
            ))
        }

        return CleanCategory(id: "browsers", title: "Browsers", items: items)
    }

    static let chromePerProfileCacheSubpaths = [
        "Cache", "Code Cache", "GPUCache",
        "Service Worker/CacheStorage", "Service Worker/ScriptCache",
        "Application Cache", "DawnGraphiteCache", "DawnWebGPUCache",
        "Shared Dictionary/cache"
    ]
}
