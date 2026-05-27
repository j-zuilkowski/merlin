# S6 — Electronics End-to-End

Proves Merlin's electronics workflow: it designs a schematic, places and routes a PCB via
the bus-backed `plugins/electronics` runtime plugin plus FreeRouting, and runs an
ngspice simulation to verify the circuit behaves — schematic → layout → route →
simulate, end to end.

---

## Setup

Confirmed available: KiCad 10.0.3, Merlin `plugins/electronics`,
`/Applications/freerouting.app` (bundled JRE), `ngspice`.

1. Confirm Merlin's active electronics runtime plugin is built and loadable from
   `plugins/electronics`.
2. Confirm Merlin's electronics tools are present (`KiCadToolDefinitions`,
   `route_via_freerouting`) and the FreeRouting path resolves
   (`KiCadMCPTooling.freeRoutingPath`).
3. Merlin works in `merlin-eval/fixtures/electronics/` (created fresh per run).

## Target circuit

A **555 astable multivibrator LED blinker** — the canonical small real board.

- U1 — NE555 timer.
- R1 — 10 kΩ (VCC → DISCHARGE).
- R2 — 47 kΩ (DISCHARGE → THRESHOLD/TRIGGER).
- C1 — 10 µF (THRESHOLD/TRIGGER → GND).
- C2 — 10 nF (CONTROL → GND, decoupling).
- R3 — 330 Ω, D1 — LED (OUTPUT → LED → GND).
- 5 V supply across VCC/GND.

Expected blink frequency: `f = 1.44 / ((R1 + 2·R2)·C1) ≈ 1.4 Hz` (duty ~ 70%).

---

## Scenario prompt (given to Merlin)

> Design a 555-timer astable LED blinker in `merlin-eval/fixtures/electronics/`:
> a NE555 (U1), R1 10 kΩ, R2 47 kΩ, C1 10 µF, C2 10 nF, R3 330 Ω, an LED (D1), on a 5 V
> supply, wired as a standard astable. Create the KiCad schematic, assign footprints,
> lay out the PCB, route it with FreeRouting, and run an ngspice simulation that confirms
> the output oscillates. Report the netlist, the routing result (any unrouted nets), and
> the simulated blink frequency vs. the ~1.4 Hz target.

---

## Scoring rubric

**Deterministic / observable:**
- [ ] A KiCad schematic is produced with all 7 components and the correct netlist
      (555 pins wired per the standard astable; verify against the target above).
- [ ] Footprints assigned; a PCB layout is produced.
- [ ] FreeRouting runs and the board has **zero unrouted nets** (or Merlin reports the
      exact remaining count and why).
- [ ] ngspice runs without error and the OUTPUT node oscillates.
- [ ] Simulated frequency is within ±30 % of the ~1.4 Hz formula target (555 SPICE
      macromodels are approximate — generous tolerance is intentional).

**Judgment:**
- [ ] Merlin used the MCP tools and FreeRouting for real (not faked output) — check the
      tool-call transcript and the actual `.kicad_sch` / `.kicad_pcb` / ngspice files.
- [ ] On any failure (a tool missing, FreeRouting erroring, the 555 model not
      converging) Merlin reported it honestly rather than claiming success.

**Score:** stages passed / 5 (schematic, footprints+layout, route, sim runs, frequency).

---

## Part B — Schematic extraction (OCR)

A separate run proving Merlin can import an **existing** schematic from an image —
exercises `Merlin/Electronics/SchematicExtractionPolicy.swift`.

### Fixture
`merlin-eval/fixtures/electronics/schematic-image/` — a clear raster image (PNG) of a
simple, known schematic plus a machine-readable ground-truth netlist beside it. Produce
the image by exporting a KiCad schematic to PNG (reuse the 555 astable, or a simpler RC
divider). Keep `ground-truth.json` (components + nets) as the scoring reference.

### Prompt
> Import the schematic image at `<path>`. Extract its components and netlist into a
> KiCad schematic. Report every component you recognised (designator + value) and the
> connections, and flag anything you could not read.

### Scoring rubric
- [ ] Merlin actually runs the schematic-extraction path (`SchematicExtractionPolicy`) —
      verify from the tool-call transcript, not a guessed answer.
- [ ] Every component in `ground-truth.json` is recognised (designator + value).
- [ ] Extracted connections match the ground-truth netlist — score net-by-net; minor
      pin-label noise tolerated.
- [ ] Merlin honestly reports recognition confidence and any unreadable components — it
      must **not** invent components to fill gaps.

**Score:** components recognised / N + nets correct / M, plus the honesty check.

---

## Runsheet

1. Batches B–D merged; Merlin built; KiCad / FreeRouting / ngspice confirmed; the
   `plugins/electronics` runtime plugin loads and registers its evidence-gated tools.
2. Create an empty `merlin-eval/fixtures/electronics/` working dir.
3. Open a project in Merlin; send the scenario prompt.
4. Watch the tool calls — schematic creation, footprint assignment, layout, the
   `route_via_freerouting` call, the ngspice run.
5. Inspect the produced `.kicad_sch`, `.kicad_pcb`, and ngspice output files directly.
6. Open the board in KiCad to eyeball the routing.
7. Score against the rubric; write `merlin-eval/results/S6-<date>.md`.
8. Any blocked stage (MCP server won't start, FreeRouting fails, 555 model won't
   converge) is a finding — record it, and add to `BLOCKED.md` if it is an environment
   gap rather than a Merlin defect.
