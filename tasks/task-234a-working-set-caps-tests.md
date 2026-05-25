# Phase 234a — Working-Set Caps Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 233b complete: ProviderBudget + pre-flight gate live; thresholds lowered to 6 K / 20 K.

Decomposes the context window into bounded components. Each component declares its share of the
provider's `usableInputTokens`, and the sum of caps never exceeds the budget. This makes
pre-flight overflow a near-zero event, not a steady-state failure mode.

New surface introduced in phase 234b:
  - `WorkingSetBudget` value type in `Merlin/Engine/WorkingSetBudget.swift`:
    ```swift
    struct WorkingSetBudget: Sendable {
        let systemPromptCap: Int
        let ragInjectionCap: Int
        let recentTurnsCap: Int
        let toolBurstCap: Int
        var total: Int { systemPromptCap + ragInjectionCap + recentTurnsCap + toolBurstCap }
        static func derive(from budget: ProviderBudget) -> WorkingSetBudget
    }
    ```
    `derive` allocates: system prompt 10%, RAG 25%, recent turns 50%, tool burst 15% of
    `usableInputTokens`. `total <= budget.usableInputTokens` always.
  - `ContextManager.applyWorkingSetCaps(_ caps: WorkingSetBudget) async` — truncates each
    component to its cap. Tool exchanges are compacted first (existing summary-compaction path),
    recent turns are dropped from oldest forward, system prompt is truncated by length only as a
    last resort with a `[truncated …]` marker.
  - `ContextManager.compactAfterToolBurst()` — new call invoked at the end of each tool-dispatch
    round (replacing/augmenting the existing `compactWithSummaryIfNeeded` at the `_ = await
    context.compactWithSummaryIfNeeded(provider:)` site near AgenticEngine.swift:1046).
    Fires when tool-burst component is over its cap, not at the global 20 K threshold.
  - `AgenticEngine.applyWorkingSetCapsBeforeSend(...)` — invoked inside `preflightCheck`. Pulls
    the current provider's budget, derives caps, applies them, re-estimates.

TDD coverage:
  File 1 — `MerlinTests/Unit/WorkingSetBudgetTests.swift`: `derive` sums to ≤ usable input
    tokens; component ratios match the documented allocation; small budgets clamp gracefully
    (none of the caps go below a minimum floor of 256 tokens each).
  File 2 — `MerlinTests/Unit/WorkingSetTruncationTests.swift`: `applyWorkingSetCaps` honours
    each cap independently — over-sized RAG gets trimmed without touching recent turns, etc.
    System-prompt truncation is the last resort and emits a `[truncated …]` marker.
  File 3 — `MerlinTests/Unit/ToolBurstCompactionTests.swift`: after a tool dispatch round that
    pushes tool-burst component over its cap, `compactAfterToolBurst()` fires and reduces
    estimated tokens by ≥ 30%. Below-cap rounds are a no-op (no compaction event).
  File 4 — `MerlinTests/Unit/PreflightCapsIntegrationTests.swift`: a request that would overflow
    at full size is brought under budget by working-set caps alone (no recovery path needed),
    and pre-flight outcome is `.ok`.

---

## Edit

- `MerlinTests/Unit/WorkingSetBudgetTests.swift`
- `MerlinTests/Unit/WorkingSetTruncationTests.swift`
- `MerlinTests/Unit/ToolBurstCompactionTests.swift`
- `MerlinTests/Unit/PreflightCapsIntegrationTests.swift`

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `WorkingSetBudget`, `ContextManager.applyWorkingSetCaps`,
`ContextManager.compactAfterToolBurst`, and `AgenticEngine.applyWorkingSetCapsBeforeSend`.

## Commit

```bash
git add tasks/task-234a-working-set-caps-tests.md \
    MerlinTests/Unit/WorkingSetBudgetTests.swift \
    MerlinTests/Unit/WorkingSetTruncationTests.swift \
    MerlinTests/Unit/ToolBurstCompactionTests.swift \
    MerlinTests/Unit/PreflightCapsIntegrationTests.swift
git commit -m "Phase 234a — WorkingSetCapsTests (failing)"
```
