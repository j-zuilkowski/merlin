# Phase 149a — LM Studio Context Auto-Resize Tests

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 148b complete: two-tier document verification in place.

## Problem

When a local Qwen3 model is loaded with `loaded_context_length: 4096` and a critic
Stage 2 prompt is ~12K tokens, LM Studio drops the connection with error 4865
(`n_keep >= n_ctx`). The critic verdict falls to `.skipped`, silently degrading
reliability for every local-model turn.

The fix: before issuing the Stage 2 critic request, query the LM Studio v0 API
for the model's current and maximum context lengths, and reload the model with the
next power-of-two context length if the estimated prompt won't fit.

## New surface introduced in phase 149b

- `LocalModelManagerProtocol.ensureContextLength(modelID:minimumTokens:)` — async throws, default no-op
- `LMStudioModelManager.ensureContextLength(modelID:minimumTokens:)` — queries `/api/v0/models`, reloads if needed
- `CriticEngine.init(..., modelManager: (any LocalModelManagerProtocol)?)` — optional manager parameter
- `AgenticEngine.localModelManagers: [String: any LocalModelManagerProtocol]` — set by AppState

## TDD coverage

File 1 — `LMStudioContextAutoResizeTests.swift`:
  - `testNoResizeWhenContextSufficient` — model with loaded_ctx=8192, request for 4000 tokens → no reload
  - `testResizeWhenContextInsufficient` — loaded_ctx=4096, request for 8000 → reload to next power-of-two
  - `testResizeTargetIsPowerOf2` — minimumTokens=5000 → target=8192
  - `testGracefulFailureOnAPIError` — API returns 500 → ensureContextLength swallows error

File 2 — `CriticEngineContextAutoResizeTests.swift`:
  - `testCriticCallsEnsureContextLength` — critic calls manager before Stage 2
  - `testCriticProceedsIfManagerThrows` — manager throws → critic still evaluates
  - `testEstimatedTokensExceed512` — estimated tokens = prompt.count/4 + 512 > 512

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
# Expected: BUILD FAILED — ensureContextLength not defined (expected)
```

## Commit
```bash
git add MerlinTests/Unit/LMStudioContextAutoResizeTests.swift \
        MerlinTests/Unit/CriticEngineContextAutoResizeTests.swift
git commit -m "Phase 149a — LM Studio context auto-resize tests (failing)"
```
