import Foundation
import Testing
@testable import TidyCore

@Suite("PathGuard")
struct PathGuardTests {

    // MARK: - Universal refusals, independent of protected/declared roots

    @Test("refuses an empty path")
    func refusesEmptyPath() {
        let guardian = PathGuard(protectedRoots: [])
        #expect(throws: PathGuardError.empty) {
            try guardian.validate("")
        }
    }

    @Test("refuses a relative path")
    func refusesRelativePath() {
        let guardian = PathGuard(protectedRoots: [])
        #expect(throws: PathGuardError.notAbsolute(path: "Library/Caches")) {
            try guardian.validate("Library/Caches")
        }
    }

    @Test("refuses the root of the filesystem")
    func refusesFilesystemRoot() {
        let guardian = PathGuard(protectedRoots: [])
        #expect(throws: PathGuardError.isRoot) {
            try guardian.validate("/")
        }
    }

    @Test("refuses the home directory exactly")
    func refusesHomeDirectoryExactly() {
        let guardian = PathGuard(protectedRoots: [])
        #expect(throws: PathGuardError.isHome) {
            try guardian.validate("/Users/tester", home: "/Users/tester")
        }
    }

    @Test("refuses the home directory with a trailing slash")
    func refusesHomeDirectoryTrailingSlash() {
        let guardian = PathGuard(protectedRoots: [])
        #expect(throws: PathGuardError.isHome) {
            try guardian.validate("/Users/tester/", home: "/Users/tester")
        }
    }

    @Test("allows an ordinary path under home when nothing restricts it")
    func allowsOrdinaryPathUnderHome() throws {
        let guardian = PathGuard(protectedRoots: [])
        try guardian.validate("/Users/tester/Library/Caches/Homebrew", home: "/Users/tester")
    }

    // MARK: - Protected roots (iCloud, etc.)

    @Test("refuses a protected root exactly")
    func refusesProtectedRootExactly() {
        let guardian = PathGuard(protectedRoots: ["/Users/tester/Library/CloudStorage"])
        #expect(throws: PathGuardError.self) {
            try guardian.validate("/Users/tester/Library/CloudStorage", home: "/Users/tester")
        }
    }

    @Test("refuses a path nested inside a protected root")
    func refusesNestedInsideProtectedRoot() {
        let guardian = PathGuard(protectedRoots: ["/Users/tester/Library/CloudStorage"])
        #expect(throws: PathGuardError.self) {
            try guardian.validate(
                "/Users/tester/Library/CloudStorage/iCloud Drive/Documents/file.txt",
                home: "/Users/tester"
            )
        }
    }

    @Test("does not treat a same-prefix sibling as protected")
    func doesNotTreatSiblingWithSharedPrefixAsProtected() throws {
        let guardian = PathGuard(protectedRoots: ["/Users/tester/Library/CloudStorage"])
        // "CloudStorageArchive" shares a string prefix with "CloudStorage" but
        // is a different directory; the "/" boundary must stop a false match.
        try guardian.validate("/Users/tester/Library/CloudStorageArchive", home: "/Users/tester")
    }

    @Test("enforces every protected root in a multi-root list")
    func enforcesEveryProtectedRootInList() {
        let guardian = PathGuard(protectedRoots: [
            "/Users/tester/Library/CloudStorage",
            "/Users/tester/Library/Mobile Documents"
        ])
        #expect(throws: PathGuardError.self) {
            try guardian.validate(
                "/Users/tester/Library/Mobile Documents/com~apple~CloudDocs/notes.txt",
                home: "/Users/tester"
            )
        }
    }

    // MARK: - Declared root (an item may only touch its own territory)

    @Test("allows a path under its declared root")
    func allowsPathUnderDeclaredRoot() throws {
        let guardian = PathGuard(protectedRoots: [])
        try guardian.validate(
            "/Users/tester/Library/Caches/Homebrew/downloads",
            mustBeUnder: "/Users/tester/Library/Caches",
            home: "/Users/tester"
        )
    }

    @Test("allows a path equal to its declared root")
    func allowsPathEqualToDeclaredRoot() throws {
        let guardian = PathGuard(protectedRoots: [])
        try guardian.validate(
            "/Users/tester/Library/Caches",
            mustBeUnder: "/Users/tester/Library/Caches",
            home: "/Users/tester"
        )
    }

    @Test("refuses a path outside its declared root")
    func refusesPathOutsideDeclaredRoot() {
        let guardian = PathGuard(protectedRoots: [])
        #expect(throws: PathGuardError.self) {
            try guardian.validate(
                "/Users/tester/Documents/report.pdf",
                mustBeUnder: "/Users/tester/Library/Caches",
                home: "/Users/tester"
            )
        }
    }

    @Test("refuses a declared-root escape via a same-prefix sibling")
    func refusesDeclaredRootEscapeViaSiblingPrefix() {
        let guardian = PathGuard(protectedRoots: [])
        #expect(throws: PathGuardError.self) {
            try guardian.validate(
                "/Users/tester/Library/Caches2/evil",
                mustBeUnder: "/Users/tester/Library/Caches",
                home: "/Users/tester"
            )
        }
    }

    @Test("a protected root still wins even when the path is under its declared root")
    func protectedRootWinsOverDeclaredRoot() {
        let guardian = PathGuard(protectedRoots: ["/Users/tester/Library/CloudStorage"])
        #expect(throws: PathGuardError.self) {
            try guardian.validate(
                "/Users/tester/Library/CloudStorage/Desktop/file.txt",
                mustBeUnder: "/Users/tester/Library/CloudStorage",
                home: "/Users/tester"
            )
        }
    }

    // MARK: - isSafe (non-throwing convenience)

    @Test("isSafe mirrors validate without throwing")
    func isSafeMirrorsValidate() {
        let guardian = PathGuard(protectedRoots: ["/Users/tester/Library/CloudStorage"])
        #expect(guardian.isSafe("/Users/tester/Library/Caches", home: "/Users/tester"))
        #expect(!guardian.isSafe("/Users/tester/Library/CloudStorage/x", home: "/Users/tester"))
        #expect(!guardian.isSafe("", home: "/Users/tester"))
        #expect(!guardian.isSafe("/", home: "/Users/tester"))
    }

    // MARK: - Canonicalization

    @Test("canonicalize strips a trailing slash")
    func canonicalizeStripsTrailingSlash() {
        #expect(PathGuard.canonicalize("/Users/tester/Library/Caches/") == PathGuard.canonicalize("/Users/tester/Library/Caches"))
    }

    @Test("canonicalize expands a leading tilde")
    func canonicalizeExpandsTilde() {
        let expanded = PathGuard.canonicalize("~/Library/Caches")
        let home = PathGuard.canonicalize(NSHomeDirectory())
        #expect(expanded == home + "/Library/Caches")
    }

    @Test("canonicalize resolves a real symlink so it cannot be used to escape a declared root")
    func canonicalizeResolvesRealSymlink() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("PathGuardTests-\(UUID().uuidString)")
        let insideRoot = scratch.appendingPathComponent("root")
        let outsideRoot = scratch.appendingPathComponent("outside")
        try fm.createDirectory(at: insideRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        let target = outsideRoot.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: target)

        let link = insideRoot.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)

        let guardian = PathGuard(protectedRoots: [])
        #expect(throws: PathGuardError.self) {
            try guardian.validate(link.path, mustBeUnder: insideRoot.path)
        }
    }

    @Test("isEqualOrDescendant requires an exact match or a slash boundary")
    func isEqualOrDescendantBoundary() {
        #expect(PathGuard.isEqualOrDescendant("/a/b", of: "/a/b"))
        #expect(PathGuard.isEqualOrDescendant("/a/b/c", of: "/a/b"))
        #expect(!PathGuard.isEqualOrDescendant("/a/bc", of: "/a/b"))
        #expect(!PathGuard.isEqualOrDescendant("/a/b", of: ""))
    }
}
