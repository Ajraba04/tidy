import Foundation
import Testing
@testable import TidyCore

@Suite("StaleNodeModulesScanner")
struct StaleNodeModulesScannerTests {

    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StaleNodeModulesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func setModificationDate(_ date: Date, at url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test("finds a node_modules directory older than the threshold")
    func findsStaleNodeModules() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let project = scratch.appendingPathComponent("project", isDirectory: true)
        let nodeModules = project.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try setModificationDate(Date().addingTimeInterval(-90 * 86400), at: nodeModules)

        let results = StaleNodeModulesScanner.find(roots: [scratch.path], olderThanDays: 60)
        #expect(results.map(\.path) == [PathGuard.canonicalize(nodeModules.path)])
    }

    @Test("does not report a recently touched node_modules directory")
    func ignoresFreshNodeModules() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let project = scratch.appendingPathComponent("project", isDirectory: true)
        let nodeModules = project.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)

        let results = StaleNodeModulesScanner.find(roots: [scratch.path], olderThanDays: 60)
        #expect(results.isEmpty)
    }

    @Test("does not walk into a node_modules directory's own contents")
    func prunesNodeModulesContents() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let project = scratch.appendingPathComponent("project", isDirectory: true)
        let nodeModules = project.appendingPathComponent("node_modules", isDirectory: true)
        let nested = nodeModules.appendingPathComponent("some-package/node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try setModificationDate(Date().addingTimeInterval(-90 * 86400), at: nodeModules)
        try setModificationDate(Date().addingTimeInterval(-90 * 86400), at: nested)

        let results = StaleNodeModulesScanner.find(roots: [scratch.path], olderThanDays: 60)
        #expect(results.map(\.path) == [PathGuard.canonicalize(nodeModules.path)])
    }

    @Test("returns nothing when the threshold is not positive")
    func returnsNothingForNonPositiveThreshold() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let results = StaleNodeModulesScanner.find(roots: [scratch.path], olderThanDays: 0)
        #expect(results.isEmpty)
    }
}
