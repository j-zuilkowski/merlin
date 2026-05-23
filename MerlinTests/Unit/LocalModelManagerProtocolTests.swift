import XCTest
@testable import Merlin

// MARK: - Minimal stub for compile + capability tests

private struct StubRuntimeManager: LocalModelManagerProtocol {
    let providerID = "stub-runtime"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [.contextLength, .gpuLayers]
    )

    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {}
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
    func reloadedModelID(afterApplying config: LocalModelConfig, to modelID: String) -> String { modelID }
}

private struct StubRestartOnlyManager: LocalModelManagerProtocol {
    let providerID = "stub-restart"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [.contextLength, .gpuLayers, .cpuThreads]
    )

    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {
        let instructions = restartInstructions(modelID: modelID, config: config)!
        throw ModelManagerError.requiresRestart(instructions)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(
            shellCommand: "stub-server --model \(modelID)",
            configSnippet: nil,
            explanation: "Stub provider requires restart."
        )
    }
    func reloadedModelID(afterApplying config: LocalModelConfig, to modelID: String) -> String { modelID }
}

// MARK: - Tests

final class LocalModelManagerProtocolTests: XCTestCase {

    // MARK: Type existence (compile-time failures without phase 125b)

    func testLoadParamEnumExists() {
        let _: LoadParam = .contextLength
        let _: LoadParam = .gpuLayers
        let _: LoadParam = .cpuThreads
        let _: LoadParam = .flashAttention
        let _: LoadParam = .cacheTypeK
        let _: LoadParam = .cacheTypeV
        let _: LoadParam = .ropeFrequencyBase
        let _: LoadParam = .batchSize
        let _: LoadParam = .useMmap
        let _: LoadParam = .useMlock
    }

    func testLocalModelConfigFieldsExist() {
        var config = LocalModelConfig()
        config.contextLength = 16384
        config.gpuLayers = -1
        config.cpuThreads = 8
        config.flashAttention = true
        config.cacheTypeK = "q8_0"
        config.cacheTypeV = "q8_0"
        config.ropeFrequencyBase = 1_000_000.0
        config.batchSize = 512
        config.useMmap = true
        config.useMlock = false
        XCTAssertEqual(config.contextLength, 16384)
        XCTAssertEqual(config.gpuLayers, -1)
    }

    func testModelManagerCapabilitiesFieldsExist() {
        let caps = ModelManagerCapabilities(
            canReloadAtRuntime: true,
            supportedLoadParams: [.contextLength, .gpuLayers]
        )
        XCTAssertTrue(caps.canReloadAtRuntime)
        XCTAssertTrue(caps.supportedLoadParams.contains(.contextLength))
    }

    func testLoadedModelInfoFieldsExist() {
        let info = LoadedModelInfo(modelID: "qwen2.5-coder:32b", knownConfig: LocalModelConfig())
        XCTAssertEqual(info.modelID, "qwen2.5-coder:32b")
    }

    func testRestartInstructionsFieldsExist() {
        let instr = RestartInstructions(
            shellCommand: "ollama run qwen2.5",
            configSnippet: "PARAMETER num_ctx 16384",
            explanation: "Context length requires model restart."
        )
        XCTAssertFalse(instr.shellCommand.isEmpty)
    }

    func testModelManagerErrorCasesExist() {
        let instr = RestartInstructions(shellCommand: "cmd", configSnippet: nil, explanation: "e")
        let _: ModelManagerError = .requiresRestart(instr)
        let _: ModelManagerError = .providerUnavailable
        let _: ModelManagerError = .reloadFailed("reason")
        let _: ModelManagerError = .parameterNotSupported(.flashAttention)
    }

    // MARK: Protocol conformance

    func testStubRuntimeManagerConformsToProtocol() {
        let manager: any LocalModelManagerProtocol = StubRuntimeManager()
        XCTAssertTrue(manager.capabilities.canReloadAtRuntime)
    }

    func testStubRestartOnlyManagerThrowsRequiresRestart() async {
        let manager: any LocalModelManagerProtocol = StubRestartOnlyManager()
        do {
            try await manager.reload(modelID: "model", config: LocalModelConfig())
            XCTFail("Expected ModelManagerError.requiresRestart")
        } catch ModelManagerError.requiresRestart(let instr) {
            XCTAssertFalse(instr.shellCommand.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRestartInstructionsReturnedWhenCannotReload() {
        let manager = StubRestartOnlyManager()
        let instr = manager.restartInstructions(modelID: "model", config: LocalModelConfig())
        XCTAssertNotNil(instr)
        XCTAssertFalse(instr!.shellCommand.isEmpty)
    }

    // MARK: LMStudioModelManager capability assertions

    func testLMStudioManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = LMStudioModelManager(baseURL: URL(string: "http://localhost:1234")!)
    }

    func testLMStudioCapabilitiesCanReloadAtRuntime() {
        let manager = LMStudioModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertTrue(manager.capabilities.canReloadAtRuntime)
    }

    func testLMStudioCapabilitiesIncludeContextLength() {
        let manager = LMStudioModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.contextLength))
    }

    func testLMStudioCapabilitiesIncludeFlashAttention() {
        let manager = LMStudioModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.flashAttention))
    }

    func testLMStudioCapabilitiesIncludeCacheTypeK() {
        let manager = LMStudioModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.cacheTypeK))
    }

    // MARK: OllamaModelManager capability assertions

    func testOllamaManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = OllamaModelManager(baseURL: URL(string: "http://localhost:11434")!)
    }

    func testOllamaCapabilitiesCanReloadAtRuntime() {
        let manager = OllamaModelManager(baseURL: URL(string: "http://localhost:11434")!)
        XCTAssertTrue(manager.capabilities.canReloadAtRuntime)
    }

    func testOllamaCapabilitiesIncludeUseMmap() {
        let manager = OllamaModelManager(baseURL: URL(string: "http://localhost:11434")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.useMmap))
    }

    func testOllamaCapabilitiesDoNotIncludeFlashAttention() {
        let manager = OllamaModelManager(baseURL: URL(string: "http://localhost:11434")!)
        XCTAssertFalse(manager.capabilities.supportedLoadParams.contains(.flashAttention))
    }

    func testOllamaReloadedModelIDUsesMerlinVariant() {
        let manager = OllamaModelManager(baseURL: URL(string: "http://localhost:11434")!)
        XCTAssertEqual(
            manager.reloadedModelID(afterApplying: LocalModelConfig(contextLength: 8192), to: "qwen3-coder"),
            "qwen3-coder-merlin"
        )
        XCTAssertEqual(
            manager.reloadedModelID(afterApplying: LocalModelConfig(contextLength: 8192), to: "qwen3-coder-merlin"),
            "qwen3-coder-merlin"
        )
    }

    func testOllamaLoadedModelsPrefersRunningModelsEndpoint() async throws {
        let session = Self.makeMockSession { request in
            switch request.url?.path {
            case "/api/ps":
                return Self.okResponse(
                    for: request,
                    data: Data(#"{"models":[{"name":"qwen3-coder-merlin"}]}"#.utf8)
                )
            case "/api/show":
                return Self.okResponse(
                    for: request,
                    data: Data(#"{"parameters":"num_ctx 8192\nnum_gpu -1\nuse_mmap true"}"#.utf8)
                )
            case "/api/tags":
                return Self.okResponse(
                    for: request,
                    data: Data(#"{"models":[{"name":"downloaded-only"}]}"#.utf8)
                )
            default:
                return Self.okResponse(for: request, data: Data(#"{"models":[]}"#.utf8))
            }
        }
        let manager = OllamaModelManager(
            baseURL: URL(string: "http://localhost:11434")!,
            session: session
        )
        let models = try await manager.loadedModels()
        XCTAssertEqual(models.map(\.modelID), ["qwen3-coder-merlin"])
        XCTAssertEqual(models.first?.knownConfig.contextLength, 8192)
        XCTAssertEqual(models.first?.knownConfig.gpuLayers, -1)
        XCTAssertEqual(models.first?.knownConfig.useMmap, true)
    }

    func testOllamaLoadedModelsFallsBackToTags() async throws {
        let session = Self.makeMockSession { request in
            switch request.url?.path {
            case "/api/ps":
                return (
                    HTTPURLResponse(
                        url: request.url ?? URL(string: "http://localhost")!,
                        statusCode: 404,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            case "/api/tags":
                return Self.okResponse(
                    for: request,
                    data: Data(#"{"models":[{"name":"qwen3-coder"}]}"#.utf8)
                )
            default:
                return Self.okResponse(for: request, data: Data(#"{"models":[]}"#.utf8))
            }
        }
        let manager = OllamaModelManager(
            baseURL: URL(string: "http://localhost:11434")!,
            session: session
        )
        let models = try await manager.loadedModels().map(\.modelID)
        XCTAssertEqual(models, ["qwen3-coder"])
    }

    func testOllamaEnsureContextLengthReloadsWithNextPowerOf2() async throws {
        let capturedModelfile = CapturedStringBox()
        let session = Self.makeMockSession { request in
            switch request.url?.path {
            case "/api/show":
                return Self.okResponse(
                    for: request,
                    data: Data(#"{"parameters":"num_ctx 4096\nnum_gpu -1\nnum_thread 8"}"#.utf8)
                )
            case "/api/create":
                if let body = request.httpBody,
                   let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let modelfile = json["modelfile"] as? String {
                    capturedModelfile.set(modelfile)
                }
                return Self.okResponse(for: request)
            case "/api/generate":
                return Self.okResponse(for: request)
            default:
                return Self.okResponse(for: request)
            }
        }
        let manager = OllamaModelManager(
            baseURL: URL(string: "http://localhost:11434")!,
            session: session
        )
        let reloadedModelID = try await manager.ensureContextLength(modelID: "qwen3-coder", minimumTokens: 20000)
        XCTAssertEqual(reloadedModelID, "qwen3-coder-merlin")
        XCTAssertTrue(capturedModelfile.value?.contains("PARAMETER num_ctx 32768") == true)
        XCTAssertTrue(capturedModelfile.value?.contains("PARAMETER num_gpu -1") == true)
        XCTAssertTrue(capturedModelfile.value?.contains("PARAMETER num_thread 8") == true)
    }
}

extension LocalModelManagerProtocolTests {
    private static func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        LocalManagerMockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LocalManagerMockURLProtocol.self]
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

private final class CapturedStringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String?

    func set(_ value: String) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class LocalManagerMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = LocalManagerMockURLProtocol.handler else {
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
