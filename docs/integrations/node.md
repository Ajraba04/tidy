# Node integration

`package.json` and lockfiles are parsed only as bounded local data by project inventory. Package scripts, lifecycle hooks, package-manager configuration, and network operations are never evaluated.

`node_modules` is always manual-risk because edited/untracked state is unknown. It is never selected for Build Prep or maintenance by this adapter. Project outputs such as `dist`, `build`, `.next`, and `.turbo` receive exact identities, but remain unavailable for mutation until producer ownership, a reviewed descendant manifest, quiescence, and terminal proof are registered. Shared npm/yarn/pnpm caches remain report-only when consumer ownership is incomplete.
