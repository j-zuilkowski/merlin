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
}
