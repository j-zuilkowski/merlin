# Task 399b - Electronics training corpus implementation

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#research-derived-design-commitments
- Test task: tasks/task-399a-electronics-training-corpus-tests.md

## Behavior

The plugin SHALL persist structured electronics traces that can train or
evaluate planner, critic, and repair models against verifier outcomes.

## Implementation

- Log accepted and rejected `DesignIntent` drafts.
- Log Circuit IR validation failures and repairs.
- Log ERC/DRC/SPICE/BOM diagnostics.
- Log repair patches and verifier outcomes.
- Build training pairs for requirements-to-intent, intent-to-Circuit-IR,
  diagnostics-to-patch, and patch-to-verifier-result.
- Add evaluation manifests for the planned electronics scenarios.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsTrainingCorpusTests
```

Expected green state: verifier-grounded traces and scenario manifests are
created in the plugin-owned format.

## Commit

Stage only training-corpus implementation, manifests, and focused tests.
