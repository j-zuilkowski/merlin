# Task 428a - Handoff Missing Evidence Stop Tests

Date: 2026-05-30

## Goal

Add failing tests proving orchestration stops before a KiCad tool when required
handoff evidence is missing.

## Test Scope

1. Circuit IR generation requires a DesignIntent path.
2. Component selection requires DesignIntent and Circuit IR paths.
3. Footprint assignment requires DesignIntent and component matrix paths.
4. Compile requires DesignIntent, Circuit IR, component matrix, footprint
   assignment, and output directory paths.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests
```

Expected before Task 428b: missing handoff evidence can still allow later tool
execution.
