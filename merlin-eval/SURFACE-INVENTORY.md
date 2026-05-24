# Merlin Surface Inventory & Coverage Map

> **SUPERSEDED by `SURFACE-CENSUS.md`.** This file was assembled by judgement and is a
> subset by construction (it undercounted controls, missed the standard macOS menu bar,
> and never enumerated the agent tool surface). `SURFACE-CENSUS.md` is the mechanically-
> derived, authoritative coverage spec. Kept for its prose notes on test mechanisms and
> scenario rationale; for *what must be covered*, use the census.

The complete catalogue of every user-facing and operator-facing surface in Merlin, from a
deep-dive audit of the codebase. **Every row must be covered by the eval suite — an
uncovered row is untested surface.** S1–S6 are the capability scenarios; S7–S17 below are
the surface-coverage scenarios this inventory defines.

## Test mechanisms

| # | Mechanism | Used for |
|---|---|---|
| M1 | Agentic harness (`EvalHarness`, MerlinE2ETests) | Merlin doing real work — capability scenarios |
| M2 | XCUITest UI automation | Menus, windows, panels, settings, dialogs — driven via `AccessibilityID` |
| M3 | Renderer + host-render unit tests | Every view renders without crash; `ConversationHTMLRenderer` HTML asserted per entry kind |
| M4 | Operator/headless scripted tests | config.toml, hooks, mcp.json, inject.txt, automations — written, then driven and asserted |
| M5 | Manual runsheet | Voice dictation, visual judgement, KiCad GUI |

## Evidence & end-to-end value logging

**Everything must be tested, and values logged end to end.** A control or setting is
"tested" only when its value is captured through the *whole* pipeline — not a bare ✓/✗:

> initial value → value set → in-app effect observed → value on disk
> (`config.toml` / `api-keys.json` / Keychain) → value after reload / relaunch

Each `results/SN-<date>.md` records these concrete values per check, so a reviewer sees
exactly what was observed at each stage. A check that logs only "passed" is not done.

---

**Prerequisite for M2 (exhaustive UI automation):** every interactive control needs an
`AccessibilityID`. Phase 306 added ~110 identifiers across the UI — but that pass ran
without this catalogue (it was missing from the checkout) and was driven from source, so
it is substantial yet not verified-exhaustive. Each of S7–S11 cross-checks its catalogue
section against `Merlin/Support/AccessibilityID.swift` and adds any missing identifier as
scenario setup. Known-suspect gaps: the six `WorkspaceView` toolbar toggles; the
`library` / `performance` / `scheduler` settings panes; `ScreenPreviewView` /
`PreviewPane` controls; the tool-requirement sheet.

---

## Defects found during the surface audit

The deep dive is also a bug hunt. Found so far — must be fixed before the proving run:

- **DEAD MENU ITEMS** — `MerlinCommands.swift:87–94`: the View menu's **"Toggle Terminal"
  (⌃`)**, **"Toggle Side Chat" (⌘⇧/)**, and **"Review Memories" (⌘⇧M)** have empty `{}`
  action bodies. Three menu commands + their keyboard shortcuts do nothing — the
  dead-control bug class again. Needs a fix phase.

Running S7–S17 will surface more; each is logged to `BLOCKED.md` or the fix backlog.

---

## A. Windows & scenes — `[S7]` · M2/M5
- Main workspace `WindowGroup` — `MerlinApp.swift`
- Settings scene (⌘,) — `MerlinApp.swift`
- Floating pop-out session window (⌘⇧P) — `FloatingWindowManager`
- Help windows: User Guide (⌘?), Developer Manual — `HelpWindowManager`

## B. Menu bar & keyboard shortcuts — `[S7]` · M2

**B1 — custom commands.** 16 commands (`MerlinCommands.swift`): About; New Project
Workspace (⌘N); Session → Stop (⌘.), Compact Context (⌘⇧K); Window → Pop Out Session
(⌘⇧P); Provider → (dynamic per provider); View → Toggle Terminal (⌃`)†, Toggle Side Chat
(⌘⇧/)†, Review Memories (⌘⇧M)†; Copy Conversation (⌘⇧A); Help → User Guide (⌘?),
Developer Manual. †= was dead, fixed by phase 305 — S7 re-checks as a regression.

**B2 — standard macOS menu bar.** `MerlinCommands` customises only the groups in B1
(`CommandGroup(replacing:)` / `CommandMenu`); **every other menu item is OS/SwiftUI-
provided and is still Merlin's surface — it must work and is tested in S7**: Merlin menu
→ **Settings…** (⌘, — opens the Settings scene), **Hide Merlin** (⌘H), **Hide Others**
(⌥⌘H), **Show All**, **Quit Merlin** (⌘Q — must quit cleanly and persist open sessions +
`config.toml`); File → **Close** (⌘W); Edit → **Undo** (⌘Z), **Redo** (⇧⌘Z), **Cut**
(⌘X), **Copy** (⌘C), **Paste** (⌘V), **Select All** (⌘A) — driven inside a real text
field (chat input + a settings field); Window → **Minimize** (⌘M), **Zoom** — including
on the floating pop-out window. (Services and the AppKit text sub-menus — Spelling,
Substitutions, Speech — are OS-provided and out of scope.)

**Dialog shortcuts:** Return / ⌘Return / Esc (auth popup), Esc/Return (tool-requirement
sheet), Esc (btw overlay). In-chat ⌘⇧M (cycle permission mode).

## C. Slash commands — `[S7]` · M1
`/compact`, `/calibrate`, `/rewind [N]`, `/btw [prefill]` (`SlashCommandHandler.swift`,
`ChatView.swift`), plus every skill surfaced as a `/`-command via the skills picker.

## D. Workspace panels & toolbar toggles — `[S9]` · M2/M3
SessionSidebar, ChatView, ToolLogView (tool log), TerminalPane (terminal), ScreenPreview
View (screen capture), DiffPane (staged changes), FilePane (file viewer), PreviewPane
(web preview), SideChatPane, SlotStatusPanel, PendingAttentionChip/Panel. Six toolbar toggles
(`WorkspaceView.swift`): Staged Changes, File Viewer, Terminal, Preview, Side Chat,
Memories. Each panel: open it, drive its data, assert it reflects state, screenshot.

## E. Settings — 17 panes, ~90 controls — `[S8]` · M2/M4
general, appearance, providers, roleSlots, agents, hooks, scheduler, memories, library,
mcp, skills, search, permissions, connectors, performance, lora, advanced
(`SettingsWindowView.swift` + per-pane views). Every toggle/stepper/picker/field/button
is exercised; each setting is set, then verified to persist to `config.toml` and reload.
Includes `ModelControlView`, `LoRASettingsSection` + `DPOReviewQueueView`,
`RoleSlotSettingsView`, `MemoryBrowserView`.

## F. Chat-interaction surfaces — `[S10]` · M1/M2
Message input field, send/stop button, attachment panel (paperclip), drag-and-drop,
paste (file/image), @-mention picker, skills/slash picker, voice dictation button, BTW
overlay, toolbar actions bar, scroll-lock banner, permission-mode cycle, header controls
(`ChatView.swift`).

## G. Chat rendering kinds — `[S10]` · M3
Every `ChatEntry` kind via `ConversationHTMLRenderer` (pure function — unit-testable):
user / assistant / system / error messages, thinking block (collapsible), tool-call rows
(collapsible), grounding report, RAG sources block, subagent block. Plus the JS-bridge
interactive elements (thinking toggle, tool-row toggle, scroll-lock).

## H. Modal / transient UI — `[S11]` · M2
~20 sheets/popovers/dialogs/overlays: auth popup, first-launch setup, calibration flow
(3 steps), API-key entry, restart-instructions, tool-requirement, project picker, memory
review, add-scheduled-task, dismiss-rationale; project-header
popover, @-mention/skills popovers; reset-settings confirmation; btw overlay, scroll-lock
banner, pending-attention panel.

## I. Agent-triggered dialogs — `[S11]` · M1
Auth popup — the 3 decision paths (Allow Once / Allow Always / Deny). Tool-requirement
sheet (missing-tool install flow). Both raised mid-loop by the running agent.

## J. Session & project lifecycle — `[S11]` · M2
New / switch / pop-out / close / restore / archive / delete session; new / open / close
project; project picker; recent projects; multi-project workspace; context menus on
sessions.

## K. Operator: config.toml — `[S12]` · M4
40+ fields across `[memory] [kag] [lora] [inference] [appearance] [[providers]]
[[hooks]] [slots] [domain] [planner] [critic] [model_capabilities]` plus top-level
(`AppSettings.swift`). FSEvents-watched — external edits apply live. Each section: edit
the file, assert the running app picks it up.

## L. Operator: hooks — `[S12]` · M4
5 events — PreToolUse, PostToolUse, UserPromptSubmit, Stop, SessionStart
(`HookConfig.swift`, `HookEngine.swift`). Each: configure a hook, trigger the event,
assert the hook ran and its decision/rewrite took effect.

## M. Operator: MCP & file injection & automations — `[S12]` · M4
MCP servers (`~/.merlin/mcp.json` + `<project>/.mcp.json`, stdio/sse/http,
`${VAR}` expansion); the `~/.merlin/inject.txt` 2-second-poll message injection;
scheduled automations (5-field cron, `ThreadAutomationEngine`).

## N. Providers, keys, connectors — `[S13]` · M2/M4
12 providers; API keys in `~/.merlin/api-keys.json` (0600); connectors GitHub / Slack /
Linear / Brave-search (Keychain) + xcalibre-server (config). Each: configure, authenticate,
exercise a connector tool.

## O. Skills & agents — `[S14]` · M1/M4
Custom skills (`~/.merlin/skills/`, `<project>/.merlin/skills/`, `SKILL.md` frontmatter,
`$ARGUMENTS`, shell injection, file-watch reload); custom agents (`~/.merlin/agents/`,
TOML); built-in agents (default/explorer/worker); subagent spawn.

## P. Memories — `[S15]` · M1/M2/M4
Generation (idle-timer), secret/path redaction, pending review (approve/reject), library
search + delete, memory backend selection.

## Q. AppIntents / Shortcuts / Siri — `[S16]` · M4
`StartMerlinSessionIntent`, `SendMerlinPromptIntent` (`AppIntentsSupport.swift`).

## R. Notifications — `[S17]` · M2/M5
"Task complete" and "Approval needed" system notifications (`NotificationEngine.swift`).

## S. Environment / CLI — `[S12]` · M4
`XCALIBRE_BASE_URL`, `HOME`, `--show-auth-popup-for-testing`, MCP env expansion.

## T. Schematic extraction / OCR — `[S6]` · M1/M5
`SchematicExtractionPolicy.swift` — importing a schematic *image* and extracting the
circuit. Folded into the electronics scenario S6 as a distinct stage.

---

## Scenario map (S1–S17)

| Scenario | Covers | Status |
|---|---|---|
| S1 Swift GUI | capability — debug a buggy SwiftUI app | spec written |
| S2 Rust | capability — debug a buggy Rust project | spec written |
| S3 Dictation | voice input (F) | spec written |
| S4 RAG | retrieval (xcalibre-server) | spec written |
| S5 LoRA | training pipeline | spec written |
| S6 Electronics | KiCad/route/sim **+ schematic extraction (T)** | spec written — add OCR stage |
| **S7** | Windows, menus, shortcuts, slash commands (A,B,C) | to author |
| **S8** | All 17 settings panes (E) | to author |
| **S9** | Workspace panels & toolbar (D) | to author |
| **S10** | Chat input surfaces & rendering kinds (F,G) | to author |
| **S11** | Modal UI, agent dialogs, session/project lifecycle (H,I,J) | to author |
| **S12** | Operator config — config.toml, hooks, MCP, inject.txt, automations, env (K,L,M,S) | to author |
| **S13** | Providers, keys, connectors (N) | to author |
| **S14** | Skills & agents (O) | to author |
| **S15** | Memories (P) | to author |
| **S16** | AppIntents / Shortcuts (Q) | to author |
| **S17** | Notifications (R) | to author |

S7–S17 + the S6 OCR stage are the exhaustive surface coverage. They are authored next,
in batches.
