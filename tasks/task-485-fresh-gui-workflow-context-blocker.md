# Task 485 - Fresh GUI Workflow Context Blocker

## Objective

Run the fresh full GUI workflow required by finish criterion F4 after F1-F3
were green, using AmpDemo only as an evidence check and without manually
hand-designing the sample project.

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN the fresh GUI electronics workflow is run THE release evidence SHALL record whether Merlin advances from its own gated workflow evidence.

## Setup

Verified the fixed checklist still had F1-F3 complete and F4/F5 open. Recreated
the configured llama.cpp router preset under `/tmp/ampdemo-llamacpp`, started
one router-mode `llama-server` on `127.0.0.1:8081`, and verified:

- `GET /health` returned `{"status":"ok"}`.
- `/v1/models` reported `qwen3-coder-next-local` as `loaded`.
- A direct chat completion to `qwen3-coder-next-local` returned `OK`.

Built and installed the current app:

```bash
rm -rf /tmp/merlin-derived-task485-build && xcodebuild build -project Merlin.xcodeproj -scheme Merlin -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task485-build
rm -rf /Applications/Merlin.app && /usr/bin/ditto /tmp/merlin-derived-task485-build/Build/Products/Debug/Merlin.app /Applications/Merlin.app
codesign --verify --deep --strict /Applications/Merlin.app
```

Result: build succeeded and `/Applications/Merlin.app` passed codesign
verification.

Cleaned generated AmpDemo state while preserving `spec.md`, removed the Merlin
session for that project, cleared `~/.merlin/inject.txt`, and reset telemetry.

## GUI Run

Launched:

```bash
open -na /Applications/Merlin.app --args --open-project /Users/jonzuilkowski/Documents/localProject/AmpDemo --active-domain electronics
```

Injected the full workflow request through `~/.merlin/inject.txt`. The prompt
required Merlin-generated artifacts and truthful stop at `FAB_READY` or the
first actionable blocker. It explicitly forbade hand-designed parts, narrative
advancement, placeholders, missing SPICE evidence, placeholder BOM/vendor data,
and declared-only fabrication paths.

The GUI run generated:

- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/B82020EC-5367-486D-806D-68B526EE9E6C-design_intent.json`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/5FACF97B-8360-4B6B-940A-A0F759F4AAF7-design_intent.json`

The approved DesignIntent decomposed the request into two boards:

- `isolated_secondary`
- `mains_power`

No Circuit IR, component matrix, footprint assignment, schematic, PCB, ERC,
DRC, SPICE, BOM/vendor, fabrication/CAM, `FAB_READY`, or completion artifact was
generated.

## Blocker

The GUI workflow exposed a continuation/context blocker before Circuit IR.

Telemetry sequence:

- `kicad_build_intent_model` completed.
- `kicad_approve_design_intent` completed.
- Continuation evidence was scheduled with two verified steps.
- The next turn read the approved DesignIntent/spec evidence.
- The following continuation exceeded the `qwen3-coder-next-local` context:
  `request (20014 tokens) exceeds the available context size (16384 tokens)`.
- Merlin forced compaction, then repeated the same pattern:
  - `read_file` of the 22,726-byte approved DesignIntent evidence,
  - continuation scheduled with the same verified step count,
  - context errors at `16829`, `17410`, `18169`, and `18906` prompt tokens,
  - forced compaction each time.

This is not an external evidence blocker and does not close F4. It is an
internal GUI/workflow continuation blocker: the full GUI path cannot yet carry
large approved electronics evidence into the next gate without rereading it and
overrunning context.

## Evidence

Screenshots:

- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/01_clean_session_task485.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/02_request_injected_task485.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_design_intent_task485.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/04_stopped_after_context_compaction_task485.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/05_continuation_injected_task485.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/06_context_loop_blocker_task485.png`

Reports:

- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/reports/task485-summary.json`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/reports/task485-telemetry-interesting.jsonl`

Conclusion: F4 remains open. The next task must fix generic GUI continuation
context handling for large electronics artifacts before another full GUI
completion run can be considered meaningful.
