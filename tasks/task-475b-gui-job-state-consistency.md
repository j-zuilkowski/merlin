# Task 475b - GUI Job State Consistency

## Objective

Make the electronics job panel use a single shared display-state projection so
the job list, running/blocked/fab-ready/complete groups, and live leaderboard
cannot disagree about each job's visible state.

## Implementation

- Added `ElectronicsJobDisplayBucket`:
  - `running`
  - `blocked`
  - `fabReady`
  - `complete`
- Added `ElectronicsJobDisplayState` with:
  - `jobID`
  - `statusLabel`
  - `message`
  - `bucket`
- Added `ElectronicsJob.displayState`.
- Added store projections:
  - `leaderboardRows`
  - `runningRows`
  - `blockedRows`
  - `fabReadyRows`
  - `completedRows`
- Updated `ElectronicsJobPanelView` to render all job status sections from those
  row projections instead of mixing raw `KiCadStatus` with end-to-end workflow
  labels.
- Split blocked and fab-ready jobs out of the previous non-running/completed
  bucket.

## Verification

Fail-first command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testGUIProjectionsUseSingleDisplayStateForFabReadyJobs \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testGUIProjectionsSeparateRunningBlockedFabReadyAndCompleteStates
```

Red result before implementation: `TEST FAILED` at compile time because the
shared display-state/projection API did not exist.

Green command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testGUIProjectionsUseSingleDisplayStateForFabReadyJobs \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testGUIProjectionsSeparateRunningBlockedFabReadyAndCompleteStates
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

Broader focused command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsJobStoreTests \
  -only-testing:MerlinTests/ElectronicsJobPanelLiveWorkflowTests
```

Result: `TEST SUCCEEDED`, 7 tests, 0 failures.

## Notes

The provider `SlotStatusPanel` is a separate LLM-provider health surface and was
not changed. The full AmpDemo GUI demo was not run.
