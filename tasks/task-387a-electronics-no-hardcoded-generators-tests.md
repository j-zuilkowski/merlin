# Task 387a - Electronics no-hardcoded-generators tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Merlin spec reference: spec.md#merlin-v20--electronicskicad-feature-set
- Plugin spec reference: plugins/electronics/spec.md#non-negotiable-invariants
- Roadmap reference: plugins/electronics/tasks.md#numbered-tdd-task-map

## Behavior

WHEN `workflow.requirements_to_pcb` receives only natural-language requirements THE electronics plugin SHALL block generically and SHALL NOT create KiCad, BOM, fabrication, SPICE, or report artifacts.

GIVEN a developer attempts to reintroduce a named demo generator,
THEN focused tests SHALL fail on generator names, hard-coded project symbols, and
requirements-only artifact creation.

## Red Tests

- Add or update unit tests covering at least three unrelated prompts:
  amplifier, ESP32 IoT, and power supply.
- Assert the route returns `BLOCKED_ARTIFACT` with `DESIGN_INTENT_REQUIRED`.
- Assert no output subdirectories such as `kicad`, `bom`, `gerbers`, `drill`, or
  `simulation` are created.
- Add a source-level regression test that fails on named generator functions and
  hard-coded project-local symbols.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsWorkflowCompletionTests/testRequirementsWorkflowBlocksAnyPromptWithoutGeneratingArtifacts \
  -only-testing:MerlinTests/ElectronicsNoPlaceholderCompletionTests/testElectronicsRuntimePluginSourceHasNoHardCodedCompletePlaceholders
```

Expected red state: tests fail while requirements-only workflows can create
hard-coded electronics artifacts or the runtime contains named generators.

## Commit

Stage only the new or edited focused tests for this task.
