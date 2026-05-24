## Merlin Status Snapshot — 2026-05-23

### Scope completed

This repair wave covered the architecture-conformance investigation follow-up and the highest-severity runtime defects found during that pass.

### Repaired

- Subagents now execute real tool calls instead of placeholder completions.
- Worker subagents now perform real worktree-backed writes.
- `/calibrate` now presents correctly in the GUI, uses shared readiness gating, and surfaces failures instead of silently collapsing.
- Scheduler behavior is standardized on `SchedulerEngine`.
- Scheduled runs now:
  - honor `permissionMode`
  - wait for MCP readiness
  - mark completion only after successful execution
  - retry the same slot after failure
- Settings no longer use sidecar `AppState` / `ProviderRegistry` for runtime-sensitive panes.
- `SessionStart` hooks are now visible, configurable, and executed.
- Electronics is now a real built-in domain with:
  - session-backed selection
  - `.kicad_pro` project auto-activation
  - prompt-driven activation confirmation
- External MCP domain manifests now register through `MCPBridge`.
- MCP tool exposure is now domain-scoped.
- The KiCad MCP plugin now exposes `merlin://domain/manifest` and validates against Merlin’s domain registration flow.
- KAG graph context now reaches the live prompt path.
- Memory generation now routes through the execute path instead of being pinned to the reason slot.
- Ollama reload semantics now switch Merlin to the active reloaded variant.
- Ollama context auto-resize now propagates the effective runtime model ID into live requests.
- Jan and Ollama local model manager behavior is closer to parity for runtime context handling.
- Provider readiness is now centralized in `ProviderRegistry`.
- Jan and LocalAI now correctly advertise vision support.

### Verified after repair

- Code review follow-up findings closed:
  - Ollama context resize/runtime-tag propagation
  - scheduler completion bookkeeping
- Focused follow-up test runs passed.
- Integrated repaired-subsystem sweep passed:
  - `239` tests
  - `0` failures

### Still partial

- Provider routing and fallback behavior are working, but the behavior is still more nuanced than the simplified architecture description.
- Local model manager parity is improved but not complete:
  - restart-only providers still cannot self-resize at runtime
  - `loadedModels()` semantics still differ somewhat across backends
- Calibration runtime remains intentionally sequential across prompts rather than fully parallel across the prompt set.
- Nested subagent spawning remains unsupported.
- Some settings are intentionally save-only for future sessions rather than live-mutating the active session.

### Intentionally unsupported or externally blocked

- `vLLM-Metal` vision remains upstream-blocked.
- `Ollama` vision remains not recommended due to runner instability with the tested imported Qwen3-VL path.
- `mistral.rs` remains unusable for the tested Qwen3 MoE Metal path pending upstream work.

### Recommended next backlog

1. Provider/runtime cleanup:
   - tighten remaining `loadedModels()` semantic differences
   - decide whether additional runtime parity work is worth it for restart-only backends
2. Final product-level live validation pass:
   - scheduler in-app run
   - subagent write/accept cycle
   - Electronics workflow with external MCP server attached
3. Residual documentation cleanup only where claims still over-simplify repaired runtime behavior

### Live validation update — 2026-05-23 afternoon

The final product-level live validation pass was resumed under a cleaned machine
state and found several concrete runtime failures:

- Provider/runtime cleanup continued and passed:
  - `loadedModels()` is now classified as `runtimeLoaded`,
    `serverExposed`, or `catalogFallback`
  - focused parity sweep passed: `60` tests, `0` failures
- Worker subagent live validation failed:
  - forcing `spawn_agent` against a clean LM Studio session produced a visible
    `spawn_agent` error in the UI
  - no worker diff appeared
  - no `LIVE_SUBAGENT_CHECK.txt` file was created under
    `/Users/jonzuilkowski/Documents/localProject/xcalibre-server`
- Scheduler live validation failed:
  - fresh task `live scheduler check 2` was created for `13:49`
  - at `2026-05-23 13:49:18 EDT` and `2026-05-23 13:50:39 EDT`,
    `~/Library/Application Support/Merlin/schedules.json` still contained no
    `lastRunAt`
  - no visible scheduled session or execution artifact appeared
- Electronics auto-activation failed in live behavior:
  - opening
    `/Users/jonzuilkowski/Documents/localProject/merlin/kicad-projects/astable-led-blinker`
    created workspace session state under
    `~/Library/Application Support/Merlin/sessions/Documents_localProject_merlin_kicad-projects_astable-led-blinker/`
  - that session persisted with `activeDomainIDs: ["software"]`
  - automatic Electronics activation did not occur
- Prompt-triggered Electronics switching also failed in live behavior:
  - a prompt explicitly mentioning KiCad, PCB, schematic, BOM, and Gerber did
    not surface any Electronics-switch confirmation
  - the model simply began a normal plan
- The first-launch provider sheet resurfaced during live tests until it was
  explicitly switched to `LM Studio (local)`

### Follow-up update — 2026-05-24

- Live `spawn_agent` request failure is resolved:
  - OpenAI-incompatible tool names are encoded at the provider boundary and decoded before Merlin executes tools.
  - `spawn_agent` now returns a matching tool result to the parent provider turn.
  - A DeepSeek live run completed without the prior HTTP 400.
- Scheduler firing/completion recording is resolved:
  - scheduled runs now fire through `SchedulerEngine`
  - completion is recorded after successful execution
  - live validation observed `lastRunAt` being written
- Subagent presentation follow-up is now addressed in this branch:
  - older assistant bubbles refresh when delayed tool results arrive, so `spawn_agent` moves from `running...` to `done`
  - worker sidebar entries auto-select, exposing the worker diff path as soon as the worker is available

### Current immediate backlog

1. Fix `.kicad_pro` Electronics auto-activation in the live session path
2. Fix prompt-driven Electronics switch confirmation in the live chat path
3. Fix repeated first-launch provider sheet resurfacing
4. Run one final live worker write/accept pass after the UI refresh and worker-diff selection fixes land

### Current machine state at handoff

- `LM Studio` was left running on `127.0.0.1:1234`
- `Merlin` was left open
- no shell command, test run, or calibration harness was still running
- the additional provider/runtime parity code changes are still uncommitted in
  the worktree
