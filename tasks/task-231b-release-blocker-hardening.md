# Task 231b — Release Blocker Hardening

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 231a complete: failing tests are in place for release-blocking isolation and lifecycle fixes.

---

## Edit

- `Merlin/Memories/MemoryBackendPlugin.swift`
- `Merlin/Memories/LocalVectorPlugin.swift`
- `Merlin/Engine/AgenticEngine.swift`
- `Merlin/Auth/AuthMemory.swift`
- `Merlin/App/AppState.swift`
- `Merlin/Sessions/LiveSession.swift`
- `Merlin/Sessions/SessionManager.swift`
- `Merlin/Config/AppSettings.swift`

Implemented:
  - Local memory search accepts a project path and `AgenticEngine` passes `currentProjectPath` into RAG memory retrieval.
  - `AuthMemory.save()` sets auth file permissions to `0600` after atomic writes.
  - AppState stores all NotificationCenter observer tokens, removes them in `deinit`, drops the initial settings change sink event, and resumes pending auth continuations on cancellation.
  - LiveSession tracks lifecycle tasks, cancels them on close, and stops MCP, automation, memory timers, and active engine work.
  - Stream finish state is an actor rather than an unchecked mutable class.
  - AppSettings debounces file-watch reloads and cancels pending reloads when watching stops.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all task 231a tests pass.

## Commit

```bash
git add tasks/task-231b-release-blocker-hardening.md \
    Merlin/Memories/MemoryBackendPlugin.swift \
    Merlin/Memories/LocalVectorPlugin.swift \
    Merlin/Engine/AgenticEngine.swift \
    Merlin/Auth/AuthMemory.swift \
    Merlin/App/AppState.swift \
    Merlin/Sessions/LiveSession.swift \
    Merlin/Sessions/SessionManager.swift \
    Merlin/Config/AppSettings.swift
git commit -m "Task 231b — Release blocker hardening"
```
