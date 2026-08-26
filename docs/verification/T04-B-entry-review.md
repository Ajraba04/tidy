# T04.B independent implementation-entry review

Independent reviewer `t04b_entry_review`, 2026-08-26: spec-entry READY, quality-entry READY with implementation/runtime gates. No Critical or Important findings. Requirements: original B card, final controller corrections in `.superpowers/sdd/T04.B-entry-proposal.md`, and `T04-B-process-entry-supplement.md`.

The coordinated non-consuming waitid observer and shared lock around actual signal/consuming wait are coherent. Optional identity does not authorize signals; real identity-less reaping is cached separately. Raw wait status, decoded exit, actual timeout, stream completeness and UTF-8 validity are distinguished. Fixture cleanup preserves uncertain ownership and requires registered descendant exit evidence. No source approval or process execution is implied.

Minor carried to source/runtime verification: Foundation coexistence currently covers one Foundation-first overlap, not both launch orders/repeated interactions. It is adequate bounded-entry evidence, not universal Foundation/macOS14/Intel compatibility proof. Strengthen where practical without a broad stress loop.

Exact reviewed Darwin choices: zeroed siginfo and matching positive child/exit-class codes with waitid(P_PID,WEXITED|WNOWAIT); exact-child waitpid(WNOHANG) under the ownership lock; F_DUPFD_CLOEXEC minimum3; POSIX_SPAWN_CLOEXEC_DEFAULT and explicit stdio actions; descriptor-local F_SETNOSIGPIPE on control writes; raw normal-exit mask127 and decoded code shift8/mask255. API/header evidence does not establish runtime behavior. Controller's primary-source notes are `.superpowers/sdd/T04.B-darwin-api-notes.md`.

Before source acceptance, inspect sole kill site, consuming waits, cancellation/grant transfer, failure ownership, source-cancel/FD closure and retained-supervisor lifetimes. Execute the actual disposable fixture tests and bounded compatibility check. T04.A quality approval and controller source assignment remain prerequisites. Accepted-effect/C integration and supported physical hardware gates remain open.

Review was read-only: no files, processes, signals, tests, builds or Git state changed by reviewer.
