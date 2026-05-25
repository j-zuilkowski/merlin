# Phase 235b — Adaptive RAG

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 235a complete: failing tests for budget-aware RAG selection and the text estimator.

RAG injection now adapts to the active provider's budget. The user's `ragChunkLimit` becomes a
ceiling, not the actual chunk count. Smaller models get less grounding, automatically.

---

## Edit

- `Merlin/Engine/RAGSelector.swift` — new file. Pure greedy-by-token selector.
- `Merlin/Engine/TokenEstimator.swift` — add `estimateText(_ text: String) -> Int`. Companion
  to the request estimator from 233b.
- `Merlin/Engine/AgenticEngine.swift`:
    - RAG block at lines ~643–656: retrieve up to 20 candidates from xcalibre and memory,
      compute `workingSet` from active `ProviderBudget`, then trim via
      `RAGSelector.selectChunks(candidates: ragChunks, budget: workingSet.ragInjectionCap,
       userCeiling: ragChunkLimit)`.
    - Emit `engine.rag.selected` telemetry with `candidate_count`, `selected_count`,
      `tokens_used`, `budget_cap`.
- `Merlin/Config/AppSettings.swift` — update doc-comment on `ragChunkLimit` to read
  "Upper bound on retrieved chunks. Effective count is the smaller of this ceiling and what
  fits in the active provider's RAG budget."

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all phase 235a tests pass.

## Commit

```bash
git add tasks/task-235b-adaptive-rag.md \
    Merlin/Engine/RAGSelector.swift \
    Merlin/Engine/TokenEstimator.swift \
    Merlin/Engine/AgenticEngine.swift \
    Merlin/Config/AppSettings.swift
git commit -m "Phase 235b — Adaptive RAG (budget-derived chunk selection)"
```

## PASTE-LIST update

Append phase 235a/235b under the "Budget-Aware Execution (v2.1.0)" section.
