extension CleanCatalog {
    /// Section 5 of the shell script: per-repo `git gc`, with reflog expiry
    /// conservative at Normal and total at Deep. Populated in Phases 5 and 6.
    static var gitCleanup: CleanCategory {
        CleanCategory(id: "git", title: "Git repositories", items: [])
    }
}
