import Darwin
import Foundation

public enum LocalEndpointDenial: String, Error, Equatable, Sendable {
    case malformed
    case remote
    case symbolicLink
    case notSocket
    case notApproved
    case changed
}

public enum LocalEndpointGuard {
    public static func permitsLocalEndpointSyntax(_ endpoint: String) -> Bool {
        endpoint.hasPrefix("unix://") && !endpoint.contains("\n")
            && !endpoint.contains("\r") && !endpoint.utf8.contains(0)
    }

    static func captureApproved(endpoint: String,
                                approved: Set<LocalSocketApproval>)
        -> Result<LocalSocketApproval, LocalEndpointDenial> {
        guard permitsLocalEndpointSyntax(endpoint) else {
            return .failure(endpoint.contains("://") && !endpoint.hasPrefix("unix://")
                ? .remote : .malformed)
        }
        let raw = String(endpoint.dropFirst("unix://".count))
        guard raw.hasPrefix("/"), raw.utf8.count <= 4_096 else { return .failure(.malformed) }
        let path = URL(fileURLWithPath: raw).standardizedFileURL.path
        var metadata = stat()
        guard lstat(path, &metadata) == 0 else { return .failure(.changed) }
        guard metadata.st_mode & S_IFMT != S_IFLNK else { return .failure(.symbolicLink) }
        guard metadata.st_mode & S_IFMT == S_IFSOCK else { return .failure(.notSocket) }
        let identity: LocalSocketApproval
        do {
            identity = try LocalSocketApproval.verify(socket: URL(fileURLWithPath: path))
        } catch {
            return .failure(.notSocket)
        }
        guard approved.contains(identity) else { return .failure(.notApproved) }
        guard (try? LocalSocketApproval.verify(socket: URL(fileURLWithPath: path))) == identity else {
            return .failure(.changed)
        }
        return .success(identity)
    }
}
