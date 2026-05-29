# Task 406a — Electronics Focused Slice Drift Tests

## Goal

Reproduce the focused GUI slice failure where Merlin read the AmpDemo spec, then
drifted to general tools (`spawn_agent`, `xcode_open_file`) instead of the first
electronics/KiCad runtime tool.

## Failing Tests

Add focused tests proving:

1. Active electronics workflow plans are not parallelized into `spawn_agent`
   batches.
2. `xcode_open_file` is rejected while the electronics workflow lock is active.
3. Chat submission waits for runtime plugin tools before the first provider turn.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/LoopContinuationTests/testElectronicsEvidencePlansDoNotUseSpawnAgentBatches \
  -only-testing:MerlinTests/AgenticEngineTests/testActiveElectronicsWorkflowLockRejectsXcodeOpenFile
```

Expected: tests fail before Task 406b.

