# Electronics Research Design Overview

Date: 2026-05-29

This document distills the circuit-design research direction into a practical
Merlin electronics architecture. It is a design overview, not a claim that the
current implementation can already perform these steps end to end.

## Problem Statement

Merlin must not turn arbitrary requirements into fabricated KiCad-looking files
or mark electronics workflows complete from narrative progress. The electronics
domain should become a KiCad-backed design and verification pipeline:

1. Requirements are converted into a structured, auditable design intent.
2. Design intent is expanded into a machine-checkable circuit representation.
3. KiCad owns project artifacts, library resolution, ERC/DRC, board state, and
   fabrication exports.
4. ngspice and other simulators own simulation evidence when simulation is
   required.
5. Merlin orchestrates tool use, parses diagnostics, proposes repairs, and
   blocks honestly when evidence is missing or failed.

The invariant is generic: no hard-coded design generators and no per-example
guardrails. A guitar amplifier, ESP32 IoT device, power supply, sensor board, or
unknown future request all pass through the same evidence-producing pipeline.

## Research Lessons To Incorporate

### CircuitLM

CircuitLM frames natural-language circuit generation as a staged system rather
than a single prompt. Its useful ideas for Merlin are component identification,
pinout retrieval, expert reasoning, structured circuit JSON, and validation
against a component knowledge base. The key lesson is that the model should
produce machine-checkable intermediate data, not final-looking schematics by
itself.

Merlin adaptation:

- Add a first-class Circuit IR between `DesignIntent` and KiCad files.
- Require canonical pinout and library evidence before a part can enter the IR.
- Validate all generated components, pins, nets, and constraints before KiCad
  project materialization.

### AnalogSeeker

AnalogSeeker shows that domain fine-tuning can improve analog-circuit knowledge,
especially when training data is distilled into granular learning nodes and
reasoned QA. Its useful role in Merlin is specialist critique and repair
reasoning, not unilateral artifact generation.

Merlin adaptation:

- Use analog-specialist models as optional critics for analog sections.
- Train or fine-tune on Merlin repair traces, not only textbook QA.
- Keep simulator and KiCad evidence as the source of truth.

### AnalogCoder

AnalogCoder is useful less as a model choice and more as a pattern: generate
tool-driving code or structured actions, execute the design tools, then iterate
from diagnostics.

Merlin adaptation:

- Treat model outputs as proposed tool actions or patches.
- Prefer generated SPICE scenarios, parameter sweeps, and repair patches over
  prose explanations.
- Score the model by verifier outcomes: valid JSON, valid symbols, ERC/DRC pass,
  SPICE measurements, and BOM resolution.

### AutoCkt

AutoCkt demonstrates simulator/reward-driven analog optimization for constrained
topologies. It is not a general PCB designer, but it is relevant for narrow
subproblems where a topology is known and parameters need optimization.

Merlin adaptation:

- Later add optimization loops for bounded subcircuits.
- Use simulator rewards for values, bias points, and tolerance sweeps.
- Do not apply RL-style optimization to broad product requirements before the
  circuit topology and constraints are machine-represented.

## Target Architecture

```text
requirements / schematic / reference docs
  -> DesignIntent
  -> Circuit IR
  -> library and pinout resolution
  -> KiCad project materialization
  -> ERC / DRC / parity / simulation / BOM / fabrication checks
  -> diagnostic repair loop
  -> evidence-gated completion or honest block
```

### DesignIntent

`DesignIntent` is the requirements contract. It records what the design is meant
to do, known assumptions, constraints, safety profile, board profile, and open
engineering decisions.

It should not contain fake certainty. If a transformer rating, ESP32 module,
thermal path, isolation requirement, or sensor interface is unknown, the intent
records it as unresolved and the workflow blocks or asks a targeted
clarification.

### Circuit IR

Circuit IR is the missing layer. It should represent:

- components with reference designators, role, selected symbol, selected
  footprint, manufacturer part, and source evidence;
- pins with canonical electrical names and KiCad symbol/footprint pin mapping;
- nets with endpoint pins, roles, net classes, constraints, and safety domains;
- simulation scenarios and expected measurement envelopes;
- placement constraints, keepouts, current paths, thermal notes, and RF or
  isolation rules;
- unresolved decisions and blocked reasons.

Circuit IR is the contract that prevents models from drawing plausible nonsense.
KiCad project generation should compile this IR, not raw natural language.

### KiCad As Artifact Authority

KiCad should own concrete electronics artifacts wherever possible:

- project creation and file validation;
- symbol, footprint, field, and library introspection;
- netlist extraction and schematic/PCB parity;
- ERC, DRC, board rules, net classes, and fabrication export;
- DSN/SES interchange for routing through FreeRouting or a future router.

Merlin may maintain parsers/writers for KiCad S-expressions, but only to perform
structured mutations and round-trip verified patches. Merlin should not emit
project files from hidden product-specific string generators.

### Model Roles

Models are planners and repair agents, not judges of correctness.

| Role | Model responsibility | Must not do |
|---|---|---|
| Orchestrate | choose next tool, maintain workflow state | mark completion without evidence |
| Execute | emit structured tool payloads and patches | invent symbols, pinouts, or footprints |
| Reason/Critic | review design intent, constraints, diagnostics | override KiCad/SPICE/BOM failures |
| Vision | visual QA fallback for screenshots | certify electrical or fabrication correctness |

## Generic Gates

These gates apply to every electronics project, independent of example type.

1. Requirements-only input cannot complete or create release artifacts.
2. Every component must resolve to source evidence: KiCad library entry,
   project-local library entry, manufacturer part, or explicit user-approved
   placeholder.
3. Every footprint assignment must prove pin compatibility.
4. Every net must connect valid component pins.
5. KiCad ERC and DRC results must be parsed and stored as evidence.
6. Simulation must run when required by the design class or user requirement.
7. Fabrication outputs must include Gerbers, drills, BOM, placement data where
   applicable, and a fabricator-profile report.
8. Completion state is derived only from verified artifacts and gate results.
9. Failed ERC/DRC/SPICE/BOM/fabrication checks feed a repair loop before final
   block.
10. High-stakes hazards require explicit signoff and cannot be waived by a model.

## Diagnostic Repair Loop

The repair loop should be tool-driven:

```text
run verifier
  -> parse diagnostics
  -> classify failure
  -> propose minimal structured patch
  -> apply patch through KiCad/Circuit IR mutation
  -> rerun verifier
  -> repeat until pass, iteration cap, or hard block
```

Typical failure classes:

- ERC: missing power flag, unconnected pin, pin type conflict, ambiguous net.
- DRC: clearance, unrouted net, courtyard collision, board edge violation.
- SPICE: missing model, convergence failure, measurement outside tolerance.
- BOM: missing MPN, obsolete part, footprint/MPN mismatch, unavailable vendor.
- Fabrication: missing drill, unsupported layer stack, board-house rule failure.

The model proposes repairs, but the tool result decides whether the repair
worked.

## Training Data For Better Models

If Merlin trains or fine-tunes local models for this domain, the dataset should
come from verifier-grounded traces:

- requirements to `DesignIntent`;
- `DesignIntent` to Circuit IR;
- Circuit IR to KiCad tool calls;
- ERC/DRC/SPICE/BOM failures to repair patches;
- accepted and rejected repair attempts;
- final evidence packages with pass/fail labels.

Good training examples are not polished prose. They are structured inputs,
tool-call payloads, diagnostics, patches, and verified outcomes.

## Implementation Sequence

1. Define Circuit IR schemas and validation rules.
2. Add KiCad library and pinout resolver tools.
3. Change `kicad_compile_project` to compile `DesignIntent` plus Circuit IR
   instead of writing skeletal project files.
4. Add machine-readable diagnostic parsers for KiCad ERC/DRC, ngspice, BOM, and
   fabrication export.
5. Add a bounded repair-loop executor with iteration caps and clear blocked
   states.
6. Build small verified fixtures first: simple sensor board, simple power
   supply, simple analog filter.
7. Only after fixtures pass, attempt broader generated designs such as ESP32 IoT
   boards or audio amplifier subsystems.

## Non-Goals

- No hidden hard-coded generators for named demo projects.
- No model-certified completion.
- No raw KiCad string emission as a product-specific shortcut.
- No claim that a design is buildable until the required artifacts and gates
  exist.
- No autonomous mains, hazardous-energy, or thermal-safety approval.

## References

- CircuitLM: <https://arxiv.org/abs/2601.04505>
- AnalogSeeker: <https://arxiv.org/abs/2508.10409>
- AnalogCoder: <https://arxiv.org/abs/2405.14918>
- AutoCkt: <https://arxiv.org/abs/2001.01808>
