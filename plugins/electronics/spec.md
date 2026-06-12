# Electronics Plugin Spec

Date: 2026-05-29

This specification belongs to `plugins/electronics`. Merlin core provides the
workspace bus, provider routing, session UI, and plugin loading. Electronics
design behavior, schemas, roles, verifier policy, and repair-loop rules belong
to this plugin.

## Objective

The electronics plugin SHALL provide a generic, KiCad-backed electronics design
workflow that converts approved structured design intent into verified KiCad
artifacts. It SHALL never claim electronics completion from natural-language
requirements, model narrative, screenshots, or unverified generated files.

The supported production path is evidence-gated from requirements through
release packaging:

```text
requirements -> DesignIntent -> Circuit IR -> component selection/revision
  -> footprint assignment
  -> KiCad project materialization
  -> ERC repair loop
  -> PCB placement/routing and DRC repair loop
  -> SPICE scenario generation and SPICE run
  -> BOM/vendor package
  -> fabrication/CAM package
  -> FAB_READY or blocked evidence package
```

The workflow may stop before `FAB_READY` when an evidence gate blocks. The
current full-GUI proof stops at `COMPONENT_SELECTION_REVISION_BLOCKED` when
component choices lack concrete manufacturer, MPN, package, ratings,
datasheet/provenance, and footprint/pin compatibility evidence. That stop is
successful gate behavior, not fabrication completion.

## Scope Boundary

### In Scope

1. Plugin-owned `DesignIntent` and Circuit IR schemas.
2. Model-assisted drafting of `DesignIntent`.
3. User approval before KiCad mutation when intent originated from natural
   language.
4. Component selection and revision with catalog/datasheet evidence.
5. KiCad library, symbol, footprint, pin, and field resolution.
6. KiCad-backed schematic and PCB materialization.
7. ERC/DRC execution, diagnostics parsing, concrete repair mutation, and
   explicit rerun evidence.
8. SPICE scenario/model/envelope generation and SPICE execution gates.
9. BOM/vendor package and fabrication/CAM evidence gates.
10. Evidence-gated `SCHEMATIC_VERIFIED`, `PCB_VERIFIED`, `SPICE_PASS`,
   `BOM_READY`, `FAB_READY`, and `COMPLETE` status handling.
11. Plugin-declared dynamic roles such as `electronics.analog_critic`.
12. First acceptance fixture: 25W Class A solid-state guitar amplifier,
   represented as generic design data, not hard-coded generator logic.

### Non-Product Claims

1. Fabrication, assembly, ordering, or safety certification.
2. Model-certified engineering signoff.
3. Silent substitution for qualified electrical, thermal, regulatory, medical,
   automotive, or life-safety review.
4. Irreversible vendor ordering or fabrication submission without explicit user
   approval.
5. Certification of mains, thermal, enclosure, regulatory, medical, automotive,
   or life-safety compliance.

## Non-Negotiable Invariants

1. No hard-coded project generators.
2. No named-example special cases for AmpDemo, ESP32, 555, power supplies, or
   future demo projects.
3. No raw KiCad S-expression string emitters as product shortcuts.
4. No model-certified completion.
5. No completion without parsed evidence from required tools.
6. No KiCad mutation from natural-language-originated requirements until the
   `DesignIntent` is user-reviewed or explicitly approved.
7. Plugin-specific roles disappear when the electronics plugin is unloaded.

## Research-Derived Design Commitments

The plugin incorporates prior research as architecture, not as copied examples.

### CircuitLM

CircuitLM informs the staged pipeline:

```text
requirements -> DesignIntent -> Circuit IR -> pin/library resolution -> KiCad
```

The plugin SHALL use machine-checkable intermediate data and SHALL validate
component identity, pin mappings, nets, and constraints before KiCad
materialization.

### AnalogCoder

AnalogCoder informs repair action style. Model output SHOULD be structured tool
payloads and patches, not prose. Repair actions include examples such as
`add_power_flag`, `connect_net`, `replace_symbol`, `assign_footprint`,
`update_component_value`, and `add_no_connect`.

### AnalogSeeker

AnalogSeeker informs optional analog-specialist critique and future training.
The plugin MAY declare `electronics.analog_critic`; critic output SHALL raise
issues or propose repairs only. It SHALL NOT pass verification gates.

### AutoCkt

AutoCkt informs simulator-driven optimization for bounded analog subcircuits
after topology is fixed. Optimization output still passes through the same
SPICE model, scenario, envelope, and measurement gates before it can affect
workflow status.

## Dynamic Plugin Roles

Merlin core SHALL support plugin-declared roles. The electronics plugin MAY
declare roles such as:

```json
{
  "id": "electronics.analog_critic",
  "display_name": "Analog Critic",
  "plugin_id": "electronics",
  "scope": "electronics",
  "default_fallback": "reason",
  "required_capabilities": ["structured_output", "long_context"],
  "recommended_models": ["analog-specialist", "deepseek-r1-70b"]
}
```

Role behavior:

1. Built-in Merlin roles remain available: `execute`, `reason`, `orchestrate`,
   and `vision`.
2. Plugin roles are registered only while the plugin is loaded.
3. Plugin roles appear in role settings, routing, calibration, status display,
   and token accounting only while available.
4. If an optional plugin role is unassigned, workflows MAY fall back to a built-in
   role.
5. If a workflow marks a plugin role required, missing assignment SHALL block
   with `ROLE_UNASSIGNED`.

`electronics.analog_critic` is optional unless a workflow explicitly marks it
required.

## DesignIntent

`DesignIntent` is the human-reviewed design contract. It records requirements,
assumptions, unresolved decisions, board boundaries, safety constraints, and
verification expectations.

Minimum fields:

```json
{
  "design_id": "string",
  "title": "string",
  "origin": "natural_language | schematic_ingest | user_authored",
  "approval": {
    "status": "draft | approved | rejected",
    "approved_by": "string",
    "approved_at": "ISO-8601 timestamp"
  },
  "requirements": [],
  "assumptions": [],
  "unresolved_decisions": [],
  "boards": [],
  "safety_profile": {},
  "verification_plan": {}
}
```

Rules:

1. Natural-language-originated intent starts as `draft`.
2. KiCad mutation requires `approved` intent unless the user explicitly invokes a
   draft-only preview mode that cannot complete gates.
3. Unknown engineering values SHALL be represented as unresolved decisions, not
   guessed certainty.
4. The plugin SHALL help the user draft the intent, but user approval remains the
   transition from requirements analysis to artifact mutation.

## Circuit IR

Circuit IR is the machine-checkable bridge from `DesignIntent` to KiCad.

Minimum entities:

1. `CircuitComponent`
   - reference designator
   - role
   - selected symbol
   - selected footprint when applicable
   - manufacturer/vendor candidate when applicable
   - source evidence
   - pin map
2. `CircuitPin`
   - component refdes
   - pin number
   - canonical name
   - electrical type
   - KiCad symbol pin mapping
   - footprint pad mapping when applicable
3. `CircuitNet`
   - name
   - role
   - endpoint pins
   - net class
   - safety or isolation domain
4. `CircuitConstraint`
   - current, voltage, impedance, clearance, creepage, thermal, RF, placement,
     or routing constraint
5. `VerificationScenario`
   - ERC expectations
   - future DRC expectations
   - future SPICE scenario and measurement envelope

Rules:

1. Every component entering KiCad must have source evidence.
2. Every net endpoint must refer to a valid component pin.
3. Every footprint assignment must prove pin/pad compatibility before PCB work.
4. Circuit IR validation failures block before KiCad file mutation.

## Component Catalog And Evidence Layer

The electronics plugin SHALL not rely on model memory for component identity,
pinout, package, lifecycle, availability, datasheet, footprint, or vendor
ordering claims. Component selection is an evidence-backed plugin workflow.

### Provider Classes

The plugin supports catalog providers behind a common interface. Providers are
plugin-owned and optional; Merlin core only supplies configuration, credential
storage, routing, and UI surfaces.

Provider classes:

1. `KiCadLibraryCatalogProvider`
   - local KiCad symbols, footprints, 3D models, pin definitions, footprint pad
     maps, and library metadata.
   - does not prove vendor availability or manufacturer part status.
2. `StaticFixtureCatalogProvider`
   - deterministic test fixtures for TDD and offline evaluation.
   - cannot be used as release evidence unless the fixture declares release
     provenance.
3. `DistributorCatalogProvider`
   - Digi-Key, Mouser, or other distributor APIs.
   - supplies MPN, manufacturer, parametric data, inventory, price, packaging,
     lifecycle flags when available, and datasheet URLs.
4. `AggregatorCatalogProvider`
   - Nexar/Octopart, TrustedParts, Findchips, SiliconExpert, Datasheets.com, or
     equivalent sources.
   - supplies cross-vendor availability, lifecycle, alternate-source evidence,
     and datasheet or compliance metadata.
5. `CadModelCatalogProvider`
   - SnapMagic/SnapEDA, Ultra Librarian, SamacSys, KiCad libraries, or local
     project libraries.
   - supplies symbol, footprint, 3D model, pin/pad mapping, and source
     provenance.
6. `DatasheetCorpusProvider`
   - local PDFs, downloaded datasheets, application notes, reference designs,
     manufacturer design guides, and later RAG indices.
   - supplies cited evidence only; it does not directly select parts without a
     structured selection decision.

### Core Data Contracts

Minimum plugin-owned schemas:

1. `ComponentSearchRequest`
   - component role
   - required electrical constraints
   - package and mounting constraints
   - safety/thermal/current/voltage constraints
   - preferred or excluded manufacturers/vendors
   - lifecycle and availability constraints
   - required evidence types
2. `ComponentCandidate`
   - MPN
   - manufacturer
   - normalized category
   - value/specification fields
   - package
   - ratings
   - lifecycle state
   - availability summary
   - datasheet references
   - provider provenance
3. `ComponentEvidence`
   - provider ID
   - source URL or local path
   - retrieval timestamp
   - license/cache policy
   - hash when local content is stored
   - extracted parameter values
   - confidence and blocking warnings
4. `DatasheetEvidence`
   - manufacturer
   - MPN
   - datasheet URL
   - local artifact path when downloaded
   - content hash
   - cited pages/sections when RAG is used
   - extraction timestamp
5. `FootprintCandidate`
   - footprint library
   - footprint name
   - package compatibility evidence
   - pin-to-pad mapping
   - source provider
   - 3D model reference when available
6. `PartSelectionDecision`
   - refdes
   - selected candidate or candidate set
   - status: `selected`, `ambiguous`, `blocked`, or
     `requires_vendor_resolution`
   - rationale
   - evidence references
   - unresolved decisions
7. `ComponentMatrix`
   - design ID
   - one `PartSelectionDecision` per component intent
   - matrix-level warnings
   - provider list and cache metadata

### Selection Rules

1. A model may propose search constraints, but SHALL NOT directly certify a part
   selection.
2. `selected` requires structured evidence for manufacturer, MPN, package,
   required ratings, datasheet URL or local datasheet artifact, and provider
   provenance.
3. `ambiguous` is allowed when several candidates satisfy the constraints and
   user choice or additional constraints are needed.
4. `blocked` is required when no candidate satisfies mandatory electrical,
   package, thermal, lifecycle, safety, or evidence constraints.
5. `requires_vendor_resolution` is allowed only before vendor/API providers are
   configured or when the workflow is explicitly in non-release draft mode.
6. Component selection SHALL preserve all source URLs, provider names, retrieval
   timestamps, and hashes for locally cached artifacts.
7. High-stakes parts require explicit evidence for ratings and shall carry
   review notes; catalog evidence does not certify safe use.

### Datasheet And PDF Strategy

Datasheets, app notes, reference designs, and manufacturer design guides are
evidence artifacts. The first implementation may store metadata only:

```json
{
  "manufacturer": "string",
  "mpn": "string",
  "url": "https://example.com/datasheet.pdf",
  "provider_id": "digikey",
  "retrieved_at": "ISO-8601 timestamp",
  "local_path": "optional",
  "sha256": "optional",
  "license": "source_terms_unknown"
}
```

Later RAG indexing may add chunk IDs, page citations, extracted tables, and
semantic search. RAG output SHALL be treated as cited evidence requiring
structured extraction and verifier checks. It SHALL NOT override datasheet,
catalog, KiCad, ERC, DRC, SPICE, or safety gates.

### Cache And Credentials

1. Catalog providers may cache normalized responses with provider-specific TTLs.
2. Datasheet PDFs may be cached only when terms allow local storage.
3. The plugin owns a `datasheet_cache_directory` setting. The default location
   is the user's Application Support path under
   `Merlin/plugins/electronics/datasheets`, and users may override it in the
   electronics plugin settings.
4. The plugin owns a `datasheet_cache_revalidate_after_seconds` setting. Fresh
   local PDFs SHALL be reused before any network request; stale entries may be
   conditionally revalidated and replaced only when the source changes.
5. API keys and credentials belong in user configuration or keychain-backed
   storage, not in plugin fixtures or committed files.
6. Cached data must retain source provider, retrieval timestamp, and original
   query metadata.

### Workflow Gates

The following downstream gates require catalog evidence:

1. `kicad_select_components`
   - requires component intents.
   - returns `ComponentMatrix`.
   - cannot claim selected parts without catalog evidence.
2. `kicad_assign_footprints`
   - requires `ComponentMatrix`.
   - requires footprint candidate and pin/pad compatibility evidence.
3. `kicad_compile_project`
   - natural-language/electronics-generated designs SHALL NOT compile to KiCad
     from DesignIntent alone.
   - compile requires approved DesignIntent, Circuit IR, selected or explicitly
     unresolved component decisions, and footprint assignment for PCB-bound
     components.
4. BOM and fabrication release
   - requires MPNs, vendor availability evidence, lifecycle/availability checks,
     normalized BOM, and explicit approval for irreversible ordering or
     fabrication actions.

## KiCad Integration Strategy

Preferred order:

1. KiCad CLI for deterministic checks and exports.
2. Plugin-owned KiCad S-expression parser/writer for structured file mutation.
3. KiCad library and file introspection for symbols, footprints, fields, netlists,
   and parity.
4. GUI automation or vision only for visual QA fallback and operations that
   cannot safely be performed through CLI or parser/writer paths.

The plugin SHALL round-trip test parser/writer mutations. GUI state and
screenshots SHALL NOT be electrical authority.

## First Acceptance Target: 25W Class A Guitar Amplifier

The first acceptance fixture is a 25W pure Class A solid-state guitar amplifier.
It is not a hard-coded path. It is a demanding fixture for the generic pipeline.

The design is split into separate boards:

1. `amp_low_voltage_audio`
   - low-voltage isolated secondary-side amplifier and audio circuitry.
   - includes preamp, 3-band tone circuit, sweepable boost/cut filter, driver,
     output stage, speaker output, low-voltage rail distribution, and thermal
     constraints.
2. `amp_mains_power_supply`
   - mains inlet, fuse, switch, protective earth, transformer primary, secondary
     interface, and related safety constraints.
   - second schematic and second PCB.
   - must remain under high-stakes safety policy and cannot be certified by the
     model.

## Status Model

The electronics workflow uses explicit status labels for each verified stage.

`SCHEMATIC_VERIFIED` requires:

1. Approved `DesignIntent`.
2. Valid Circuit IR.
3. `.kicad_pro`.
4. `.kicad_sch`.
5. Resolved symbols and required fields.
6. KiCad ERC report.
7. No blocking ERC errors.
8. Schematic verification report.

`SCHEMATIC_VERIFIED` is not full product completion and SHALL NOT imply PCB,
fabrication, SPICE, BOM, safety, or build approval.

`PCB_VERIFIED` requires selected components, footprint/pin compatibility
evidence, a KiCad board, placement/routing evidence, DRC report evidence, and
explicit rerun evidence after any repair mutation.

`SPICE_PASS` requires model records, simulation envelopes, non-generic scenario
decks, an executed SPICE run, and measurement evidence tied back to the
scenario.

`BOM_READY` requires concrete manufacturer/vendor records, availability,
lifecycle evidence, normalized BOM output, and any required user approval.

`FAB_READY` requires all upstream gates plus fabrication/CAM artifacts, drill
outputs, package manifests, verification reports, and approval records. It
SHALL NOT be emitted from unresolved components, placeholder schematic/PCB
files, generic smoke decks, missing SPICE evidence, placeholder BOM rows, or
declared-only fabrication paths.

`COMPLETE` may be used only when the workflow's requested scope is satisfied
and the corresponding status evidence is present.

## ERC Repair Loop

Algorithm:

```text
materialize schematic
run ERC
parse violations
classify each violation
propose structured patch
apply patch through Circuit IR and KiCad parser/writer
rerun ERC
repeat up to cap
block with diagnostics if unresolved
```

Default cap: 3 repair attempts per workflow unless a narrower workflow policy
applies.

Allowed repair classes include:

1. Add explicit no-connect marker.
2. Add or correct power flag.
3. Correct net label mismatch.
4. Repair missing connection from known Circuit IR endpoint.
5. Correct symbol field or pin mapping when resolver evidence proves the change.

The plugin SHALL NOT invent components, pinouts, or safety assumptions as an ERC
repair shortcut.

## DRC And PCB Verification

DRC is the second verification loop after schematic verification. The DRC loop
requires:

1. footprint assignment with pin compatibility proof;
2. board outline and stackup;
3. net classes and design rules;
4. placement constraints;
5. routing or explicit unrouted diagnostics;
6. KiCad DRC report parsing.

DRC repair actions may include placement, net-class, clearance, board-profile,
and routing repairs. Fabrication-profile or layer-count changes require user
approval.

## Safety Policy

High-stakes safety means designs involving hazardous voltage, mains, high
current, high temperature, stored energy, regulatory compliance, or life-safety
impact.

For high-stakes areas, the plugin may:

1. document assumptions;
2. produce CAD artifacts;
3. run ERC/DRC/SPICE/fabrication checks;
4. identify required qualified review.

The plugin SHALL NOT:

1. certify safety;
2. declare a mains design safe to build or use;
3. waive thermal, enclosure, grounding, creepage, clearance, or regulatory
   review;
4. submit irreversible fabrication or ordering actions without explicit approval.

The 25W amplifier power-supply board is high-stakes by default.

## Current Completion Contract

The electronics domain finish checklist is complete when Merlin has evidence
for the generic workflow gates and the GUI path proves honest stop behavior.
The current contract is:

1. F1: GUI resolver answers can feed structured component-selection revision.
2. F2: generic schematic and PCB realism is proven by materially different
   non-AmpDemo fixtures.
3. F3: the full artifact chain cannot skip or narrate requirements,
   DesignIntent, Circuit IR, component selection/revision, footprint
   assignment, schematic, PCB, ERC, DRC, SPICE, BOM/vendor, or fabrication/CAM
   gates.
4. F4: the rebuilt GUI workflow reads the active project spec, generates
   DesignIntent and Circuit IR, then stops at
   `COMPONENT_SELECTION_REVISION_BLOCKED` with actionable component evidence
   questions instead of advancing to placeholders.
5. F5: status documentation records that the electronics domain is finished as
   evidence-gated workflow infrastructure. That is not a claim that AmpDemo or
   every future design request reaches `FAB_READY` without user/vendor/catalog
   evidence.
