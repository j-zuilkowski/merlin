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
