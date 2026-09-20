# Apple developer integration

Supported parser contract: `simctl-json-v1`, tested with the appendix device fixture containing an exact UUID, runtime ID, name, state, and availability. Input is UTF-8 JSON, at most 1 MiB, with nesting at most 16. Unknown or malformed shapes are rejected.

Filesystem inventory is limited to authorized roots and known Xcode, CoreSimulator, SwiftPM, and CocoaPods locations. It follows no symbolic links and reports producer/activity uncertainty. DerivedData, archives, runtimes, and device support remain inventory-only without complete producer ownership and quiescence evidence.

The only described simulator argv are `simctl shutdown <UDID>` and `simctl delete <UDID>`. Bulk erase/delete-unavailable is forbidden. The current capability registry and ProcessRunner expose no accepted mutation dispatch, so generated effect specifications remain unavailable. Unsupported versions stay read-only.
