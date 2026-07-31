extension CleanCatalog {
    /// Section 5 of the shell script: per-repo `git gc`, with reflog expiry
    /// conservative here. The Deep tier's `--git-deep` equivalent (expire
    /// everything now) is a separate, prominently-warned item (Phase 6).
    static var gitCleanup: CleanCategory {
        let item = CleanItem(
            id: "normal.git.housekeeping",
            title: "Git housekeeping (gc, remote prune, conservative reflog expiry)",
            tier: .normal,
            requires: .git,
            declaredRoot: { env in env.homeDirectory },
            locate: { env in
                GitRepoScanner.findRepositories(roots: env.gitRoots, protectedRoots: env.protectedRoots)
                    .map { TargetPath(path: $0, label: PathDisplay.tilde($0, homeDirectory: env.homeDirectory)) }
            },
            action: .custom(.gitRepoGC)
        )

        return CleanCategory(id: "git", title: "Git repositories", items: [item])
    }
}
