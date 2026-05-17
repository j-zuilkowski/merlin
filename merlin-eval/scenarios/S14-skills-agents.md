# S14 — Skills & Agents

Proves custom skills and custom subagents load, render, and run. Covers
`SURFACE-INVENTORY.md` section O.

## Mechanism
M4 (drop skill/agent definition files) + M1 (`EvalHarness` to invoke them) + M2 (the
Skills settings pane).

## What is exercised

**Skills:**
- Drop a `SKILL.md` in `~/.merlin/skills/<name>/` (personal) and one in
  `<project>/.merlin/skills/<name>/` (project-scoped); assert both are discovered.
- File-watch reload: edit a `SKILL.md` while Merlin runs; assert the change is picked up
  without restart.
- Frontmatter: a skill exercising each field — `argument-hint`, `model`,
  `user-invocable`, `disable-model-invocation`, `allowed-tools`, `context`, `role`,
  `complexity`, `critic` — assert each is honoured.
- Rendering: `$ARGUMENTS` substitution; the ` ```! ``` ` block-shell and `` !`cmd` ``
  inline-shell injection produce the command output.
- Invocation: invoke a skill as a `/`-command via the skills picker; confirm a
  `user-invocable: false` skill is not offered; confirm a `disable-model-invocation`
  skill is not auto-called by the agent.
- Skills settings pane: disable a skill via the toggle; assert it disappears from the
  picker and `disabledSkillNames` is persisted.

**Agents:**
- Drop a TOML agent definition in `~/.merlin/agents/`; assert `AgentRegistry` loads it.
- The three built-in agents — `default`, `explorer`, `worker` — each spawnable; assert
  `explorer` is read-only (restricted toolset), `worker` gets its own git worktree.
- Subagent spawn: drive a task that spawns a subagent; assert the subagent runs and its
  events surface (overlaps S10's subagent-block rendering).

## Scoring rubric
- [ ] Personal and project skills are both discovered; live edits reload.
- [ ] Every frontmatter field is honoured.
- [ ] `$ARGUMENTS` and shell injection render correctly.
- [ ] Skill invocation rules (user-invocable, disable-model-invocation) are enforced.
- [ ] Disabling a skill persists and removes it from the picker.
- [ ] Custom TOML agents load; the three built-in agents behave per their role.
- [ ] A spawned subagent runs and reports back.

**Score:** skill checks / N + agent checks / M.

## Runsheet
1. Phases B–D, 301–306 merged; Merlin built.
2. Place the test skill and agent definition files (keep a few crafted fixtures in
   `merlin-eval/fixtures/skills-agents/`).
3. Invoke skills via the picker; drive a subagent-spawning task via `EvalHarness`.
4. Score; write `results/S14-<date>.md`.
