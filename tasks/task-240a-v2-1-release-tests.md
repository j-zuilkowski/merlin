# Task 240a — v2.1.0 Release Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Tasks 232b–239b complete: budget-aware execution shipped end to end.

This is the release milestone for v2.1.0 — "Budget-Aware Execution." Per the versioning policy
in `spec.md` § Versioning Policy:
  - new feature / task milestone / behaviour change → minor bump → MARKETING_VERSION `2.0.0` → `2.1.0`
  - CURRENT_PROJECT_VERSION `15` → `16` (strictly-increasing integer)

New surface introduced in task 240b:
  - `project.yml` carries `MARKETING_VERSION: "2.1.0"` and `CURRENT_PROJECT_VERSION: 16`.
  - `RELEASE-v2.1.0.md` at repo root summarising the eight-task budget-aware execution work,
    matching the existing `RELEASE-v2.0.0.md` format.
  - "About Merlin" displays version `2.1.0` (verified manually post-build; an automated test
    asserts the bundle's `CFBundleShortVersionString` via `Bundle.main.infoDictionary`).
  - `constitution.md` "Current version" line updated.

`spec.md` already contains the "V2.1 — Budget-Aware Execution" section (written before
the task series began). Task 240b does **not** modify `spec.md`. The architectural
content of v2.1.0 is its source of truth;  tasks only need to *match* it, not extend it.

TDD coverage:
  File 1 — `MerlinTests/Unit/AppVersionTests.swift`: `Bundle.main.infoDictionary?["CFBundleShortVersionString"]
    as? String == "2.1.0"` and `CFBundleVersion == "16"`. (Set as failing until 240b lands the
    project.yml update.)
  File 2 — `MerlinTests/Unit/ReleaseNotesPresenceTests.swift`: `RELEASE-v2.1.0.md` exists at
    repo root and contains the expected section headers (`## Summary`, `## What's new`,
    `## Internal changes`, `## Migration`).

---

## Edit

- `MerlinTests/Unit/AppVersionTests.swift`
- `MerlinTests/Unit/ReleaseNotesPresenceTests.swift`

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Build should succeed but the new tests fail until 240b runs (the version is still 2.0.0 and
the release notes file does not yet exist).

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: `AppVersionTests` and `ReleaseNotesPresenceTests` fail; all other tests pass.

## Commit

```bash
git add tasks/task-240a-v2-1-release-tests.md \
    MerlinTests/Unit/AppVersionTests.swift \
    MerlinTests/Unit/ReleaseNotesPresenceTests.swift
git commit -m "Task 240a — V2_1ReleaseTests (failing)"
```
