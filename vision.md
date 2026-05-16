# Merlin — Vision Document

`vision.md` is Merlin's idea launchpad. New ideas land in `## Active`, then are either
promoted to `architecture.md` as committed design or parked in `## Deferred` with a
clear reconsideration trigger.

Architectural source of truth remains `architecture.md`; this document captures intent
upstream of committed design.

## Active

_No ideas currently awaiting promotion._

## Deferred

### Electronics / KiCad Domain

The v2.0 Electronics/KiCad feature set in `architecture.md` is scoped to two product intents (raster → PCB; requirements → design) with deterministic gates, BOM/distributor integration, and high-stakes sign-off. The following extensions are explicitly out of scope for v2.0.

#### EMC / EMI compliance testing

EMC compliance is fundamentally a lab activity (anechoic chamber, EMI receiver, LISN, conducted/radiated emissions sweeps). It cannot be performed by a design tool.

**v2.0 already covers the design-side mitigations:** return-path continuity in placement criteria, ground/plane net-class category, stackup-aware impedance control, keepout/return-path checks for Ethernet differential pairs, and module-first preference for high-speed interfaces.

**Reconsider when:** Merlin gains integration with a third-party EMC pre-compliance simulator (CST, HFSS, OpenEMS) or near-field probe hardware. The hook point is a new `kicad_run_emc_precompliance` tool returning a `BLOCKED_EMC` status alongside the existing simulation gates.

#### Detailed thermal simulation

Thermal analysis (junction temperatures, copper area for heat dissipation, thermal via design, PCB-level CFD) is not addressed. SPICE handles electrical simulation only.

**Why deferred:** For the v2.0 product intents (start/stop control with Ethernet, generic 2-layer prototypes), thermal is rarely a blocker. Current architecture handles the design-side basics through placement criteria (thermal spacing) and via design rules in the board profile.

**Reconsider when:** High-current power-electronics designs (>5A continuous, switching converters, motor drivers) become a target. The natural hook is a `kicad_run_thermal` tool returning `BLOCKED_THERMAL` and tolerance envelopes added to `BoardProfile` (max copper temp rise, max junction temp by component class).

#### Firmware / software integration

A controller board needs firmware. v2.0 does not address firmware co-development.

**Why deferred:** Merlin already has the software development domain (`SoftwareDomain`). Firmware naturally lives there, not in the electronics domain. Cross-domain coupling would muddy both.

**Reconsider when:** The most common follow-up to "design a control board" is "write the firmware for it" — likely immediately. The clean architectural hook is to emit a `PinoutManifest` artifact from the electronics workflow (component → connector → pin assignments, peripheral mappings, voltage rails, indicator semantics) that the software domain can consume as a first-class input. This is a small extension, not a re-architecture.

#### Mechanical / enclosure CAD round-trip

v2.0 accepts mechanical constraints from the user (board outline, mounting, height, assembly-side) and emits STEP for clearance checking. It does not round-trip with enclosure CAD systems (SolidWorks, Fusion 360, Onshape, FreeCAD).

**Why deferred:** Bidirectional CAD integration is large surface area and most prototype designs do not need it.

**Reconsider when:** Designs routinely require enclosure-driven board outlines or interference checks against existing mechanical assemblies. Natural hooks: STEP import for board-outline derivation; STEP export already exists; a `kicad_check_enclosure_fit` tool consuming an enclosure STEP and the project's STEP output.

#### Regulatory certification workflows

UL, CE, FCC, RoHS, REACH certification workflows are not modeled. v2.0 treats certification needs through the high-stakes sign-off gate only.

**Why deferred:** Certification is paperwork-and-lab-time intensive, requires accredited test houses, and is target-market-specific. Out of scope for a design tool.

**Reconsider when:** Users repeatedly request a structured certification-readiness checklist (creepage/clearance verification against IEC 60664, isolation barrier audits, declared-component-of-compliance tracking). Implementable as a `CertificationProfile` extension to `SafetyProfile` with profile-specific design rules layered on top of the fabricator profile.

#### Cost-optimized part selection

The v2.0 BOM architecture surfaces pricing and availability per vendor, but the component selection matrix is not driven by cost optimization. Selection is driven by requirements, reference-design provenance, and lifecycle status.

**Why deferred:** Cost optimization can produce designs that pass every gate but choose subtly wrong parts (lower temp range, tighter tolerance budgets, end-of-life-soon devices). Provenance-first selection is safer for the first release.

**Reconsider when:** v2.0 ships and users explicitly ask for cost-driven workflows. The hook point is a `selectionPolicy` field on the component selection matrix — `provenance_first` (default), `cost_minimize_within_provenance`, `lifecycle_maximize`, `single_vendor_minimize` — with the same approval surface for substitutions.

#### Manufacturing yield analysis (deep DFM)

CAM checks in v2.0 validate basic manufacturability (file presence, layer naming, drill units, copper-to-edge, soldermask/paste presence). Deeper DFM — paste mask coverage analysis, stencil aperture optimization, reflow profile compatibility, IPC-A-610 acceptance class checks — is not addressed.

**Why deferred:** Most board houses run their own DFM checks at order time and report issues back. Duplicating their tooling is high effort for low MVP value.

**Reconsider when:** Users repeatedly hit board-house DFM rejections that the local checks could have caught earlier. Natural extension: per-fabricator-profile DFM rule packs invoked by `kicad_export_fab` before the final CAM report.

#### Multi-board / system-level design

v2.0 targets single-board designs. Multi-board systems (motherboard + daughterboards, backplane systems, panelized arrays with shared nets via connectors) are not modeled.

**Why deferred:** The single-board pipeline is already a large build. System-level design adds cross-board net management, connector-pair-validation, and shared-power-budget analysis.

**Reconsider when:** A user workflow naturally spans multiple linked boards. The architectural hook is a new `SystemIntent` schema that owns multiple `DesignIntent` instances linked by `InterconnectSpec` records validating connector pinouts agree on both sides.

#### Cloud/remote KiCad execution

v2.0 runs `merlin-kicad-mcp` locally alongside the Merlin app. There is no remote/cloud KiCad execution.

**Why deferred:** Local execution is simpler, has no per-job cost, and matches the rest of Merlin's local-first stance. KiCad is desktop software.

**Reconsider when:** Routing or simulation jobs grow long enough that the local machine being tied up is a real productivity drag. Natural hook: the same `merlin-kicad-mcp` tool contracts targeting a remote KiCad worker over SSH (already a deferred-roadmap item for Merlin generally).

---

### How to use this document

When implementing v2.0 phases, check this file before adding scope. If an idea matches an item here, it stays out of v2.0 — note the existing entry in the phase doc rather than re-debating scope.

When v2.0 ships and users request capabilities, check this file first. If the request matches an entry, the architectural hook is already identified; the work becomes a new domain extension, not a re-architecture.

When new out-of-scope ideas surface during v2.0 implementation, add them here with the same fields: what, why deferred, reconsider when, architectural hook.
