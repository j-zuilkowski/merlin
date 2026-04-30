# Phase 127a — Model Manager Wiring Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 126b complete: all 6 provider managers implemented. All prior tests pass.

New surface introduced in phase 127b:

  `AppState`:
  - `var localModelManagers: [String: any LocalModelManagerProtocol]` — keyed by providerID
  - `func manager(for providerID: String) -> (any LocalModelManagerProtocol)?`
  - `func applyAdvisory(_ advisory: ParameterAdvisory) async throws` — routes to active manager

  `AgenticEngine`:
  - `var isReloadingModel: Bool` — true while a reload is in progress; pauses the run loop
  - `func pauseForReload() async` — sets isReloadingModel = true, waits for it to clear

  `ProviderConfig`:
  - `var localModelManagerID: String?` — maps a provider config to its manager type

TDD coverage:
  File 1 — MerlinTests/Unit/ModelManagerWiringTests.swift

---

## Write to: MerlinTests/Unit/ModelManagerWiringTests.swift

```swift
import XCTest
@testable import Merlin

// MARK: - Stubs

private actor StubReloadableManager: LocalModelManagerProtocol {
    let providerID: String
    let capabilities: ModelManagerCapabilities
    var reloadCallCount = 0
    var lastReloadConfig: LocalModelConfig?

    init(providerID: String) {
        self.providerID = providerID
        self.capabilities = ModelManagerCapabilities(
            canReloadAtRuntime: true,
            supportedLoadParams: [.contextLength, .gpuLayers]
        )
    }

    func loadedModels() async throws -> [LoadedModelInfo] { [] }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        reloadCallCount += 1
        lastReloadConfig = config
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
}

private actor StubRestartRequiredManager: LocalModelManagerProtocol {
    let providerID = "stub-restart"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [.contextLength]
    )
    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {
        throw ModelManagerError.requiresRestart(
            RestartInstructions(shellCommand: "server --ctx 8192", configSnippet: nil, explanation: "restart")
        )
    }
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(shellCommand: "server --ctx 8192", configSnippet: nil, explanation: "restart")
    }
}

// MARK: - Tests

final class ModelManagerWiringTests: XCTestCase {

    // MARK: AppState manager registry

    func testAppStateHasLocalModelManagers() {
        // Compile-time: AppState must have localModelManagers property
        let appState = AppState()
        let _: [String: any LocalModelManagerProtocol] = appState.localModelManagers
    }

    func testAppStateManagerForProviderID() {
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "ollama")
        appState.localModelManagers["ollama"] = stub
        let manager = appState.manager(for: "ollama")
        XCTAssertNotNil(manager)
    }

    func testAppStateManagerReturnsNilForUnknownProvider() {
        let appState = AppState()
        let manager = appState.manager(for: "unknown-provider")
        XCTAssertNil(manager)
    }

    // MARK: applyAdvisory routing

    func testApplyAdvisoryContextLengthCallsReload() async throws {
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "lmstudio")
        appState.localModelManagers["lmstudio"] = stub
        appState.activeLocalProviderID = "lmstudio"

        let advisory = ParameterAdvisory(
            kind: .contextLengthTooSmall,
            parameterName: "contextLength",
            currentValue: "4096",
            suggestedValue: "16384",
            explanation: "Context exceeded.",
            modelID: "qwen2.5-vl-72b",
            detectedAt: Date()
        )
        try await appState.applyAdvisory(advisory)
        let count = await stub.reloadCallCount
        XCTAssertEqual(count, 1, "applyAdvisory(.contextLengthTooSmall) must call manager.reload()")
    }

    func testApplyAdvisoryContextLengthSetsCorrectValue() async throws {
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "lmstudio")
        appState.localModelManagers["lmstudio"] = stub
        appState.activeLocalProviderID = "lmstudio"

        let advisory = ParameterAdvisory(
            kind: .contextLengthTooSmall,
            parameterName: "contextLength",
            currentValue: "4096",
            suggestedValue: "16384",
            explanation: "Context exceeded.",
            modelID: "qwen2.5-vl-72b",
            detectedAt: Date()
        )
        try await appState.applyAdvisory(advisory)
        let config = await stub.lastReloadConfig
        XCTAssertEqual(config?.contextLength, 16384)
    }

    func testApplyAdvisoryRestartRequiredPublishesInstructions() async {
        let appState = AppState()
        let stub = StubRestartRequiredManager()
        appState.localModelManagers["stub-restart"] = stub
        appState.activeLocalProviderID = "stub-restart"

        let advisory = ParameterAdvisory(
            kind: .contextLengthTooSmall,
            parameterName: "contextLength",
            currentValue: "4096",
            suggestedValue: "8192",
            explanation: "Context exceeded.",
            modelID: "model",
            detectedAt: Date()
        )
        do {
            try await appState.applyAdvisory(advisory)
        } catch ModelManagerError.requiresRestart(let instr) {
            XCTAssertFalse(instr.shellCommand.isEmpty)
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // If applyAdvisory stores the instructions instead of rethrowing, check that:
        // XCTAssertNotNil(appState.pendingRestartInstructions)
    }

    func testApplyInferenceAdvisoryDoesNotCallReload() async throws {
        // Temperature/maxTokens advisories should update AppSettings, not reload the model
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "lmstudio")
        appState.localModelManagers["lmstudio"] = stub
        appState.activeLocalProviderID = "lmstudio"

        let advisory = ParameterAdvisory(
            kind: .maxTokensTooLow,
            parameterName: "maxTokens",
            currentValue: "1024",
            suggestedValue: "2048",
            explanation: "Truncated.",
            modelID: "model",
            detectedAt: Date()
        )
        try await appState.applyAdvisory(advisory)
        let count = await stub.reloadCallCount
        XCTAssertEqual(count, 0, "Inference-param advisories must not call manager.reload()")
    }

    // MARK: AgenticEngine reload pause

    func testAgenticEngineHasIsReloadingModelProperty() {
        let engine = EngineFactory.make()
        let _: Bool = engine.isReloadingModel
    }

    func testAgenticEngineIsReloadingModelDefaultsFalse() {
        let engine = EngineFactory.make()
        XCTAssertFalse(engine.isReloadingModel)
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
Expected: **BUILD FAILED** — `AppState.localModelManagers`, `AppState.applyAdvisory`, `AppState.activeLocalProviderID`, `AgenticEngine.isReloadingModel` not defined.

## Commit
```bash
git add MerlinTests/Unit/ModelManagerWiringTests.swift
git commit -m "Phase 127a — ModelManagerWiringTests (failing)"
```
