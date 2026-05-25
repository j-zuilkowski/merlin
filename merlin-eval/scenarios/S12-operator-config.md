# S12 — Operator Config

Proves every headless/operator configuration surface works — the ways someone drives or
configures Merlin without the chat UI. Covers `SURFACE-INVENTORY.md` sections K, L, M, S.

## Mechanism
M4 — write a config file / drop a trigger file / define an automation, then launch or
drive Merlin and assert the behaviour.

## What is exercised

**config.toml (K):** for each of the 12 sections (`[memory] [kag] [lora] [inference]
[[providers]] [[hooks]] [slots] [domain] [planner] [critic] [model_capabilities]` +
top-level), write a known value, launch Merlin, assert it is applied. Then — since
`config.toml` is FSEvents-watched — edit it while Merlin is running and assert the change
applies live without restart.

**Hooks (L):** for each of the 5 events (PreToolUse, PostToolUse, UserPromptSubmit, Stop,
SessionStart), configure a hook script and assert: it runs at the right time; its
decision/rewrite takes effect (PreToolUse `deny` blocks the tool; PostToolUse rewrite
changes the result; UserPromptSubmit rewrite changes the prompt; Stop `proceed`
continues the loop; SessionStart note is surfaced).

**MCP (M):** put a server in `~/.merlin/mcp.json` and one in `<project>/.mcp.json`;
assert both launch, the project one overrides the global, `${VAR}` env expansion works,
and the server's tools register into the tool registry.

**inject.txt (M):** `echo "a prompt" > ~/.merlin/inject.txt`; assert within ~2 s Merlin
submits it as a real user message with a full response.

**Automations (M):** define a cron automation; assert it fires the prompt into the
session at the scheduled time (use a near-future cron to keep the test short).

**Environment (S):** set `XCALIBRE_BASE_URL`; assert the xcalibre client uses it. Launch
with `--show-auth-popup-for-testing`; assert the auth popup is forced.

## Scoring rubric
- [ ] Every config.toml section is honoured at launch; a live edit applies without restart.
- [ ] All 5 hook events run and their decisions/rewrites take effect.
- [ ] MCP servers from both locations launch; project overrides global; env expansion works.
- [ ] `inject.txt` is consumed within the poll interval and submitted.
- [ ] A cron automation fires on schedule.
- [ ] `XCALIBRE_BASE_URL` and the test CLI flag are honoured.

**Score:** config sections / 12 + hook events / 5 + the MCP / inject / automation / env checks.

## Runsheet
1. Tasks B–D, 301–306 merged; Merlin built. Back up the real `~/.merlin/` first.
2. For each surface: write the config/file/automation, launch or drive Merlin, observe.
3. For the live-reload check, edit `config.toml` with Merlin running.
4. Score; write `results/S12-<date>.md`. A setting silently ignored is a finding.
