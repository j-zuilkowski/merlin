# S8 — Settings (all 17 panes)

Proves every Settings pane renders and every control works — set it, confirm the effect,
confirm it persists to `~/.merlin/config.toml`, confirm it reloads. Covers every
Settings-pane control in `SURFACE-CENSUS.md` §1.2 — the `settings*` `AccessibilityID`
constants plus any un-IDed control (§1.2 lists the library/performance/scheduler-pane
gap). Counts come from the census, not an estimate.

## Mechanism
M2 (XCUITest navigation + control manipulation) + M4 (read back `config.toml` to confirm
persistence). **Prerequisite:** phase 306 (AccessibilityID pass).

## What is exercised

For EACH of the 17 panes — general, appearance, providers, roleSlots, agents, hooks,
scheduler, memories, library, mcp, skills, search, permissions, connectors, performance,
lora, advanced:
- Navigate to the pane; assert it renders without crash.
- Exercise **every** interactive control listed in `SURFACE-INVENTORY.md` §E / the
  surface-audit report: every toggle, stepper, picker, text field, secure field, button,
  slider, list, text editor.
- For each persisted setting: change it, assert the in-app effect, quit/relaunch (or
  re-open Settings), assert it survived; for `config.toml`-backed settings, read the
  file and confirm the new value is written.
- Destructive/confirm controls (Advanced → Reset All Settings) exercised with the
  confirmation dialog.

Pane-specific deep checks:
- **providers** — add/edit an API key via `APIKeyEntrySheet`; enable/disable a provider;
  Refresh Models.
- **roleSlots** — reassign each `AgentSlot`; the unavailable-provider warning shows.
- **hooks / mcp / scheduler** — add and delete an entry; confirm it persists.
- **lora** — the master toggle gates the dependent controls; `DPOReviewQueueView`
  accept/decline.
- **connectors** — save each token; confirm stored (Keychain) and reloaded.

## Accessibility-ID coverage
Phase 306b's `AccessibilityID` pass ran without this catalogue and was driven from
source — substantial (~110 identifiers), but not verified-exhaustive. Before the
pane-walk, cross-check every control in all 17 panes against
`Merlin/Support/AccessibilityID.swift`. **Known-suspect gaps:** the `library`,
`performance`, and `scheduler` *settings panes* have no `settings-<pane>-*` constants
(the existing `scheduler*` IDs are the add-task **dialog**, not the pane). Any control
lacking an identifier gets one added (extend `AccessibilityID.swift` + apply
`.accessibilityIdentifier(...)`) as setup for this scenario.

## Scoring rubric
- [ ] All 17 panes render without crash (host-render smoke + live navigation).
- [ ] Every control is reachable and operable.
- [ ] Every persisted setting round-trips: set → effect → reload → still set; and lands
      in `config.toml` where applicable.
- [ ] Add/delete flows (hooks, MCP, scheduler) persist correctly.
- [ ] Reset-to-defaults works and is gated by its confirmation dialog.

**Score:** controls verified / ~90, plus panes-rendered / 17.

## Runsheet
1. Phases B–D, 301–306 merged; Merlin built; back up any real `config.toml` first.
2. Run the S8 XCUITest pane-walk suite.
3. For settings not auto-checkable, manually set + relaunch + verify; diff `config.toml`.
4. Score; write `results/S8-<date>.md`. Any control that does nothing, fails to persist,
   or crashes a pane is a finding.
