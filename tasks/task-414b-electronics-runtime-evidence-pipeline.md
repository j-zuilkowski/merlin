# Task 414b - Electronics Runtime Evidence Pipeline

## Goal

Wire compile evidence blocking through a specific runtime evidence pipeline so
Merlin can only continue from the first verified missing artifact.

## Implementation

1. Replace generic compile evidence continuation actions with stage-specific
   actions.
2. Keep the evidence order strict: Circuit IR, ComponentMatrix, footprint
   assignment, then compile.
3. Ensure invalid footprint coverage routes back to footprint assignment.
4. Preserve user-authored fixture compile behavior.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CompileGateEvidenceTests
```

Expected: tests pass.
