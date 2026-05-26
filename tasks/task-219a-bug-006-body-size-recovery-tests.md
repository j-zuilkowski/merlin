# Task 219a - BUG-006 Body-Size Recovery Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 218b complete: Merlin v2.0 version release exists.

Deep BUG-006 examination:
  - Original BUG-006 root cause, "no mid-run compaction", is already addressed by  tasks 205b and 206b.
  - `AgenticEngine.runLoop` compacts after each regular tool batch via `compactWithSummaryIfNeeded(provider:)`.
  - `ProviderError.isContextLengthExceeded` catches context-window phrases but does not catch generic HTTP body-size phrases such as "request body too large" or "payload too large".
  - Remaining active slice: provider HTTP 400 body-size failures can still surface as fatal instead of compacting and restarting the turn.
  - Required behavior: context/body overruns are self-correcting like Codex/Claude-style long-run recovery: compact, inject explicit restart/resume directions, retry from the same user turn, and stop after a bounded counter.

New surface introduced in task 219b:
  - `ProviderError.isContextLengthExceeded` recognizes provider request/body-size overflow phrases.
  - `AgenticEngine` uses a bounded context-overrun recovery counter.
  - `AgenticEngine` injects restart/resume directions after compaction so the model continues the interrupted work instead of treating the retry as a fresh vague turn.

TDD coverage:
  File 1 - `ContextLengthRecoveryTests`: body-size HTTP 400 phrases classify as context overflow, trigger bounded recovery, and include restart/resume directions.

---

## Edit: MerlinTests/Unit/ContextLengthRecoveryTests.swift

Add tests that assert:

1. `ProviderError.httpError(statusCode: 400, body: "request body too large", providerID: "mock").isContextLengthExceeded == true`
2. The same is true for:
   - `payload too large`
   - `request entity too large`
   - `body size limit exceeded`
   - `maximum request body size exceeded`
   - `content length exceeded`
3. A `MockProvider(failFirstCallWith: .httpError(statusCode: 400, body: "request body too large", providerID: "mock"))` causes `AgenticEngine.send(userMessage:)` to retry and emit a compaction system note, matching the existing context-window retry tests.
4. The retry path appends a user-visible or context-visible restart directive containing:
   - the phrase `CONTEXT_OVERRUN_RECOVERY`
   - the current recovery attempt number
   - instructions to continue from the interrupted task and avoid restarting completed work
5. Repeated context/body-size failures stop after a finite maximum attempt count and surface an error event instead of recursively retrying forever.
6. Non-400 responses with the same body-size phrases remain false.

Do not loosen classification for generic `"bad request"` or malformed-request bodies.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because body-size phrases are not yet classified by `ProviderError.isContextLengthExceeded`.

## Commit

```bash
git add MerlinTests/Unit/ContextLengthRecoveryTests.swift
git commit -m "Task 219a - BUG-006 body-size recovery tests (failing)"
```
