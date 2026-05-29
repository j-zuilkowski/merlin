# Task 387b - Electronics no-hardcoded-generators implementation

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Merlin spec reference: spec.md#merlin-v20--electronicskicad-feature-set
- Plugin spec reference: plugins/electronics/spec.md#non-negotiable-invariants
- Test task: tasks/task-387a-electronics-no-hardcoded-generators-tests.md

## Behavior

WHEN requirements arrive without approved design evidence THE electronics plugin
SHALL block with generic `DesignIntent` next actions and SHALL NOT synthesize
placeholder KiCad artifacts.

## Implementation

- Remove any hard-coded requirements-to-PCB artifact generators.
- Ensure requirements-only flows return a structured blocked result with
  `DESIGN_INTENT_REQUIRED`.
- Keep completion derived only from explicit evidence supplied to workflow
  routes.
- Keep plugin documentation under `plugins/electronics`.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsWorkflowCompletionTests/testRequirementsWorkflowBlocksAnyPromptWithoutGeneratingArtifacts \
  -only-testing:MerlinTests/ElectronicsNoPlaceholderCompletionTests/testElectronicsRuntimePluginSourceHasNoHardCodedCompletePlaceholders
```

Expected green state: focused tests pass and requirements-only workflows create
no electronics artifacts.

## Commit

Stage only the runtime and focused test files changed for this task.
