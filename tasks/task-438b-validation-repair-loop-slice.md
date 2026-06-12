# Task 438b - Validation Repair Loop Slice

Date: 2026-05-30

## Goal

Complete the focused validation and repair-routing slice for electronics.

## Implementation Scope

1. Keep KiCad and SPICE tools as the validation authorities.
2. Parse validation outputs into structured diagnostics.
3. Preserve failed artifacts for repair.
4. Prevent downstream workflow advancement without validation handoff evidence.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests
```

Expected after Task 438b: validation failures are blocked, preserved, and routed
to repair.
