# Task 337a — CalibrationReportSaver Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 336b complete: LoRA serving-target picker shipped.

CalibrationCoordinator builds a `CalibrationReport` and shows it in a SwiftUI
sheet — but the report is never persisted. The `merlin-eval/results/CALIBRATION-harness-*.md`
files were produced manually. For the per-provider calibration sweep we need
a CLI consumer to read each completed report from disk + capture wall-clock
elapsed time.

New surface introduced in task 337b:
  - `CalibrationReportSaver` (actor) — writes a `CalibrationReport` to disk
    under a configurable directory (default `~/.merlin/calibration/`).
  - `CalibrationReport.wallClockSeconds: TimeInterval` — new field capturing
    the start-to-finish elapsed time of the runner.
  - `CalibrationReport` and its components made `Codable` so JSON encoding works.

TDD coverage:
  File 1 — `MerlinTests/Unit/CalibrationReportSaverTests.swift`:
    `testSaverCreatesDirectoryWhenMissing` — target dir auto-created
    `testSavedFilenameIncludesProviderAndTimestamp` — `<provider>-<iso8601>.json`
    `testSavedJSONRoundTripsAllFields` — full Codable round-trip including wallClockSeconds
    `testTwoSequentialSavesProduceDifferentFiles` — second-resolution timestamp uniqueness

---

## Write to: MerlinTests/Unit/CalibrationReportSaverTests.swift
(see committed file)

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10
```
Expected: BUILD FAILED with errors naming `CalibrationReportSaver`,
`wallClockSeconds`, and `CalibrationReport: Decodable` as missing.

## Commit
```bash
git add MerlinTests/Unit/CalibrationReportSaverTests.swift \
        tasks/task-337a-calibration-report-saver-tests.md
git commit -m "Task 337a — CalibrationReportSaverTests (failing)"
```
