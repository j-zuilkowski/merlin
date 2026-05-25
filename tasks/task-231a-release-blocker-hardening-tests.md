# Phase 231a — Release Blocker Hardening Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 230b complete: App Intents/Siri support is in place.

New surface introduced in phase 231b:
  - `MemoryBackendPlugin.search(query:topK:projectPath:)` — scoped memory retrieval for the active project.
  - `LiveSession.close()` / `LiveSession.isClosed` — explicit teardown for per-session resources.
  - `AppSettings.scheduleWatchedConfigReload(for:delay:)` — debounced config reload scheduling for file-watch events.
  - `AppState.requestDecision(...)` — cancellation-safe auth continuation cleanup.

TDD coverage:
  File 1 — `LocalVectorPluginTests`: scoped local vector search excludes chunks from other projects.
  File 2 — `AuthMemoryTests`: auth memory writes persist with owner-only permissions.
  File 3 — `AppStateSessionTests`: cancelled auth requests clear pending popup state.
  File 4 — `SessionManagerTests`: closing a session calls explicit LiveSession teardown.
  File 5 — `AppSettingsTests`: rapid config-watch events coalesce to the final reload.

---

## Edit

- `MerlinTests/Unit/LocalVectorPluginTests.swift`
- `MerlinTests/Unit/AuthMemoryTests.swift`
- `MerlinTests/Unit/AppStateSessionTests.swift`
- `MerlinTests/Unit/SessionManagerTests.swift`
- `MerlinTests/Unit/AppSettingsTests.swift`

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming the missing phase 231b surfaces.

## Commit

```bash
git add tasks/task-231a-release-blocker-hardening-tests.md \
    MerlinTests/Unit/LocalVectorPluginTests.swift \
    MerlinTests/Unit/AuthMemoryTests.swift \
    MerlinTests/Unit/AppStateSessionTests.swift \
    MerlinTests/Unit/SessionManagerTests.swift \
    MerlinTests/Unit/AppSettingsTests.swift
git commit -m "Phase 231a — ReleaseBlockerHardeningTests (failing)"
```
