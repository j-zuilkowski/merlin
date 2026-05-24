# Phase 338b — llama.cpp Router Provider Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 338a complete: llama.cpp router-provider tests are failing for the new
surface area.

Recommended execution model: GPT-5.3-Codex.

Implement llama.cpp as a first-class local provider backed by one router-mode
`llama-server`. Do not model the general and vision pair as two provider
processes.

---

## Edit: Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift

Extend the local manager abstraction with router semantics while preserving
defaults for existing managers:

- `ModelManagerCapabilities.supportsRouterMode: Bool = false`
- `ModelManagerCapabilities.supportsRuntimeModelLoad: Bool = false`
- `ModelManagerCapabilities.supportsRuntimeModelUnload: Bool = false`
- `LocalModelManagerProtocol.ensureModelLoaded(modelID:) async throws`
- `LocalModelManagerProtocol.unloadModel(modelID:) async throws`

Default protocol implementations should throw a clear unsupported-operation
manager error so Ollama, Jan, LocalAI, mistral.rs, vLLM, and LM Studio behavior
does not change.

## Write to: Merlin/Providers/LocalModelManager/LlamaCppModelManager.swift

Add `LlamaCppModelManager: LocalModelManagerProtocol`.

Required behavior:

- `id == "llamacpp"`.
- Capabilities advertise router mode and runtime load/unload.
- Normalize configured OpenAI base URLs like `http://localhost:8081/v1` to the
  server root for router endpoints.
- `loadedModels(config:)` tries router catalog discovery first:
  - `GET /models`
  - fallback `GET /v1/models`
- Decode router-aware model entries with `id` plus optional `state`/`status`.
  Treat `loaded` and `active` as loaded. Treat `unloaded`, `sleeping`, or
  missing runtime state as discovered but not necessarily loaded.
- `ensureModelLoaded(modelID:)` no-ops when the router catalog says the model is
  already loaded; otherwise POSTs JSON to `/models/load`.
- `unloadModel(modelID:)` POSTs JSON to `/models/unload`.
- If the server only exposes a plain OpenAI-compatible `/v1/models` response
  and router endpoints are unavailable, return restart guidance instead of
  claiming runtime swapping succeeded.
- `restartInstructions(config:)` returns a one-process router-mode command using
  `/opt/homebrew/bin/llama-server`, host `127.0.0.1`, port `8081`, and either a
  model directory or preset path. The command must not launch separate general
  and vision instances.

Prefer small private request/response structs and keep HTTP behavior consistent
with the existing local managers.

## Edit: Merlin/Providers/ProviderConfig.swift

Add a disabled default provider:

- `id: "llamacpp"`
- `displayName: "llama.cpp"`
- `baseURL: "http://localhost:8081/v1"`
- empty `model`
- `kind: .openAICompatible`
- `supportsVision: true`
- `isEnabled: false`
- `localModelManagerID: "llamacpp"`

The provider should appear in Settings as inventory, but it must not imply any
slot is configured. Slot assignment behavior is handled in phase 339.

## Edit: Merlin/App/AppState.swift

Wire `localModelManagerID == "llamacpp"` to `LlamaCppModelManager` in the same
lookup path used by the other local providers.

## Edit: Registry/Calibration Tests As Required

Update the existing provider-count and calibration-default assertions required
by 338a. Keep the change narrow and avoid unrelated provider registry refactors.

## Edit: Immediate llama.cpp Documentation

Update the documentation directly coupled to the new provider so the shipped
feature is not undocumented:

- `README.md` - add llama.cpp to the local provider table and LoRA/GGUF serving
  notes.
- `FEATURES.md` - add llama.cpp to LLM Providers and Local Model Management.
- `Merlin/Docs/UserGuide.md` - add llama.cpp to Providers, local setup, and
  LoRA deployment notes.
- `Merlin/Docs/DeveloperManual.md` - add `LlamaCppModelManager`, provider
  defaults, router-mode load/unload, and virtual provider ID behavior.
- `docs/local-provider-configs/README.md` - add llama.cpp install, router-mode
  launch, model-pair, mmproj, LoRA fuse+convert, memory, and one-local-provider
  pair guidance.
- `docs/local-provider-configs/smoke-test.sh` - add `llamacpp` on
  `http://localhost:8081/v1` to usage, dispatch, and `all`.
- `docs/local-provider-configs/benchmark-throughput.sh` - add `llamacpp` on
  `http://localhost:8081/v1` to dispatch and `all`.
- `docs/local-provider-configs/RESULTS.md` - add llama.cpp as pending
  calibration unless fresh live results are produced during this phase.

Do not edit historical release notes or old handoff snapshots for this provider
unless the file presents itself as current release documentation.

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```
Expected: all unit tests pass, including the new llama.cpp router-provider
tests from 338a.

```bash
xcodebuild -scheme MerlinTests-Live build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head
```
Expected: `** TEST BUILD SUCCEEDED **`.

## Commit
```bash
git add Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift \
        Merlin/Providers/LocalModelManager/LlamaCppModelManager.swift \
        Merlin/Providers/ProviderConfig.swift \
        Merlin/App/AppState.swift \
        README.md \
        FEATURES.md \
        Merlin/Docs/UserGuide.md \
        Merlin/Docs/DeveloperManual.md \
        docs/local-provider-configs/README.md \
        docs/local-provider-configs/smoke-test.sh \
        docs/local-provider-configs/benchmark-throughput.sh \
        docs/local-provider-configs/RESULTS.md \
        MerlinTests/Unit/LlamaCppModelManagerTests.swift \
        MerlinTests/Unit/ProviderConfigLlamaCppTests.swift \
        MerlinTests/Unit/ModelManagerWiringTests.swift \
        MerlinTests/Unit/ProviderRegistryTests.swift \
        MerlinTests/Unit/ProviderConfigCalibrationDefaultsTests.swift \
        phases/phase-338b-llamacpp-router-provider.md
git commit -m "Phase 338b — llama.cpp first-class router provider"
```
