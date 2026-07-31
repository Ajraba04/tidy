extension CleanCatalog {
    /// The shell script's `--android` tier: AVDs, unused system-images, NDK.
    /// Populated in Phase 6.
    static var android: CleanCategory {
        CleanCategory(id: "android", title: "Android", items: [])
    }
}
