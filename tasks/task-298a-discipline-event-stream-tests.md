# Task 298a — Discipline Event Stream Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Unit C2 of the wiring plan. Task 297 complete (the `merlin-discipline` CLI exists).

The CLI runs gates in a git-hook subprocess — outside the app. To keep it observable,
the CLI writes a structured JSONL event stream to `<project>/.merlin/discipline-events.jsonl`,
and the app watches that file and surfaces each gate run.

New surface in task 298b:
  - `DisciplineEvent` — `Codable, Sendable` event (`timestamp`, `subcommand`, `step`,
    `detail`, `passed: Bool?`).
  - `DisciplineEventLog` (actor) — `record(_:)`, `events(since:)`, reading/appending
    `discipline-events.jsonl` (mirror `OverrideAuditLog`'s JSONL approach).
  - `DisciplineCLI` appends a `DisciplineEvent` per step and a final result event.
  - App-side: `AppState` watches `discipline-events.jsonl` and surfaces new events as
    `.system` tool-log lines / a chip refresh.

TDD coverage:
  `MerlinTests/Unit/DisciplineEventStreamTests.swift` — `DisciplineEventLog` round-trips
  events; `DisciplineCLI.run` writes at least one event to `discipline-events.jsonl`.

## Write to: MerlinTests/Unit/DisciplineEventStreamTests.swift

```swift
import XCTest
@testable import Merlin

/// Task 298a — failing tests for the discipline event stream.
final class DisciplineEventStreamTests: XCTestCase {

    private func makeTmpProject() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("des-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testEventLogRoundTrip() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let log = DisciplineEventLog(
            logPath: project.appendingPathComponent(".merlin/discipline-events.jsonl").path)
        try await log.record(DisciplineEvent(
            timestamp: Date(), subcommand: "pre-push", step: "why-comment-gate",
            detail: "scanned 3 files", passed: true))
        let events = await log.events(since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.step, "why-comment-gate")
        XCTAssertEqual(events.first?.passed, true)
    }

    func testCLIWritesEvents() async {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        _ = await DisciplineCLI.run(arguments: ["merlin-discipline", "post-commit", project.path])
        let log = DisciplineEventLog(
            logPath: project.appendingPathComponent(".merlin/discipline-events.jsonl").path)
        let events = await log.events(since: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(events.isEmpty, "a CLI run must emit at least one event")
    }
}
```

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD FAILED — `DisciplineEvent`, `DisciplineEventLog` do not exist.

## Commit
```
git add MerlinTests/Unit/DisciplineEventStreamTests.swift tasks/task-298a-discipline-event-stream-tests.md
git commit -m "Task 298a — Discipline event stream tests (failing)"
```
