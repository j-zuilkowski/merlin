# Task 486 - F4 electronics artifact context cap

## Objective

Fix the generic GUI/workflow continuation blocker recorded in Task 485: after
DesignIntent approval, the full electronics workflow could reread a large
generated electronics artifact into model context, exceed the local model's
context window, compact, and repeat before reaching Circuit IR.

## Fail-First Evidence

Added focused continuation tests in `LoopContinuationTests`:

- `testApprovedDesignIntentSchedulesFocusedCircuitIRHandoffInsteadOfBroadContinuation`
  proves the continuation chain through requirements read, DesignIntent build,
  and DesignIntent approval schedules an exact `kicad_generate_circuit_ir`
  handoff instead of a broad evidence-gated continuation.
- `testGeneratedElectronicsArtifactReadIsCompactedBeforeContextAppend` proves a
  generated electronics artifact read must not enter `ContextManager` verbatim.

Red command:

```bash
rm -rf /tmp/merlin-derived-task486-red-context && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task486-red-context -only-testing:MerlinTests/LoopContinuationTests/testGeneratedElectronicsArtifactReadIsCompactedBeforeContextAppend
```

Result: `TEST FAILED`. The tool message contained the full large generated
DesignIntent payload with no compact marker.

## Implementation

`AgenticEngine.dispatchRegularCalls` now preserves the full `ToolResult` for UI
tool events, post-tool hooks, and continuation evidence, but stores a compacted
context-only representation when all of these are true:

- the call is `read_file`;
- the electronics workflow lock is active;
- the path is a generated Merlin electronics artifact such as
  `.merlin/electronics-artifacts/*-design_intent.json`, `*-circuit_ir.json`,
  `*-component_matrix.json`, or `*-footprint_assignment.json`;
- the result exceeds the electronics artifact context cap.

The compact context entry records the artifact path and original byte count and
instructs the model to use the path with the next electronics handoff tool
instead of rereading the file.

## Green Evidence

Focused command:

```bash
rm -rf /tmp/merlin-derived-task486-green && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task486-green -only-testing:MerlinTests/LoopContinuationTests/testGeneratedElectronicsArtifactReadIsCompactedBeforeContextAppend -only-testing:MerlinTests/LoopContinuationTests/testApprovedDesignIntentSchedulesFocusedCircuitIRHandoffInsteadOfBroadContinuation
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

## Status

This fixes the generic context-overrun loop that blocked Task 485 before Circuit
IR. F4 is not complete yet because the fresh full GUI workflow has not been
rerun with this fix.
