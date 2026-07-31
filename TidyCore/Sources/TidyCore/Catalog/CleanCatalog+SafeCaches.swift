extension CleanCatalog {
    /// Section 1 of the shell script: regeneratable developer tool caches
    /// and package-manager cache-clean commands. Populated in Phase 4.
    static var safeCaches: CleanCategory {
        CleanCategory(id: "safe-caches", title: "Developer tool caches", items: [])
    }
}
