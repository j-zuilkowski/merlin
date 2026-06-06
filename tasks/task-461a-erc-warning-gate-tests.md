Status: complete

# Task 461a - ERC Warning Gate Tests

Add focused tests proving KiCad ERC warnings that indicate schematic generation
quality problems cannot silently pass schematic verification.

Acceptance:
- KiCad 10 `label_multiple_wires` and `multiple_net_names` warning reports are
  parsed into structured ERC violations.
- Schematic verification treats those warning codes as blocking until repaired.
- ERC repair planning routes those warning codes to concrete repair actions.
- Generic Circuit IR schematic materialization does not emit those warning types
  in a real KiCad ERC run.
