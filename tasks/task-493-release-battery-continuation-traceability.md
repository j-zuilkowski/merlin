# Task 493 - Release Battery Continuation Traceability

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN release-battery continuation and documentation gates run THE workflow SHALL scope traceability checks to current post-policy task files and preserve evidence-gated electronics handoffs.

WHEN downstream footprint evidence exists THE workflow SHALL NOT treat a
schematic/PCB compile-project handoff as satisfied by a prior DesignIntent
artifact.

WHEN workspace window recovery unit tests evaluate visible workspace candidates
THE tests SHALL use non-AppKit window fixtures so the release battery does not
inherit desktop-server or AppKit memory-checker teardown crashes.

WHEN floating window runtime tests create testing-mode windows THE manager
SHALL close them without transform animations or retained content/delegate
references.

## Goal

Repair the gate #1 failures from the v2.4.0 release ledger without advancing to
post-green screenshots.

## Evidence

- Red: full `MerlinTests` gate failed in `docs/e2e/2026-06-08-v2.4.0-release/logs/01-MerlinTests.log`.
- Red: rerun of focused failures reproduced missing continuation inject files
  for compile-project handoff scheduling while
  `WorkspaceCoordinatorTests.test_removeProject_last_sets_active_nil` passed in
  isolation.
- Red: full gate #1 rerun reported
  `WorkspaceCoordinatorTests.test_removeProject_last_sets_active_nil` as a
  crash; the crash report showed `EXC_BAD_ACCESS` in AppKit window transform
  animation teardown during XCTest cleanup.
- Red: focused window sequence still crashed in
  `WorkspaceCoordinatorTests.test_fallbackWindowRecoveryRequiresUsableVisibleWorkspaceWindow`;
  crash report `Merlin-2026-06-08-150055.ips` showed
  `EXC_BAD_ACCESS` while XCTest's memory checker released AppKit objects after
  the test scope.
- Green: `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests
  -destination 'platform=macOS' -derivedDataPath
  /tmp/merlin-derived-task493-window-green
  -only-testing:MerlinTests/FloatingWindowRuntimeTests
  -only-testing:MerlinTests/WorkspaceCoordinatorTests` passed, 30 tests, 0
  failures.
- Green: `xcodegen generate && xcodebuild test -project Merlin.xcodeproj
  -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath
  /tmp/merlin-derived-v240-full-core` passed the full core suite: 2,571
  tests, 55 skipped, 0 failures. Evidence log:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/01-MerlinTests.log`; xcresult:
  `/tmp/merlin-derived-v240-full-core/Logs/Test/Test-MerlinTests-2026.06.08_15-03-02--0400.xcresult`.
