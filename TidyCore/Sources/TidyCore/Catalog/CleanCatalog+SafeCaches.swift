extension CleanCatalog {
    /// Section 1 of the shell script: regeneratable developer tool and
    /// system caches, package-manager cache-clean commands, logs, and a
    /// safe slice of Gradle's cache. Every one of these rebuilds itself on
    /// next use.
    static var safeCaches: CleanCategory {
        let appCacheNames: [(id: String, folder: String, requires: ToolchainID?)] = [
            ("puccinialin", "puccinialin", nil),
            ("swiftpm-cache", "org.swift.swiftpm", nil),
            ("pip-cache", "pip", .pip),
            ("node-gyp", "node-gyp", .node),
            ("deno-cache", "deno", .deno),
            ("playwright-mcp-cache", "ms-playwright-mcp", .playwright),
            ("homebrew-cache", "Homebrew", .homebrew),
            ("xcode-cache", "com.apple.dt.Xcode", .xcode),
            ("itmstransporter-cache", "com.apple.amp.itmstransporter", .xcode),
            ("typescript-cache", "typescript", nil),
            ("electron-cache", "electron", nil),
            ("electron-builder-cache", "electron-builder", nil),
            ("yarn-cache", "Yarn", .yarn),
            ("go-build-cache", "go-build", .go),
            ("jetbrains-cache", "JetBrains", .jetbrains)
        ]

        let appCacheItems = appCacheNames.map { entry in
            fixedPathItem(
                id: "safe.cache.\(entry.id)",
                title: "~/Library/Caches/\(entry.folder)",
                tier: .safe,
                requires: entry.requires,
                relativePath: "Library/Caches/\(entry.folder)",
                declaredRootRelativePath: "Library/Caches"
            )
        }

        let miscCacheItems = [
            fixedPathItem(
                id: "safe.cache.swiftpm-clones",
                title: "~/Library/org.swift.swiftpm (SwiftPM clones)",
                tier: .safe,
                relativePath: "Library/org.swift.swiftpm",
                declaredRootRelativePath: "Library"
            ),
            fixedPathItem(
                id: "safe.cache.helpd",
                title: "~/Library/Caches/com.apple.helpd",
                tier: .safe,
                relativePath: "Library/Caches/com.apple.helpd",
                declaredRootRelativePath: "Library/Caches"
            ),
            fixedPathItem(
                id: "safe.cache.perplexity",
                title: "Perplexity cache",
                tier: .safe,
                relativePath: "Library/Caches/ai.perplexity.macv3",
                declaredRootRelativePath: "Library/Caches"
            ),
            fixedPathItem(
                id: "safe.cache.claude-desktop-cache",
                title: "Claude Desktop/Cache",
                tier: .safe,
                relativePath: "Library/Application Support/Claude/Cache",
                declaredRootRelativePath: "Library/Application Support/Claude"
            ),
            fixedPathItem(
                id: "safe.cache.claude-desktop-code-cache",
                title: "Claude Desktop/Code Cache",
                tier: .safe,
                relativePath: "Library/Application Support/Claude/Code Cache",
                declaredRootRelativePath: "Library/Application Support/Claude"
            ),
            fixedPathItem(
                id: "safe.cache.claude-desktop-gpu-cache",
                title: "Claude Desktop/GPUCache",
                tier: .safe,
                relativePath: "Library/Application Support/Claude/GPUCache",
                declaredRootRelativePath: "Library/Application Support/Claude"
            ),
            fixedPathItem(
                id: "safe.cache.npm-cacache",
                title: "~/.npm/_cacache",
                tier: .safe,
                requires: .npm,
                relativePath: ".npm/_cacache",
                declaredRootRelativePath: ".npm"
            ),
            fixedPathItem(
                id: "safe.cache.uv-dir",
                title: "~/.cache/uv",
                tier: .safe,
                requires: .uv,
                relativePath: ".cache/uv",
                declaredRootRelativePath: ".cache"
            ),
            fixedPathItem(
                id: "safe.cache.puppeteer",
                title: "~/.cache/puppeteer",
                tier: .safe,
                relativePath: ".cache/puppeteer",
                declaredRootRelativePath: ".cache"
            ),
            fixedPathItem(
                id: "safe.cache.bun-install-cache",
                title: "~/.bun install cache",
                tier: .safe,
                requires: .bun,
                relativePath: ".bun/install/cache",
                declaredRootRelativePath: ".bun"
            ),
            fixedPathItem(
                id: "safe.cache.mcp-repos",
                title: "~/.claude/mcp-repos (re-cloned on demand)",
                tier: .safe,
                relativePath: ".claude/mcp-repos",
                declaredRootRelativePath: ".claude"
            )
        ]

        let logItems: [(id: String, folder: String, requires: ToolchainID?)] = [
            ("claude", "Claude", nil),
            ("core-simulator", "CoreSimulator", .xcode),
            ("google", "Google", nil),
            ("diagnostic-reports", "DiagnosticReports", nil),
            ("creative-cloud", "CreativeCloud", nil),
            ("ngl", "NGL", nil),
            ("content-delivery", "ContentDelivery", nil)
        ]

        let logCacheItems = logItems.map { entry in
            fixedPathItem(
                id: "safe.logs.\(entry.id)",
                title: "~/Library/Logs/\(entry.folder)",
                tier: .safe,
                requires: entry.requires,
                relativePath: "Library/Logs/\(entry.folder)",
                declaredRootRelativePath: "Library/Logs",
                action: .deleteContents
            )
        }

        let packageManagerCommands = [
            toolRunItem(
                id: "safe.tool.npm-cache-clean",
                title: "npm cache clean --force",
                tier: .safe,
                requires: .npm,
                tool: .npm,
                arguments: ["cache", "clean", "--force"]
            ),
            toolRunItem(
                id: "safe.tool.brew-cleanup",
                title: "brew cleanup --prune=all",
                tier: .safe,
                requires: .homebrew,
                tool: .brew,
                arguments: ["cleanup", "--prune=all"]
            ),
            toolRunItem(
                id: "safe.tool.brew-autoremove",
                title: "brew autoremove",
                tier: .safe,
                requires: .homebrew,
                tool: .brew,
                arguments: ["autoremove"]
            ),
            toolRunItem(
                id: "safe.tool.pod-cache-clean",
                title: "pod cache clean --all",
                tier: .safe,
                requires: .cocoapods,
                tool: .pod,
                arguments: ["cache", "clean", "--all"]
            ),
            toolRunItem(
                id: "safe.tool.uv-cache-prune",
                title: "uv cache prune",
                tier: .safe,
                requires: .uv,
                tool: .uv,
                arguments: ["cache", "prune"]
            ),
            toolRunItem(
                id: "safe.tool.pnpm-store-prune",
                title: "pnpm store prune",
                tier: .safe,
                requires: .pnpm,
                tool: .pnpm,
                arguments: ["store", "prune"]
            ),
            toolRunItem(
                id: "safe.tool.deno-clean",
                title: "deno clean",
                tier: .safe,
                requires: .deno,
                tool: .deno,
                arguments: ["clean"]
            ),
            toolRunItem(
                id: "safe.tool.pip3-cache-purge",
                title: "pip3 cache purge",
                tier: .safe,
                requires: .pip,
                tool: .pip3,
                arguments: ["cache", "purge"]
            )
        ]

        let gradleItems = [
            globPrefixItem(
                id: "safe.gradle.build-cache",
                title: "~/.gradle/caches (build-cache, transforms, jars, journal)",
                tier: .safe,
                requires: .gradle,
                directoryRelativePath: ".gradle/caches",
                prefixes: ["build-cache-", "transforms-", "jars-", "journal-"],
                declaredRootRelativePath: ".gradle/caches"
            ),
            fixedPathItem(
                id: "safe.gradle.daemon-logs",
                title: "~/.gradle/daemon (logs)",
                tier: .safe,
                requires: .gradle,
                relativePath: ".gradle/daemon",
                declaredRootRelativePath: ".gradle",
                action: .deleteContents
            )
        ]

        let systemCacheItems = [
            fixedPathItem(
                id: "safe.system.quicklook-thumbnails",
                title: "QuickLook thumbnail cache",
                tier: .safe,
                relativePath: "Library/Caches/com.apple.QuickLook.thumbnailcache",
                declaredRootRelativePath: "Library/Caches",
                action: .deleteContents
            ),
            fixedPathItem(
                id: "safe.system.cloudkit-cache",
                title: "CloudKit cache",
                tier: .safe,
                relativePath: "Library/Caches/CloudKit",
                declaredRootRelativePath: "Library/Caches",
                action: .deleteContents
            ),
            CleanItem(
                id: "safe.system.qlmanage-reset",
                title: "Reset QuickLook cache (qlmanage -r cache)",
                tier: .safe,
                declaredRoot: { env in env.homeDirectory },
                locate: { _ in [] },
                action: .runTool(ToolCommand(.qlmanage, ["-r", "cache"]))
            )
        ]

        return CleanCategory(
            id: "safe-caches",
            title: "Regeneratable caches",
            items: appCacheItems + miscCacheItems + logCacheItems + packageManagerCommands + gradleItems + systemCacheItems
        )
    }
}
