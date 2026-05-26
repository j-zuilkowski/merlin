# Merlin v2.2.4

## Summary

v2.2.4 makes the provider context-overflow class of failures structurally
impossible, adds first-use detection of missing external tools, lets you target a
specific loaded local model per role slot, and introduces `vision.md` as the first
artifact of the Project Discipline pipeline.

## What's new

- **Context-overflow HTTP 400s are fixed at the source.** Three layers, end to end:
  tool output (`run_shell`, `read_file`) is capped before it can enter the model
  context (task 284); the per-request budget is discovered from the active model's
  real context window — queried live for local runners and OpenRouter, learned from
  the first 400 and persisted for commercial providers (task 285); and every LLM
  request on every engine path — planner, critic, subagents, summariser, memory,
  KAG, vision — is sized to fit the provider window before it is sent, not just the
  main turn loop (task 286).
- **Local model picker.** When a local runner has several models loaded, each can be
  assigned to a role slot directly from the chat HUD and the slot picker (task 283).
- **Missing-tool detection.** When a feature needs an external CLI tool that is not
  installed, Merlin detects it on first use and offers a one-click `brew install` for
  the Homebrew-safe tools, or shows the install command/URL for the rest — instead of
  a raw "command not found" (task 287).
- **Vision launchpad.** `vision.md` is now the first artifact of the discipline
  pipeline — `vision → spec → task → code`. `project:init` seeds it,
  `project:adopt` incorporates an existing one, `project:revise` grows and promotes
  ideas from it (task 288).

## Internal changes

- New types: `ToolOutput`, `ContextBudgetResolver` / `ContextBudgetStore`,
  `PreflightGuard`, `ToolRequirement` / `ToolRequirements` / `ToolRequirementChecker`.
- All 14 `provider.complete` send sites now route through `PreflightGuard`.
- Learned context windows persist to `ProviderConfig.budget` in `providers.json` —
  the same field a manually-entered budget uses.

## Migration

None. No configuration changes are required; context-budget discovery and tool
detection are automatic.
