# Phase 278b — v2.2.2 Release

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 278a complete: failing version + release-notes tests are in place.

This phase ships **v2.2.2** — the phase 274–277 CI-readiness remediation and engine
regression fixes, as a patch release. Follow `architecture.md` § Versioning Policy.
Tag locally only; the push and GitHub release are an explicit manual step (as with 273b).

---

## Edit

- `project.yml`:
    - `MARKETING_VERSION: "2.2.1"` → `MARKETING_VERSION: "2.2.2"`.
    - `CURRENT_PROJECT_VERSION: 18` → `CURRENT_PROJECT_VERSION: 19`.
    - Under `MerlinTests` → `resources:`, add a third entry `- path: RELEASE-v2.2.2.md`
      (keep the existing `project.yml` and `RELEASE-v2.2.1.md` entries).
- **Delete** `MerlinTests/Unit/AppVersion221Tests.swift`. It asserts the bundle version
  is `2.2.1` / build `18`; after this bump it would fail. It is superseded by
  `AppVersion222Tests`. (`ReleaseNotes221Tests.swift` stays — `RELEASE-v2.2.1.md` still
  exists and that test still passes.)
- **Version banners — update every doc that carries one** (2.2.1 → 2.2.2, build 18 → 19):
    - `CLAUDE.md`: `**Current version: 2.2.1** (build 18, tag v2.2.1)` →
      `**Current version: 2.2.2** (build 19, tag v2.2.2)`.
    - `README.md`: `**Version 2.2.1** (build 18, tag v2.2.1)` →
      `**Version 2.2.2** (build 19, tag v2.2.2)`.
    - `Merlin/Docs/UserGuide.md`: `**Version 2.2.1**` → `**Version 2.2.2**`.
    - `Merlin/Docs/DeveloperManual.md`: `**Version 2.2.1**` → `**Version 2.2.2**`.
    - `Requirements.md`: `Current version: **2.2.1** (build 18)` →
      `Current version: **2.2.2** (build 19)`.
- `RELEASE-v2.2.2.md` — new file at the repository root, content below.
- After all edits run `xcodegen generate`.

### RELEASE-v2.2.2.md

```markdown
# Merlin v2.2.2 — Project Discipline: CI Readiness & Regression Fixes

Released: 2026-05-15

## Summary

v2.2.2 makes the v2.2 Project Discipline subsystem real and the test suite green on a
headless runner. It wires the discipline engine and pending-attention chip into the
running app, gates environment-dependent engine tests behind an opt-in so GitHub CI
passes, and fixes two genuine engine regressions found in code review. It also adds a
full external-dependency inventory.

## What's new

- The Project Discipline subsystem is now wired into the running app: `DisciplineEngine`
  is constructed in `AppState`, the pending-attention chip/panel appear in `ChatView`,
  the `SessionStart` hook surfaces findings, and a scan runs after each turn.
- Live-environment test gate: engine tests that need a real LLM endpoint are gated
  behind `RUN_LIVE_TESTS=1` (`skipUnlessLiveEnvironment()`), so CI and headless sandboxes
  run green; developers opt in for full coverage.
- `Requirements.md` — a complete external-dependency inventory (toolchain, providers,
  local runners, models, LoRA, KiCad, doc tools, services, MCP, frameworks) with a
  source link for every dependency.

## Internal changes

- Fixed the pending-attention chip showing stale data — the view model now reads through
  the shared `DisciplineEngine` instead of a separate queue instance.
- Fixed an unbounded context-overrun retry: `EscalationHandler` now consumes its
  per-turn budget on every escalation attempt, closing a loop that retried ~199 times
  without a terminal event.
- Fixed `parseSteps` silently dropping a planner step (and a downstream crash):
  `ComplexityTier` now decodes `high_stakes` / `highStakes` / `high-stakes` and falls
  back to `.standard` for unknown values.
- Removed the dead `TelemetryRecorder` / `TelemetrySink` / `TelemetryEmitter.sink` test
  seam; telemetry tests use the file-based `resetForTesting` / `flushForTesting` API via
  a shared `readTelemetryEvents(fromFile:)` helper.
- CI workflow: the build step now uses `set -o pipefail` so a failed build fails the job.

## Migration

- No user data migration required.
- The `v2.2.1` tag remains at the Phase 273b commit as an unreleased intermediate;
  v2.2.2 is the published successor to v2.2.0.
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and **all phase 278a tests pass** (`AppVersion222Tests`,
`ReleaseNotes222Tests`). The full suite is green headless — zero failures. `AppVersion221Tests`
is gone.

Then run the version-banner sweep and confirm there is no stale string left:

```bash
grep -rnE "2\.2\.1|build 18|Version 2\.0|2\.0\.0" \
    README.md CLAUDE.md Requirements.md Merlin/Docs/UserGuide.md Merlin/Docs/DeveloperManual.md
```

Expected: **no output** except, in `CLAUDE.md`, the historical "Versioning" example text
if any. Every "current version" / "Version" banner must read `2.2.2` / build `19`. If any
doc still shows an older version, fix it before committing.

## Commit & tag

```bash
cd ~/Documents/localProject/merlin
git add phases/phase-278b-v2-2-2-release.md \
    project.yml \
    CLAUDE.md \
    README.md \
    Requirements.md \
    Merlin/Docs/UserGuide.md \
    Merlin/Docs/DeveloperManual.md \
    RELEASE-v2.2.2.md \
    Merlin.xcodeproj/project.pbxproj \
    MerlinTests/Unit/AppVersion222Tests.swift \
    MerlinTests/Unit/ReleaseNotes222Tests.swift \
    phases/phase-278a-v2-2-2-release-tests.md
git rm MerlinTests/Unit/AppVersion221Tests.swift
git commit -m "Phase 278b — Bump version to 2.2.2 (build 19)"

git tag v2.2.2
```

Create the LOCAL tag only. **Do not** `git push` and **do not** run `gh release create`
— the push and GitHub release are an explicit manual step for the user.

## PASTE-LIST update

Append phase 278a/278b under the Project Discipline section and mark v2.2.2 as the
release that ships the CI-readiness remediation.
