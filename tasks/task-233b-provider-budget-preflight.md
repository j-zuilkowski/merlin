# Task 233b — ProviderBudget + Pre-Flight Gate

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 233a complete: failing tests for ProviderBudget, TokenEstimator, pre-flight overflow path,
lowered thresholds, and telemetry.

This task installs the budget contract and the pre-flight gate. The recursive 400-recovery loop
at `AgenticEngine.swift:1049–1081` is left in place untouched — task 237b deletes and replaces
it. Pre-flight reduces the rate at which that path fires; later  tasks retire it.

---

## Edit

- `Merlin/Providers/ProviderBudget.swift` — new file. Conforms to `Sendable`, `Equatable`, `Codable`.
- `Merlin/Providers/ProviderConfig.swift` (or wherever `registry?.config(for:)` resolves —
  inspect during implementation) — add optional `budget: ProviderBudget?` field. Default fallback
  for `nil` is `ProviderBudget(maxInputTokens: 32_000, reservedOutputTokens: 4_096)`.
  Update built-in provider seeds:
    - DeepSeek: `(65_536, 8_192)`
    - Claude (Anthropic Sonnet/Opus 4.7): `(200_000, 16_384)`
    - Claude Haiku 4.5: `(200_000, 8_192)`
    - OpenAI gpt-4-class (best-effort, override per config): `(128_000, 8_192)`
    - LM Studio local: derive from `LocalModelManager.currentContextLength` minus the
      `reservedOutputTokens`. If unknown, fall back to the default.
- `Merlin/Engine/TokenEstimator.swift` — new file. Encodes a `CompletionRequest` via the same
  `encodeRequest` path used at `AgenticEngine.swift:847`. Public surface:
  ```swift
  enum TokenEstimator {
      static func estimate(request: CompletionRequest, baseURL: URL, modelID: String) -> Int
  }
  ```
- `Merlin/Engine/AgenticEngine.swift`:
    - Add `preflightCheck(...)` returning `PreflightOutcome`. Call it immediately before
      `completeWithRetry(...)` at line ~859. On `.wouldOverflow`, invoke
      `context.compactWithSummaryIfNeeded(provider:)` and re-estimate. If still over, throw
      `EngineError.preflightOverflow(estimated:budget:)`. Emit the three new telemetry events.
    - Add nested `enum EngineError: Error, Sendable { case preflightOverflow(estimated: Int, budget: Int) }`.
      Keep it nested inside `AgenticEngine` (or in `Merlin/Engine/EngineError.swift` if it
      already exists — check before duplicating).
- `Merlin/Engine/ContextManager.swift`:
    - `preRunCompactionThreshold` 10_000 → 6_000.
    - `midLoopCompactionThreshold` 40_000 → 20_000.
    - Both stay `var` (or `let` for the pre-run case — confirm test relies on `var`).

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all task 233a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-233b-provider-budget-preflight.md \
    Merlin/Providers/ProviderBudget.swift \
    Merlin/Providers/ProviderConfig.swift \
    Merlin/Engine/TokenEstimator.swift \
    Merlin/Engine/AgenticEngine.swift \
    Merlin/Engine/ContextManager.swift
git commit -m "Task 233b — ProviderBudget and pre-flight gate"
```

## PASTE-LIST update

Append task 233a/233b under the "Budget-Aware Execution (v2.1.0)" section started in 232b.
