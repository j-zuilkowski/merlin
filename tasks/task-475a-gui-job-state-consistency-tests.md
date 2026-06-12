# Task 475a - GUI Job State Consistency Tests

## Objective

Add fail-first coverage proving the electronics GUI projections use one shared
display state for job list, running/blocked/fab-ready/complete groups, and live
leaderboard rows.

## Fail-First Tests

Focused command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testGUIProjectionsUseSingleDisplayStateForFabReadyJobs \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testGUIProjectionsSeparateRunningBlockedFabReadyAndCompleteStates
```

Expected red state before implementation:

- `ElectronicsJob.displayState` does not exist.
- `ElectronicsJobStore.leaderboardRows`, `runningRows`, `blockedRows`,
  `fabReadyRows`, and `completedRows` do not exist.
- Existing store projections collapse non-running jobs into `completedJobs`, so
  blocked, fab-ready, and complete states cannot be distinguished by the GUI.

Observed red result:

`TEST FAILED` at compile time because the shared display-state/projection API
did not exist yet.
