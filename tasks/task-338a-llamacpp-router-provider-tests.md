# Phase 338a — llama.cpp Router Provider Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 337b complete: CalibrationReportSaver shipped.

Recommended execution model: GPT-5.3-Codex.

llama.cpp is installed on this machine via Homebrew:
`/opt/homebrew/bin/llama-server`, version 9290. GGUF model pairs already exist
locally and should be consumed by one router-mode `llama-server`, not by two
separate server processes.

New surface introduced in phase 338b:
  - `LlamaCppModelManager` - local model manager for a single router-mode
    `llama-server`.
  - First-class default provider config for `llamacpp`.
  - Runtime router operations for loading, unloading, and reporting model
    state by model ID.
  - AppState wiring so local provider refresh/reload paths resolve
    `localModelManagerID == "llamacpp"`.

TDD coverage:
  File 1 - `MerlinTests/Unit/LlamaCppModelManagerTests.swift`:
    `testCapabilitiesAdvertiseRouterModeAndRuntimeLoadUnload` - capabilities
    expose router mode and runtime load/unload support.
    `testLoadedModelsReadsRouterCatalogFromModelsEndpoint` - mocked router
    catalog returns both loaded and unloaded model IDs.
    `testEnsureModelLoadedSkipsAlreadyLoadedModel` - no POST when the target
    model is already loaded.
    `testEnsureModelLoadedPostsModelsLoadWhenUnloaded` - POSTs
    `/models/load` with the selected model ID.
    `testUnloadModelPostsModelsUnload` - POSTs `/models/unload`.
    `testSingleModelServerFallsBackToRestartInstructions` - a non-router
    server response produces restart guidance instead of pretending runtime
    swapping is available.
    `testRestartInstructionsUseSingleRouterServer` - restart guidance launches
    one `llama-server` on port 8081 with a model directory or preset, never
    separate general/vision processes.

  File 2 - `MerlinTests/Unit/ProviderConfigLlamaCppTests.swift`:
    `testDefaultProvidersIncludeDisabledLlamaCppProvider` - default provider
    exists with `id == "llamacpp"`, display name `llama.cpp`, base URL
    `http://localhost:8081/v1`, empty default model, disabled by default,
    `kind == .openAICompatible`, `supportsVision == true`, and
    `localModelManagerID == "llamacpp"`.
    `testDefaultProviderCountIncludesLlamaCpp` - updates the default count
    from 11 to 12.
    `testLocalProviderCalibrationDefaultsIncludeLlamaCpp` - the calibration
    defaults local-provider list includes `llamacpp`.
    `testSlotPickerCanExposeLlamaCppVirtualModelIDs` - registry slot entries
    include `llamacpp:<model-id>` virtual IDs from the router catalog.
    `testVirtualLlamaCppProviderPreservesSelectedModelID` - resolving a
    virtual provider ID produces an OpenAI-compatible provider pointed at the
    selected llama.cpp model.

  File 3 - `MerlinTests/Unit/ModelManagerWiringTests.swift`:
    Add a llama.cpp case proving AppState/manager lookup resolves
    `LlamaCppModelManager` for `localModelManagerID == "llamacpp"`.

---

## Write to: MerlinTests/Unit/LlamaCppModelManagerTests.swift

Use `URLProtocol`-backed HTTP stubs, matching the existing local manager tests.
The manager should be initialized with `baseURL: http://127.0.0.1:8081/v1`
or equivalent test URL, and tests should assert paths and JSON bodies exactly.

Router catalog fixtures should cover both response shapes Merlin may encounter:

```json
{"models":[{"id":"qwen3-coder","state":"loaded"},{"id":"qwen3-vl","state":"unloaded"}]}
```

and the OpenAI-compatible model list fallback:

```json
{"data":[{"id":"qwen3-coder","object":"model"}]}
```

The first shape is router-aware. The second shape is usable for discovery but
must not imply runtime model swapping unless router endpoints succeed.

## Write to: MerlinTests/Unit/ProviderConfigLlamaCppTests.swift

Keep these tests focused on provider defaults, registry virtual IDs, and
calibration defaults. Do not boot `llama-server` in unit tests.

## Edit: MerlinTests/Unit/ProviderRegistryTests.swift

Update the default-provider count assertion to include the new llama.cpp
provider. Prefer moving llama.cpp-specific assertions into
`ProviderConfigLlamaCppTests` so this broad registry test stays small.

## Edit: MerlinTests/Unit/ProviderConfigCalibrationDefaultsTests.swift

Add `llamacpp` to the local provider defaults assertion.

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD FAILED with errors naming missing `LlamaCppModelManager`,
router capability fields, and llama.cpp default-provider wiring.

## Commit
```bash
git add MerlinTests/Unit/LlamaCppModelManagerTests.swift \
        MerlinTests/Unit/ProviderConfigLlamaCppTests.swift \
        MerlinTests/Unit/ModelManagerWiringTests.swift \
        MerlinTests/Unit/ProviderRegistryTests.swift \
        MerlinTests/Unit/ProviderConfigCalibrationDefaultsTests.swift \
        tasks/task-338a-llamacpp-router-provider-tests.md
git commit -m "Phase 338a — llama.cpp router provider tests (failing)"
```
