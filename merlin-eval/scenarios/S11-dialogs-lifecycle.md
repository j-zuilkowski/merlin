# S11 — Modal UI, Agent Dialogs, Session & Project Lifecycle

Proves every sheet/popover/dialog/overlay works, the agent-raised dialogs behave, and the
full session/project lifecycle is sound. Covers `SURFACE-INVENTORY.md` sections H, I, J.

## Mechanism
M2 (XCUITest) for navigation/dismissal; M1 (`EvalHarness`) to raise the agent dialogs.
**Prerequisite:** phase 306 (AccessibilityID pass).

## What is exercised

**Modal / transient UI (H):** open, interact with, and dismiss each — auth popup;
first-launch setup; calibration flow (all 3 steps: provider pick → progress → report);
API-key entry sheet; restart-instructions sheet; tool-requirement sheet; project picker;
memory review sheet; add-scheduled-task sheet; dismiss-rationale sheet; Provider-HUD
popover; project-header popover; @-mention & skills popovers; reset-settings
confirmation; BTW overlay; scroll-lock banner; pending-attention panel. Each: assert it
appears on its trigger, its controls work, and every dismissal path (button, keyboard
shortcut, tap-outside) closes it.

**Agent-triggered dialogs (I):** drive a scenario through `EvalHarness` that forces a
tool-permission request — exercise all three paths: **Allow Once**, **Allow Always**
(assert the pattern is persisted), **Deny** (assert the tool is blocked). Force a
missing-tool condition → the tool-requirement sheet appears with install info.

**Session & project lifecycle (J):** new session; switch sessions; pop out a session to
a floating window; close a session; restore a prior session; archive and recall;
delete; new project; open a project via the picker; recent-projects list; close a
project; multiple projects open at once. Assert state is correct after each transition
(no orphaned windows, no lost history, the active session is right).

## Accessibility-ID coverage
Phase 306b's `AccessibilityID` pass ran without this catalogue and was driven from
source — substantial (~110 identifiers), but not verified-exhaustive. Before the M2
portion, cross-check every modal/dialog control against
`Merlin/Support/AccessibilityID.swift`. **Known-suspect gap:** the tool-requirement
sheet (section I) has no `tool-requirement-*` constants. Add identifiers (extend
`AccessibilityID.swift` + apply `.accessibilityIdentifier(...)`) for it and for any
other uncovered modal control as setup for this scenario.

## Scoring rubric
- [ ] Every modal surface appears on trigger, operates, and closes via every path.
- [ ] Auth popup — all three decision paths behave; "Allow Always" persists the pattern.
- [ ] Tool-requirement sheet appears for a genuinely missing tool.
- [ ] Every session lifecycle transition leaves correct state; pop-out window is a real
      independent window; restore reloads history.
- [ ] Project lifecycle: open/close/switch/multi-project all sound.
- [ ] No crash on any transition (regression net for the env-object class of bug).

**Score:** modal surfaces / N + lifecycle transitions / M + auth paths / 3.

## Runsheet
1. Phases B–D, 301–306 merged; Merlin built.
2. Run the S11 XCUITest suite.
3. Use `EvalHarness` (or a manual run) to raise the auth popup and tool-requirement
   sheet; exercise each path.
4. Walk the full session/project lifecycle manually.
5. Score; write `results/S11-<date>.md`.
