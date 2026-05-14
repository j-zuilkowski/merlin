import XCTest
@testable import Merlin

@MainActor
final class MCPHTTPTransportTests: XCTestCase {

    func test_httpTransport_sendsJSONRPCPost_withApplicationJSON() async throws {
        let session = makeSession { request in
            MCPHTTPMockURLProtocolState.shared.capturedRequest = request
            return okResponse(
                url: request.url ?? URL(string: "http://example.test")!,
                body: #"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#
            )
        }

        let transport = MCPHTTPTransport(
            endpoint: URL(string: "http://example.test/rpc")!,
            session: session
        )

        let response = try await transport.call(
            method: "tools/list",
            params: ["scope": "all"]
        )

        let capturedRequest = try XCTUnwrap(MCPHTTPMockURLProtocolState.shared.capturedRequest)
        XCTAssertEqual(capturedRequest.httpMethod, "POST")
        XCTAssertEqual(capturedRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(capturedRequest.url?.absoluteString, "http://example.test/rpc")

        let body = try XCTUnwrap(capturedRequest.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json?["method"] as? String, "tools/list")
        XCTAssertEqual(response["ok"] as? Bool, true)
    }

    func test_httpTransport_matchesResponseID_toPendingRequest() async throws {
        let session = makeSession { request in
            let body = try XCTUnwrap(request.httpBody)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let requestID = json?["id"] as? Int ?? -1
            let method = json?["method"] as? String ?? ""
            return okResponse(
                url: request.url ?? URL(string: "http://example.test")!,
                body: #"{"jsonrpc":"2.0","id":\#(requestID),"result":{"method":"\#(method)"}}"#
            )
        }

        let transport = MCPHTTPTransport(
            endpoint: URL(string: "http://example.test/rpc")!,
            session: session
        )

        async let first = transport.call(method: "alpha", params: ["index": 1])
        async let second = transport.call(method: "beta", params: ["index": 2])

        let results = try await [first, second]
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0]["method"] as? String, "alpha")
        XCTAssertEqual(results[1]["method"] as? String, "beta")
    }

    func test_httpTransport_throwsTypedError_forHTTPFailure() async throws {
        let session = makeSession { request in
            httpResponse(
                url: request.url ?? URL(string: "http://example.test")!,
                statusCode: 503,
                body: #"{"error":"unavailable"}"#
            )
        }

        let transport = MCPHTTPTransport(
            endpoint: URL(string: "http://example.test/rpc")!,
            session: session
        )

        do {
            _ = try await transport.call(method: "tools/list", params: [:])
            XCTFail("expected typed transport error")
        } catch let error as MCPTransportError {
            if case .httpStatus(let status, let body) = error {
                XCTAssertEqual(status, 503)
                XCTAssertTrue(body.contains("unavailable"))
            } else {
                XCTFail("unexpected error: \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func test_httpTransport_throwsTypedDecodeError_forMalformedJSON() async throws {
        let session = makeSession { request in
            okResponse(
                url: request.url ?? URL(string: "http://example.test")!,
                body: #"{"jsonrpc":"2.0","id":1,"result": {"ok": true}"#
            )
        }

        let transport = MCPHTTPTransport(
            endpoint: URL(string: "http://example.test/rpc")!,
            session: session
        )

        do {
            _ = try await transport.call(method: "tools/list", params: [:])
            XCTFail("expected decode error")
        } catch let error as MCPTransportError {
            if case .decodeError = error {
                return
            }
            XCTFail("unexpected error: \(error)")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}

private func makeSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    MCPHTTPMockURLProtocolState.shared.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MCPHTTPMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func okResponse(url: URL, body: String) -> (HTTPURLResponse, Data) {
    httpResponse(url: url, statusCode: 200, body: body)
}

private func httpResponse(url: URL, statusCode: Int, body: String) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(body.utf8))
}

final class MCPHTTPMockURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MCPHTTPMockURLProtocolState.shared.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            var hydrated = request
            if hydrated.httpBody == nil, let stream = hydrated.httpBodyStream {
                var bodyData = Data()
                stream.open()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 65_536)
                defer { buf.deallocate() }
                while stream.hasBytesAvailable {
                    let n = stream.read(buf, maxLength: 65_536)
                    if n > 0 { bodyData.append(buf, count: n) }
                }
                stream.close()
                hydrated.httpBody = bodyData
            }
            MCPHTTPMockURLProtocolState.shared.capturedRequest = hydrated
            let (response, data) = try handler(hydrated)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class MCPHTTPMockURLProtocolState: @unchecked Sendable {
    static let shared = MCPHTTPMockURLProtocolState()
    var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    var capturedRequest: URLRequest?
}
