# Phase 298b — Discipline Event Stream (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 298a complete: failing tests in `DisciplineEventStreamTests`. Unit C2 of the plan.

## Write to: Merlin/Discipline/DisciplineEvent.swift (new)

```swift
import Foundation

/// One structured event emitted by `merlin-discipline` during a gate run, written to
/// `<project>/.merlin/discipline-events.jsonl` so the app can observe CLI activity.
struct DisciplineEvent: Codable, Sendable {
    let timestamp: Date
    let subcommand: String      // "post-commit" | "pre-push"
    let step: String            // e.g. "why-comment-gate", "prose-gate", "result"
    let detail: String
    let passed: Bool?           // nil for progress steps; set on result
}
```

## Write to: Merlin/Discipline/DisciplineEventLog.swift (new)

An actor mirroring `OverrideAuditLog`'s JSONL pattern:
- `init(logPath: String)`
- `func record(_ event: DisciplineEvent) async throws` — append one JSON line.
- `func events(since date: Date) async -> [DisciplineEvent]` — parse + filter.

Foundation-only (it compiles in the CLI target too).

## Edit: Merlin/Discipline/DisciplineCLI.swift
Each gate step and the final result now also append a `DisciplineEvent` via
`DisciplineEventLog` at `<projectPath>/.merlin/discipline-events.jsonl`, in addition to
the human-readable stdout.

## Edit: Merlin/App/AppState.swift — app-side watcher
When a project is open, watch `<projectPath>/.merlin/discipline-events.jsonl` for new
events and surface them. Reuse the existing `~/.merlin/config.toml` file-watch mechanism
(locate it via `AppSettings` / `Merlin/Config/`). On new events, append a `.system`
`ToolLogLine` summarising the gate run (`"[discipline] pre-push: why-comment-gate —
passed"`) and call `pendingAttention.refresh(projectPath:)`. A 2-second poll of
`DisciplineEventLog.events(since:)` (like the `inject.txt` poll in `LiveSession`) is an
acceptable fallback if FSEvents wiring is heavier than warranted — choose the lighter
option that matches existing patterns.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:MerlinTests/DisciplineEventStreamTests
xcodebuild -scheme merlin-discipline build -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD SUCCEEDED for both; tests pass.

Runtime check: run `merlin-discipline pre-push <repo>`, confirm
`.merlin/discipline-events.jsonl` is written; with the app open on that project, confirm
a `[discipline]` system note appears.

## Commit
```
git add Merlin/Discipline/DisciplineEvent.swift Merlin/Discipline/DisciplineEventLog.swift \
  Merlin/Discipline/DisciplineCLI.swift Merlin/App/AppState.swift \
  phases/phase-298b-discipline-event-stream.md
git commit -m "Phase 298b — Discipline event stream"
```
