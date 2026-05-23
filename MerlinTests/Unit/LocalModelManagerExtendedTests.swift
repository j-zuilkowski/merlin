import XCTest
@testable import Merlin

final class LocalModelManagerExtendedTests: XCTestCase {

    // MARK: - JanModelManager

    func testJanManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = JanModelManager(baseURL: URL(string: "http://localhost:1337")!)
    }

    func testJanManagerCanReloadAtRuntime() {
        let manager = JanModelManager(baseURL: URL(string: "http://localhost:1337")!)
        XCTAssertTrue(manager.capabilities.canReloadAtRuntime)
    }

    func testJanManagerSupportsContextLength() {
        let manager = JanModelManager(baseURL: URL(string: "http://localhost:1337")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.contextLength))
    }

    func testJanManagerReturnsNilRestartInstructions() {
        let manager = JanModelManager(baseURL: URL(string: "http://localhost:1337")!)
        let instr = manager.restartInstructions(modelID: "model", config: LocalModelConfig())
        XCTAssertNil(instr, "Jan can reload at runtime, so restartInstructions must be nil")
    }

    func testJanLoadedModelsReadsKnownConfigFromModelJSON() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelDir = tempDir.appendingPathComponent("qwen3-coder", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let json = """
        {"ctx_len":8192,"ngl":-1,"cpu_threads":10}
        """
        try json.data(using: .utf8)?.write(to: modelDir.appendingPathComponent("model.json"))

        let session = Self.makeMockSession { request in
            Self.okResponse(
                for: request,
                data: Data(#"{"data":[{"id":"qwen3-coder"}]}"#.utf8)
            )
        }

        let manager = JanModelManager(
            baseURL: URL(string: "http://localhost:1337")!,
            janModelsDir: tempDir,
            session: session
        )
        let models = try await manager.loadedModels()
        let model = try XCTUnwrap(models.first)
        XCTAssertEqual(model.knownConfig.contextLength, 8192)
        XCTAssertEqual(model.knownConfig.gpuLayers, -1)
        XCTAssertEqual(model.knownConfig.cpuThreads, 10)
    }

    func testJanEnsureContextLengthReloadsWithNextPowerOf2() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelDir = tempDir.appendingPathComponent("qwen3-coder", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let json = """
        {"ctx_len":4096,"ngl":-1,"cpu_threads":8}
        """
        try json.data(using: .utf8)?.write(to: modelDir.appendingPathComponent("model.json"))

        let captured = ExtendedCapturedIntBox()
        let session = Self.makeMockSession { request in
            if request.url?.path == "/v1/models/qwen3-coder/reload",
               let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let context = json["contextLength"] as? Int {
                captured.set(context)
            }
            return Self.okResponse(for: request)
        }

        let manager = JanModelManager(
            baseURL: URL(string: "http://localhost:1337")!,
            janModelsDir: tempDir,
            session: session
        )
        let reloadedModelID = try await manager.ensureContextLength(modelID: "qwen3-coder", minimumTokens: 20000)
        XCTAssertEqual(reloadedModelID, "qwen3-coder")
        XCTAssertEqual(captured.value, 32768)
    }

    // MARK: - LocalAIModelManager

    func testLocalAIManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = LocalAIModelManager(baseURL: URL(string: "http://localhost:8080")!)
    }

    func testLocalAIManagerCannotReloadAtRuntime() {
        let manager = LocalAIModelManager(baseURL: URL(string: "http://localhost:8080")!)
        XCTAssertFalse(manager.capabilities.canReloadAtRuntime)
    }

    func testLocalAIManagerSupportsContextLength() {
        let manager = LocalAIModelManager(baseURL: URL(string: "http://localhost:8080")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.contextLength))
    }

    func testLocalAIManagerReturnsRestartInstructions() {
        let manager = LocalAIModelManager(baseURL: URL(string: "http://localhost:8080")!)
        let config = LocalModelConfig(contextLength: 8192, gpuLayers: -1)
        let instr = manager.restartInstructions(modelID: "mistral-7b", config: config)
        XCTAssertNotNil(instr)
        XCTAssertFalse(instr!.shellCommand.isEmpty)
        XCTAssertTrue(instr!.shellCommand.contains("/opt/homebrew/bin/local-ai run"))
        XCTAssertTrue(instr!.shellCommand.contains("--context-size 8192"))
        XCTAssertFalse(instr!.shellCommand.contains("systemctl"))
    }

    func testLocalAIManagerReloadThrowsRequiresRestart() async {
        let manager = LocalAIModelManager(baseURL: URL(string: "http://localhost:8080")!)
        do {
            try await manager.reload(modelID: "model", config: LocalModelConfig())
            XCTFail("Expected ModelManagerError.requiresRestart")
        } catch ModelManagerError.requiresRestart(let instr) {
            XCTAssertFalse(instr.shellCommand.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - MistralRSModelManager

    func testMistralRSManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = MistralRSModelManager(baseURL: URL(string: "http://localhost:1234")!)
    }

    func testMistralRSManagerCannotReloadAtRuntime() {
        let manager = MistralRSModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertFalse(manager.capabilities.canReloadAtRuntime)
    }

    func testMistralRSManagerReturnsShellCommand() {
        let manager = MistralRSModelManager(baseURL: URL(string: "http://localhost:1234")!)
        var config = LocalModelConfig()
        config.contextLength = 16384
        config.gpuLayers = -1
        let instr = manager.restartInstructions(modelID: "mistral-7b-v0.1.Q4_K_M.gguf", config: config)
        XCTAssertNotNil(instr)
        XCTAssertTrue(instr!.shellCommand.contains("\"$MISTRALRS\" serve -p 1235"))
        XCTAssertTrue(instr!.shellCommand.contains("--quantized-file \"$GGUF_PATH\""))
        XCTAssertTrue(instr!.shellCommand.contains("16384"))
    }

    func testMistralRSManagerReloadThrowsRequiresRestart() async {
        let manager = MistralRSModelManager(baseURL: URL(string: "http://localhost:1234")!)
        do {
            try await manager.reload(modelID: "model", config: LocalModelConfig())
            XCTFail("Expected ModelManagerError.requiresRestart")
        } catch ModelManagerError.requiresRestart(_) {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMistralRSManagerSupportsFlashAttention() {
        let manager = MistralRSModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.flashAttention))
    }

    // MARK: - VLLMModelManager

    func testVLLMManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = VLLMModelManager(baseURL: URL(string: "http://localhost:8000")!)
    }

    func testVLLMManagerCannotReloadAtRuntime() {
        let manager = VLLMModelManager(baseURL: URL(string: "http://localhost:8000")!)
        XCTAssertFalse(manager.capabilities.canReloadAtRuntime)
    }

    func testVLLMManagerReturnsShellCommand() {
        let manager = VLLMModelManager(baseURL: URL(string: "http://localhost:8000")!)
        var config = LocalModelConfig()
        config.contextLength = 32768
        let instr = manager.restartInstructions(modelID: "Qwen/Qwen2.5-Coder-32B-Instruct", config: config)
        XCTAssertNotNil(instr)
        XCTAssertTrue(instr!.shellCommand.contains("\"$VLLM\" serve \"$MODEL_DIR\""))
        XCTAssertTrue(instr!.shellCommand.contains("--served-model-name \"$SERVED_MODEL_NAME\""))
        XCTAssertTrue(instr!.shellCommand.contains("32768"))
    }

    func testVLLMManagerReloadThrowsRequiresRestart() async {
        let manager = VLLMModelManager(baseURL: URL(string: "http://localhost:8000")!)
        do {
            try await manager.reload(modelID: "model", config: LocalModelConfig())
            XCTFail("Expected ModelManagerError.requiresRestart")
        } catch ModelManagerError.requiresRestart(_) {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVLLMManagerSupportsCacheTypeK() {
        let manager = VLLMModelManager(baseURL: URL(string: "http://localhost:8000")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.cacheTypeK))
    }
}

extension LocalModelManagerExtendedTests {
    private static func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        LocalManagerExtendedMockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LocalManagerExtendedMockURLProtocol.self]
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

private final class ExtendedCapturedIntBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int?

    func set(_ value: Int) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    var value: Int? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class LocalManagerExtendedMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = LocalManagerExtendedMockURLProtocol.handler else {
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
