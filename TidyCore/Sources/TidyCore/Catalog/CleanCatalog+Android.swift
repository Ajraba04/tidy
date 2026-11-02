import Foundation

extension CleanCatalog {
    /// Covers AVDs, system-images, NDK, and SDK temp files. API levels
    /// are discovered by listing what's actually present under
    /// `system-images` rather than hardcoded, since specific versions
    /// like `android-29` are tied to one machine, not a general default.
    static var android: CleanCategory {
        var items: [CleanItem] = []

        items.append(fixedPathItem(
            id: "deep.android.avds",
            title: "Android AVDs",
            tier: .deep,
            requires: .android,
            costNote: "Recreatable from Android Studio's Device Manager in a minute",
            relativePath: ".android/avd",
            declaredRootRelativePath: ".android",
            action: .deleteContents
        ))

        items.append(fixedPathItem(
            id: "deep.android.cache",
            title: "~/.android/cache",
            tier: .deep,
            requires: .android,
            relativePath: ".android/cache",
            declaredRootRelativePath: ".android"
        ))

        items.append(CleanItem(
            id: "deep.android.system-images",
            title: "Android SDK system-images",
            tier: .deep,
            requires: .android,
            costNote: "Re-downloadable via the SDK Manager",
            declaredRoot: { env in env.homeDirectory + "/Library/Android/sdk/system-images" },
            locate: { env in
                let root = env.homeDirectory + "/Library/Android/sdk/system-images"
                guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
                let canonicalRoot = PathGuard.canonicalize(root)
                return entries.filter { name in
                    PathGuard.isEqualOrDescendant(PathGuard.canonicalize(root + "/" + name),
                        of: canonicalRoot)
                }.map { name in
                    TargetPath(path: root + "/" + name, label: "Android system-image \(name)")
                }
            },
            action: .deletePath
        ))

        items.append(fixedPathItem(
            id: "deep.android.ndk",
            title: "Android NDK",
            tier: .deep,
            requires: .android,
            costNote: "Re-installable via the SDK Manager",
            relativePath: "Library/Android/sdk/ndk",
            declaredRootRelativePath: "Library/Android/sdk"
        ))

        items.append(fixedPathItem(
            id: "deep.android.sdk-temp",
            title: "Android SDK temp",
            tier: .deep,
            requires: .android,
            relativePath: "Library/Android/sdk/temp",
            declaredRootRelativePath: "Library/Android/sdk"
        ))

        return CleanCategory(id: "android", title: "Android", items: items)
    }
}
