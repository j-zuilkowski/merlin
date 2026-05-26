# Task 227b - Chat Renderer Dead-Code Cleanup

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 227a complete: failing chat renderer cleanup tests exist.

---

## Edit: Merlin/Views/ChatView.swift

Remove unused legacy renderer code:

1. `RenderedMessage`
2. Any remaining `ChatEntryRow`
3. Any remaining `markdownText` helper

Do not change `ConversationWebView`, `ConversationHTMLRenderer`, `ChatEntry`, or tool-call behavior except where needed to remove dead code.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. Chat renderer cleanup tests pass.

## Commit

```bash
git add Merlin/Views/ChatView.swift MerlinTests/Unit/ChatRendererCleanupTests.swift
git commit -m "Task 227b - remove dead chat renderer helpers"
```

