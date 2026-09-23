import Foundation
import TidyCore

/// Budgets report measured allocation within the approved inventory scope.
/// Missing, shared, overlapping, or service-only sizes remain unknown.
enum InventoryBudgetProjection {
    static func measurements(_ inventory: DeveloperInventorySnapshot, volumeID: UUID)
        -> [BudgetMeasurement] {
        var rows: [BudgetID: [InventoryRecord]] = [:]
        for entry in inventory.entries {
            guard case .filesystem(let file) = entry.record.resource,
                  file.volumeID == volumeID else { continue }
            rows[budget(for: entry.record), default: []].append(entry.record)
        }
        return BudgetID.allCases.map { id in
            guard inventory.projects.coverage.isComplete, inventory.probeIssues.isEmpty,
                  let records = rows[id], !records.isEmpty else {
                return .init(budgetID: id, volumeID: volumeID, allocatedBytes: nil)
            }
            var total: Int64 = 0
            var files: [FileResourceIdentity] = []
            for record in records {
                guard case .filesystem(let file) = record.resource,
                      let bytes = record.allocatedBytes, bytes >= 0,
                      !files.contains(where: {
                          ($0.device == file.device && $0.inode == file.inode) ||
                          isEqualOrDescendant(file.canonicalPath, of: $0.canonicalPath) ||
                          isEqualOrDescendant($0.canonicalPath, of: file.canonicalPath)
                      }) else {
                    return .init(budgetID: id, volumeID: volumeID, allocatedBytes: nil)
                }
                let (sum, overflow) = total.addingReportingOverflow(bytes)
                guard !overflow else {
                    return .init(budgetID: id, volumeID: volumeID, allocatedBytes: nil)
                }
                total = sum
                files.append(file)
            }
            return .init(budgetID: id, volumeID: volumeID, allocatedBytes: total)
        }
    }

    private static func isEqualOrDescendant(_ path: String, of root: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    private static func budget(for record: InventoryRecord) -> BudgetID {
        switch record.adapterID {
        case "apple.developer":
            if record.kind.contains("DerivedData") { return .appleDerivedData }
            if record.kind.contains("Simulator") { return .appleSimulators }
            return .other
        case "android.developer": return .android
        case "docker.local": return .docker
        case "language.caches", "homebrew": return .packageCaches
        case "node.developer": return record.kind == "node-shared-cache" ? .packageCaches : .other
        case "local.models": return .models
        case "ide.caches": return .ides
        case "git.storage": return .git
        case "data.directories": return .data
        default: return .other
        }
    }
}
