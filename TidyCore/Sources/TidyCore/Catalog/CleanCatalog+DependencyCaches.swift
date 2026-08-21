import Foundation

extension CleanCatalog {
    /// The shell script's `--deep` tier: full Gradle/SwiftPM/pub caches,
    /// `.npm/_npx`, Maven, CocoaPods repo cache. Each one costs a
    /// re-download the next time its ecosystem's tool runs.
    static var dependencyCaches: CleanCategory {
        var items: [CleanItem] = [
            fixedPathItem(
                id: "deep.deps.gradle-caches-full",
                title: "~/.gradle/caches (full)",
                tier: .deep,
                requires: .gradle,
                costNote: "Every dependency your Gradle projects use re-downloads on next build",
                relativePath: ".gradle/caches",
                declaredRootRelativePath: ".gradle",
                action: .deleteContents
            ),
            fixedPathItem(
                id: "deep.deps.gradle-wrapper",
                title: "~/.gradle/wrapper (Gradle distributions)",
                tier: .deep,
                requires: .gradle,
                costNote: "Each Gradle version in use re-downloads on next build",
                relativePath: ".gradle/wrapper",
                declaredRootRelativePath: ".gradle",
                action: .deleteContents
            ),
            fixedPathItem(
                id: "deep.deps.npm-npx",
                title: "~/.npm/_npx",
                tier: .deep,
                requires: .npm,
                costNote: "npx re-downloads packages it hasn't cached",
                relativePath: ".npm/_npx",
                declaredRootRelativePath: ".npm"
            ),
            fixedPathItem(
                id: "deep.deps.maven-repository",
                title: "~/.m2/repository (Maven)",
                tier: .deep,
                costNote: "Every Maven dependency re-downloads on next build",
                relativePath: ".m2/repository",
                declaredRootRelativePath: ".m2"
            ),
            fixedPathItem(
                id: "deep.deps.pub-cache",
                title: "~/.pub-cache (Dart)",
                tier: .deep,
                requires: .dart,
                costNote: "Run 'dart pub get' afterward to restore packages",
                relativePath: ".pub-cache",
                declaredRootRelativePath: "."
            ),
            fixedPathItem(
                id: "deep.deps.dart-server",
                title: "~/.dartServer",
                tier: .deep,
                requires: .dart,
                relativePath: ".dartServer",
                declaredRootRelativePath: "."
            ),
            fixedPathItem(
                id: "deep.deps.bubblewrap",
                title: "~/.bubblewrap",
                tier: .deep,
                relativePath: ".bubblewrap",
                declaredRootRelativePath: "."
            ),
            fixedPathItem(
                id: "deep.deps.cocoapods-repos",
                title: "~/.cocoapods/repos",
                tier: .deep,
                requires: .cocoapods,
                costNote: "CocoaPods re-clones its spec repos on next use",
                relativePath: ".cocoapods/repos",
                declaredRootRelativePath: ".cocoapods"
            )
        ]

        items.append(toolRunItem(
            id: "deep.deps.go-clean-modcache",
            title: "go clean -modcache",
            tier: .deep,
            requires: .go,
            tool: .go,
            arguments: ["clean", "-modcache"]
        ))

        // Flutter was detected by `ToolchainDetector` but required by no
        // item, leaving `.flutter` a toolchain the app could recognise and
        // then do nothing about. Its engine artifacts are the largest
        // single thing a Flutter install puts on disk.
        items.append(fixedPathItem(
            id: "safe.flutter.tool-state",
            title: "~/.flutter_tool_state",
            tier: .safe,
            requires: .flutter,
            relativePath: ".flutter_tool_state",
            declaredRootRelativePath: ".flutter_tool_state"
        ))

        items.append(CleanItem(
            id: "deep.flutter.sdk-cache",
            title: "Flutter SDK bin/cache (engine artifacts)",
            tier: .deep,
            requires: .flutter,
            costNote: "Several GB of engine artifacts; 'flutter precache' re-downloads them",
            declaredRoot: { env in env.homeDirectory },
            locate: { env in
                // The SDK lives wherever the user unpacked it, so it is
                // resolved from the `flutter` executable rather than
                // guessed. Only offered when the SDK sits inside $HOME:
                // an SDK installed system-wide is outside this item's
                // declared root, and PathGuard would refuse it anyway.
                guard let executable = ToolLocator.locate("flutter") else { return [] }
                let sdkRoot = ((executable as NSString).deletingLastPathComponent as NSString)
                    .deletingLastPathComponent
                let cachePath = sdkRoot + "/bin/cache"
                guard PathGuard.isEqualOrDescendant(
                    PathGuard.canonicalize(cachePath),
                    of: PathGuard.canonicalize(env.homeDirectory)
                ) else { return [] }
                guard FileManager.default.fileExists(atPath: cachePath) else { return [] }
                return [TargetPath(path: cachePath, label: PathDisplay.tilde(cachePath))]
            },
            action: .deletePath
        ))

        return CleanCategory(id: "dependency-caches", title: "Dependency caches", items: items)
    }
}
