# Task 445a - Runtime Repair Patch Application Tests

Date: 2026-05-30

## Goal

Add focused tests proving runtime repair plans resolve to callable apply tools
and that applying a repair plan does not count as validation evidence.

## Test Scope

1. Repair next actions resolve to registered KiCad tool names.
2. ERC repair application mutates the schematic and produces only an
   application artifact.
3. DRC repair application does not claim a DRC report or PCB verification.
4. SPICE repair application does not claim simulation measurements.
5. Every apply action requires the matching `kicad_run_*` gate before workflow
   advancement.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testRepairPatchApplicationRequiresGateRerunBeforeAdvancement \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests/test_evidenceNextActions_resolveToCallableKiCadTools
```

Expected before Task 445b: repair plans expose placeholder actions and apply
tools are missing.
