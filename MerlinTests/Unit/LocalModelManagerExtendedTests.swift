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
        // Shell command must contain the binary name and context length
        XCTAssertTrue(instr!.shellCommand.contains("mistralrs"))
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
        XCTAssertTrue(instr!.shellCommand.contains("vllm"))
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
