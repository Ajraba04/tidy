import Foundation
import Testing
@testable import TidyCore

@Suite("Bounded Docker HTTP framing")
struct DockerHTTPFramingTests {
    @Test("HTTP framing waits for the complete finite body and preserves response status")
    func completeFiniteBody() throws {
        let prefix = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n".utf8)
        #expect(try DockerHTTPFraming.parse(prefix + Data("{".utf8)) == nil)
        let response = try #require(try DockerHTTPFraming.parse(prefix + Data("{}".utf8)))
        #expect(response.status == 200)
        #expect(response.body == Data("{}".utf8))
        #expect(!response.connectionWillClose)
        let noContent = try #require(try DockerHTTPFraming.parse(Data("HTTP/1.1 204 No Content\r\n\r\n".utf8)))
        #expect(noContent.status == 204)
        #expect(noContent.body.isEmpty)
    }

    @Test("HTTP framing rejects ambiguous unbounded or pipelined replies")
    func hostileFraming() throws {
        let invalid = [
            "HTTP/1.1 200 OK\r\n\r\n{}",
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\n{}",
            "HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nTransfer-Encoding: chunked\r\n\r\n{}",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
            "HTTP/1.1 204 No Content\r\nContent-Length: 1\r\n\r\nx",
            "HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n",
            "HTTP/1.1 100 Continue\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\nHTTP/1.1 204 No Content\r\n\r\n",
            "HTTP/1.1 200 OK\r\n folded: value\r\nContent-Length: 0\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 2097153\r\n\r\n"
        ]
        for text in invalid {
            #expect(throws: DockerHTTPFramingError.self) { try DockerHTTPFraming.parse(Data(text.utf8)) }
        }
        #expect(throws: DockerHTTPFramingError.tooLarge) {
            try DockerHTTPFraming.parse(Data(repeating: 65, count: 16_385))
        }
    }

    @Test("HTTP connection close is explicit and exact Docker routes cannot expand scope")
    func exactRequestAndConnectionDisposition() throws {
        let response = try #require(try DockerHTTPFraming.parse(Data(
            "HTTP/1.1 409 Conflict\r\nConnection: close\r\nContent-Length: 2\r\n\r\n{}".utf8)))
        #expect(response.connectionWillClose)
        #expect(response.status == 409)
        let id = String(repeating: "a", count: 64)
        let request = try DockerHTTPRequest.removeContainer(apiVersion: "1.51", id: id)
        #expect(String(decoding: request, as: UTF8.self).hasPrefix(
            "DELETE /v1.51/containers/\(id)?force=false&v=false&link=false HTTP/1.1\r\n"))
        #expect(!String(decoding: request, as: UTF8.self).contains("Authorization:"))
        for invalid in ["name", String(repeating: "a", count: 63), String(repeating: "A", count: 64),
                        "sha256:" + id, id + "?force=true", id + "\r\n"] {
            #expect(throws: DockerHTTPFramingError.self) {
                try DockerHTTPRequest.removeContainer(apiVersion: "1.51", id: invalid)
            }
        }
        #expect(throws: DockerHTTPFramingError.self) {
            try DockerHTTPRequest.removeContainer(apiVersion: "1.51/../../images", id: id)
        }
    }
}
