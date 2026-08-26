# T05.A3 app-cutover entry review

Entry proposal3ecb4b4, correctionca0ecd8. Independent reviewer `t05a3_entry_review` read both complete generated packages and the preparation/fix report; focused unchanged checks covered actual I/O and app APIs, existing assertions, unhosted target membership, report presentation and the transitive onboarding route. No source tests/builds/launches/Git mutations by reviewer.

Initial verdict: Needs fixes, one Important. The exact ownership list omitted MenuBarContentView, whose popover appearance automatically opened onboarding and thus synchronous tool detection, contradicting the no-startup-discovery contract. Fresh documentation fixer added that file, exact automatic-route removal and explicit click-only setup access, plus the requested source-adoption check. A Minor added a complete real-v1 app bootstrap/first-edit/exact-backup regression.

Independent re-review: **entry spec compliant; quality-entry Approved; design READY** throughca0ecd8. No Critical or Important remains. Remaining Minor requested initial enabled/admission assertions for migrated startup; controller added both `services.isExecutionEnabled` and the existing `.ready(revision: 1)` policy observation to that same proposed regression. No source implementation or test execution is claimed by this documentation change.

Root read the full entry and corrections and checked actual source/signatures. Actual A2P acceptance remains required before A3 source assignment. Debug package testability, real RED/GREEN, atomic source adoption, native UI, B1/B2, stable macOS/Intel and full-program acceptance remain unverified. Manual click-initiated onboarding discovery remains T08 work. This entry approval does not authorize live settings migration, user cleanup or publication.
