# Phase 286b — Universal Pre-flight Guard

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 286a complete: failing tests for `PreflightGuard.fit`.
Phase 285 complete: `ContextBudgetResolver` discovers the active model's real context
window — the guard takes its budget from the resolver, never a hardcoded value.

After this phase, **every** LLM request is sized to fit the provider's input window
before it is sent — not just the main turn loop. The HTTP 400 context-overflow class
becomes structurally impossible regardless of which engine path makes the call.

---

## Edit

### 1. New file — `Merlin/Engine/PreflightGuard.swift`

```swift
import Foundation

/// Last-line guard so no `provider.complete` call sends an over-budget request.
/// The main turn loop has the richer `AgenticEngine.preflightCheck` (which compacts
/// the live ContextManager); this guard is the universal floor for every other path
/// — planner, critic, subagents, summariser, etc. — none of which own a ContextManager.
enum PreflightGuard {

    /// Returns a request whose `TokenEstimator.estimate` is <= `usableInputTokens`.
    /// Already fits → returned unchanged. Otherwise: keep the leading system
    /// message(s); drop oldest non-system messages; if still over, head/tail-truncate
    /// the single largest remaining message (via `ToolOutput.clamp`). Never throws —
    /// worst case it returns just the (possibly truncated) system message.
    static func fit(_ request: CompletionRequest,
                    usableInputTokens: Int) -> CompletionRequest {
        guard TokenEstimator.estimate(request: request) > usableInputTokens else {
            return request
        }
        // Implementation: iteratively drop the oldest non-system message and
        // re-estimate; when only system + one message remain and it is still over,
        // truncate the largest message's text content with ToolOutput.clamp.
        // Emit `engine.preflight.guard_clamped` telemetry when a clamp occurs.
        // (Full body written here.)
    }

    /// Clamp-to-fit then send. A drop-in replacement for `provider.complete(request:)`.
    /// The budget is discovered live via `ContextBudgetResolver` — never hardcoded, so
    /// it tracks whatever model the provider currently has loaded.
    ///
    /// Learn-from-400: if the provider still rejects the request with a
    /// context-overflow 400 (the conservative pre-size was too generous — only
    /// possible on a commercial provider whose window was never discovered), parse
    /// the real limit out of the error, feed it to
    /// `ContextBudgetResolver.recordObservedLimit` (which persists it to
    /// providers.json), re-`fit` against the now-known budget, and retry **once**.
    static func complete(_ request: CompletionRequest,
                         provider: any LLMProvider)
        async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let budget = await ContextBudgetResolver.shared.usableInputTokens(for: provider)
        do {
            return try await provider.complete(
                request: fit(request, usableInputTokens: budget))
        } catch let error as ProviderError where error.isContextLengthExceeded {
            // The pre-size was still too big. Learn the real window from the 400,
            // persist it, and retry once against the corrected budget.
            if let learned = error.observedContextLimit {
                await ContextBudgetResolver.shared.recordObservedLimit(
                    contextTokens: learned, for: provider)
            }
            let corrected = await ContextBudgetResolver.shared.usableInputTokens(for: provider)
            return try await provider.complete(
                request: fit(request, usableInputTokens: corrected))
        }
    }
}
```

Reuse `ToolOutput.clamp` (phase 284) for the per-message truncation. Emit a
`engine.preflight.guard_clamped` telemetry event with the before/after estimate when a
request is clamped, so this is observable.

A context-overflow 400 may surface either as a throw from `try await provider.complete`
or as the terminal error of the returned stream. If the providers in this codebase
deliver it as a stream-terminal error, the catch above will not see it — in that case
wrap the returned `AsyncThrowingStream` so the guard observes the terminal error,
calls `recordObservedLimit`, and (only if nothing has been yielded yet) retries once.
Match whichever the providers actually do; the learn-and-retry semantics are the
requirement, not the exact catch site.

### 1a. `Merlin/Providers/ProviderError.swift` — extract the learned limit

`isContextLengthExceeded` already classifies the 400. Add a sibling accessor that
extracts the number the provider reports, so `recordObservedLimit` has something to
persist:

```swift
/// The context-window size (tokens) the provider reported in a context-overflow
/// 400 body, e.g. the 8192 in "maximum context length is 8192 tokens". nil when
/// the body carries no parseable number.
var observedContextLimit: Int? { ... }
```

Implementation: only when `isContextLengthExceeded`; scan the body for an integer
adjacent to the context phrasing ("context length", "context window", "maximum
context", "tokens"). Pick the largest plausible match (a body may mention both the
limit and the request size — the limit is the window). Best-effort: ambiguous or
absent → nil (the resolver then keeps its conservative value).

### 2. Route every send site through the guard

For each `provider.complete(request:)` site below, replace the bare call with
`PreflightGuard.complete(request, provider: provider)`. The guard resolves the budget
itself via `ContextBudgetResolver` — call sites pass no budget and need no knowledge of
the model's context window.

| File | Line(s) |
|---|---|
| `Merlin/Engine/PlannerEngine.swift` | 319, 409, 472 |
| `Merlin/Engine/CriticEngine.swift` | 374 |
| `Merlin/Agents/SubagentEngine.swift` | 103 |
| `Merlin/Agents/WorkerSubagentEngine.swift` | 134 |
| `Merlin/Engine/ContextManager.swift` | 210 (the summariser) |
| `Merlin/Memories/MemoryEngine.swift` | 104 |
| `Merlin/KAG/KAGEngine.swift` | 83 |
| `Merlin/Tools/VisionQueryTool.swift` | 31 |
| `Merlin/Views/BtwSession.swift` | 38 |
| `Merlin/Calibration/CalibrationCoordinator.swift` | 280 |

The main `AgenticEngine` send (`:2042`, `:2249`) already runs `preflightCheck`; leave its
existing gate, but it may also call `PreflightGuard.fit` as a final net — harmless,
idempotent (a fitting request is returned unchanged).

Line numbers will have shifted — match on the `provider.complete(request:)` call, not
the line. The guard must be a true drop-in: same `AsyncThrowingStream<CompletionChunk, Error>`
return type.

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

Expected: **BUILD SUCCEEDED**, all phase 286a tests pass, no prior phase regresses.

Then confirm no un-guarded send remains:

```bash
grep -rn "provider.complete(request\|executeProvider.complete(request" Merlin --include="*.swift"
```

Every hit must be inside `PreflightGuard` itself or a `PreflightGuard.complete(...)`
call. A bare `provider.complete(request:)` anywhere else is an un-guarded path — fix it.

## Commit

```bash
git add tasks/task-286b-universal-preflight.md \
    Merlin/Engine/PreflightGuard.swift \
    Merlin/Providers/ProviderError.swift \
    Merlin/Engine/PlannerEngine.swift \
    Merlin/Engine/CriticEngine.swift \
    Merlin/Agents/SubagentEngine.swift \
    Merlin/Agents/WorkerSubagentEngine.swift \
    Merlin/Engine/ContextManager.swift \
    Merlin/Memories/MemoryEngine.swift \
    Merlin/KAG/KAGEngine.swift \
    Merlin/Tools/VisionQueryTool.swift \
    Merlin/Views/BtwSession.swift \
    Merlin/Calibration/CalibrationCoordinator.swift \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Phase 286b — Route every provider send through PreflightGuard"
```

## Fixes

`spec.md`'s guarantee — every LLM request sized to the provider window before
sending — is now true in the code. All 14 `provider.complete` sites pass through
`PreflightGuard`; the planner, critic, subagent, summariser, memory, KAG, vision, btw,
and calibration paths can no longer send an over-budget request and trigger an HTTP 400.

If a commercial provider's window was never discovered and the conservative pre-size
was still too large, the guard catches the resulting context-overflow 400, parses the
real limit from the error, and feeds it to `ContextBudgetResolver.recordObservedLimit`
— which persists it to `ProviderConfig.budget` in `providers.json`. The provider is
budgeted correctly from that point on and across restarts, so the 400 is paid at most
once per model, ever.
