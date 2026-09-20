# Git storage integration

Git inventory consumes project identities from the bounded project scanner. Worktree marker, git-dir, common-dir, and worktree identities are captured without CLI calls. Common storage is de-duplicated and records all observed project owners. External common directories outside authorized roots remain unknown and are not traversed.

An `index.lock` is never deleted merely because it is old. Missing lock-owner proof, hooks/config side effects, live operations, dirty/untracked uncertainty, external common directories, or incomplete worktree owners block maintenance. Remote checks, remote prune, forced lock removal, repository/worktree/LFS deletion, and broad gc/reflog effects remain unavailable.
