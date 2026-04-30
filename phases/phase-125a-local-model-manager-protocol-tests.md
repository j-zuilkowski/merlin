# Phase 125a — LocalModelManagerProtocol Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 124b complete: ModelParameterAdvisor in place. All prior tests pass.

## Purpose
Abstract local LLM provider management behind a single protocol so Merlin can
adjust load-time parameters (context length, GPU layers, etc.) and reload models
at runtime for any supported local provider, or gracefully fall back to restart
instructions when the provider requires a server restart.

New surface introduced in phase 125b:

**Types — Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift**

  `LoadParam` — enum of all controllable load-time parameters:
    .contextLength, .gpuLayers, .cpuThreads, .flashAttention,
    .cacheTypeK, .cacheTypeV, .ropeFrequencyBase, .batchSize, .useMmap, .useMlock

  `LocalModelConfig: Sendable` — optional fields for every LoadParam

  `ModelManagerCapabilities: Sendable`:
    - canReloadAtRuntime: Bool
    - supportedLoadParams: Set<LoadParam>

  `LoadedModelInfo: Sendable`:
    - modelID: String
    - knownConfig: LocalModelConfig   (populated with whatever the provider reports)

  `RestartInstructions: Sendable`:
    - shellCommand: String
    - configSnippet: String?
    - explanation: String

  `ModelManagerError: Error, Sendable`:
    - .requiresRestart(RestartInstructions)
    - .providerUnavailable
    - .reloadFailed(String)
    - .parameterNotSupported(LoadParam)

  `protocol LocalModelManagerProtocol: Sendable`:
    - var providerID: String { get }
    - var capabilities: ModelManagerCapabilities { get }
    - func loadedModels() async throws -> [LoadedModelInfo]
    - func reload(modelID: String, config: LocalModelConfig) async throws
    - func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions?

**Implementations — Merlin/Providers/LocalModelManager/**

  `LMStudioModelManager` — REST API + lms CLI fallback
    capabilities: canReloadAtRuntime = true
    supportedLoadParams: all except .useMmap, .useMlock

  `OllamaModelManager` — REST API + Modelfile generation
    capabilities: canReloadAtRuntime = true
    supportedLoadParams: .contextLength, .gpuLayers, .cpuThreads,
                         .ropeFrequencyBase, .batchSize, .useMmap, .useMlock

TDD coverage:
  File 1 — MerlinTests/Unit/LocalModelManagerProtocolTests.swift

---

## Write to: MerlinTests/Unit/LocalModelManagerProtocolTests.swift

```swift
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
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD FAILED** — `LocalModelManagerProtocol`, `LocalModelConfig`, `LMStudioModelManager`, `OllamaModelManager` not defined.

## Commit
```bash
git add MerlinTests/Unit/LocalModelManagerProtocolTests.swift
git commit -m "Phase 125a — LocalModelManagerProtocolTests (failing)"
```
