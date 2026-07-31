extension CleanCatalog {
    /// Per-repo `git gc`, with conservative reflog expiry at Normal. The
    /// Deep tier's `--git-deep` equivalent (expire every reflog now) is
    /// a separate, prominently-warned, opt-in item: nothing survives
    /// it, so there is no `git reset` rescue afterward.
    static var gitCleanup: CleanCategory {
        let housekeeping = CleanItem(
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

        let aggressiveReflogExpiry = CleanItem(
            id: "deep.git.reflog-expire-all",
            title: "Expire ALL git reflogs now",
            tier: .deep,
            requires: .git,
            dangerNote: "Loses git undo history: no `git reset` rescue survives this",
            declaredRoot: { env in env.homeDirectory },
            locate: { env in
                GitRepoScanner.findRepositories(roots: env.gitRoots, protectedRoots: env.protectedRoots)
                    .map { TargetPath(path: $0, label: PathDisplay.tilde($0, homeDirectory: env.homeDirectory)) }
            },
            action: .custom(.gitReflogExpireAggressive)
        )

        return CleanCategory(id: "git", title: "Git repositories", items: [housekeeping, aggressiveReflogExpiry])
    }
}
