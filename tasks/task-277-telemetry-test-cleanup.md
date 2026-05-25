# Phase 277 — Telemetry Test-Seam Cleanup

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 276b complete: v2.2.1 + CI-readiness remediation landed; full suite green headless.

This is a **cleanup phase** (no new behaviour, single task file — no NNa/NNb pair).
Commit `ad67f38` ("Stabilize telemetry tests for full-suite runs") migrated ~9 telemetry
tests from the in-memory `TelemetryEmitter.sink` + `TelemetryRecorder` seam to the
file-based `resetForTesting(path:)` / `flushForTesting()` API. That migration was correct
— the old seam had no flush barrier and raced in full-suite runs — but it left debt:

1. `TelemetryRecorder`, the `TelemetrySink` protocol, and `TelemetryEmitter.sink` are now
   referenced by nothing — dead code.
2. The ~10-line "read JSONL file → parse events" block is copy-pasted into 9 test files.
3. `PendingAttentionViewModelTests.testEmptyQueueAfterLastDismiss` had its assertion
   weakened from `XCTAssertTrue(vm.findings.isEmpty)` to
   `XCTAssertFalse(vm.findings.contains(dismissed))`. The scan in that test legitimately
   produces two findings (a `phaseDrift` and a `docStaleReference`); the test dismisses
   only one, so the strong assertion failed. The test name still claims "EmptyQueue
   AfterLastDismiss" — it must dismiss *every* finding and then assert empty.
4. Four task docs still describe the removed `TelemetryRecorder` / `sink` seam.

This phase removes the dead code, deduplicates the helper, fixes the misleading test,
and updates the documentation.

---

## Edit 1 — Delete the dead telemetry test seam

- **Delete** `TestHelpers/TelemetryRecorder.swift` (`git rm`). It is referenced by no
  other file.
- `Merlin/Telemetry/TelemetryEmitter.swift` — remove the now-unused seam. Confirm each
  symbol is unreferenced before removing (grep), then delete:
    - the `public protocol TelemetrySink` declaration,
    - the `public nonisolated(unsafe) static var sink` property,
    - the `Self.sink?.record(e)` call inside `emit(...)`,
    - the `var name: String { event }` "backward-compatible alias for older test and
      sink code" on `TelemetryEvent` — confirm it is unreferenced and remove it.
  Leave `TelemetrySpan`, `resetForTesting(path:)`, and `flushForTesting()` untouched —
  those are live.

## Edit 2 — Deduplicate the telemetry-file reader

- New file `TestHelpers/TelemetryTestSupport.swift`:

  ```swift
  import Foundation

  /// Reads a telemetry JSONL file written via `TelemetryEmitter.resetForTesting(path:)`
  /// and returns the decoded event objects. Returns `[]` when the file is missing or
  /// empty. Pair with `await TelemetryEmitter.shared.flushForTesting()` before calling.
  func readTelemetryEvents(fromFile path: String) -> [[String: Any]] {
      guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let content = String(data: data, encoding: .utf8) else {
          return []
      }
      return content
          .split(separator: "\n", omittingEmptySubsequences: true)
          .compactMap { line in
              try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
          }
  }
  ```

- In each of the 9 telemetry test files below, replace the inline
  `if let data = try? Data(contentsOf:…) … .split(…).compactMap(…)` block with a single
  `let events = readTelemetryEvents(fromFile: tempPath)` call. Keep each test's own
  per-event `.filter { $0["event"] as? String == "…" }` at the call site. Files:
    - `AdaptiveRAGIntegrationTests.swift`
    - `DisciplineEngineTests.swift`
    - `IterationCapEscalationTests.swift`
    - `PlannerRefineTelemetryTests.swift`
    - `PlannerStepTelemetryTests.swift`
    - `PreflightGateTests.swift`
    - `PreflightOkTelemetryTests.swift`
    - `PreflightTelemetryTests.swift`
    - `TelemetryErrorBodyTests.swift`
  Behaviour is unchanged — this is a pure de-duplication. `import Foundation` lines added
  in `ad67f38` that are now only needed for the removed block can stay (harmless) or be
  removed if unused.

## Edit 3 — Fix `testEmptyQueueAfterLastDismiss`

`MerlinTests/Unit/PendingAttentionViewModelTests.swift` — replace
`testEmptyQueueAfterLastDismiss` with a version that honours its name: dismiss every
finding the scan produced, then assert the queue is empty.

```swift
    func testEmptyQueueAfterLastDismiss() async throws {
        let projectRoot = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let tasksDir = projectRoot.appendingPathComponent("phases")
        try FileManager.default.createDirectory(at: tasksDir, withIntermediateDirectories: true)
        let taskDoc = """
        # Phase 001b — Example

        New surface introduced in phase 001b:
          - `GhostTypeThatDoesNotExist` — a surface with no implementation
        """
        try taskDoc.write(
            to: tasksDir.appendingPathComponent("task-001b-example.md"),
            atomically: true,
            encoding: .utf8
        )

        let engine = makeEngine(projectRoot: projectRoot)
        _ = await engine.scan(projectPath: projectRoot.path)

        let vm = PendingAttentionViewModel(disciplineEngine: engine)
        await vm.refresh(projectPath: projectRoot.path)
        XCTAssertFalse(vm.findings.isEmpty, "scan must produce at least one finding")

        // Dismiss every finding the scan produced — the scan can yield more than one
        // (e.g. a phaseDrift and a docStaleReference for the same ghost symbol).
        var guardCount = 0
        while let finding = vm.findings.first, guardCount < 100 {
            await vm.dismiss(finding: finding, rationale: "done")
            await vm.refresh(projectPath: projectRoot.path)
            guardCount += 1
        }

        XCTAssertTrue(vm.findings.isEmpty, "queue must be empty after the last dismiss")
    }
```

## Edit 4 — Update the documentation

Four task docs still describe the removed seam. Update each:

- `tasks/task-232a-budget-telemetry-tests.md` and
  `tasks/task-232b-budget-telemetry.md` — these introduce `TelemetryRecorder` /
  `TelemetrySink` / `static var sink`. Add a superseded banner immediately under the
  title of each:
  `> **Superseded by phase 277.** The `TelemetryRecorder` / `TelemetrySink` / `TelemetryEmitter.sink` seam was removed. Telemetry tests now write to a temp JSONL file via `TelemetryEmitter.resetForTesting(path:)` / `flushForTesting()` and read it with `readTelemetryEvents(fromFile:)` (`TestHelpers/TelemetryTestSupport.swift`).`
- `tasks/task-237a-executor-gate-tests.md` — the prose "reading it back via
  `TelemetryRecorder`" must be updated to "reading it back from the telemetry JSONL file
  via `readTelemetryEvents(fromFile:)`".
- `tasks/task-245a-discipline-engine-tests.md` — the embedded test code uses
  `let recorder = TelemetryRecorder()`. Update that embedded snippet to the file-based
  pattern (`resetForTesting` / `flushForTesting` / `readTelemetryEvents`) so the phase
  doc matches the committed test.
- Then run a final check and fix anything missed:
  `grep -rn "TelemetryRecorder\|TelemetrySink\|TelemetryEmitter\.sink" --include="*.md" .`
  — after this phase, the only `.md` hits allowed are inside this file
  (`task-277-telemetry-test-cleanup.md`) and the superseded banners.
- `tasks/PASTE-LIST.md` — append phase 277 under the Project Discipline section.

## Edit 5 — Regenerate the Xcode project

`TestHelpers/TelemetryRecorder.swift` was deleted and `TestHelpers/TelemetryTestSupport.swift`
added, so the project file must be regenerated:

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
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

Expected: **BUILD SUCCEEDED**, zero warnings, and the full suite green headless
(`RUN_LIVE_TESTS` unset → engine tests skip; zero failures). `testEmptyQueueAfterLastDismiss`
passes with the restored strong assertion. A clean build with `TelemetryRecorder` /
`TelemetrySink` / `sink` deleted proves they were dead.

## Commit

```bash
git add tasks/task-277-telemetry-test-cleanup.md \
    Merlin/Telemetry/TelemetryEmitter.swift \
    TestHelpers/TelemetryTestSupport.swift \
    Merlin.xcodeproj/project.pbxproj \
    tasks/task-232a-budget-telemetry-tests.md \
    tasks/task-232b-budget-telemetry.md \
    tasks/task-237a-executor-gate-tests.md \
    tasks/task-245a-discipline-engine-tests.md \
    tasks/PASTE-LIST.md \
    MerlinTests/Unit/AdaptiveRAGIntegrationTests.swift \
    MerlinTests/Unit/DisciplineEngineTests.swift \
    MerlinTests/Unit/IterationCapEscalationTests.swift \
    MerlinTests/Unit/PlannerRefineTelemetryTests.swift \
    MerlinTests/Unit/PlannerStepTelemetryTests.swift \
    MerlinTests/Unit/PreflightGateTests.swift \
    MerlinTests/Unit/PreflightOkTelemetryTests.swift \
    MerlinTests/Unit/PreflightTelemetryTests.swift \
    MerlinTests/Unit/TelemetryErrorBodyTests.swift \
    MerlinTests/Unit/PendingAttentionViewModelTests.swift
git rm TestHelpers/TelemetryRecorder.swift
git commit -m "Phase 277 — Remove dead telemetry test seam, dedup reader, fix dismiss test"
```

## Fixes

Removes `TelemetryRecorder`, `TelemetrySink`, and `TelemetryEmitter.sink` — dead since
`ad67f38` migrated telemetry tests to the file-based `resetForTesting`/`flushForTesting`
API. Deduplicates the JSONL reader into `readTelemetryEvents(fromFile:)`. Restores the
strong assertion in `testEmptyQueueAfterLastDismiss` (dismiss every finding, then assert
the queue is empty). Updates the four task docs that referenced the removed seam.
