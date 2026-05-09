import XCTest
@testable import Merlin

final class XcalibreKAGPluginTests: XCTestCase {

    // MARK: - Helpers

    private func makePlugin(
        handler: @escaping (URLRequest) -> (Data, URLResponse)
    ) -> XcalibreKAGPlugin {
        let session = URLSession.mock(handler: handler)
        return XcalibreKAGPlugin(
            baseURL: URL(string: "http://xcalibre.local")!,
            token: "test-token",
            session: session
        )
    }

    // MARK: - writeTriples

    func test_writeTriples_sends_post_with_correct_body() async throws {
        var capturedRequest: URLRequest?

        let plugin = makePlugin { req in
            capturedRequest = req
            let body = """
            {"written":1}
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201,
                                       httpVersion: nil, headerFields: nil)!
            return (body, resp)
        }

        let triple = KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                               domainId: "electronics", source: .session, confidence: 0.9)
        try await plugin.writeTriples([triple])

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertTrue(req.url?.path == "/api/v1/graph/triples")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")

        let bodyData = try XCTUnwrap(req.httpBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        let triples = json?["triples"] as? [[String: Any]]
        XCTAssertEqual(triples?.count, 1)
        XCTAssertEqual(triples?.first?["subject"] as? String, "U4")
        XCTAssertEqual(triples?.first?["predicate"] as? String, "shares_net")
        XCTAssertEqual(triples?.first?["object"] as? String, "VCC")
    }

    func test_writeTriples_throws_on_401() async {
        let plugin = makePlugin { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
            return (Data(), resp)
        }

        do {
            try await plugin.writeTriples([
                KAGTriple(subject: "A", predicate: "b", object: "C",
                          domainId: "", source: .session, confidence: 1.0)
            ])
            XCTFail("Expected throw on 401")
        } catch {
            // expected
        }
    }

    // MARK: - traverse

    func test_traverse_builds_correct_url() async throws {
        var capturedRequest: URLRequest?

        let plugin = makePlugin { req in
            capturedRequest = req
            let body = """
            {"triples":[]}
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (body, resp)
        }

        _ = try await plugin.traverse(anchor: "FnA", hops: 2, domainId: "software")

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.httpMethod, "GET")
        let urlStr = req.url?.absoluteString ?? ""
        XCTAssertTrue(urlStr.contains("/api/v1/graph/traverse"))
        XCTAssertTrue(urlStr.contains("anchor=FnA"))
        XCTAssertTrue(urlStr.contains("hops=2"))
        XCTAssertTrue(urlStr.contains("domain_id=software"))
    }

    func test_traverse_returns_parsed_triples() async throws {
        let plugin = makePlugin { req in
            let body = """
            {"triples":[
                {"subject":"FnA","predicate":"calls","object":"FnB",
                 "domain_id":"software","source":"session","confidence":0.9,
                 "id":"1","source_id":"s1","chunk_index":null,"created_at":0}
            ]}
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (body, resp)
        }

        let result = try await plugin.traverse(anchor: "FnA", hops: 1, domainId: nil)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.subject, "FnA")
        XCTAssertEqual(result.first?.predicate, "calls")
    }

    func test_traverse_throws_on_network_error() async {
        let session = URLSession.mock { _ in
            throw URLError(.notConnectedToInternet)
        }
        let plugin = XcalibreKAGPlugin(
            baseURL: URL(string: "http://xcalibre.local")!,
            token: "tok",
            session: session
        )

        do {
            _ = try await plugin.traverse(anchor: "A", hops: 1, domainId: nil)
            XCTFail("Expected throw on network error")
        } catch {
            // expected
        }
    }
}

// MARK: - URLSession mock helper

extension URLSession {
    static func mock(handler: @escaping (URLRequest) throws -> (Data, URLResponse)) -> URLSession {
        MockURLSession.register(handler: handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MockURLProtocol must be accessible from test target — add to TestHelpers/ if needed.
// For now declare it here:
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, URLResponse))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            var effectiveRequest = request
            if effectiveRequest.httpBody == nil,
               let stream = effectiveRequest.httpBodyStream {
                stream.open()
                defer { stream.close() }
                let bufferSize = 1024
                var data = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let bytesRead = stream.read(buffer, maxLength: bufferSize)
                    if bytesRead > 0 {
                        data.append(buffer, count: bytesRead)
                    } else {
                        break
                    }
                }
                if !data.isEmpty {
                    effectiveRequest.httpBody = data
                }
            }
            let (data, response) = try handler(effectiveRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

enum MockURLSession {
    static func register(handler: @escaping (URLRequest) throws -> (Data, URLResponse)) {
        MockURLProtocol.handler = handler
    }
}
