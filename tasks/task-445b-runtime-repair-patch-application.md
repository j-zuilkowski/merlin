# Task 445b - Runtime Repair Patch Application

Date: 2026-05-30

## Goal

Implement plugin-owned runtime actions for applying repair plans without
falsely satisfying ERC, DRC, or SPICE gates.

## Implementation Scope

1. Add `kicad_apply_erc_repair_patch`,
   `kicad_apply_drc_repair_patch`, and
   `kicad_apply_spice_repair_patch` to the plugin manifest and tool
   definitions.
2. Make repair-plan `nextActions` use registered tool names.
3. Apply ERC patches through the KiCad schematic parser/writer.
4. For DRC and SPICE, record patch-application artifacts without claiming board
   or deck mutation until concrete generic mutators exist.
5. Return only application artifacts and require the matching validation rerun.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests \
  -only-testing:MerlinTests/ElectronicsRealRegistrationTests
```

Expected after Task 445b: repair application is callable, truthful, and still
requires real gate evidence.
