# Task 357a — Electronics artifacts and gates tests

## Traceability

- spec.md — Electronics Product Completion Pass / Required completion artifacts
- spec.md — Hard completion gates

## Behavior

GIVEN an electronics workflow reaches verification/export,
WHEN any required gate or artifact is missing,
THEN the workflow SHALL finish blocked or failed, never `COMPLETE`.

## Red Test

Add failing tests that prove:

- required KiCad, routing, fabrication, assembly, and verification artifacts are tracked by typed artifact refs;
- ERC, DRC, parity, CAM, simulation-when-applicable, visual-QA-when-applicable, and high-stakes signoff gates are evaluated before `COMPLETE`;
- missing Gerbers, drills, BOM, pick-and-place, verification report, or route result blocks release;
- user approvals are recorded as artifacts/events and cannot bypass high-stakes hard rules;
- final reports summarize artifacts, gate results, blocked reasons, and approvals.

Suggested file:

- `MerlinTests/Unit/ElectronicsArtifactGateTests.swift`

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsArtifactGateTests test
```

Expected: tests fail until artifact and gate enforcement is complete.

## Commit

```bash
git add MerlinTests/Unit/ElectronicsArtifactGateTests.swift \
        tasks/task-357a-electronics-artifacts-gates-tests.md
git commit -m "Task 357a — electronics artifact gate tests"
```
