# Task 384a — KiCad green-fixture DRC tests

## Traceability

- Vision reference: vision.md#merlin-v20--electronicskicad-feature-set
- Spec reference: spec.md#electronics-product-completion-pass
- Prior failure: real `kicad-cli pcb drc` found an invalid board outline

## Behavior

WHEN Merlin's checked-in KiCad green-board fixture is validated with the real KiCad CLI THE fixture SHALL pass ERC and DRC without design-rule violations.

GIVEN the fixture project is used for electronics proving,
WHEN `kicad-cli pcb drc` runs,
THEN the generated JSON report SHALL contain zero violations and zero
unconnected items.

## Red Tests

- Add a focused test or script-backed fixture test that locates the checked-in
  KiCad fixture and runs:
  - `kicad-cli sch erc`;
  - `kicad-cli pcb drc`;
  - `kicad-cli pcb export gerbers`.
- Parse the DRC JSON report and fail if any violation is present.
- Specifically guard against the observed `invalid_outline` condition where no
  closed `Edge.Cuts` outline exists.
- Skip only when KiCad CLI is genuinely unavailable; do not skip because the
  fixture is invalid.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsGreenBoardTests test
```

Expected red state: the test fails on the existing fixture with
`invalid_outline` until the board has a valid closed `Edge.Cuts` outline.
