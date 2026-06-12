Status: complete

# Task 457b - Generic schematic evidence gate

Make compile-time schematic generation merge upstream evidence generically,
without product-specific schematic emitters.

Acceptance:
- `kicad_compile_project` enriches Circuit IR from ComponentMatrix and
  FootprintAssignment artifacts before materializing KiCad files.
- The enrichment is keyed by refdes and evidence fields, not by AmpDemo-specific
  roles or component names.
- Compilation blocks if the resulting schematic is missing discrete symbols,
  values, footprints, source evidence, or Circuit IR net labels.
- The implementation contains no hard-coded AmpDemo or ESP32 schematic generator.
