# Task 225a - Floating Window Runtime Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
`FloatingWindowManager` still contains a `FloatingWindowStubView` fallback with placeholder text in test/runtime-unavailable contexts.

New surface introduced in task 225b:
  - Floating windows always host a real chat-capable view model.
  - Testability is achieved by injecting a deterministic runtime environment instead of rendering a placeholder UI.

TDD coverage:
  File 1 - `FloatingWindowRuntimeTests`: root view selection, session binding, close behavior.

---

## Add: MerlinTests/Unit/FloatingWindowRuntimeTests.swift

Create tests that assert:

1. `FloatingWindowManager` can be initialized with a test runtime mode that still builds the real floating chat container.
2. Opening a floating session does not choose a placeholder view.
3. The floating chat view is bound to the supplied `Session`.
4. Closing the window removes it from the manager's window registry.
5. Always-on-top mode sets window level to `.floating`.

Use dependency injection around window creation if direct `NSWindow` inspection is too brittle.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because the manager still uses a placeholder fallback and lacks injectable runtime mode.

## Commit

```bash
git add MerlinTests/Unit/FloatingWindowRuntimeTests.swift
git commit -m "Task 225a - FloatingWindowRuntimeTests (failing)"
```

