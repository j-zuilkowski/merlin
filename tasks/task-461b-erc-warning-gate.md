Status: complete

# Task 461b - ERC Warning Gate

Tighten schematic verification and generic schematic materialization around
KiCad ERC warning evidence.

Acceptance:
- ERC reports expose a schematic-verification blocking view distinct from hard
  ERC errors.
- Runtime and harness schematic gates use the stricter verification view.
- The generic schematic materializer uses endpoint label stubs instead of
  star-junction wires that trigger KiCad label warnings.
- The constrained AmpDemo schematic/ERC slice produces an ERC report with zero
  violations.
