# Task 222b - Streaming Shell Pane

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 222a complete: failing shell stream view-model tests exist.

---

## Add: Merlin/Views/ShellStreamViewModel.swift

Implement `@MainActor final class ShellStreamViewModel: ObservableObject`.

Rules:

1. Consume `ShellTool.stream()` via `Task`.
2. Publish append-only line records with stream kind, text, timestamp, and optional exit status.
3. Support cancellation.
4. Never run shell commands in unit tests; inject a stream factory.

---

## Edit: Merlin/Views/TerminalPane.swift

Wire `ShellStreamViewModel` into the existing terminal pane.

Rules:

1. Show stdout/stderr live.
2. Keep layout stable during streaming.
3. Provide a stop button that cancels only the active stream task.
4. Preserve existing placeholder behavior when no command has run.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `ShellStreamViewModelTests` pass.

## Commit

```bash
git add Merlin/Views/ShellStreamViewModel.swift Merlin/Views/TerminalPane.swift MerlinTests/Unit/ShellStreamViewModelTests.swift
git commit -m "Task 222b - streaming shell pane"
```

