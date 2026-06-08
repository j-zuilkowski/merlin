# Task 399a - Electronics training corpus tests

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#research-derived-design-commitments
- Roadmap reference: plugins/electronics/tasks.md#numbered-tdd-task-map

## Behavior

The plugin SHALL collect verifier-grounded traces suitable for model selection
and future fine-tuning.

## Red Tests

- Add tests for logging accepted/rejected `DesignIntent` drafts.
- Add tests for logging Circuit IR validation failures and repairs.
- Add tests for logging ERC/DRC/SPICE/BOM diagnostics.
- Add tests for logging repair patches and verifier outcomes.
- Add evaluation scenario manifest tests for sensor board, power supply, analog
  filter, amp low-voltage board, and amp power-supply board.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsTrainingCorpusTests
```

Expected red state: tests fail until verifier-grounded trace collection exists.

## Commit

Stage only training-corpus tests and manifests.
