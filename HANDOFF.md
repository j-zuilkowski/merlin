# Codex Task: Merlin — Bug Fixes + Scroll Lock + /rewind + /btw (Tasks 200–204)

## Objective

Five TDD task pairs (200a through 204b) that address the three open bugs and close all
remaining local feature gaps vs. Claude Code. All work follows strict TDD: write failing
tests first (a-task), commit, implement until green (b-task), commit again.

## Context
- Language/Framework: Swift 5.10, macOS 14+, SwiftUI, async/await, actors
- Project root: ~/Documents/localProject/merlin
- `SWIFT_STRICT_CONCURRENCY=complete` — zero warnings, zero errors required
- No third-party Swift packages in production or test targets
- Non-sandboxed macOS app
- Task files (source of truth): ~/Documents/localProject/merlin/tasks/

## Tasks Overview

| Task | File | What it does |
|-------|------|--------------|
| 200a  | task-200a-spawn-agent-error-isolation-tests.md | Failing tests for unknown agent warning + subagent failure isolation |
| 200b  | task-200b-spawn-agent-error-isolation.md | Fix BUG-001: `AgentRegistry.knownNames()`, `.systemNote` on unknown agent, `do-catch` in TaskGroup |
| 201a  | task-201a-compact-and-context-recovery-tests.md | Failing tests for `/compact` + `ProviderError.isContextLengthExceeded` + engine retry |
| 201b  | task-201b-compact-and-context-recovery.md | Fix BUG-002 + BUG-003: `/compact` slash, context-length auto-compact-retry |
| 202a  | task-202a-scroll-lock-tests.md | Failing tests for `ConversationWebView.Coordinator` `scrollLock` bridge message |
| 202b  | task-202b-scroll-lock.md | JS→Swift scroll-lock bridge, resume banner in `ChatView` |
| 203a  | task-203a-rewind-checkpoint-tests.md | Failing tests for `CheckpointStore` + `RewindCommand` |
| 203b  | task-203b-rewind-checkpoint.md | `/rewind` checkpoint save + restore |
| 204a  | task-204a-btw-overlay-tests.md | Failing tests for `BtwSession` |
| 204b  | task-204b-btw-overlay.md | `/btw` floating overlay with isolated provider call |

## Key Files

- `Merlin/Engine/AgenticEngine.swift` — bug fixes land here: spawn_agent isolation, context-length retry, checkpoint save, `/compact` emit
- `Merlin/Providers/ProviderError.swift` — add `isContextLengthExceeded` computed property
- `Merlin/Agents/AgentRegistry.swift` — add `knownNames() -> Set<String>`
- `Merlin/Views/ChatView.swift` — extend `handleSlashCommandIfNeeded` for `/compact`, `/rewind`, `/btw`; scroll-lock banner wiring
- `Merlin/Views/Chat/ConversationWebView.swift` — add `onScrollLockChange` callback + `handleBridgeBody` helper
- `Merlin/Views/Chat/ConversationHTMLRenderer.swift` — post `scrollLock` bridge message on `_userScrolled` change
- `Merlin/Sessions/SessionCheckpoint.swift` — **NEW** struct
- `Merlin/Sessions/CheckpointStore.swift` — **NEW** @MainActor class, capped at 50
- `Merlin/Sessions/RewindCommand.swift` — **NEW** parser
- `Merlin/Views/BtwSession.swift` — **NEW** @MainActor ObservableObject
- `Merlin/Views/BtwOverlayView.swift` — **NEW** SwiftUI view
- `TestHelpers/MockProvider.swift` — extend with `response:`, `delay:`, `failFirstCallWith:`, `failAllCallsWith:`, `callCount`
- `MerlinTests/Unit/SpawnAgentErrorIsolationTests.swift` — **NEW** (task 200a)
- `MerlinTests/Unit/ContextLengthRecoveryTests.swift` — **NEW** (task 201a)
- `MerlinTests/Unit/CompactSlashCommandTests.swift` — **NEW** (task 201a)
- `MerlinTests/Unit/ScrollLockTests.swift` — **NEW** (task 202a)
- `MerlinTests/Unit/CheckpointStoreTests.swift` — **NEW** (task 203a)
- `MerlinTests/Unit/RewindSlashCommandTests.swift` — **NEW** (task 203a)
- `MerlinTests/Unit/BtwSessionTests.swift` — **NEW** (task 204a)

## Do NOT Touch
- `ToolRouter.swift` — no changes needed
- `project.yml` — do not add packages or targets
- Any file not listed above unless a compile error forces a minimal fix

## Task-by-Task Requirements

### Task 200a — SpawnAgent Error Isolation Tests (failing)
Full spec: `tasks/task-200a-spawn-agent-error-isolation-tests.md`

Write `MerlinTests/Unit/SpawnAgentErrorIsolationTests.swift` exactly as specified.
4 tests:
- `test_knownNames_containsBuiltins`
- `test_knownNames_excludesUnregistered`
- `test_spawnAgent_unknownName_emitsSystemNote`
- `test_spawnAgent_unknownName_doesNotAbort_loopContinues`
- `test_spawnAgent_subagentProviderError_emitsSystemNote_notError`

Verify BUILD FAILED (symbols don't exist). Commit: `Task 200a — SpawnAgentErrorIsolationTests (failing)`

### Task 200b — SpawnAgent Error Isolation
Full spec: `tasks/task-200b-spawn-agent-error-isolation.md`

1. Add `knownNames() -> Set<String>` to `AgentRegistry`
2. In `handleSpawnAgents`: when `requestedDefinition == nil`, emit `.systemNote` warning naming the unknown agent and listing known agents
3. Wrap each subagent's TaskGroup task in `do-catch`; catch yields `.systemNote` error description
4. Add `agentName: String` to the local `SubagentPlan` struct
5. Extend `MockProvider` with `shouldFail: Bool`

Verify BUILD SUCCEEDED + all 200a tests pass. Commit: `Task 200b — SpawnAgent error isolation: unknown-agent warning + subagent failure catch (BUG-001)`

---

### Task 201a — /compact + Context-Length Recovery Tests (failing)
Full spec: `tasks/task-201a-compact-and-context-recovery-tests.md`

Write two test files:
- `MerlinTests/Unit/ContextLengthRecoveryTests.swift` — 5 tests for `ProviderError.isContextLengthExceeded` and engine retry behaviour
- `MerlinTests/Unit/CompactSlashCommandTests.swift` — 2 tests for compaction trigger

Verify BUILD FAILED. Commit: `Task 201a — ContextLengthRecoveryTests + CompactSlashCommandTests (failing)`

### Task 201b — /compact + Context-Length Recovery
Full spec: `tasks/task-201b-compact-and-context-recovery.md`

1. Add `isContextLengthExceeded: Bool` to `ProviderError` (HTTP 400 + body substring match)
2. In `AgenticEngine.runLoop` catch block: intercept `isContextLengthExceeded`, call `forceCompaction()`, emit systemNote, retry once; second failure surfaces as error
3. Add `contextLengthRetryCount` property; reset in `send(userMessage:)` alongside `ceilingContinuationCount`
4. Add `/compact` case to `handleSlashCommandIfNeeded`: call `forceCompaction()`, emit systemNote, return `true`
5. Add `activeContinuation` property + `emitSystemNote()` helper to `AgenticEngine`
6. Extend `MockProvider` with `failFirstCallWith:`, `failAllCallsWith:`, `callCount`

Verify BUILD SUCCEEDED + all tests pass. Commit: `Task 201b — /compact slash + context-length auto-compact-retry (BUG-002, BUG-003)`

---

### Task 202a — Scroll Lock Tests (failing)
Full spec: `tasks/task-202a-scroll-lock-tests.md`

Write `MerlinTests/Unit/ScrollLockTests.swift`. 5 tests for `ConversationWebView.Coordinator`:
- `test_scrollLock_true_message_sets_locked`
- `test_scrollLock_false_message_resumes`
- `test_unknown_message_type_does_not_crash`
- `test_scrollLock_message_without_locked_key_is_ignored`
- `test_coordinator_init_accepts_onScrollLockChange`

Uses `simulateBridgeMessage` extension on `Coordinator` that calls `handleBridgeBody`.

Verify BUILD FAILED. Commit: `Task 202a — ScrollLockTests (failing)`

### Task 202b — Scroll Lock
Full spec: `tasks/task-202b-scroll-lock.md`

1. In `ConversationHTMLRenderer` JS scroll listener: post `{type:'scrollLock', locked:'true'/'false'}` only when `_userScrolled` changes value. Add `merlin.resumeAutoScroll()` to the JS `merlin` object.
2. In `ConversationWebView`: add `onScrollLockChange: (Bool) -> Void` property; update `makeCoordinator()`; add `handleBridgeBody` extracting switch logic from `userContentController`; add `scrollLock` case routing to `onScrollLockChange`; add `resumeAutoScroll()` method
3. In `ConversationWebView.Coordinator.init`: add `onScrollLockChange` parameter
4. In `ChatView.messageList`: pass `onScrollLockChange` to `ConversationWebView`, updating `autoScrollEnabled` and `scrollLockVisible`
5. Place `scrollLockBanner(proxy:)` in an `.overlay(alignment: .bottom)` conditioned on `scrollLockVisible`
6. In `sendMessage()`: call `webView.resumeAutoScroll()` alongside clearing `scrollLockVisible`

Verify BUILD SUCCEEDED + all ScrollLockTests pass. Commit: `Task 202b — Scroll lock: JS→Swift bridge + resume banner`

---

### Task 203a — /rewind Checkpoint Tests (failing)
Full spec: `tasks/task-203a-rewind-checkpoint-tests.md`

Write two test files:
- `MerlinTests/Unit/CheckpointStoreTests.swift` — 10 tests for `CheckpointStore` and `SessionCheckpoint`
- `MerlinTests/Unit/RewindSlashCommandTests.swift` — 5 tests for `RewindCommand.parse`

Verify BUILD FAILED. Commit: `Task 203a — CheckpointStoreTests + RewindSlashCommandTests (failing)`

### Task 203b — /rewind Checkpoint Restoration
Full spec: `tasks/task-203b-rewind-checkpoint.md`

1. Write `Merlin/Sessions/SessionCheckpoint.swift` — `struct`, `Sendable`, `Identifiable`
2. Write `Merlin/Sessions/CheckpointStore.swift` — `@MainActor final class`, capped at 50, `save/restore/clear`
3. Write `Merlin/Sessions/RewindCommand.swift` — `enum` with `parse(_ input: String) -> (stepsBack: Int, valid: Bool)`
4. In `AgenticEngine`: add `checkpointStore: CheckpointStore`; call `checkpointStore.save(messages:)` before each user turn; `checkpointStore.clear()` on session reset
5. In `ChatView.handleSlashCommandIfNeeded`: add `/rewind` handling — parse with `RewindCommand.parse`, call `checkpointStore.restore(stepsBack:)`, call `contextManager.load` + `model.load(from:)`, emit systemNote

Verify BUILD SUCCEEDED + all tests pass. Commit: `Task 203b — /rewind checkpoint restoration`

---

### Task 204a — /btw Overlay Tests (failing)
Full spec: `tasks/task-204a-btw-overlay-tests.md`

Write `MerlinTests/Unit/BtwSessionTests.swift`. 8 tests for `BtwSession`:
- `ask()` calls provider exactly once
- `ask()` populates `answer`
- `ask()` does NOT modify any shared `ContextManager`
- `ask()` uses isolated message array (two parallel sessions don't contaminate each other)
- `isLoading` state transitions
- Error handling sets `error`, clears `answer`
- Initial state (nil answer/error, not loading)
- `reset()` clears all fields

Extend `MockProvider` with `response: String` and `delay: TimeInterval` parameters.

Verify BUILD FAILED. Commit: `Task 204a — BtwSessionTests (failing)`

### Task 204b — /btw Side-Question Overlay
Full spec: `tasks/task-204b-btw-overlay.md`

1. Extend `MockProvider` with `response:` and `delay:` init parameters
2. Write `Merlin/Views/BtwSession.swift` — `@MainActor final class ObservableObject` with `ask(question:provider:)` using an isolated `[Message]` (never touches `ContextManager`); `reset()`
3. Write `Merlin/Views/BtwOverlayView.swift` — floating `VStack` in a material background: input field (focused on appear), streaming answer in `ScrollView`, error label, dismiss button + Esc key handler, outside-click dismiss
4. In `ChatView`: add `showBtwOverlay: Bool` + `btwPrefill: String` state; add `/btw` case to `handleSlashCommandIfNeeded` (extracts argument as prefill); present `BtwOverlayView` via `.overlay` with spring animation and `Color.clear` tap-to-dismiss layer

Verify BUILD SUCCEEDED + all BtwSessionTests pass. Commit: `Task 204b — /btw side-question overlay`

---

## Acceptance Criteria
- [ ] BUILD SUCCEEDED with zero warnings, zero errors after each b-task
- [ ] All 200a tests pass after 200b
- [ ] All 201a tests pass after 201b
- [ ] All 202a tests pass after 202b
- [ ] All 203a tests pass after 203b
- [ ] All 204a tests pass after 204b
- [ ] Full test suite passes (no regressions): `xcodebuild -scheme MerlinTests test`
- [ ] Exactly 10 git commits created (200a–204b)

## Build Commands (use exactly these)

```bash
# Build for testing
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Run tests
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

## Additional Notes

- `AgenticEngine` is `@MainActor final class` — `CheckpointStore` is also `@MainActor`; no bridging issues
- `ConversationWebView.Coordinator` is `NSObject` — `handleBridgeBody` can be `internal` (not `private`) to allow the test-only `simulateBridgeMessage` extension to call it
- `BtwSession.ask(question:provider:)` must accept `any LLMProviderProtocol` — check the exact protocol name in `Merlin/Providers/LLMProvider.swift`; it may be `LLMProvider` or `ProviderAdapter`
- `RewindCommand` is a pure value-type enum with no stored state — it's safe to use from any actor context
- `CheckpointStore.restore(stepsBack:)` uses 0-based indexing from the end: `stepsBack=0` → most recent, `stepsBack=1` → one before that
- Scroll-lock JS change: post the message only when `nowLocked !== _userScrolled` to avoid flooding the bridge on every scroll event
- The `_stablePrefixDirty` / `_stablePrefixCached` pattern from task 197b should not interfere; these  tasks touch different sections of `AgenticEngine`
