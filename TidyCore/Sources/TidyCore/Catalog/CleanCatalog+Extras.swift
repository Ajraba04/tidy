extension CleanCatalog {
    /// Section 6 (stale node_modules, build outputs, old session
    /// transcripts) and section 7 (Trash) of the shell script. Populated in
    /// Phases 4 and 5.
    static var extras: CleanCategory {
        CleanCategory(id: "extras", title: "Projects & Trash", items: [])
    }
}
