# Task 228a - Compact Slash Command Integration Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
`CompactSlashCommandTests` still contains a placeholder assertion for the ChatView wiring check.

New surface introduced in task 228b:
  - Slash command handling is testable without a live SwiftUI environment.
  - `/compact` integration test proves the message is consumed and not forwarded to provider.

TDD coverage:
  File 1 - `CompactSlashCommandTests`: replace placeholder with real slash-command routing test.

---

## Edit: MerlinTests/Unit/CompactSlashCommandTests.swift

Replace the placeholder test with a real test that asserts:

1. `/compact` invokes `ContextManager.forceCompaction()`.
2. `/compact` is consumed and not forwarded to `AgenticEngine.send(userMessage:)`.
3. `/compact extra text` still compacts and is not forwarded.
4. Unknown slash commands are not consumed.

If `ChatView.handleSlashCommandIfNeeded` is private and hard to call, introduce a small pure helper in task 228b and write the test against that helper.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because slash-command handling is not directly testable yet.

## Commit

```bash
git add MerlinTests/Unit/CompactSlashCommandTests.swift
git commit -m "Task 228a - CompactSlashCommand integration tests (failing)"
```

