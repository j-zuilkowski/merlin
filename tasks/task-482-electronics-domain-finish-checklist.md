# Task 482 - Electronics Domain Finish Checklist

## Objective

Replace the rolling electronics "next group" backlog with a finite finish
checklist so future work closes named criteria instead of moving the finish
line after each group.

## Result

`tasks/HANDOFF.md` now contains `Electronics Domain Finish Criteria` with five
fixed criteria:

- F1: GUI resolver answer entry.
- F2: Generic schematic and PCB realism proof.
- F3: Full generic artifact-chain proof.
- F4: Fresh full GUI workflow completion evidence.
- F5: Completion contract and status cleanup.

Future electronics tasks must close one unchecked criterion. New finish criteria
may be added only when focused tests, full-workflow artifacts, or GUI evidence
prove a real blocker not covered by the checklist, and that blocker must be
documented in a numbered task file before changing the finish line.

Task 486 fixed the generated electronics artifact context blocker discovered
during F4 without adding a new finish criterion. F4 remains the required fresh
GUI workflow evidence target.

## Verification

Documentation-only update. `git diff --check` must pass.
