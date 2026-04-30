# Phase 132 — V7 Documentation & Code Comment Update

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 131b complete: all v7 and v8 implementation in place. All tests pass.

This is a documentation-only phase — no new symbols, no test changes.
Update every file touched in phases 122–128 so that:
  1. All `//` line comments and `///` doc-comments reflect the current implementation.
  2. `architecture.md` cross-references and file-layout tables are accurate.
  3. `FEATURES.md` entries for the v7 surface are complete and accurate.
  4. No stale references to "TODO", "Phase NNb", or pre-v7 type names remain.

---

## Files to audit and update

### Merlin/Providers/LLMProvider.swift
- Doc-comment on `CompletionRequest`: list all 10 fields (the original 2 + the 8 new sampling params).
- Each new field (`topP`, `topK`, `minP`, `repeatPenalty`, `frequencyPenalty`, `presencePenalty`, `seed`, `stop`) should have a `///` line explaining its effect and valid range.
- Note that `nil` means "use provider default / AppSettings inference default".

### Merlin/Providers/SSEParser.swift (or equivalent)
- `Body` struct: doc-comment on each new CodingKey mapping (snake_case ↔ Swift name).
- `encodeRequest`: comment explaining that nil fields are omitted from JSON via `encodeIfPresent`.

### Merlin/Settings/AppSettings.swift
- Each `inferenceTopP`, `inferenceTopK`, etc. property: `///` with the TOML key name and default.
- `applyInferenceDefaults(to:)`: explain the fill-without-override contract.
- `[inference]` TOML section: comment block listing all keys.

### Merlin/Engine/ModelParameterAdvisor.swift
- `ModelParameterAdvisor` actor: class-level doc explaining the four detection algorithms
  (finishReason truncation, score variance, trigram repetition, context overflow markers).
- `ParameterAdvisoryKind`: each case doc with the threshold that triggers it.
- `ParameterAdvisory`: struct-level doc; note that `Equatable` is by `kind + modelID`.
- `checkRecord(_:)`: explain single-record checks (finishReason, context markers).
- `analyze(records:modelID:)`: explain multi-record checks (variance, repetition ratio).
- `dismiss(_:)`: explain removal by kind+modelID equality.
- `repetitionRatio(in:)`: explain the trigram algorithm.

### Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift
- Protocol doc: one-paragraph explanation of the runtime-reload vs restart-instructions
  split controlled by `capabilities.canReloadAtRuntime`.
- `LoadParam` enum: each case doc with the CLI flag / API field it maps to per provider.
- `LocalModelConfig`: struct doc noting nil = "don't change this parameter".
- `ModelManagerCapabilities`: struct doc.
- `RestartInstructions`: struct doc explaining `shellCommand`, `configSnippet`, `explanation`.
- `ModelManagerError`: each case doc.

### Merlin/Providers/LocalModelManager/LMStudioModelManager.swift
- Actor doc: explain REST-first strategy with `lms` CLI fallback.
- `reload(modelID:config:)`: note the unload → load sequence via `/api/v1/unload` + `/api/v1/load`.

### Merlin/Providers/LocalModelManager/OllamaModelManager.swift
- Actor doc: explain the Modelfile generation strategy for baking in parameters.
- `buildModelfile(config:)`: comment the PARAMETER directive format.
- Note why flashAttention is absent from supportedLoadParams.

### Merlin/Providers/LocalModelManager/JanModelManager.swift
- Actor doc: explain the stop → edit model.json → start cycle.
- `modelJSONPath(for:)`: note the `~/jan/models/<id>/model.json` path convention.

### Merlin/Providers/LocalModelManager/LocalAIModelManager.swift
- Actor doc: explain why canReloadAtRuntime = false (LocalAI requires process restart).
- `restartInstructions(modelID:config:)`: comment the YAML snippet format.

### Merlin/Providers/LocalModelManager/MistralRSModelManager.swift
- Actor doc: note the `mistralrs-server` CLI flag mapping for each supported LoadParam.

### Merlin/Providers/LocalModelManager/VLLMModelManager.swift
- Actor doc: note the `python -m vllm.entrypoints.openai.api_server` flag mapping.

### Merlin/Providers/LocalModelManager/NullModelManager.swift
- Struct doc: explain when NullModelManager is used (unknown provider ID or invalid URL).

### Merlin/App/AppState.swift
- `localModelManagers`: `///` noting it is keyed by providerID, built at init from ProviderRegistry.
- `activeLocalProviderID`: `///` explaining it is set when user selects a local provider.
- `pendingRestartInstructions`: `///` — published so the UI can show a restart sheet.
- `manager(for:)`: one-line doc.
- `makeManager(for:)`: comment the switch cases and why NullModelManager is the default.
- `applyAdvisory(_:)`: doc-comment listing each advisory kind and its routing destination.

### Merlin/Engine/AgenticEngine.swift
- `isReloadingModel`: `///` — explain the run-loop pause contract.
- `onAdvisory`: `///` — explain the callback is set by AppState; clears isReloadingModel after attempt.
- Run-loop reload guard block: inline comment explaining the 500ms poll interval.

### Merlin/Views/Settings/ModelControlView.swift
- `ModelControlView`: struct-level doc explaining the capability-filtered form.
- `applyAndReload()`: comment the error routing (requiresRestart → sheet, reloadFailed → inline).
- `IntField` / `DoubleField`: brief doc on the nil-passthrough Binding pattern.
- `RestartInstructionsSheet`: doc explaining the NSPasteboard copy pattern.

---

## architecture.md updates

Verify the following sections are accurate against the current implementation:

1. **Version summary line** — v7 line is correct (already updated).
2. **[v7] Architecture section** — ASCII diagrams match actual type names and flow.
3. **Local Model Management [v7]** — capability matrix table matches actual `supportedLoadParams`
   sets in each manager (cross-check against the 6 manager files).
4. **File layout** — all 8 manager files listed; `ModelControlView.swift` entry present.

If any discrepancy is found, correct the architecture.md entry. Do not invent new content —
only fix what does not match the implementation.

---

## FEATURES.md updates

Find the existing sections for:
- **Inference Settings** (or equivalent) — add a bullet for the 8 new sampling params and
  the `[inference]` TOML section with `applyInferenceDefaults`.
- **Local Model Management** — if not present, add a section describing:
  - Per-provider load parameter editing in Settings → Providers
  - Runtime reload (LM Studio, Ollama, Jan) vs restart instructions (LocalAI, Mistral.rs, vLLM)
  - Parameter advisory auto-detection (truncation, variance, repetition, context overflow)
  - One-tap fix via PerformanceDashboard "Fix this" button
- **AI-Generated Memories** — confirm the dual-path (file injection + xcalibre RAG) bullet is present.

---

## Verify (no regressions)
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD SUCCEEDED** — zero warnings, zero errors, all prior tests pass.

## Commit
```bash
git add Merlin/Providers/LLMProvider.swift
git add Merlin/Providers/SSEParser.swift
git add Merlin/Settings/AppSettings.swift
git add Merlin/Engine/ModelParameterAdvisor.swift
git add Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift
git add Merlin/Providers/LocalModelManager/LMStudioModelManager.swift
git add Merlin/Providers/LocalModelManager/OllamaModelManager.swift
git add Merlin/Providers/LocalModelManager/JanModelManager.swift
git add Merlin/Providers/LocalModelManager/LocalAIModelManager.swift
git add Merlin/Providers/LocalModelManager/MistralRSModelManager.swift
git add Merlin/Providers/LocalModelManager/VLLMModelManager.swift
git add Merlin/Providers/LocalModelManager/NullModelManager.swift
git add Merlin/App/AppState.swift
git add Merlin/Engine/AgenticEngine.swift
git add Merlin/Views/Settings/ModelControlView.swift
git add architecture.md
git add FEATURES.md
git commit -m "Phase 132 — V7 docs + code comments: inference params, ModelParameterAdvisor, LocalModelManagerProtocol, ModelControlView"
```
