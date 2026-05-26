# Task 337b — CalibrationReportSaver Implementation

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 337a complete: 4 failing tests in `CalibrationReportSaverTests`.

---

## Write to: Merlin/Calibration/CalibrationReportSaver.swift

`actor CalibrationReportSaver` with `directory: URL` + `save(_ report:) async throws -> URL`.
Defaults to `~/.merlin/calibration/`. Encoder: JSONEncoder with iso8601 date
strategy + pretty-printed + sorted-keys. Creates the target directory if missing.

Filename format: `<localProviderID>-<ISO8601-dashed-timestamp>.json` —
colons replaced with dashes for POSIX safety. Computed via `static func
filename(for:)` so the test can assert on the format without re-implementing it.

## Edit: Merlin/Calibration/CalibrationTypes.swift

- `CalibrationResponse: Sendable, Codable` — adds Codable to the response type.
- `CalibrationReport: Sendable, Codable` — adds Codable to the report.
- `CalibrationReport.wallClockSeconds: TimeInterval` — new field for total
  run duration.
- Explicit init with `wallClockSeconds: TimeInterval = 0` default so existing
  test call sites (CalibrationRunnerTests, CalibrationSkillTests) keep
  compiling without sed updates.

## Edit: Merlin/Engine/ModelParameterAdvisor.swift

- `ParameterAdvisory: Sendable, Equatable, Identifiable, Codable` — adds the
  Codable conformance the CalibrationReport encoder needs.

## Edit: Merlin/Calibration/CalibrationCoordinator.swift

- Init grows a defaulted `reportSaver: CalibrationReportSaver` parameter.
- `start(referenceProviderID:)` captures `startedAt = Date()` before launching
  the runner, computes `elapsed` after advisory analysis, passes it as
  `wallClockSeconds`, then `try? await reportSaver.save(report)` (best-effort —
  a disk-write failure must not hide the report from the user).

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```
Expected: 1849 tests, 0 failures (4 new from 337a now passing).

```bash
xcodebuild -scheme MerlinTests-Live build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head
```
Expected: `** TEST BUILD SUCCEEDED **`.

## Commit
```bash
git add Merlin/Calibration/CalibrationReportSaver.swift \
        Merlin/Calibration/CalibrationCoordinator.swift \
        Merlin/Calibration/CalibrationTypes.swift \
        Merlin/Engine/ModelParameterAdvisor.swift \
        tasks/task-337b-calibration-report-saver.md
git commit -m "Task 337b — CalibrationReportSaver: auto-save every report to ~/.merlin/calibration/"
```
