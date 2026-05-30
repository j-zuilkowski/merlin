# Task 384b — KiCad green-fixture DRC

## Traceability

- Vision reference: vision.md#merlin-v20--electronicskicad-feature-set
- Spec reference: spec.md#electronics-product-completion-pass
- Test task: tasks/task-384a-kicad-green-fixture-drc-tests.md

## Behavior

WHEN the electronics fixture is used as the green-board proof THE KiCad project SHALL include enough board geometry for KiCad DRC and Gerber export to succeed without fixture-caused violations.

GIVEN the fixture PCB is opened by KiCad CLI,
WHEN DRC evaluates board outline rules,
THEN a closed `Edge.Cuts` outline SHALL be present.

## Implementation

- Update the checked-in KiCad fixture PCB to include a simple valid closed board
  outline on `Edge.Cuts`.
- Preserve the schematic/netlist intent of the fixture.
- Ensure generated Gerbers still include the expected copper, silkscreen,
  mask/paste, courtyard, margin, and `Edge_Cuts` outputs.
- Keep this task focused on fixture validity; do not mask KiCad CLI failures in
  production handlers.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsGreenBoardTests test
kicad-cli pcb drc merlin-eval/fixtures/electronics/schematic-image/kicad-project/project.kicad_pcb \
  --format json --output /tmp/merlin-kicad-green-fixture-drc.json
```

Expected green state: DRC reports zero violations and Gerber export still
produces the expected fabrication outputs.
