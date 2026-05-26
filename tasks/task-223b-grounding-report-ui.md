# Task 223b - Grounding Report UI

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 223a complete: failing grounding report UI tests exist.

---

## Edit: Merlin/Views/ChatView.swift

Add `groundingReport: GroundingReport?` to `ChatEntry`.

Update `ChatViewModel`:

1. Store `lastGroundingReport`.
2. Handle `.groundingReport(let report)` by updating `lastGroundingReport`.
3. Attach the latest report to the active or next assistant entry.
4. Clear report state on new session.

---

## Edit: Merlin/Views/Chat/ConversationHTMLRenderer.swift

Render a compact grounding status in assistant bubbles when present.

Rules:

1. Keep it visually small and scannable.
2. Use labels derived from `GroundingReport` fields.
3. Do not render raw report JSON.
4. Preserve current tool-call and thinking rendering.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `GroundingReportUITests` pass.

## Commit

```bash
git add Merlin/Views/ChatView.swift Merlin/Views/Chat/ConversationHTMLRenderer.swift MerlinTests/Unit/GroundingReportUITests.swift
git commit -m "Task 223b - grounding report chat UI"
```

