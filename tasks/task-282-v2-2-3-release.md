# Task 282 — v2.2.3 Release

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 281 complete: built-in skills (incl. the 5 `project:*` skills) are now bundled
into the app.

This task ships **v2.2.3** — the skill-installation fix from task 281, as a patch
release. Follows `spec.md` § Versioning Policy.

---

## Edit

- `project.yml`:
    - `MARKETING_VERSION: "2.2.2"` → `"2.2.3"`.
    - `CURRENT_PROJECT_VERSION: 19` → `20`.
    - Under `MerlinTests` → `resources:`, add `- path: RELEASE-v2.2.3.md`.
- **Version banners — every doc that carries one** (2.2.2 → 2.2.3, build 19 → 20):
    - `constitution.md`: `**Current version: 2.2.3** (build 20, tag v2.2.3)`.
    - `README.md`: `**Version 2.2.3** (build 20, tag v2.2.3)`.
    - `Merlin/Docs/UserGuide.md`: `**Version 2.2.3**`.
    - `Merlin/Docs/DeveloperManual.md`: `**Version 2.2.3**`.
    - `Requirements.md`: `Current version: **2.2.3** (build 20).`
- **Version tests:** delete `MerlinTests/Unit/AppVersion222Tests.swift` (asserts the old
  2.2.2/19 bundle version — would fail after the bump). Add `AppVersion223Tests.swift`
  (asserts 2.2.3 / 20) and `ReleaseNotes223Tests.swift` (`RELEASE-v2.2.3.md` exists with
  the four required sections). The `ReleaseNotes221Tests` / `ReleaseNotes222Tests` stay —
  their release-notes files still exist and those tests still pass.
- `RELEASE-v2.2.3.md` — new file at the repo root (Summary / What's new / Internal
  changes / Migration).
- `Info.plist` needs no edit — `CFBundleShortVersionString` / `CFBundleVersion` use
  `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`.
- Run `xcodegen generate`.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Then confirm no stale version string remains:

```bash
grep -rnE "2\.2\.2|build 19" README.md constitution.md Requirements.md \
    Merlin/Docs/UserGuide.md Merlin/Docs/DeveloperManual.md
```

Expected: **BUILD SUCCEEDED**; the grep returns nothing. CI runs the full suite —
`AppVersion223Tests` and `ReleaseNotes223Tests` pass once the version is 2.2.3.

## Release

Commit, tag `v2.2.3`, push, and create the GitHub release per the Versioning Policy.
The DMG (`scripts/package-dmg.sh`) reads the version from `project.yml` and produces
`dist/Merlin-2.2.3.dmg`.

## Fixes

Ships the task 281 built-in-skill bundling fix as v2.2.3.
