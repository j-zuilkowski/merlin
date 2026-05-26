# Task 357b — Electronics artifacts and gates

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 357b is executed THE system SHALL implement electronics artifact and gate enforcement.

GIVEN an electronics workflow has produced design outputs,
WHEN Merlin evaluates completion,
THEN `COMPLETE` SHALL require all applicable gates and required artifacts.

## Implementation

- Implement artifact tracking for KiCad project files, DSN/SES, route logs, Gerbers, drills, drill reports, BOM, pick-and-place, drawings, STEP/3D outputs, approval records, and verification reports.
- Implement gate evaluation for connectivity, ERC, DRC, schematic/PCB parity, CAM, simulation when applicable, visual QA when applicable, and high-stakes signoff.
- Ensure failures produce actionable blocked/failed diagnostics on the workspace bus.
- Ensure final reports include artifacts, gate results, assumptions, approvals, and blocked reasons.
- Remove placeholder success paths that can mark electronics work complete without artifacts or gates.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsArtifactGateTests test
```

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' build-for-testing
```

## Commit

```bash
git add Merlin MerlinTests plugins/electronics tasks
git commit -m "Task 357b — electronics artifacts and gates"
```
