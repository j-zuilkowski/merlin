# Task 406b — Electronics Focused Slice Drift Fix

## Goal

Keep focused electronics workflow slices on the plugin/KiCad runtime path.

## Implementation

1. Make evidence-gated electronics plans execute sequentially instead of creating
   parallel `spawn_agent` batches.
2. Make evidence-gated continuation prompts execute one electronics step at a
   time and never instruct the model to use `spawn_agent`.
3. Keep the active electronics workflow lock rejecting non-inspection,
   non-electronics tools such as `xcode_open_file`.
4. Ensure GUI chat submission waits for runtime plugin registration before
   sending the first prompt.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/LoopContinuationTests/testElectronicsEvidencePlansDoNotUseSpawnAgentBatches \
  -only-testing:MerlinTests/AgenticEngineTests/testActiveElectronicsWorkflowLockRejectsXcodeOpenFile
```

Expected: tests pass.

