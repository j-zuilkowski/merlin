# Task 355a — Electronics completion contract tests

## Traceability

- vision.md — Runtime plugin architecture + electronics plugin
- spec.md — Electronics Product Completion Pass

## Behavior

GIVEN the electronics plugin is bus-backed,
WHEN the completion pass begins,
THEN tests SHALL prove that bus-backed registration is not treated as product completion.

GIVEN active electronics behavior lives in `plugins/electronics`,
WHEN the repository is inspected,
THEN no production path SHALL route through `archive/legacy-merlin-kicad-mcp`.

## Red Test

Add focused failing tests that prove:

- the electronics plugin declares the workflow-first completion contract;
- requirements-to-PCB and schematic-to-PCB have registered workflow routes;
- all model-visible electronics tools route through `WorkspaceMessageBus`;
- missing KiCad/FreeRouting/tooling returns explicit blocked or failed events;
- production code does not call the archived MCP scaffold as an active route;
- the required artifact names and gate names are represented by typed contracts.

Suggested file:

- `MerlinTests/Unit/ElectronicsCompletionContractTests.swift`

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsCompletionContractTests test
```

Expected: tests fail until the completion contracts and route inventory exist.

## Commit

```bash
git add MerlinTests/Unit/ElectronicsCompletionContractTests.swift \
        tasks/task-355a-electronics-completion-contract-tests.md
git commit -m "Task 355a — electronics completion contract tests"
```
