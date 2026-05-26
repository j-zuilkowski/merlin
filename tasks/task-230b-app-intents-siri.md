# Task 230b - App Intents Siri Integration

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 230a complete: failing App Intents support tests exist.

---

## Edit: Merlin/Support/AppIntentsSupport.swift

Replace the metadata-only stub with real App Intent surfaces:

1. `StartMerlinSessionIntent`
2. `SendMerlinPromptIntent`

Rules:

1. Intent handlers delegate to injectable app/session actions.
2. Empty prompts fail validation with a user-readable error.
3. No provider client is constructed directly inside an intent.
4. Keep `MerlinMetadataIntent` only if Xcode metadata extraction still requires it.

---

## Edit: Merlin/App/AppState.swift

Expose the minimal intent delegation hooks needed by `AppIntentsSupport`.

Do not duplicate chat send logic; reuse existing session and engine entry points.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. App Intents support tests pass.

## Commit

```bash
git add Merlin/Support/AppIntentsSupport.swift Merlin/App/AppState.swift MerlinTests/Unit/AppIntentsSupportTests.swift
git commit -m "Task 230b - App Intents Siri integration"
```

