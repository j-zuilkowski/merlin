# Phase 172a — ContextPreRunCompactionTests: standalone tool messages (failing — pre-existing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 171b complete: criticOverride fix in AgenticEngineV5Tests.

## Problem

`ContextPreRunCompactionTests.testTokensReducedAfterPreRunCompaction` fails because
`ContextManager.compact(force: true)` only removes complete assistant+tool exchange groups.
When the context contains standalone `.tool` messages (no preceding assistant message
with `tool_calls`), `groupsToRemove` is empty. The `groupsToRemove.isEmpty && force`
branch at ~line 143 simply appends a `[context compacted]` marker without removing
any messages — so token count is unchanged.

Root cause: `Merlin/Engine/ContextManager.swift` ~line 143.

## Existing test file

`MerlinTests/Unit/ContextPreRunCompactionTests.swift` — already committed.
Failing test: `testTokensReducedAfterPreRunCompaction`

## Verify (current state — expected FAILING)

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ContextPreRunCompaction.*failed|BUILD' | head -10
```

Expected: `testTokensReducedAfterPreRunCompaction` fails.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add phases/phase-172a-context-compaction-tool-msgs-tests.md
git commit -m "Phase 172a — ContextPreRunCompaction standalone-tool failure documented"
```
