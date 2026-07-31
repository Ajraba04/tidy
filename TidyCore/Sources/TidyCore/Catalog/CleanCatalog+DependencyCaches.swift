extension CleanCatalog {
    /// The shell script's `--deep` tier: full Gradle/SwiftPM/pub caches,
    /// `.npm/_npx`, Maven, CocoaPods repo cache. Populated in Phase 6.
    static var dependencyCaches: CleanCategory {
        CleanCategory(id: "dependency-caches", title: "Dependency caches", items: [])
    }
}
