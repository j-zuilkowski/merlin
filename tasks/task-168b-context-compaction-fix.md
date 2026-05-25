# Task 168b — Context Compaction Fix (remove complete exchange pairs)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 168a complete: ContextCompactionTests in place (failing).

---

## Root cause (confirmed via telemetry at ~/.merlin/telemetry.jsonl)

Every HTTP 400 from DeepSeek Flash in multi-step xcalibre-server sessions was:

```json
{
  "error": {
    "message": "An assistant message with 'tool_calls' must be followed by tool messages
                responding to each 'tool_call_id'. (insufficient tool messages following
                tool_calls message)"
  }
}
```

**Sequence that triggers it:**

1. User submits xcalibre-server task.
2. Planner creates 4 steps; step 1 runs this turn on the execute slot (Flash).
   Steps 2–4 are stored as `pendingContinuationSteps`.
3. After each step completes, `schedulePendingContinuation()` writes a
   `[CONTINUATION]` message to disk. AppState picks it up and calls `send()`.
4. Continuation turns are classified as `.highStakes` → `workingSlot = .reason`
   → Provider = DeepSeek Pro (supportsThinking: true).
5. Pro runs continuation steps 2–4 with thinking enabled (xcalibre prompt contains
   "failing", which triggers `ThinkingModeDetector`). Each step makes tool calls
   and stores assistant messages carrying `reasoning_content` in context.
6. After 3–4 continuation turns (each reading files), `estimatedTokens` exceeds
   the `preRunCompactionThreshold` (10 000 tokens).
7. The user's next message (non-continuation) triggers `compactIfNeededBeforeRun`.
8. The old `compact()` removes `role == .tool` messages but leaves their
   preceding `role == .assistant` messages that carried `toolCalls`
   (and, for Pro turns, `reasoning_content`).
9. The next request to Flash contains these orphaned assistant messages →
   HTTP 400.

---

## Fix: Merlin/Engine/ContextManager.swift

Replace the `compact()` logic to find and remove complete **exchange groups**:
one assistant message with `toolCalls` + all consecutive tool result messages
that follow it.  Partial groups (lone tool results without a preceding assistant
message) are left alone — they are edge-case residue and pose no API risk.

Key change in pseudo-code:

```
Old: indicesToCompact = indices of all role==.tool messages in old part of history
     rebuild = messages minus indicesToCompact     ← leaves orphaned assistant messages

New: groups = [(assistantIdx, [toolResultIndices...])] for each exchange in history
     groupsToRemove = old groups (older than recentStart), or all groups if forced
     allIndices = flatMap groupsToRemove to get both assistant and tool result indices
     rebuild = messages minus allIndices            ← no orphaned messages possible
```

### Updated summary message

The summary line changes from:

```
[context compacted — N tool results summarised] …
```

to:

```
[context compacted — N tool exchange(s) summarised] …
```

---

## Edit: Merlin/Engine/ContextManager.swift

(see source for full implementation of the revised `compact()` method)

---

## Edit: MerlinTests/Unit/ContextManagerTests.swift

`testCompactionFiresAt800k` and `testCompactionPreservesUserAssistantMessages`
updated to use proper exchange pairs (assistant tool_call + tool result) so the
new compact logic can find and remove them.  The old tests appended bare tool
messages without a preceding assistant tool_call, which is not a valid context
state and would not be compacted under either the old or the new logic.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED, all 168a ContextCompactionTests pass.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ContextManager.swift \
        MerlinTests/Unit/ContextManagerTests.swift \
        tasks/task-168b-context-compaction-fix.md
git commit -m "Task 168b — Fix context compaction: remove complete exchange pairs"
```
