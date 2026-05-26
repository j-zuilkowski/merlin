# Merlin — Vision Document

`vision.md` is Merlin's idea launchpad. New ideas land in `## Active`, then are either
promoted to `spec.md` as committed design or parked in `## Deferred` with a
clear reconsideration trigger.

Architectural source of truth remains `spec.md`; this document captures intent
upstream of committed design.

## Active

### Spec-Driven Development alignment

Merlin's discipline subsystem now uses Spec-Driven Development (SDD) terms directly:
`constitution.md` is the constitution, `vision.md` is the idea launchpad, `spec.md`
is the committed design/spec, `tasks/` are the task decomposition, and the
`vision → spec → task → code` pipeline is the SDD workflow. The methodology is named,
consistent, and legible to the wider SDD ecosystem (GitHub Spec Kit, Amazon Kiro).

**What:**
- **Vocabulary rename** — completed across code, docs, historical task sheets, and the
  `project:*` skill subsystem: *constitution* (`constitution.md`), *spec* (`spec.md`),
  *tasks* (`tasks/`), *vision* (`vision.md`).
- **EARS acceptance criteria** — add a `## Behavior` block to the task template
  using EARS notation (`WHEN [trigger] THE [system] SHALL [response]`, plus `WHILE`,
  `IF … THEN`, `WHERE`, and ubiquitous forms). Each task states its intended behavior
  in a standardized, testable form that the `a`-task TDD tests verify directly.
- **Backfill** — retrofit the EARS `## Behavior` block and the SDD vocabulary into the
  existing committed task files, not new tasks only.
- **Consistency gate** — extend `DisciplineEngine` with a vision↔spec↔task coherence
  check (the SDD `/analyze` equivalent), run before implementation rather than only as
  post-hoc drift detection. It verifies that every task traces to a spec section and
  every spec section to a vision item, and flags divergence up front.

**Why:** Merlin converged on SDD independently; naming it removes ambiguity, EARS
sharpens every task's acceptance criteria, a shared vocabulary makes the discipline
subsystem legible to the ecosystem, and the consistency gate catches spec/task
divergence before code is written. SDD is additive here — keep the task-file + TDD
engine; do not swap the `project:*` subsystem for Spec Kit's CLI.

**Rename scope — completed: structural rename.** The repository now uses
`constitution.md`, `vision.md`, `spec.md`, and `tasks/` consistently. The cutover touched
the task files, the discipline scanner code that walks `tasks/`, `REBUILD-GUIDE.md`,
`PASTE-LIST.md`, `ALL-TASKS.md`, and all five `project:*` skills (`init`, `adopt`,
`task`, `revise`, `release`).

For the `project:*` skills the rename is **two-sided**: not only their own prose but
also the artifacts they *scaffold* must change — `project:init` and `project:adopt`
write `spec.md` / `tasks/`, `project:task` and
`project:revise` operate on `tasks/`, and the doc templates under
`~/.merlin/templates/docs/` follow suit. So every project Merlin creates or adopts after
the rename uses the SDD names from the start, not just the Merlin repo itself.

**Design consideration — keep it domain-agnostic.** The discipline subsystem must serve
software, electronics (KiCad), and the planned mechanical-CAD (Fusion) domain — not just
Swift code. Write the methodology generically: constitution → vision → spec → tasks →
produce → verify, with the **verification gate as a pluggable per-domain step**. This
is not new infrastructure — domains are already plugins (`DomainPlugin` / `DomainRegistry`,
plus `MCPDomainAdapter` for fully external MCP domains), and `DomainPlugin.verificationBackend`
— with `DomainManifest.verificationCommands` for external domains — already *is* the
per-domain verification seam. SDD builds on it: each domain's `verificationBackend`
supplies that domain's acceptance check — TDD tests for software, ERC/DRC/SPICE for
KiCad, interference/clearance for Fusion. (This is distinct from `AdapterRegistry`,
which is the project *build* toolchain — `swift-xcode` / `rust-cargo`.) One adjustment
for non-code domains: SDD's "the spec regenerates the artifact" assumption holds for
code but weakens for PCB layout and CAD geometry — those are stateful craft artifacts
the spec *governs and gates* rather than *regenerates*. The `spec.md` methodology
section must state this explicitly, so the EARS `## Behavior` blocks and the consistency
gate are written to *verify* hardware artifacts, not regenerate them.

**Status: promoted and implemented.** The structural rename is complete. `spec.md` now
defines the SDD methodology, `project:task` and `project:init` create task documents with
`## Traceability` and `## Behavior`, existing task sheets are backfilled, and
`SDDTraceabilityScanner` runs through `DisciplineEngine.scan` to flag missing or dangling
vision/spec/task coherence before implementation starts.

### Runtime plugin architecture + the electronics plugin

Merlin's domains become **runtime-loaded plugins**. `merlin/plugins/` holds plugin
source — one subdirectory per plugin. Each plugin builds to a **shared library**; at
launch Merlin scans the installed-plugins location, loads each one, and registers it
with `DomainRegistry`. A plugin contributes its domain logic, tools, and verification
backend — **and its own settings panel**, which Merlin discovers and renders
dynamically in the Settings window. Adding a domain (with its settings UI) becomes
dropping in a plugin, not editing the app. For now every plugin lives in the Merlin
repo and is built together with Merlin; splitting plugins into their own repos is
expected later but explicitly deferred.

**The electronics plugin** — `merlin/plugins/electronics/` — is the first plugin and
consolidates *all* KiCad and FreeRouting work into one directory: the current in-app
KiCad client (`Merlin/Electronics/` — contracts, schemas, the `.kicad_sch` parser,
`KiCadToolDefinitions`, `KiCadWorkflowOrchestrator`, policies) plus the `kicad-cli` /
FreeRouting execution the `merlin-kicad-mcp` scaffold was started for. One plugin, one
directory.

**FreeRouting backend — local or hosted.** Routing (`kicad_route_pass`) supports two
interchangeable backends, user-selectable, behind the one `kicad_route_pass` contract
and the same KiCad DSN/SES interchange:
- **Local (default)** — the FreeRouting install at `/Applications/freerouting.app`. The
  app bundle ships its own Java runtime (jpackage-style); the plugin invokes its
  launcher `/Applications/freerouting.app/Contents/MacOS/freerouting` in headless/CLI
  mode. No separate JRE is needed — and the system has none installed (`/usr/bin/java`
  is only Apple's stub).
- **Hosted API (optional)** — `api.freerouting.app/v1` with an API key, for when the
  local install is absent or remote routing is wanted.

**This supersedes the separate-MCP-server model.** `merlin-kicad-mcp` was scaffolded as
a standalone out-of-process MCP server (stdio JSON-RPC). Under the runtime-plugin model
the electronics plugin is **in-process** — a loadable `DomainPlugin`, not a server
process. The KiCad/FreeRouting *logic* and the ~23-tool contract survive; the stdio MCP
transport does not. The former `merlin/plugins/merlin-kicad-mcp/` scaffold
(constitution, ROADMAP, tasks 00/01a/01b) is archived at
`archive/legacy-merlin-kicad-mcp/` for historical reference; active electronics work
lives under `merlin/plugins/electronics/`.

**Infrastructure this needs first (before the electronics plugin):**
- A **workspace message bus** — one `WorkspaceMessageBus` per `WorkspaceRuntime`, shared
  by every session and subagent in that workspace. It is Merlin's general control plane,
  not plugin-only plumbing.
- **Shared message contracts** — envelope types, origin/scope, settings schema,
  capabilities, diagnostics, artifact references, timeout/cancellation, and event
  payloads. These can start in the app target, then move into a shared
  `MerlinPluginAPI` dynamic library when external plugin targets land.
- **All tool dispatch through the bus** — `ToolRouter` becomes a bus client. Built-in
  tools, MCP tools, domain verification, workflow actions, and future plugin tools all
  use registered handlers/transports. Direct `ToolRouter` closure dispatch is not a
  completed state.
- A **plugin loader** in Merlin after the bus foundation: at launch, scan the plugins
  location, `dlopen` each bundle, `dlsym` a `@_cdecl` factory symbol, instantiate, and
  register handlers/capabilities. Merlin is non-sandboxed, so `dlopen` of bundles is
  permitted.
- **Build wiring** so every `merlin/plugins/*/` package builds to its shared library
  alongside the Merlin build.

**Two-tier plugin model — decided.** Plugins load by trust level — not one mechanism
for all:
- **Tier 1 — in-process, first-party** (electronics, software, future Fusion): a
  `dlopen`'d shared library, built and rebuilt together with Merlin. ABI coupling is
  handled by "rebuild everything" — no `-enable-library-evolution` gymnastics needed.
  Fast, no IPC. Accepted cost: a Tier-1 plugin crash or hang takes Merlin down with it.
- **Tier 2 — out-of-process, third-party / store**: a separate process Merlin talks to,
  bridged by the existing `MCPDomainAdapter`. This is what the plugin store distributes
  — third-party native code is **never** `dlopen`'d into Merlin. Rationale: Merlin is
  non-sandboxed (filesystem, shell, AX, screen capture, input synthesis); an in-process
  third-party plugin would inherit all of it with no boundary. A separate process
  restores crash isolation and gives a real security boundary. The IPC cost is
  negligible for domains like electronics whose work is already `kicad-cli`-subprocess
  and HTTP bound.

`DomainPlugin` is metadata and policy over both tiers; runtime behavior flows through
workspace bus capabilities. `MCPDomainAdapter` bridges Tier 2 by translating bus
requests to the external protocol. Design the shared message contracts for both tiers
from the start — do not assume every plugin is in-process, and do not over-invest in
library-evolution resilience for a third-party-in-process case that should not exist.

**Future — plugin store.** Once the model is proven, a **plugins menu** lets the user
browse, search, and install plugins from an online store (likely GitHub-hosted). Store
plugins are **Tier 2** — out-of-process, signed and notarized (macOS Gatekeeper blocks
unsigned downloaded bundles) — never `dlopen`'d into Merlin. It is the marketplace
layer on top of the Tier-2 bridge; deferred until the in-repo first-party model is
proven, not a prerequisite for it.

**Promotion:** promoted to `spec.md` as the workspace message bus architecture. The
implementation order is now: (1) shared message contracts; (2) `WorkspaceRuntime`; (3)
`WorkspaceMessageBus`; (4) all built-in tool dispatch converted to bus handlers; (5)
subagent origin/scope propagation; (6) MCP tools as bus transports; (7) domain
capabilities and verification through the bus; (8) host-rendered dynamic settings
panels; (9) the Tier-1 in-process loader + launch scan and build wiring; (10+) the
electronics plugin — the KiCad/FreeRouting ~23-tool contract from the old
`merlin-kicad-mcp` ROADMAP, re-homed as a Tier-1 loadable plugin with bus handlers and
the local-or-hosted FreeRouting backend; (later) the Tier-2 store + plugins menu.

_Status: promoted to `spec.md` and implemented as the workspace-scoped Merlin control plane. The message bus foundation is implemented: `WorkspaceRuntime`, `WorkspaceMessageBus`, shared contracts, bus-backed tool routing, MCP bus transports, workspace settings/events/artifacts, Tier-1 loading, and the electronics bus migration are active. Full KiCad/FreeRouting product completion remains separate follow-on work; the former `merlin/plugins/merlin-kicad-mcp/` scaffold is archived under `archive/legacy-merlin-kicad-mcp/` for historical reference._

_Electronics completion decision: the next product pass is workflow-first.
Completion means requirements-to-PCB and schematic-to-PCB work end to end through
local FreeRouting, deterministic gates, required artifacts, explicit blocked/error
states, and an electronics job/status panel. Hosted FreeRouting is optional until
its API contract is known. Archived MCP code is reference material only._

## Deferred

### Electronics / KiCad Domain

The v2.0 Electronics/KiCad feature set in `spec.md` is scoped to two product intents (raster → PCB; requirements → design) with deterministic gates, BOM/distributor integration, and high-stakes sign-off. The following extensions are explicitly out of scope for v2.0.

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

When implementing v2.0  tasks, check this file before adding scope. If an idea matches an item here, it stays out of v2.0 — note the existing entry in the task doc rather than re-debating scope.

When v2.0 ships and users request capabilities, check this file first. If the request matches an entry, the architectural hook is already identified; the work becomes a new domain extension, not a re-architecture.

When new out-of-scope ideas surface during v2.0 implementation, add them here with the same fields: what, why deferred, reconsider when, architectural hook.
