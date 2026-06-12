# Task 509 — Correct Invalid KiCad Release Evidence

## Objective

Record the v2.4.0 release attempt as invalid at gate #10 and define the next
repair boundary: gate #10 may not pass again until Merlin proves it creates a
real populated KiCad board, not merely files that open in KiCad.

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN KiCad release screenshots do not prove a usable populated board THE system SHALL mark gate #10 invalid and block downstream release claims until real board-creation evidence exists.

## Failure Found

The release screenshots captured for Task 505 are not sufficient release
evidence. They prove the generated schematic and PCB files can open in KiCad,
but they do not prove a realistic generated electronics board:

- `pcb-editor-screenshot.png` shows pads/traces but no credible populated board
  evidence.
- `board-3d-viewer-screenshot.png` is effectively a bare board view, not a
  populated 3D board.
- `layers/routed-composite.png` shows simplified routing artifacts, not a
  release-quality board layout.
- The copied `.kicad_pcb` contains footprint/pad records, but no 3D model
  references were present in the inspected source artifact.
- `source/drc.json` reports 26 DRC violations.

The correct status is that gate #10 failed substantively. Gates #11-#16 were
advanced from invalid evidence and must not be considered release-valid.

## Required Board-Creation Proof Before Gate #10 Can Pass Again

The next gate #10 repair must add deterministic checks that fail unless the
generated KiCad PCB is a real board artifact. At minimum, the proof must verify:

- The `.kicad_pcb` has a board outline, nonzero placed footprints, nonzero pads,
  and nonzero routed copper segments tied to named nets.
- The placed footprints correspond to the component matrix and footprint
  assignment evidence by reference designator, not just generic pad carriers.
- Components are distributed with plausible XY placements inside the board
  outline, not collapsed into a line or title-block-adjacent cluster.
- 3D board evidence contains component bodies or an explicit, bounded list of
  missing 3D models that blocks release-quality screenshots.
- The PCB screenshot and 3D screenshot are inspected as evidence; a blank,
  bare-board, or visually unpopulated capture fails the gate.
- KiCad DRC status is reported honestly. A board with blocking DRC violations
  cannot be labeled release-ready or used to justify downstream release gates.

## Scope Limit

This task file only records the corrective task and the board-proof contract.
It does not repair the release ledger, rewrite the report, create/delete tags,
publish releases, or rerun gate #10. Those are separate tasks.
