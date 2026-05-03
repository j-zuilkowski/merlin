import XCTest
@testable import Merlin

final class LMStudioContextAutoResizeTests: XCTestCase {

    func testNoResizeWhenContextSufficient() async throws {
        var reloadCallCount = 0
        let session = makeMockSession { request in
            if let path = request.url?.path, path.contains("v0") && path.hasSuffix("models") {
                return self.modelsResponse(id: "qwen/qwen3.6-27b", loadedCtx: 32768, maxCtx: 262144)
            }
            if let path = request.url?.path, path.contains("unload") || path.contains("load") {
                reloadCallCount += 1
            }
            return self.okResponse(for: request)
        }
        let manager = LMStudioModelManager(
            baseURL: URL(string: "http://localhost:1234")!,
            session: session
        )
        try await manager.ensureContextLength(modelID: "qwen/qwen3.6-27b", minimumTokens: 8192)
        XCTAssertEqual(reloadCallCount, 0, "reload must not be called when loaded context is sufficient")
    }

    func testResizesWhenContextInsufficient() async throws {
        var reloadCallCount = 0
        let session = makeMockSession { request in
            if let path = request.url?.path, path.contains("v0") && path.hasSuffix("models") {
                return self.modelsResponse(id: "qwen/qwen3.6-27b", loadedCtx: 4096, maxCtx: 262144)
            }
            if let path = request.url?.path, path.contains("unload") || path.contains("load") {
                reloadCallCount += 1
            }
            return self.okResponse(for: request)
        }
        let manager = LMStudioModelManager(
            baseURL: URL(string: "http://localhost:1234")!,
            session: session
        )
        try await manager.ensureContextLength(modelID: "qwen/qwen3.6-27b", minimumTokens: 32768)
        XCTAssertGreaterThan(reloadCallCount, 0, "reload must be called when loaded context is insufficient")
    }

    func testResizeTargetIsPowerOf2() async throws {
        var capturedContextLength: Int?
        let session = makeMockSession { request in
            if let path = request.url?.path, path.contains("v0") && path.hasSuffix("models") {
                return self.modelsResponse(id: "qwen/qwen3.6-27b", loadedCtx: 4096, maxCtx: 262144)
            }
            if let path = request.url?.path, path.hasSuffix("load"),
               let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let config = json["config"] as? [String: Any],
               let ctx = config["contextLength"] as? Int {
                capturedContextLength = ctx
            }
            return self.okResponse(for: request)
        }
        let manager = LMStudioModelManager(
            baseURL: URL(string: "http://localhost:1234")!,
            session: session
        )
        try await manager.ensureContextLength(modelID: "qwen/qwen3.6-27b", minimumTokens: 20000)
        XCTAssertEqual(capturedContextLength, 32768,
                       "context length target must be next power-of-2 above minimumTokens")
    }

    func testHandlesV0APIFailureGracefully() async {
        let session = makeMockSession { _ in throw URLError(.notConnectedToInternet) }
        let manager = LMStudioModelManager(
            baseURL: URL(string: "http://localhost:1234")!,
            session: session
        )
        do {
            try await manager.ensureContextLength(modelID: "qwen/qwen3.6-27b", minimumTokens: 32768)
        } catch {
            // Expected — caller uses try? so this is fine
        }
    }
}

extension LMStudioContextAutoResizeTests {
    private func modelsResponse(id: String, loadedCtx: Int, maxCtx: Int) -> (HTTPURLResponse, Data) {
        let json = """
        {"data":[{"id":"\(id)","object":"model","state":"loaded","loaded_context_length":\(loadedCtx),"max_context_length":\(maxCtx)}]}
        """
        return okResponse(data: json.data(using: .utf8) ?? Data())
    }

    private func okResponse(for request: URLRequest = URLRequest(url: URL(string: "http://localhost")!), data: Data = Data()) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url ?? URL(string: "http://localhost")!,
                         statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        CtxResizeMockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CtxResizeMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class CtxResizeMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = CtxResizeMockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            // URLSession converts httpBody to httpBodyStream when routing through URLProtocol.
            // Re-materialise the body so the handler can read it as Data.
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
