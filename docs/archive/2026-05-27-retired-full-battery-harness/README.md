# Retired Full-Battery Harness

This directory archives the May 26-27, 2026 full-battery shell runner and the tasks/tests written to repair it.

These files are historical reference only. They are not part of active verification, release gating, or the current Merlin testing process. If Merlin needs another end-to-end harness, create a new one from current requirements instead of extending this archived runner.

Archived active pieces:

- `scripts/run-live-full.sh`
- `tests/FullBatteryCleanupTests.swift`
- `tests/LocalProviderSmokeScriptTests.swift`
- `tasks/task-386*` through `tasks/task-389*`

The current full-green proof should be performed through direct GUI/operator validation plus targeted commands until a replacement harness is explicitly specified.
