# Task 494 - Release UI Battery

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN the v2.4.0 release ledger advances past the full core test gate THE
workflow SHALL run the full `MerlinUITests` gate and record the result in the
release evidence ledger before any post-green screenshot work.

WHEN the full UI gate fails THE workflow SHALL preserve the failure log and name
the next repair in `RELEASE-RUN.md` instead of advancing to KiCad or release
screenshots.

## Goal

Run release gate #2 from the fixed v2.4.0 release ledger and repair any blocker
found there without running the full AmpDemo GUI demo.

## Evidence

- Green: `xcodebuild test -project Merlin.xcodeproj -scheme
  MerlinUITests -destination 'platform=macOS' -derivedDataPath
  /tmp/merlin-derived-v240-ui` passed the full UI suite: 12 tests, 0 failures.
  Evidence log:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/02-MerlinUITests.log`; xcresult:
  `/tmp/merlin-derived-v240-ui/Logs/Test/Test-MerlinUITests-2026.06.08_15-06-46--0400.xcresult`.
- Green: `xcodebuild test -project Merlin.xcodeproj -scheme MerlinUITests
  -destination 'platform=macOS' -derivedDataPath
  /tmp/merlin-derived-v240-visual
  -only-testing:MerlinUITests/VisualLayoutTests` passed the focused visual
  suite: 6 tests, 0 failures. Evidence log:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/03-VisualLayoutTests.log`;
  xcresult:
  `/tmp/merlin-derived-v240-visual/Logs/Test/Test-MerlinUITests-2026.06.08_15-09-16--0400.xcresult`.
