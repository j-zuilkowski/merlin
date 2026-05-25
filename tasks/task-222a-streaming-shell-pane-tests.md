# Phase 222a - Streaming Shell Pane Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Architecture currently marks the streaming shell pane as deferred.

New surface introduced in phase 222b:
  - `ShellStreamViewModel` - consumes `ShellTool.stream()` output incrementally.
  - `TerminalPane` displays live stdout/stderr lines and exit status.
  - Shell streaming can be canceled from UI without killing unrelated processes.

TDD coverage:
  File 1 - `ShellStreamViewModelTests`: line ordering, stderr styling metadata, cancellation, exit status.

---

## Add: MerlinTests/Unit/ShellStreamViewModelTests.swift

Create tests that use a fake `AsyncThrowingStream<ShellOutputLine, Error>`.

Assert:

1. stdout and stderr lines append in arrival order.
2. stderr lines are marked as error output.
3. completion records the process exit status.
4. thrown stream errors surface as a terminal error state.
5. cancel stops consuming future stream values.

No real shell process in unit tests.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because `ShellStreamViewModel` does not exist.

## Commit

```bash
git add MerlinTests/Unit/ShellStreamViewModelTests.swift
git commit -m "Phase 222a - ShellStreamViewModelTests (failing)"
```

