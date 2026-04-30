import XCTest
import SwiftUI
@testable import Merlin

// MARK: - Stub manager for UI tests

private struct StubRuntimeManagerForUI: LocalModelManagerProtocol {
    let providerID = "lmstudio"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [.contextLength, .gpuLayers, .flashAttention, .cacheTypeK]
    )
    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {}
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
}

private struct StubRestartManagerForUI: LocalModelManagerProtocol {
    let providerID = "vllm"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [.contextLength, .gpuLayers]
    )
    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {
        throw ModelManagerError.requiresRestart(
            RestartInstructions(shellCommand: "vllm serve model", configSnippet: nil, explanation: "restart needed")
        )
    }
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(shellCommand: "vllm serve model", configSnippet: nil, explanation: "restart needed")
    }
}

// MARK: - Tests

@MainActor
final class ModelControlViewTests: XCTestCase {

    func testModelControlViewExists() {
        // Compile-time proof the type exists.
        let manager = StubRuntimeManagerForUI()
        let _ = ModelControlView(manager: manager, modelID: "qwen2.5-vl-72b")
    }

    func testModelControlViewRendersWithoutCrash() {
        let manager = StubRuntimeManagerForUI()
        let view = ModelControlView(manager: manager, modelID: "qwen2.5-vl-72b")
        let host = NSHostingController(rootView: view)
        host.loadView()
        XCTAssertNotNil(host.view)
    }

    func testRestartInstructionsSheetExists() {
        let instr = RestartInstructions(
            shellCommand: "server --ctx 16384",
            configSnippet: "context_size: 16384",
            explanation: "Restart required."
        )
        let _ = RestartInstructionsSheet(instructions: instr)
    }

    func testRestartInstructionsSheetRendersWithoutCrash() {
        let instr = RestartInstructions(
            shellCommand: "server --ctx 16384",
            configSnippet: nil,
            explanation: "Restart required."
        )
        let view = RestartInstructionsSheet(instructions: instr)
        let host = NSHostingController(rootView: view)
        host.loadView()
        XCTAssertNotNil(host.view)
    }

    func testModelControlSectionViewExists() {
        // Compile-time: ModelControlSectionView must exist for the settings integration.
        let manager = StubRuntimeManagerForUI()
        let _ = ModelControlSectionView(manager: manager, modelID: "test-model")
    }

    func testModelControlSectionViewRendersWithoutCrash() {
        let manager = StubRuntimeManagerForUI()
        let view = ModelControlSectionView(manager: manager, modelID: "test-model")
        let host = NSHostingController(rootView: view)
        host.loadView()
        XCTAssertNotNil(host.view)
    }
}
