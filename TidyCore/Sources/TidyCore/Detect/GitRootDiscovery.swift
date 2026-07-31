import Foundation

/// Probes common project-root locations for git repositories, for
/// onboarding to present as candidates the user confirms — never assumed
/// or shipped as a default.
public enum GitRootDiscovery: Sendable {
    public static let candidateRootNames = ["Developer", "Desktop", "Documents", "development", "Projects"]

    public struct Candidate: Sendable, Equatable {
        public let path: String
        public let repositoryCount: Int
    }

    /// A candidate root is one of the well-known names whose immediate
    /// children include at least one directory with a `.git` — i.e. it
    /// looks like "the folder that holds my projects", not a project
    /// itself.
    public static func discoverCandidates(homeDirectory: String = NSHomeDirectory()) -> [Candidate] {
        let fm = FileManager.default
        var results: [Candidate] = []

        for name in candidateRootNames {
            let path = homeDirectory + "/" + name
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else { continue }

            var repositoryCount = 0
            for entry in entries {
                let entryPath = path + "/" + entry
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: entryPath, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                if fm.fileExists(atPath: entryPath + "/.git") {
                    repositoryCount += 1
                }
            }

            if repositoryCount > 0 {
                results.append(Candidate(path: path, repositoryCount: repositoryCount))
            }
        }

        return results
    }
}
