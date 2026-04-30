# Phase 128a — Model Control UI Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 127b complete: wiring in place. All prior tests pass.

New surface introduced in phase 128b:

  `ModelControlView` — SwiftUI View shown in Settings → Providers for local providers:
    - Accepts a `manager: any LocalModelManagerProtocol` and `providerConfig: ProviderConfig`
    - Shows each LoadParam that `capabilities.supportedLoadParams` contains as an editable field
    - "Apply & Reload" button: calls `manager.reload()` with the edited config
    - For `canReloadAtRuntime = false`: "Apply & Reload" is replaced by "Show Restart Instructions"
    - `RestartInstructionsSheet` — sheet shown when restart is required, with copyable command

  `ModelControlSectionView` — thin wrapper shown in ProviderSettingsView for local providers:
    - Appears as a "Model Control" section below the existing provider config fields
    - Instantiates `ModelControlView` with the right manager from AppState

TDD coverage:
  File 1 — MerlinTests/Unit/ModelControlViewTests.swift
  (Uses NSHostingController to force body evaluation, same pattern as LoRASettingsUITests)

---

## Write to: MerlinTests/Unit/ModelControlViewTests.swift

```swift
import XCTest
import SwiftUI
@testable import Merlin

// MARK: - Stub manager for UI tests

private actor StubRuntimeManagerForUI: LocalModelManagerProtocol {
    let providerID = "lmstudio"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [.contextLength, .gpuLayers, .flashAttention, .cacheTypeK]
    )
    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {}
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
}

private actor StubRestartManagerForUI: LocalModelManagerProtocol {
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
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD FAILED** — `ModelControlView`, `RestartInstructionsSheet`, `ModelControlSectionView` not defined.

## Commit
```bash
git add MerlinTests/Unit/ModelControlViewTests.swift
git commit -m "Phase 128a — ModelControlViewTests (failing)"
```
