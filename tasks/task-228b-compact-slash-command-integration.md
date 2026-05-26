# Task 228b - Compact Slash Command Integration

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 228a complete: failing compact slash command integration tests exist.

---

## Add: Merlin/Views/SlashCommandHandler.swift

Extract slash-command routing into a small testable helper.

Rules:

1. `/compact` calls an injected compaction closure and returns `.consumed`.
2. `/calibrate` preserves existing behavior through injected action closure.
3. Unknown slash commands return `.notHandled`.
4. No SwiftUI environment is required to unit test the helper.

---

## Edit: Merlin/Views/ChatView.swift

Route existing slash-command handling through `SlashCommandHandler`.

Preserve current UI behavior and system notes.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `CompactSlashCommandTests` pass without placeholder assertions.

## Commit

```bash
git add Merlin/Views/SlashCommandHandler.swift Merlin/Views/ChatView.swift MerlinTests/Unit/CompactSlashCommandTests.swift
git commit -m "Task 228b - compact slash command integration"
```

