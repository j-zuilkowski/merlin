# Task 227a - Chat Renderer Dead-Code Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 166b replaced SwiftUI message rendering with `ConversationWebView`, but left superseded renderer helpers for follow-up cleanup.

New surface introduced in task 227b:
  - `ChatView.swift` contains no dead `RenderedMessage` type or legacy markdown helpers.
  - Conversation rendering remains covered by `ConversationHTMLRenderer`.

TDD coverage:
  File 1 - `ChatRendererCleanupTests`: source-level guard against resurrecting dead renderer helpers.

---

## Add: MerlinTests/Unit/ChatRendererCleanupTests.swift

Create a source-level test that reads `Merlin/Views/ChatView.swift` from the repository root and asserts:

1. It does not contain `private struct RenderedMessage`.
2. It does not contain `ChatEntryRow`.
3. It does not contain a legacy `markdownText` helper.
4. It does contain `ConversationWebView`.

Use the same repository-root resource pattern used by `MerlinV2VersionTests`.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because `RenderedMessage` still exists in `ChatView.swift`.

## Commit

```bash
git add MerlinTests/Unit/ChatRendererCleanupTests.swift
git commit -m "Task 227a - ChatRendererCleanupTests (failing)"
```

