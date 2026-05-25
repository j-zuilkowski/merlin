# Task 237b — Unified Executor Gate + Recovery Deletion

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 237a complete: failing tests for the EscalationHandler, no-recursion invariant, retry-counter
deletion, and clean-stop outcome.

This task deletes the recursive recovery path and replaces it with a bounded escalation helper.
Net code volume drops noticeably even though new logic is added — the deletion of `contextLengthRetryCount`,
`maxContextOverrunRecoveryAttempts`, `contextOverrunRecoveryDirective`, and the recursive
`runLoop` self-call together remove ~120 lines.

After this task the infinite-loop bug class observed previously is structurally impossible.
No code path inside a catch block re-enters `runLoop`.

---

## Edit

- `Merlin/Engine/EscalationHandler.swift` — new file.
- `Merlin/Engine/AgenticEngine.swift`:
    - **Delete**:
        - `contextLengthRetryCount` instance property (line 182-ish).
        - `maxContextOverrunRecoveryAttempts` instance property.
        - `contextOverrunRecoveryDirective(attempt:maxAttempts:userMessage:)` method (lines ~1840–1855).
        - The entire `catch let pe as ProviderError where pe.isContextLengthExceeded { … try await runLoop(...) }`
          block at lines ~1049–1081 — replace with a non-recursive last-ditch compaction + escalation call.
    - **Add**:
        - `let escalation: EscalationHandler` — initialised alongside `critic` / `planner` in the same factory.
        - `handleEscalation(currentStep:reason:continuation:) async throws` — invokes
          `escalation.escalateOrStop(...)`; on `.continueWith(replacementSteps:)`, appends a user
          message describing the substeps and continues the existing while-loop in-place;
          on `.stop(message:)`, yields `.cleanStop` / `.systemNote`, breaks out of the loop, returns.
    - In the existing iteration-ceiling block (lines ~788–798): if `loopCount >= maxIterations
      - nearCeilingThreshold` *and* the engine made no observable progress in the last 3
      iterations (no `writtenFilePaths` growth, no new assistant text, no new tool calls), call
      `handleEscalation(reason: .iterationCap)`. If escalation says `.continueWith`, replace the
      `[CONTINUATION]` injection path with the planner's substeps and reset `loopCount` for the
      next pass. The hard ceiling check itself remains — escalation does not extend the ceiling,
      it lets the loop end gracefully and start a fresh, smaller-scoped run.
    - In the existing `catch let pe as ProviderError where pe.isContextLengthExceeded` (now
      simplified): emit telemetry, attempt one summary compaction, re-estimate; if still over
      → `handleEscalation(reason: .preflightOverflow)`. **No recursion.**
- `Merlin/Engine/AgentEvent.swift` (or wherever AgentEvent lives) — add
  `case cleanStop(reason: String, summary: String)`. UI render parity with `.systemNote` is
  acceptable for v2.1.0; distinct affordance is a future UI task.

The architectural spec for this task lives in `spec.md` § "V2.1 — Budget-Aware
Execution" (already written, lines ~3759–4301). Do not duplicate it; the implementation must
match it. If the spec and the test surfaces disagree, the test surfaces win — flag the
divergence in your completion summary.

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

Expected: **BUILD SUCCEEDED** and all task 237a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-237b-executor-gate.md \
    Merlin/Engine/EscalationHandler.swift \
    Merlin/Engine/AgenticEngine.swift \
    Merlin/Engine/AgentEvent.swift
git commit -m "Task 237b — Unified executor gate, delete recursive recovery"
```

## PASTE-LIST update

Append task 237a/237b under the "Budget-Aware Execution (v2.1.0)" section.
