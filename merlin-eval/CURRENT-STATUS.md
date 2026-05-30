# Merlin Current Status

Updated: 2026-05-27

This file is the control point for getting Merlin back on track. Older harness
logs, rerun folders, and handoff notes are evidence only; they are not the
current plan of record.

## Snapshot

- Stabilization branch: `codex/stabilize-merlin-e2e`
- Base commit when stabilization started: `ff1c99e`
- Safety snapshot: `git stash` entry named `codex pre-clean stabilization snapshot 2026-05-27`
- Cleanup already performed: untracked May 27 full-battery rerun directories,
  untracked harness result files, and untracked preprocessed electronics fixture
  output were removed from the live working tree after the stash snapshot.

## Current Working Rule

Do not run the full battery again until the focused blockers below are fixed and
verified individually. The retired May 26-27 shell harness is archived under
`docs/archive/2026-05-27-retired-full-battery-harness/` and must not be used as
active verification.

## Reliable Local Providers

Treat only these local providers as reliable for Merlin's full expected local
surface:

| Provider | Status | Reason |
|---|---|---|
| LM Studio | Reliable | Text, streaming, tool calls, and vision passed. |
| Jan.ai | Reliable | Text, streaming, tool calls, and vision passed through the Jan CLI / llama-server path. |
| llama.cpp router | Reliable | One router-mode `llama-server` served explicit text and vision model IDs successfully. |

## Non-Working Local Providers

| Provider | Status | Reason |
|---|---|---|
| LocalAI | Non-working for Merlin full surface | Text, streaming, and vision responded, but tool-call requests returned plain content without OpenAI `tool_calls`. |
| Ollama | Non-working for Merlin full surface | Text works, but the tested Qwen3-VL path crashes the runner on real image requests. Check upstream issue status before retesting. |
| vLLM-Metal | Non-working / avoid | Text and auto tool calls can work, but forced tool choice is unreliable and vision is not implemented on Metal. Avoid for the foreseeable future. |
| Mistral.rs | Non-working for tested model | The tested Qwen3 MoE GGUF path fails on first inference on Apple Metal. Check upstream issue status before retesting. |

## Current Blockers

Fix these in order, with focused tests after each fix:

1. GUI test bootstrap / target shape
   - The full GUI evidence is not trustworthy until the UI test target and
     bootstrap mode are clean and repeatable.
   - Surface/visual tests that use `XCUIApplication()` must run from a real UI
     testing target, not a unit-test bundle.

2. Missing `.merlin/` file handling
   - S1 and S6-OCR evidence points to `NSError 260` for missing
     `.merlin/project.toml` or `.merlin/override-log.jsonl`.
   - Missing project-local discipline files should mean "not configured", not a
     scenario-level failure.

3. AgenticLoop key gate
   - The live agent loop can incorrectly skip with "No API key" despite keys
     existing in Merlin's actual credential stores.
   - The gate must read the same key source Merlin uses at runtime.

4. xcalibre RAG wiring
   - S4 evidence showed server readiness trouble and Merlin using the default
     `localhost:8083` path when the test configured a different base URL.
   - Verify the real readiness endpoint and the environment/config path that
     reaches the xcalibre client.

5. Electronics/KiCad agent invocation
   - Direct KiCad and FreeRouting checks passed, but the live electronics
     scenario did not make the agent call the active `plugins/electronics`
     KiCad routes.
   - The next fix is agent/tool registration and invocation, not KiCad itself.

6. S2 real verdict
   - Earlier S2 failures were contaminated by harness issues such as missing
     `cargo` in the test process environment.
   - Re-run S2 only after the test environment is known clean.

## Known Good / Mostly Good

- Deterministic unit suite was previously recorded green in the proving notes.
- LM Studio, Jan.ai, and llama.cpp router are the reliable local provider set.
- Direct FreeRouting after approval produced DSN/SES output and KiCad DRC passed
  in the focused check.
- The old full-battery shell harness is no longer part of the active process.

## Working Tree Policy

- Keep source and task-doc changes until each is reviewed and either committed
  or deliberately discarded.
- Keep the intentional screenshot deletions; GitHub feature screenshots should
  be retaken only after the full gate is green.
- Do not add new broad harness code unless a focused blocker proves direct GUI
  or targeted command validation is insufficient.
