# Electronics Plugin Task List

Date: 2026-05-29

This task list scopes the path from the current electronics plugin state to the
generic KiCad-backed workflow described in `plugins/electronics/spec.md`.

## Numbered TDD Task Map

Execution uses the repo's normal numbered task files. Each `a` task adds the
red tests; each matching `b` task implements the behavior.

| Phase | Test task | Implementation task |
|---|---|---|
| Safety and drift cleanup | `tasks/task-387a-electronics-no-hardcoded-generators-tests.md` | `tasks/task-387b-electronics-no-hardcoded-generators.md` |
| Dynamic plugin roles | `tasks/task-388a-dynamic-plugin-roles-tests.md` | `tasks/task-388b-dynamic-plugin-roles.md` |
| Plugin-owned schemas | `tasks/task-389a-electronics-plugin-schemas-tests.md` | `tasks/task-389b-electronics-plugin-schemas.md` |
| DesignIntent approval flow | `tasks/task-390a-designintent-approval-flow-tests.md` | `tasks/task-390b-designintent-approval-flow.md` |
| KiCad library and pin resolver | `tasks/task-391a-kicad-library-pin-resolver-tests.md` | `tasks/task-391b-kicad-library-pin-resolver.md` |
| Circuit IR to KiCad schematic | `tasks/task-392a-circuit-ir-to-kicad-schematic-tests.md` | `tasks/task-392b-circuit-ir-to-kicad-schematic.md` |
| ERC parser and repair loop | `tasks/task-393a-erc-parser-repair-loop-tests.md` | `tasks/task-393b-erc-parser-repair-loop.md` |
| Amp low-voltage fixture | `tasks/task-394a-amp-low-voltage-fixture-tests.md` | `tasks/task-394b-amp-low-voltage-fixture.md` |
| PCB DRC follow-on | `tasks/task-395a-pcb-drc-followon-tests.md` | `tasks/task-395b-pcb-drc-followon.md` |
| Fabrication, BOM, and release | `tasks/task-396a-fab-bom-release-tests.md` | `tasks/task-396b-fab-bom-release.md` |
| SPICE optimization | `tasks/task-397a-spice-optimization-tests.md` | `tasks/task-397b-spice-optimization.md` |
| Amp mains power board | `tasks/task-398a-amp-mains-power-board-tests.md` | `tasks/task-398b-amp-mains-power-board.md` |
| Training and evaluation corpus | `tasks/task-399a-electronics-training-corpus-tests.md` | `tasks/task-399b-electronics-training-corpus.md` |
| End-to-end backend harness | `tasks/task-400a-electronics-end-to-end-harness-tests.md` | `tasks/task-400b-electronics-end-to-end-harness.md` |
| Runtime harness integration | `tasks/task-401a-electronics-runtime-harness-integration-tests.md` | `tasks/task-401b-electronics-runtime-harness-integration.md` |
| Real verifier adapters | `tasks/task-402a-electronics-real-verifier-adapter-tests.md` | `tasks/task-402b-electronics-real-verifier-adapters.md` |
| GUI evidence status | `tasks/task-403a-electronics-gui-evidence-status-tests.md` | `tasks/task-403b-electronics-gui-evidence-status.md` |
| Runtime artifact evidence | `tasks/task-404a-electronics-runtime-artifact-evidence-tests.md` | `tasks/task-404b-electronics-runtime-artifact-evidence.md` |
| Tool failure evidence | `tasks/task-405a-electronics-tool-failure-evidence-tests.md` | `tasks/task-405b-electronics-tool-failure-evidence.md` |
| Focused slice drift lock | `tasks/task-406a-electronics-focused-slice-drift-tests.md` | `tasks/task-406b-electronics-focused-slice-drift-fix.md` |
| Topology synthesis evidence | `tasks/task-407a-electronics-topology-synthesis-tests.md` | `tasks/task-407b-electronics-topology-synthesis.md` |
| Component catalog contracts | `tasks/task-408a-component-catalog-contracts-tests.md` | `tasks/task-408b-component-catalog-contracts.md` |
| Evidence-gated component selection | `tasks/task-409a-evidence-gated-component-selection-tests.md` | `tasks/task-409b-evidence-gated-component-selection.md` |
| Datasheet evidence capture | `tasks/task-410a-datasheet-evidence-capture-tests.md` | `tasks/task-410b-datasheet-evidence-capture.md` |
| Footprint evidence gate | `tasks/task-411a-footprint-evidence-gate-tests.md` | `tasks/task-411b-footprint-evidence-gate.md` |
| Compile gate evidence tightening | `tasks/task-412a-compile-gate-evidence-tests.md` | `tasks/task-412b-compile-gate-evidence.md` |
| Real catalog provider adapters | `tasks/task-413a-real-catalog-provider-adapters-tests.md` | `tasks/task-413b-real-catalog-provider-adapters.md` |
| Runtime evidence pipeline | `tasks/task-414a-electronics-runtime-evidence-pipeline-tests.md` | `tasks/task-414b-electronics-runtime-evidence-pipeline.md` |
| Evidence action orchestration | `tasks/task-415a-electronics-evidence-action-orchestration-tests.md` | `tasks/task-415b-electronics-evidence-action-orchestration.md` |
| Discrete Circuit IR synthesis | `tasks/task-416a-discrete-circuit-ir-synthesis-tests.md` | `tasks/task-416b-discrete-circuit-ir-synthesis.md` |
| Circuit IR component selection | `tasks/task-417a-circuit-ir-component-selection-tests.md` | `tasks/task-417b-circuit-ir-component-selection.md` |
| Circuit IR footprint coverage | `tasks/task-418a-circuit-ir-footprint-coverage-tests.md` | `tasks/task-418b-circuit-ir-footprint-coverage.md` |
| Runtime catalog provider selection | `tasks/task-419a-runtime-catalog-provider-selection-tests.md` | `tasks/task-419b-runtime-catalog-provider-selection.md` |
| Runtime footprint provider evidence | `tasks/task-420a-runtime-footprint-provider-evidence-tests.md` | `tasks/task-420b-runtime-footprint-provider-evidence.md` |
| Local KiCad catalog extraction | `tasks/task-421a-local-kicad-catalog-extraction-tests.md` | `tasks/task-421b-local-kicad-catalog-extraction.md` |
| Local KiCad catalog cache | `tasks/task-422a-local-kicad-catalog-cache-tests.md` | `tasks/task-422b-local-kicad-catalog-cache.md` |
| Provider config cache | `tasks/task-423a-provider-config-cache-tests.md` | `tasks/task-423b-provider-config-cache.md` |
| Runtime KiCad config | `tasks/task-424a-runtime-kicad-config-tests.md` | `tasks/task-424b-runtime-kicad-config.md` |
| Workflow artifact handoff | `tasks/task-425a-workflow-artifact-handoff-tests.md` | `tasks/task-425b-workflow-artifact-handoff.md` |
| Focused cache handoff | `tasks/task-426a-electronics-focused-cache-handoff-tests.md` | `tasks/task-426b-electronics-focused-cache-handoff.md` |

## Phase 0: Safety And Drift Cleanup

Goal: remove false-success paths and lock the plugin boundary.

1. Remove hard-coded requirements-to-PCB generators from the runtime plugin.
2. Add tests proving arbitrary requirements do not create KiCad/BOM/fabrication
   artifacts without approved design evidence.
3. Keep plugin-owned docs under `plugins/electronics`.
4. Add tests or doc checks preventing reintroduction of named demo generators.
5. Ensure Merlin core only exposes plugin capabilities and does not own
   electronics design policy.

Exit criteria:

- `workflow.requirements_to_pcb` blocks requirements-only input generically.
- No AmpDemo/ESP32/555-specific generator path exists.
- Plugin spec and research overview live under `plugins/electronics`.

## Phase 1: Dynamic Plugin Roles

Goal: allow electronics-only model roles without hard-coding them in Merlin core.

1. Add a dynamic role registry in Merlin core.
2. Preserve built-in roles: `execute`, `reason`, `orchestrate`, `vision`.
3. Extend plugin metadata so plugins can declare roles.
4. Register `electronics.analog_critic` as an optional role in the electronics
   plugin.
5. Hide plugin roles when the plugin is unloaded.
6. Surface plugin roles in role settings, status display, calibration/configure,
   routing, and token accounting only while loaded.
7. Add fallback policy: optional plugin role falls back to `reason`; required
   missing role blocks with `ROLE_UNASSIGNED`.

Exit criteria:

- Loading electronics adds `electronics.analog_critic`.
- Unloading electronics removes it.
- Existing fixed-role behavior is preserved for non-plugin workflows.

## Phase 2: Plugin-Owned Schemas

Goal: define the data contracts before artifact generation.

1. Add plugin-owned schema files for:
   - `DesignIntent`
   - `DesignApproval`
   - `CircuitIR`
   - `CircuitComponent`
   - `CircuitPin`
   - `CircuitNet`
   - `CircuitConstraint`
   - `VerificationScenario`
   - `SchematicVerificationReport`
2. Add Swift models where runtime code needs them.
3. Add JSON schema fixtures under `plugins/electronics`.
4. Add validators for required fields, unresolved decisions, component evidence,
   pin references, net endpoints, and safety domains.
5. Add round-trip encode/decode tests.

Exit criteria:

- Invalid Circuit IR blocks before KiCad mutation.
- Valid fixture schemas round-trip.
- Natural-language-originated `DesignIntent` starts in `draft`.

## Phase 3: DesignIntent Draft And Approval Flow

Goal: let Merlin assist DesignIntent authoring without mutating KiCad.

1. Add `kicad_build_intent_model` or plugin equivalent that drafts
   `DesignIntent` from requirements or schematic extraction.
2. Add unresolved-decision extraction.
3. Add user approval action for `DesignIntent`.
4. Add blocked response when KiCad mutation is requested with unapproved
   natural-language-originated intent.
5. Add draft-only preview mode, if needed, that cannot complete gates.

Exit criteria:

- Requirements can produce a draft intent.
- Approved intent can proceed.
- Unapproved intent cannot create verified KiCad artifacts.

## Phase 4: KiCad Library And Pin Resolver

Goal: make components evidence-backed before schematic materialization.

1. Add KiCad symbol library lookup.
2. Add symbol pin extraction.
3. Add footprint lookup.
4. Add footprint pad extraction.
5. Add symbol-pin to footprint-pad compatibility checks.
6. Add manufacturer/vendor part evidence fields.
7. Add resolver diagnostics for unknown symbols, unknown footprints, pin
   mismatch, missing MPN, and unresolved package.

Exit criteria:

- Every Circuit IR component has symbol evidence.
- PCB-bound components have footprint evidence before DRC/PCB phase.
- Resolver failures block with actionable diagnostics.

## Phase 5: Circuit IR To KiCad Schematic Materialization

Goal: compile validated Circuit IR into a KiCad schematic without raw
product-specific string generation.

1. Implement or complete KiCad S-expression parser/writer.
2. Add parser/writer round-trip tests for `.kicad_sch`.
3. Add schematic builder that inserts symbols, fields, labels, wires, no-connects,
   and power symbols from Circuit IR.
4. Ensure all mutations flow through structured writer APIs.
5. Add source mapping from Circuit IR entries to KiCad refs/UUIDs.
6. Add schematic parity check: Circuit IR components/nets match KiCad schematic.

Exit criteria:

- Valid Circuit IR creates `.kicad_pro` and `.kicad_sch`.
- No product-specific string emitter is used.
- Parity check passes for fixture designs.

## Phase 6: ERC Parser And Repair Loop

Goal: produce `SCHEMATIC_VERIFIED` from KiCad evidence.

1. Run KiCad ERC through CLI.
2. Parse ERC JSON into structured violations.
3. Classify supported repair classes:
   - explicit no-connect marker
   - power flag add/correction
   - net label mismatch
   - missing known Circuit IR endpoint connection
   - symbol field or pin mapping correction with resolver evidence
4. Add repair patch schema.
5. Apply repairs through Circuit IR and KiCad parser/writer.
6. Rerun ERC after each repair.
7. Enforce 3-attempt repair cap.
8. Produce `SchematicVerificationReport`.
9. Add `SCHEMATIC_VERIFIED` status.

Exit criteria:

- ERC failures are parsed, repaired when supported, or blocked when unsupported.
- `SCHEMATIC_VERIFIED` requires approved intent, valid Circuit IR, KiCad project,
  schematic, ERC report, no blocking ERC errors, and verification report.

## Phase 7: First Acceptance Fixture

Goal: prove the generic flow on the first real target without special-casing.

1. Add `amp_low_voltage_audio` `DesignIntent` fixture.
2. Add Circuit IR fixture for the low-voltage audio board.
3. Include preamp, 3-band tone circuit, sweepable boost/cut filter, driver,
   output stage, speaker output, low-voltage rail distribution, and thermal
   constraints.
4. Mark unresolved decisions honestly.
5. Keep `amp_mains_power_supply` as a separate second-board fixture stub.
6. Run fixture through resolver, schematic materializer, ERC, repair loop, and
   schematic verification.
7. Add tests proving the fixture uses generic schemas and not named generator
   code.

Exit criteria:

- The low-voltage amp board reaches `SCHEMATIC_VERIFIED` or blocks with specific
  unresolved design decisions.
- No special-case code path exists for the amp.

## Phase 8: DRC And PCB Follow-On

Goal: extend from verified schematic to PCB verification.

1. Add board profile schema.
2. Add footprint assignment from resolver evidence.
3. Add board outline and stackup creation.
4. Add net-class generation.
5. Add placement constraints and placement mutation.
6. Add routing integration through DSN/SES and FreeRouting.
7. Run KiCad DRC.
8. Parse DRC diagnostics.
9. Add bounded DRC repair loop.
10. Define `PCB_VERIFIED` status.

Exit criteria:

- A verified schematic can produce a board.
- DRC failures are parsed and either repaired or blocked.
- `PCB_VERIFIED` is distinct from full fabrication completion.

## Phase 9: Fabrication, BOM, And Release

Goal: define full completion beyond schematic and PCB verification.

1. Normalize BOM schema.
2. Add vendor availability and MPN checks.
3. Export Gerbers, drills, BOM, placement files, and fabrication reports.
4. Add fabricator profile validation.
5. Add release package generation.
6. Add explicit approval gates for irreversible order/fab actions.
7. Define `FAB_READY` and final `COMPLETE` semantics.

Exit criteria:

- Full completion requires schematic, PCB, ERC, DRC, BOM, fabrication outputs,
  verification reports, and required approvals.

## Phase 10: Simulation And Optimization

Goal: add AnalogCoder/AutoCkt-style simulator-driven repair and optimization.

1. Add SPICE scenario schema.
2. Add model resolution policy.
3. Add ngspice execution and measurement parsing.
4. Add simulation pass/fail envelopes.
5. Add repair actions for supported simulation failures.
6. Add bounded optimization loops for fixed-topology analog subcircuits.
7. Keep optimization separate from broad topology synthesis.

Exit criteria:

- Simulation-required designs cannot complete without simulation evidence.
- Bounded optimization improves parameterized subcircuits without inventing
  unsupported topology changes.

## Phase 11: Second Board Fixture

Goal: add the separate amplifier mains/power-supply board under high-stakes
policy.

1. Add `amp_mains_power_supply` `DesignIntent` fixture.
2. Add Circuit IR fixture for the power-supply board.
3. Represent mains inlet, fuse, switch, PE bond, transformer primary, secondary
   interface, creepage/clearance constraints, and safety notes.
4. Require explicit high-stakes review state.
5. Ensure CAD verification does not imply safety certification.
6. Add tests for blocked certification language and approval requirements.

Exit criteria:

- The power-supply board can produce CAD/verification artifacts only with
  high-stakes policy active.
- Merlin never certifies it safe to build or use.

## Phase 12: Training And Evaluation Corpus

Goal: collect data for better electronics-specific models.

1. Log accepted and rejected `DesignIntent` drafts.
2. Log Circuit IR validation failures and repairs.
3. Log ERC/DRC/SPICE/BOM diagnostics.
4. Log repair patches and verifier outcomes.
5. Build training pairs:
   - requirements to intent
   - intent to Circuit IR
   - diagnostics to patch
   - patch to verifier result
6. Add evaluation scenarios for sensor board, power supply, analog filter, amp
   low-voltage board, and amp power-supply board.

Exit criteria:

- Merlin has a verifier-grounded dataset suitable for fine-tuning or model
  selection.

## Phase 13: End-To-End Backend Harness

Goal: prove the generic plugin workflow with one focused backend harness before
any GUI demo rerun.

1. Accept optional `DesignIntent`, optional `CircuitIR`, output directory,
   verifier evidence, and approvals.
2. Run schema validation, resolver checks, schematic materialization, schematic
   parity, ERC repair, schematic verification, PCB verification, SPICE evidence,
   fabrication release evaluation, and high-stakes safety policy.
3. Require concrete evidence for each status transition.
4. Keep `SCHEMATIC_VERIFIED`, `PCB_VERIFIED`, `FAB_READY`, and `COMPLETE`
   separate.
5. Block mains/high-stakes safety certification claims even when CAD artifacts
   may be prepared.

Exit criteria:

- Intent-only/spec-read input remains blocked.
- The low-voltage amp fixture can reach `FAB_READY` only with SPICE and
  fabrication evidence.
- `COMPLETE` requires release package and release approval.
- The mains board blocks without high-stakes signoff and never certifies build
  or use safety.

## Phase 14: Runtime Harness Integration

Goal: make the actual runtime workflow call the same evidence-gated backend
harness proven by Phase 13.

1. Add a structured runtime request form with DesignIntent path, Circuit IR path,
   output directory, verifier evidence, and approvals.
2. Route structured `workflow.requirements_to_pcb` and `workflow.schematic_to_pcb`
   calls through `ElectronicsEndToEndHarness`.
3. Return the harness result as the workflow payload.
4. Treat `BLOCKED` as a blocked workspace response and all verified non-final
   statuses as successful but non-complete responses.
5. Keep legacy/narrative completion out of structured workflow status.

Exit criteria:

- Runtime workflow calls with the amp low-voltage fixture return `FAB_READY`
  without release approval.
- Missing SPICE evidence blocks when SPICE is required.
- Runtime returns `COMPLETE` only when the harness reports `COMPLETE`.

## Phase 15: Real Verifier Artifact Adapters

Goal: let the generic backend harness consume concrete verifier artifacts from
KiCad, ngspice, BOM/vendor checks, and fabrication export tools.

1. Read ERC and DRC JSON reports from artifact paths.
2. Read SPICE scenario/model/output files and pass them through the SPICE gate.
3. Read normalized BOM and vendor availability evidence.
4. Read fabrication-output manifests and validate them against a fabricator
   profile.
5. Produce `ElectronicsEndToEndEvidence` without adding hard-coded example
   generators.

Exit criteria:

- Clean verifier artifacts can take the low-voltage amp fixture to `FAB_READY`.
- Blocking DRC prevents `PCB_VERIFIED`.
- Invalid BOM/vendor evidence blocks fabrication.

## Phase 16: GUI Evidence Status

Goal: make the electronics job panel display the backend harness status and
missing evidence directly.

1. Publish structured harness progress payloads with `job_id`.
2. Store `ElectronicsEndToEndResult` on live electronics jobs.
3. Show real statuses such as `SCHEMATIC_VERIFIED`, `PCB_VERIFIED`, `FAB_READY`,
   `BLOCKED`, and `COMPLETE`.
4. Show missing evidence and diagnostics without treating non-final statuses as
   complete.

Exit criteria:

- The live leaderboard shows the harness status for structured workflow calls.
- Missing release package/approval evidence is visible for `FAB_READY` jobs.

## Phase 17: Runtime Artifact Evidence

Goal: make runtime structured workflow calls accept artifact paths from real
tools rather than requiring callers to assemble internal evidence structs.

1. Accept `evidence_artifacts` on structured workflow requests.
2. Build harness evidence with `ElectronicsEvidenceArtifactAdapter`.
3. Preserve the existing explicit `evidence` path for tests and low-level calls.
4. Block if neither evidence form is provided.

Exit criteria:

- Runtime workflow calls can return `FAB_READY` from verifier artifact paths.

## Phase 18: Tool Failure Evidence

Goal: preserve real KiCad/ngspice failure artifacts for evidence gates and repair
loops.

1. Return ERC/DRC report artifacts even when KiCad exits non-zero after writing a
   report.
2. Return SPICE measurement/log artifacts even when ngspice exits non-zero after
   writing a log.
3. Keep missing executable/input failures blocked without fabricated artifacts.
4. Do not add hard-coded schematic, PCB, BOM, or SPICE generators.

Exit criteria:

- Failed DRC report artifacts can still block `PCB_VERIFIED` through the harness.
- Failed SPICE logs remain attached to the blocked tool result.

## Phase 19: Focused Slice Drift Lock

Goal: keep focused electronics workflow slices on the plugin/KiCad runtime path.

1. Do not parallelize evidence-gated electronics plans into `spawn_agent`
   batches.
2. Reject non-inspection, non-electronics tools such as `xcode_open_file` while
   the electronics workflow lock is active.
3. Wait for runtime plugin tool registration before GUI chat submission sends
   the first provider request.

Exit criteria:

- A focused read-spec-then-first-KiCad slice cannot satisfy the KiCad step with
  `spawn_agent` or `xcode_open_file`.

## Phase 20: Topology Synthesis Evidence

Goal: turn structured topology constraints into reusable component and net
intent evidence without hard-coded project generators.

1. Recognize generic topology patterns from `constraints_json`.
2. Synthesize component intents and net intents only as draft design evidence.
3. Preserve user-provided components, nets, boards, assumptions, and verification
   plans.
4. Keep generated intent unapproved unless the payload explicitly supplies
   approval.

Exit criteria:

- Structured single-ended Class-A audio constraints produce component/net
  evidence.
- Component selection can consume synthesized component intents.
- No KiCad files are created by intent synthesis.

## Phase 21: Component Catalog Contracts

Goal: define the plugin-owned provider interfaces and schemas for evidence-backed
component selection.

1. Add schemas/models for `ComponentSearchRequest`, `ComponentCandidate`,
   `ComponentEvidence`, `DatasheetEvidence`, `FootprintCandidate`,
   `PartSelectionDecision`, and `ComponentMatrix`.
2. Add `ComponentCatalogProvider` abstraction.
3. Add deterministic `StaticFixtureCatalogProvider`.
4. Add local `KiCadLibraryCatalogProvider` contract for symbol/footprint
   discovery.
5. Add validation tests for required provenance, ratings, package, datasheet,
   lifecycle, and evidence metadata.

Exit criteria:

- Component catalog data round-trips through schemas.
- Invalid candidates without required provenance or ratings are rejected.
- Tests run without network or API keys.

## Phase 22: Evidence-Gated Component Selection

Goal: make `kicad_select_components` return real evidence-backed decisions
instead of role-only placeholders.

1. Read `DesignIntent.components`.
2. Convert component intents to `ComponentSearchRequest` values.
3. Query configured catalog providers.
4. Emit `ComponentMatrix`.
5. Mark each component `selected`, `ambiguous`, `blocked`, or
   `requires_vendor_resolution`.
6. Block unsafe or incomplete choices with actionable diagnostics.

Exit criteria:

- Role text alone cannot produce `selected`.
- Fixture provider evidence can produce `selected`.
- Missing providers produce `requires_vendor_resolution`, not fake selection.

## Phase 23: Datasheet Evidence Capture

Goal: preserve datasheet and source metadata before RAG exists.

1. Add datasheet metadata artifacts with URL, provider, manufacturer, MPN,
   retrieval timestamp, and optional local hash.
2. Add cache policy metadata.
3. Add tests proving downloaded or referenced datasheets are linked from
   `ComponentEvidence`.
4. Do not require PDF indexing in this phase.

Exit criteria:

- Component selections carry datasheet evidence references.
- Local PDF hashes are recorded when PDFs are stored.
- RAG fields are optional and absent by default.

## Phase 24: Footprint Evidence Gate

Goal: require symbol/footprint compatibility evidence before PCB-bound work.

1. Resolve footprint candidates from KiCad/local/CAD model providers.
2. Extract footprint pad maps.
3. Match symbol pins to footprint pads.
4. Emit footprint assignment artifacts with source provenance.
5. Block unresolved or incompatible footprints.

Exit criteria:

- `kicad_assign_footprints` cannot complete without footprint evidence.
- Pin/pad mismatch blocks with affected refdes and candidate footprint.
- Valid fixture assignments pass.

## Phase 25: Compile Gate Evidence Tightening

Goal: prevent skeleton KiCad artifacts from being created from intent-only or
role-only evidence.

1. Require approved `DesignIntent` for natural-language-originated work.
2. Require Circuit IR.
3. Require `ComponentMatrix`.
4. Require footprint assignment for PCB-bound components.
5. Require unresolved component and footprint decisions to be explicit blockers
   or accepted draft limitations.
6. Keep draft preview mode separate from verified artifact progress.

Exit criteria:

- `kicad_compile_project` blocks without component matrix and footprint evidence.
- Existing user-authored fixture paths continue to work where explicitly allowed.
- Natural-language/electronics-generated designs cannot produce fake schematic
  or PCB files.

## Phase 26: Real Catalog Provider Adapters

Goal: add optional real online provider adapters after the offline contracts are
green.

1. Add Digi-Key provider adapter.
2. Add Mouser provider adapter.
3. Add optional Nexar/Octopart or equivalent aggregator provider adapter.
4. Add optional CAD model provider adapter hooks for SnapMagic/SnapEDA, Ultra
   Librarian, SamacSys, or equivalent sources.
5. Add provider configuration and credential validation.
6. Add TTL cache and provenance metadata.
7. Add tests with recorded fixtures; keep live API tests opt-in.

Exit criteria:

- Providers are optional and disabled without credentials.
- Recorded fixture tests pass offline.
- Live API failures degrade to blocked provider diagnostics, not fake parts.

## Phase 27: Runtime Evidence Pipeline

Goal: make runtime continuation actions follow the first missing verified
electronics artifact.

1. Use explicit next actions for compile evidence blockers.
2. Keep compile evidence order strict: Circuit IR, ComponentMatrix, footprint
   assignment, then compile.
3. Route invalid footprint coverage back to footprint assignment.
4. Preserve user-authored fixture compile behavior.

Exit criteria:

- Missing Circuit IR returns `generate_circuit_ir`.
- Missing ComponentMatrix returns `select_components`.
- Missing or invalid footprint evidence returns `assign_footprints`.
- Compile does not advance from a generic continuation action.

## Phase 28: Evidence Action Orchestration

Goal: ensure runtime evidence continuation actions map to real electronics tools
and run in verified artifact order.

1. Map `generate_circuit_ir` to `kicad_generate_circuit_ir`.
2. Map `select_components` to `kicad_select_components`.
3. Map `assign_footprints` to `kicad_assign_footprints`.
4. Order requirements workflows as DesignIntent, Circuit IR, component
   selection, footprint assignment, compile.

Exit criteria:

- Every compile-gate next action resolves to a registered electronics tool.
- Requirements workflows cannot run component selection before DesignIntent.
- Compile remains after footprint assignment.

## Phase 29: Discrete Circuit IR Synthesis

Goal: generate evidence-backed Circuit IR from approved DesignIntent without
block-level placeholder components.

1. Add `kicad_generate_circuit_ir`.
2. Convert basic discrete component intents into Circuit IR components.
3. Expand discrete RC/tone/filter intent patterns into concrete R/C/control
   components.
4. Preserve source evidence from the originating DesignIntent component.
5. Validate generated net endpoints before returning the artifact.

Exit criteria:

- The amp topology fixture emits discrete R/C/transistor/connector components.
- No `TONE1` or `FILTER1` block component appears in Circuit IR.
- Generated nets validate against component pins.

## Phase 30: Circuit IR Component Selection

Goal: make component selection consume expanded Circuit IR parts instead of
block-level DesignIntent placeholders.

1. Accept optional `circuit_ir_path` in `kicad_select_components`.
2. Prefer Circuit IR components when Circuit IR is present.
3. Preserve DesignIntent-only selection when no Circuit IR is supplied.
4. Match catalog candidates by concrete component class before selecting.

Exit criteria:

- Expanded Circuit IR refdes receive component matrix decisions.
- Block placeholders such as `TONE1` and `FILTER1` are not selected as parts
  when Circuit IR exists.
- Missing catalog evidence leaves expanded parts unresolved.

## Phase 31: Circuit IR Footprint Coverage

Goal: make footprint assignment cover every PCB-bound Circuit IR component
before compile can proceed.

1. Accept optional `circuit_ir_path` in `kicad_assign_footprints`.
2. Prefer Circuit IR components as the assignment target set when available.
3. Use Circuit IR pin evidence for pin/pad compatibility checks.
4. Block if the component matrix omits any Circuit IR component.

Exit criteria:

- Footprint assignment artifacts cover expanded Circuit IR refdes.
- Missing expanded component decisions block with affected refdes.
- Compile footprint coverage can be satisfied by Circuit IR-derived reports.

## Phase 32: Runtime Catalog Provider Selection

Goal: let `kicad_select_components` use configured provider evidence directly
instead of requiring a prebuilt `catalog_candidates_path`.

1. Accept recorded provider fixture paths keyed by provider ID.
2. Map Digi-Key, Mouser, and aggregator fixtures through provider adapters.
3. Merge provider candidates with explicit candidate-file evidence.
4. Match provider candidates to concrete Circuit IR component requests.
5. Preserve provider/cache metadata in the emitted ComponentMatrix.

Exit criteria:

- Runtime selection can select Circuit IR components from provider fixtures.
- Missing providers still leave components unresolved.
- Provider provenance and cache metadata are visible in the matrix.

## Phase 33: Runtime Footprint Provider Evidence

Goal: carry local KiCad footprint evidence from runtime selection into
footprint assignment.

1. Accept local KiCad symbol and footprint catalog paths.
2. Use Circuit IR selected symbol/footprint constraints to request local
   footprint evidence.
3. Attach local footprint candidates to selected vendor candidates.
4. Keep footprint assignment blocked if selected candidates lack footprint
   evidence.

Exit criteria:

- Provider-selected candidates can include local footprint candidates.
- Footprint assignment can consume provider-generated matrices.
- Missing footprint evidence remains a blocker.

## Phase 34: Local KiCad Catalog Extraction

Goal: extract local KiCad symbol and footprint evidence from installed or
workspace-provided library roots.

1. Parse `.kicad_sym` symbol libraries into symbol definitions.
2. Parse `.pretty/*.kicad_mod` footprint libraries into footprint definitions.
3. Preserve library-qualified names for symbol/footprint lookup.
4. Keep extraction generic and independent of any demo target.

Exit criteria:

- Local symbol roots produce `KiCadSymbolDefinition` rows.
- Local footprint roots produce `KiCadFootprintDefinition` rows.
- Runtime component selection can use extracted local library evidence.

## Phase 35: Local KiCad Catalog Cache

Goal: avoid re-extracting local KiCad libraries on every electronics tool call.

1. Write extracted catalogs to a plugin-owned cache file.
2. Load cache entries while they are within TTL.
3. Re-extract when the cache is missing or stale.

Exit criteria:

- Fresh local KiCad catalog cache is reused.
- Stale cache is ignored.
- Cache behavior is covered by focused tests.

## Phase 36: Provider Config Cache

Goal: avoid repeating catalog provider setup and fixture mapping in every tool
call.

1. Read provider fixture paths from explicit config or workspace-local plugin
   config.
2. Let request payload values override config values.
3. Cache mapped provider candidates by provider ID.
4. Reuse cached provider candidates when the fixture file is unavailable and
   the cache is fresh.

Exit criteria:

- Runtime selection can run from provider config alone.
- Provider candidate cache can satisfy a later selection call.
- Provider provenance remains visible in the component matrix.

## Phase 37: Runtime KiCad Config

Goal: wire local KiCad library roots and cache controls into runtime component
selection.

1. Accept `kicad_symbol_library_root` and `kicad_footprint_library_root`.
2. Accept `kicad_catalog_cache_directory` and TTL.
3. Extract/cache local KiCad libraries when explicit JSON catalog files are not
   supplied.
4. Use extracted footprint evidence to enrich provider-selected parts.

Exit criteria:

- Local KiCad roots can replace hand-authored JSON catalog path inputs.
- Runtime-selected parts can carry local KiCad footprint candidates.

## Phase 38: Workflow Artifact Handoff

Goal: carry verified artifact paths through structured tool results instead of
requiring narrative inference.

1. Add a structured handoff object to KiCad tool results.
2. Preserve input paths such as DesignIntent, Circuit IR, component matrix, and
   footprint assignment.
3. Add newly produced artifact paths to the handoff before returning.
4. Keep next actions separate from artifact evidence.

Exit criteria:

- Component selection returns handoff paths for DesignIntent, Circuit IR, and
  component matrix.
- Footprint assignment returns handoff paths for prior evidence and the new
  footprint assignment artifact.

## Phase 39: Focused Cache Handoff Slice

Goal: prove the runtime cache/config/handoff path as one focused electronics
slice.

1. Run component selection from provider config.
2. Reuse provider cache after fixture removal.
3. Extract/cache local KiCad library evidence.
4. Use handoff paths to drive footprint assignment.

Exit criteria:

- Focused catalog extraction, provider cache, local KiCad cache, and handoff
  tests pass together.

## Phase 40: Handoff Driven Orchestration

Goal: make KiCad workflow orchestration advance from structured handoff evidence.

1. Accumulate handoff paths from each completed KiCad tool.
2. Pass verified paths into following tool arguments.
3. Preserve explicit output directories.

Exit criteria:

- Circuit IR, component selection, footprint assignment, and compile receive the
  expected prior artifact paths.

## Phase 41: Missing Evidence Stops

Goal: prevent workflow steps from running when required handoff evidence is
absent.

1. Define required evidence paths per workflow step.
2. Stop before the tool call when evidence is missing.
3. Return blocked input quality instead of inferred progress.

Exit criteria:

- A missing DesignIntent path prevents Circuit IR execution.
- Later KiCad steps cannot run without their required upstream artifacts.

## Phase 42: KiCad Library Root Discovery

Goal: find local KiCad symbol and footprint roots without hand-authored JSON
catalogs.

1. Search configured KiCad installation roots.
2. Recognize app/support `symbols` and `footprints` layouts.
3. Ignore incomplete layouts.

Exit criteria:

- Configured KiCad install layouts resolve to concrete symbol and footprint
  roots.

## Phase 43: KiCad Root Config Cache

Goal: use provider config and TTL caching for KiCad library root discovery.

1. Read root search paths and cache settings from electronics provider config.
2. Let request payload values override config values.
3. Reuse fresh root-cache entries only.

Exit criteria:

- Runtime selection can discover KiCad roots from config and cache the result.

## Phase 44: Focused Amp Backend Handoff

Goal: prove the plugin-owned Amp fixture can move through selection and
footprints by handoff evidence.

1. Use Circuit IR-backed component intents.
2. Enrich explicit catalog candidates with local KiCad footprint evidence.
3. Preserve Circuit IR pin-to-pad mappings for footprint validation.

Exit criteria:

- The Amp backend slice reaches footprint assignment without bypassing evidence
  gates.

## Phase 45: Focused Amp Artifact Creation

Goal: prove the focused Amp backend slice creates KiCad artifacts from verified
handoff inputs.

1. Compile from DesignIntent, Circuit IR, component matrix, and footprint
   assignment paths.
2. Return project, schematic, and board artifacts.
3. Keep full-demo ERC/DRC/SPICE gates for later phases.

Exit criteria:

- The focused Amp backend slice creates KiCad project, schematic, and board
  artifacts through the generic runtime path.
