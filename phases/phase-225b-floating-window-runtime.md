# Phase 225b - Floating Window Runtime

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 225a complete: failing floating-window runtime tests exist.

---

## Edit: Merlin/Windows/FloatingWindowManager.swift

Remove `FloatingWindowStubView`.

Add minimal injection points needed for tests:

1. Runtime mode or environment predicate.
2. Window factory if needed for deterministic unit testing.
3. Root-view factory that defaults to `FloatingChatView`.

Rules:

1. Production behavior must always render the real floating chat UI.
2. Tests must not require launching a visible app window unless already established in the test target.
3. Preserve close tracking and `alwaysOnTop` behavior.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. Floating window runtime tests pass.

## Commit

```bash
git add Merlin/Windows/FloatingWindowManager.swift MerlinTests/Unit/FloatingWindowRuntimeTests.swift
git commit -m "Phase 225b - floating window real runtime"
```

