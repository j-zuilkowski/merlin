# Task 219b - BUG-006 Body-Size Recovery

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 219a complete: failing body-size recovery tests exist.

---

## Edit: Merlin/Providers/ProviderError.swift

Extend `isContextLengthExceeded` to classify provider request/body-size overflow phrases in addition to context-window phrases:

```swift
|| lower.contains("request body too large")
|| lower.contains("payload too large")
|| lower.contains("request entity too large")
|| lower.contains("body size limit exceeded")
|| lower.contains("maximum request body size")
|| lower.contains("content length exceeded")
```

Keep the existing `code == 400` guard. Do not classify authentication, model-not-found, malformed schema, or generic `bad request` bodies as context overflow.

---

## Edit: Merlin/Engine/AgenticEngine.swift

Replace the single boolean-style retry behavior with explicit bounded self-correction.

Required behavior:

1. Add `private let maxContextOverrunRecoveryAttempts = 2`.
2. Keep/reset `contextLengthRetryCount` at the beginning of each top-level user turn.
3. On `ProviderError.isContextLengthExceeded`, if `contextLengthRetryCount < maxContextOverrunRecoveryAttempts`:
   - increment `contextLengthRetryCount`
   - emit a system note such as `[context overrun - compacting and restarting attempt X/Y]`
   - call `context.forceCompaction()`
   - append a user message to context containing `CONTEXT_OVERRUN_RECOVERY`, the attempt counter, and instructions:
     - continue the interrupted task
     - do not restart completed work
     - summarize what was already done if needed
     - proceed from the next unresolved step
   - re-enter `runLoop` for the same original user message
4. If the counter is exhausted, emit or surface the provider error normally.
5. Do not create unbounded recursion or a loop that can run forever.

The recovery directive is necessary because compacting alone is not enough: the next model call must know it is resuming a partially completed run after a context/body overrun.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `ContextLengthRecoveryTests` pass, including the BUG-006 body-size variants.

## Commit

```bash
git add Merlin/Providers/ProviderError.swift Merlin/Engine/AgenticEngine.swift MerlinTests/Unit/ContextLengthRecoveryTests.swift
git commit -m "Task 219b - BUG-006 body-size HTTP 400 recovery"
```

## Fixes

**ContextLengthRecoveryTests — two assertion bugs corrected.**

1. `test_engine_compacts_and_retries_on_contextLengthExceeded` checked for
   `"CONTEXT_OVERRUN_RECOVERY"` in the `.systemNote` stream events. The engine
   never puts that token in the note — it puts it only in the user message injected
   into context (already verified separately by the `recoveryMessages` block). The
   redundant systemNote check was removed.

   The same test used case-sensitive `.contains("continue from the interrupted task")`
   and `.contains("do not restart completed work")`. The recovery directive uses
   sentence case (`"Continue"` / `"Do not"`). Fixed by calling `.lowercased()` before
   `.contains(...)`.

2. `test_engine_retries_twice_then_surfaces_error_for_repeated_body_size_failures`
   filtered systemNotes for `"CONTEXT_OVERRUN_RECOVERY"` — same wrong assumption.
   Changed to `note.lowercased().contains("overrun")` which matches the actual emitted
   note `"[context overrun - compacting and restarting attempt N/M]"`.
