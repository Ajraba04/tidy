import Foundation

enum DockerHTTPFramingError: Error, Equatable { case invalid, tooLarge, unsupported }

struct DockerHTTPResponse: Equatable, Sendable {
    let status: Int
    let body: Data
    let connectionWillClose: Bool
}

enum DockerHTTPFraming {
    static let maximumHeaderBytes = 16_384
    static let maximumBodyBytes = 2_097_152
    static let maximumHeaderCount = 64

    /// One finite response only. Unsupported chunked/close-delimited encodings
    /// are rejected, never guessed complete or reused as an absence receipt.
    static func parse(_ data: Data) throws -> DockerHTTPResponse? {
        guard data.count <= maximumHeaderBytes + maximumBodyBytes else {
            throw DockerHTTPFramingError.tooLarge
        }
        guard let separator = data.range(of: Data([13, 10, 13, 10])) else {
            guard data.count <= maximumHeaderBytes else { throw DockerHTTPFramingError.tooLarge }
            return nil
        }
        let headerCount = data.distance(from: data.startIndex, to: separator.upperBound)
        guard headerCount <= maximumHeaderBytes else { throw DockerHTTPFramingError.tooLarge }
        let headerData = data[..<separator.lowerBound]
        guard headerData.allSatisfy({ $0 == 9 || $0 == 13 || $0 == 10 || (32...126).contains($0) }),
              let text = String(data: headerData, encoding: .ascii) else {
            throw DockerHTTPFramingError.invalid
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let first = lines.first, !first.contains("\n"), !first.contains("\r") else {
            throw DockerHTTPFramingError.invalid
        }
        let statusParts = first.split(separator: " ", omittingEmptySubsequences: false)
        guard statusParts.count >= 2, statusParts[0] == "HTTP/1.1",
              statusParts[1].utf8.count == 3,
              statusParts[1].utf8.allSatisfy({ (48...57).contains($0) }),
              let status = Int(statusParts[1]), (200...599).contains(status) else {
            throw DockerHTTPFramingError.unsupported
        }
        guard lines.count - 1 <= maximumHeaderCount else { throw DockerHTTPFramingError.tooLarge }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw DockerHTTPFramingError.invalid }
            let name = String(line[..<colon]).lowercased()
            let rawValue = line[line.index(after: colon)...]
            guard !name.isEmpty,
                  name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
                  !rawValue.contains("\r"), !rawValue.contains("\n"), headers[name] == nil else {
                throw DockerHTTPFramingError.invalid
            }
            headers[name] = rawValue.trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil, headers["upgrade"] == nil else {
            throw DockerHTTPFramingError.unsupported
        }
        let length: Int
        if let raw = headers["content-length"] {
            guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
                  let count = Int(raw), count <= maximumBodyBytes else {
                throw DockerHTTPFramingError.invalid
            }
            length = count
        } else if status == 204 {
            length = 0
        } else {
            throw DockerHTTPFramingError.unsupported
        }
        guard status != 204 || length == 0 else { throw DockerHTTPFramingError.invalid }
        let available = data.count - headerCount
        guard available <= length else { throw DockerHTTPFramingError.invalid }
        guard available == length else { return nil }
        let close = headers["connection"]?.lowercased().split(separator: ",")
            .contains(where: { $0.trimmingCharacters(in: .whitespaces) == "close" }) ?? false
        return DockerHTTPResponse(status: status, body: Data(data.suffix(length)),
            connectionWillClose: close)
    }
}

enum DockerHTTPRequest {
    static func version() -> Data { request(method: "GET", path: "/version") }

    static func info(apiVersion: String) throws -> Data {
        do { _ = try ManualServiceValueBounds.apiVersion(apiVersion) }
        catch { throw DockerHTTPFramingError.invalid }
        return request(method: "GET", path: "/v\(apiVersion)/info")
    }

    static func inspectContainer(apiVersion: String, id: String) throws -> Data {
        try validate(apiVersion: apiVersion, id: id)
        return request(method: "GET", path: "/v\(apiVersion)/containers/\(id)/json")
    }

    static func removeContainer(apiVersion: String, id: String) throws -> Data {
        try validate(apiVersion: apiVersion, id: id)
        return request(method: "DELETE",
            path: "/v\(apiVersion)/containers/\(id)?force=false&v=false&link=false")
    }

    private static func validate(apiVersion: String, id: String) throws {
        do {
            _ = try ManualServiceValueBounds.apiVersion(apiVersion)
            try ManualServiceValueBounds.containerID(id)
        } catch { throw DockerHTTPFramingError.invalid }
    }

    private static func request(method: String, path: String) -> Data {
        Data(("\(method) \(path) HTTP/1.1\r\n"
            + "Host: docker\r\nAccept: application/json\r\nContent-Length: 0\r\n"
            + "Connection: keep-alive\r\n\r\n").utf8)
    }
}
