import XCTest
@testable import Merlin

final class LlamaCppModelManagerTests: XCTestCase {

    func testCapabilitiesAdvertiseRouterModeAndRuntimeLoadUnload() {
        let manager = LlamaCppModelManager(
            baseURL: URL(string: "http://127.0.0.1:8081/v1")!,
            session: Self.makeMockSession { request in Self.okResponse(for: request) }
        )

        XCTAssertTrue(manager.capabilities.canReloadAtRuntime)
        XCTAssertTrue(manager.capabilities.supportsRouterMode)
        XCTAssertTrue(manager.capabilities.supportsRuntimeModelLoad)
        XCTAssertTrue(manager.capabilities.supportsRuntimeModelUnload)
        XCTAssertEqual(manager.capabilities.supportedLoadParams, [
            .contextLength,
            .gpuLayers,
            .cpuThreads,
            .flashAttention,
            .cacheTypeK,
            .cacheTypeV,
            .ropeFrequencyBase,
            .batchSize,
            .useMmap,
            .useMlock,
        ])
    }

    func testLoadedModelsReadsRouterCatalogFromModelsEndpoint() async throws {
        let session = Self.makeMockSession { request in
            XCTAssertEqual(request.url?.path, "/models")
            let body = #"{"models":[{"id":"qwen3-coder","state":"loaded"},{"id":"qwen3-vl","state":"unloaded"}]}"#
            return Self.okResponse(for: request, data: Data(body.utf8))
        }
        let manager = LlamaCppModelManager(baseURL: URL(string: "http://127.0.0.1:8081/v1")!, session: session)

        let models = try await manager.loadedModels()
        XCTAssertEqual(models.map(\.modelID), ["qwen3-coder", "qwen3-vl"])
        XCTAssertEqual(models.first?.exposure, .runtimeLoaded)
    }

    func testEnsureModelLoadedSkipsAlreadyLoadedModel() async throws {
        let postCounter = RequestCounter()
        let session = Self.makeMockSession { request in
            if request.httpMethod == "POST" {
                postCounter.increment()
            }
            let body = #"{"models":[{"id":"qwen3-coder","state":"loaded"}]}"#
            return Self.okResponse(for: request, data: Data(body.utf8))
        }
        let manager = LlamaCppModelManager(baseURL: URL(string: "http://127.0.0.1:8081/v1")!, session: session)

        try await manager.ensureModelLoaded(modelID: "qwen3-coder")
        XCTAssertEqual(postCounter.value, 0)
    }

    func testEnsureModelLoadedPostsModelsLoadWhenUnloaded() async throws {
        let capturedBody = CapturedDataBox()
        let session = Self.makeMockSession { request in
            switch (request.httpMethod ?? "GET", request.url?.path ?? "") {
            case ("GET", "/models"):
                let body = #"{"models":[{"id":"qwen3-vl","state":"unloaded"}]}"#
                return Self.okResponse(for: request, data: Data(body.utf8))
            case ("POST", "/models/load"):
                capturedBody.set(request.httpBody ?? Data())
                return Self.okResponse(for: request)
            default:
                return Self.okResponse(for: request)
            }
        }
        let manager = LlamaCppModelManager(baseURL: URL(string: "http://127.0.0.1:8081/v1")!, session: session)

        try await manager.ensureModelLoaded(modelID: "qwen3-vl")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(capturedBody.value)) as? [String: Any])
        XCTAssertEqual(json["id"] as? String, "qwen3-vl")
    }

    func testUnloadModelPostsModelsUnload() async throws {
        let capturedBody = CapturedDataBox()
        let session = Self.makeMockSession { request in
            if request.url?.path == "/models/unload" {
                capturedBody.set(request.httpBody ?? Data())
            }
            return Self.okResponse(for: request)
        }
        let manager = LlamaCppModelManager(baseURL: URL(string: "http://127.0.0.1:8081/v1")!, session: session)

        try await manager.unloadModel(modelID: "qwen3-vl")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(capturedBody.value)) as? [String: Any])
        XCTAssertEqual(json["id"] as? String, "qwen3-vl")
    }

    func testSingleModelServerFallsBackToRestartInstructions() async {
        let session = Self.makeMockSession { request in
            switch request.url?.path {
            case "/models":
                return (
                    HTTPURLResponse(
                        url: request.url ?? URL(string: "http://localhost")!,
                        statusCode: 404,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            case "/v1/models":
                let body = #"{"data":[{"id":"qwen3-coder","object":"model"}]}"#
                return Self.okResponse(for: request, data: Data(body.utf8))
            default:
                return Self.okResponse(for: request)
            }
        }
        let manager = LlamaCppModelManager(baseURL: URL(string: "http://127.0.0.1:8081/v1")!, session: session)

        do {
            try await manager.ensureModelLoaded(modelID: "qwen3-coder")
            XCTFail("Expected restart guidance for non-router server mode")
        } catch ModelManagerError.requiresRestart(let instructions) {
            XCTAssertFalse(instructions.shellCommand.isEmpty)
            XCTAssertTrue(instructions.shellCommand.contains("/opt/homebrew/bin/llama-server"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRestartInstructionsUseSingleRouterServer() {
        let manager = LlamaCppModelManager(
            baseURL: URL(string: "http://127.0.0.1:8081/v1")!,
            session: Self.makeMockSession { request in Self.okResponse(for: request) }
        )
        let instructions = manager.restartInstructions(
            modelID: "qwen3-coder",
            config: LocalModelConfig(contextLength: 32_768, gpuLayers: -1)
        )

        XCTAssertNotNil(instructions)
        XCTAssertTrue(instructions?.shellCommand.contains("/opt/homebrew/bin/llama-server") == true)
        XCTAssertTrue(instructions?.shellCommand.contains("--host 127.0.0.1") == true)
        XCTAssertTrue(instructions?.shellCommand.contains("--port 8081") == true)
        XCTAssertTrue(instructions?.shellCommand.contains("--models-dir \"$MODEL_DIR\"") == true)
        XCTAssertTrue(instructions?.shellCommand.contains("--models-preset \"$PRESET_FILE\"") == true)
        XCTAssertTrue(instructions?.shellCommand.contains("router-preset.ini") == true)
        XCTAssertFalse(instructions?.shellCommand.contains("--model-dir ") == true)
        XCTAssertFalse(instructions?.shellCommand.contains("--props ") == true)
        XCTAssertFalse(instructions?.shellCommand.contains("&&") == true)
        XCTAssertFalse(instructions?.shellCommand.contains("vision") == true)
    }
}

extension LlamaCppModelManagerTests {
    private static func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        LlamaCppMockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LlamaCppMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func okResponse(for request: URLRequest, data: Data = Data()) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url ?? URL(string: "http://localhost")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!,
            data
        )
    }
}

private final class CapturedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Data?

    func set(_ value: Data) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    var value: Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class LlamaCppMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = LlamaCppMockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            var hydrated = request
            if hydrated.httpBody == nil, let stream = hydrated.httpBodyStream {
                var bodyData = Data()
                stream.open()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65_536)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let n = stream.read(buffer, maxLength: 65_536)
                    if n > 0 { bodyData.append(buffer, count: n) }
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
