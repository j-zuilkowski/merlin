# Phase 168a — ContextCompaction Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 167b complete: ProviderError + engine-level retry implemented.

## Root cause confirmed via telemetry (~/.merlin/telemetry.jsonl)

Every HTTP 400 from DeepSeek Flash in the xcalibre-server sessions carries:

```json
{"error":{"message":"An assistant message with 'tool_calls' must be followed by tool messages responding to each 'tool_call_id'. (insufficient tool messages following tool_calls message)"}}
```

**Root cause**: `ContextManager.compact()` removes `role == .tool` messages but leaves their
preceding `role == .assistant` messages whose `toolCalls` property is non-nil. The provider
then receives a context with orphaned assistant tool_call messages and no matching tool results
→ HTTP 400.

A secondary error also appears in later sessions:

```json
{"error":{"message":"The `reasoning_content` in the thinking mode must be passed back to the API."}}
```

This is the same root cause: when the reason-slot (Pro) ran continuation turns with
thinking enabled, its assistant messages carried `reasoning_content`. After compaction removed
the tool results but left those assistant messages, Flash's next request had orphaned assistant
messages containing `reasoning_content` — which Flash does not accept.

Both errors are resolved by the same fix: compact whole exchange groups instead of lone
tool result messages.

## New surface introduced in phase 168b

- `ContextManager.compact()` — now removes complete (assistant + tool results) exchange
  pairs rather than only the tool result messages.

## TDD coverage

File — `ContextCompactionTests`:
- `test_forceCompact_removesAssistantToolCallMessage_withToolResults` — orphaned tool_call message is NOT left after force compact
- `test_forceCompact_removesAssistantWithReasoningContent_withToolResults` — same, with reasoning content
- `test_compactionOnAppend_removesCompleteExchangePairs` — auto-compaction also removes full pairs
- `test_compactIfNeeded_nonContinuation_noOrphans` — pre-run compaction leaves no orphans
- `test_compactIfNeeded_continuation_doesNotFire` — continuation turns skip compaction
- `test_forceCompact_preservesRecentExchanges` — recent exchanges survive
- `test_compact_preservesRegularAssistantMessages` — non-tool-call assistant messages survive
- `test_tokenThreshold_dropsBelow800k_withExchangePairs` — 800K threshold still works with pairs
- `test_preservesUserMessages_afterCompaction` — user messages survive (regression guard)

---

## Write to: MerlinTests/Unit/ContextCompactionTests.swift

(file written directly — see source tree)

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED, most `ContextCompactionTests` fail (orphaned tool_call messages
exist in old compact logic).

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ContextCompactionTests.swift \
        phases/phase-168a-context-compaction-tests.md
git commit -m "Phase 168a — ContextCompactionTests (failing)"
```
