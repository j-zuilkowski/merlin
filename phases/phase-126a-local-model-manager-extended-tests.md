# Phase 126a — Local Model Manager Extended Tests (Jan, LocalAI, Mistral.rs, vLLM)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 125b complete: Protocol + LMStudio + Ollama managers. All prior tests pass.

New surface introduced in phase 126b:

  `JanModelManager` — Jan.ai REST API + model.json editing
    providerID = "jan"
    canReloadAtRuntime = true
    supportedLoadParams: .contextLength, .gpuLayers, .cpuThreads

  `LocalAIModelManager` — YAML config editing + restart
    providerID = "localai"
    canReloadAtRuntime = false  (requires server restart)
    supportedLoadParams: .contextLength, .gpuLayers, .cpuThreads, .ropeFrequencyBase, .batchSize, .useMmap

  `MistralRSModelManager` — advisory + restart instructions only
    providerID = "mistralrs"
    canReloadAtRuntime = false
    supportedLoadParams: .contextLength, .gpuLayers, .cpuThreads, .ropeFrequencyBase,
                         .flashAttention, .batchSize (all via CLI flags at start)

  `VLLMModelManager` — advisory + restart instructions only
    providerID = "vllm"
    canReloadAtRuntime = false
    supportedLoadParams: .contextLength, .gpuLayers, .ropeFrequencyBase, .batchSize,
                         .cacheTypeK (--kv-cache-dtype)

TDD coverage:
  File 1 — MerlinTests/Unit/LocalModelManagerExtendedTests.swift

---

## Write to: MerlinTests/Unit/LocalModelManagerExtendedTests.swift

```swift
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
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD FAILED** — `JanModelManager`, `LocalAIModelManager`, `MistralRSModelManager`, `VLLMModelManager` not defined.

## Commit
```bash
git add MerlinTests/Unit/LocalModelManagerExtendedTests.swift
git commit -m "Phase 126a — LocalModelManagerExtendedTests (failing)"
```
