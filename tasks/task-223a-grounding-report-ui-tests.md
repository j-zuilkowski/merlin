# Task 223a - Grounding Report UI Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
`AgenticEngine` emits `AgentEvent.groundingReport`, but `ChatViewModel` currently ignores it.

New surface introduced in task 223b:
  - `ChatEntry.groundingReport`
  - `ChatViewModel.lastGroundingReport`
  - Conversation renderer displays compact grounding metadata for assistant turns with RAG context.

TDD coverage:
  File 1 - `GroundingReportUITests`: view-model stores report and renderer emits status markup.

---

## Add: MerlinTests/Unit/GroundingReportUITests.swift

Create tests that assert:

1. When `ChatViewModel` receives `.groundingReport(report)`, it stores `lastGroundingReport`.
2. The next assistant message receives that report on its `ChatEntry`.
3. `clear()` resets the stored report.
4. `ConversationHTMLRenderer.messageHTML(for:)` includes a compact grounding status when `ChatEntry.groundingReport != nil`.
5. Rendered status distinguishes grounded, ungrounded, and stale-memory cases without exposing raw JSON.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because `ChatEntry.groundingReport` and UI handling do not exist.

## Commit

```bash
git add MerlinTests/Unit/GroundingReportUITests.swift
git commit -m "Task 223a - GroundingReportUITests (failing)"
```

