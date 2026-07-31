import Testing
@testable import TidyCore

/// Never exercises real snapshot deletion (that needs an admin password
/// prompt and would touch this machine's actual Time Machine snapshots).
/// Covers the validation gate and the empty/all-invalid early-return path,
/// which together determine whether anything ever reaches the privileged
/// shell command in the first place.
@Suite("SnapshotDeleter")
struct SnapshotDeleterTests {
    @Test("accepts tmutil's own date component format", arguments: [
        "2026-07-31-120000",
        "2020-01-01-000000",
        "9999-12-31-235959"
    ])
    func acceptsValidDateComponents(value: String) {
        #expect(SnapshotDeleter.isValidDateComponent(value))
    }

    @Test("rejects anything that isn't exactly that format", arguments: [
        "",
        "2026-07-31",
        "2026-07-31-1200000",
        "2026-07-31-12000",
        "'; rm -rf ~ #",
        "2026-07-31-120000; rm -rf ~",
        "com.apple.TimeMachine.2026-07-31-120000.local",
        "not-a-date-at-all"
    ])
    func rejectsInvalidDateComponents(value: String) {
        #expect(!SnapshotDeleter.isValidDateComponent(value))
    }

    @Test("deleting an empty snapshot list returns false without attempting anything")
    func deletingEmptyListReturnsFalse() async {
        let succeeded = await SnapshotDeleter.deleteSnapshots([])
        #expect(!succeeded)
    }

    @Test("deleting a list whose every entry fails validation returns false without attempting anything")
    func deletingAllInvalidEntriesReturnsFalse() async {
        let bogus = LocalSnapshot(identifier: "com.apple.TimeMachine.not-a-real-date.local")
        let succeeded = await SnapshotDeleter.deleteSnapshots([bogus])
        #expect(!succeeded)
    }
}
