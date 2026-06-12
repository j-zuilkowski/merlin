# Task 438a - Validation Repair Loop Slice Tests

Date: 2026-05-30

## Goal

Add a focused validation slice proving ERC, DRC, and SPICE failures are
diagnostic-driven and cannot falsely advance.

## Test Scope

1. ERC diagnostics block and route repair.
2. DRC diagnostics block and route repair.
3. SPICE diagnostics block and route repair.
4. Orchestration stops when validation report handoff is missing.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests
```

Expected before Task 438b: the combined validation repair slice is incomplete.
