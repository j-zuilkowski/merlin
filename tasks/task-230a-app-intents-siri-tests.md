# Task 230a - App Intents Siri Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
`MerlinMetadataIntent` is currently a minimal App Intents stub and Siri integration was deferred.

New surface introduced in task 230b:
  - `StartMerlinSessionIntent`
  - `SendMerlinPromptIntent`
  - AppIntent handlers route through existing session/app-state APIs without duplicating engine logic.

TDD coverage:
  File 1 - `AppIntentsSupportTests`: intent metadata, parameter validation, handler delegation.

---

## Add: MerlinTests/Unit/AppIntentsSupportTests.swift

Create tests that assert:

1. Merlin exposes at least one user-facing App Intent beyond metadata.
2. Start-session intent creates or requests a new session through an injected session action.
3. Send-prompt intent rejects empty prompts.
4. Send-prompt intent delegates to an injected prompt action with the exact prompt text.
5. Intent handlers do not directly instantiate provider clients.

Use small injectable closures/protocols so tests do not invoke Siri or the live app.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because only the metadata stub intent exists.

## Commit

```bash
git add MerlinTests/Unit/AppIntentsSupportTests.swift
git commit -m "Task 230a - AppIntentsSupportTests (failing)"
```

