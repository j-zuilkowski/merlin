# Phase 235a — Adaptive RAG Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 234b complete: working-set caps live; RAG has a budget-derived cap but RAG retrieval still
uses the static `ragChunkLimit` setting.

Replaces the global `ragChunkLimit` for chunk count with a value derived from the current
provider's `WorkingSetBudget.ragInjectionCap`. A 200 K-context provider gets richer grounding;
a 32 K-context provider gets minimal grounding; a 4 K toy model gets near-zero grounding without
the user touching settings. Setting becomes an upper bound, not the active value.

New surface introduced in phase 235b:
  - `RAGSelector.selectChunks(candidates: [RAGChunk], budget: Int, userCeiling: Int) -> [RAGChunk]`
    in `Merlin/Engine/RAGSelector.swift`. Pure function. Greedily includes chunks in retrieval
    order until adding the next one would exceed `budget` (tokens, via `TokenEstimator.estimateText`
    or a simple `chunk.text.count / 4` approximation). Never returns more than `userCeiling` chunks.
  - `TokenEstimator.estimateText(_ text: String) -> Int` — companion to the request estimator
    introduced in 233b. Pure `text.utf8.count / 4 + 16`.
  - `AppSettings.ragChunkLimit` remains as user-facing ceiling; semantics change from "the
    number to retrieve" to "the maximum allowed if budget permits." Documented inline.
  - `AgenticEngine`'s RAG injection block at lines ~643–656 changes from
    `limit: min(max(ragChunkLimit, 1), 20)` to: retrieve up to 20 candidates, then call
    `RAGSelector.selectChunks(..., budget: workingSet.ragInjectionCap, userCeiling: ragChunkLimit)`.
    Retrieval still goes to xcalibre; trimming happens locally.

TDD coverage:
  File 1 — `MerlinTests/Unit/RAGSelectorTests.swift`: greedy-by-token selection respects budget;
    returns chunks in original retrieval order; honours `userCeiling`; returns `[]` for budget < 0;
    handles `candidates.isEmpty`.
  File 2 — `MerlinTests/Unit/TokenEstimatorTextTests.swift`: `estimateText` monotonic in length,
    returns ≥ 16 for non-empty input, returns 16 for empty string.
  File 3 — `MerlinTests/Unit/AdaptiveRAGIntegrationTests.swift`: with a 6 000-token usable budget
    (small provider), RAG injection occupies ≤ `workingSet.ragInjectionCap` tokens regardless of
    `ragChunkLimit`. With a 100 000-token usable budget (large provider), more chunks come through.
    Verify via the existing `engine.preflight.estimate` event delta.

---

## Edit

- `MerlinTests/Unit/RAGSelectorTests.swift`
- `MerlinTests/Unit/TokenEstimatorTextTests.swift`
- `MerlinTests/Unit/AdaptiveRAGIntegrationTests.swift`

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `RAGSelector.selectChunks` and
`TokenEstimator.estimateText`.

## Commit

```bash
git add tasks/task-235a-adaptive-rag-tests.md \
    MerlinTests/Unit/RAGSelectorTests.swift \
    MerlinTests/Unit/TokenEstimatorTextTests.swift \
    MerlinTests/Unit/AdaptiveRAGIntegrationTests.swift
git commit -m "Phase 235a — AdaptiveRAGTests (failing)"
```
