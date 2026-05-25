# S7 — Windows, Menus, Shortcuts, Slash Commands

Proves every window opens, every menu command does what it says, every keyboard shortcut
fires, and every slash command works. Covers `SURFACE-INVENTORY.md` sections A, B, C.

## Mechanism
M2 (XCUITest) for windows/menus/shortcuts; M1 (`EvalHarness`) for slash commands.
**Prerequisite:** phase 306 (AccessibilityID pass) and phase 305 (the dead View-menu
fix) must be merged.

## What is exercised

**Windows (A):** open and assert each appears, is sized sanely, and closes cleanly —
main workspace; Settings (⌘,); pop-out session window (⌘⇧P); User Guide (⌘?);
Developer Manual.

**Custom menu commands (B1):** invoke each of the 16 `MerlinCommands` and assert its
observable effect — About; New Project Workspace (⌘N → picker appears); Stop (⌘. →
engine stops); Compact Context (⌘⇧K); Pop Out Session (⌘⇧P); each Provider-menu entry
(→ active provider changes); **Toggle Terminal (⌃`), Toggle Side Chat (⌘⇧/), Review
Memories (⌘⇧M)** — regression for phase 305, the formerly-dead commands; Copy
Conversation (⌘⇧A → clipboard holds the transcript); User Guide / Developer Manual.

**Standard macOS menu bar (B2):** `MerlinCommands` customises only the B1 groups —
every other menu item is OS/SwiftUI-provided and must still work. Exercise each and log
its effect: Merlin → **Settings…** (⌘, opens the Settings scene — the entry point to
S8), **Hide Merlin** (⌘H), **Hide Others** (⌥⌘H), **Show All**, **Quit Merlin** (⌘Q —
quits cleanly; on relaunch, open sessions and `config.toml` are intact — a data-loss
check); File → **Close** (⌘W); Edit → **Undo / Redo / Cut / Copy / Paste / Select All**
— driven inside the chat input field and a Settings text field, asserting each operates
on the text; Window → **Minimize** (⌘M), **Zoom** — on both the main window and the
floating pop-out window.

**Keyboard shortcuts (B):** press each shortcut directly (no menu) — B1 and B2 — and
assert it fires the same effect. Includes the dialog shortcuts (Return / ⌘Return / Esc).

**Slash commands (C):** in chat, run `/compact`, `/calibrate`, `/rewind`, `/rewind 2`,
`/btw test` — assert each is consumed and produces its effect (compaction note;
calibration sheet; checkpoint restore; btw overlay).

## Accessibility-ID coverage
Phase 306b's `AccessibilityID` pass ran without this catalogue (it was missing from the
checkout) and was driven from source — substantial (~110 identifiers), but not
verified-exhaustive. Before the M2 portion, confirm coverage for sections A–B: SwiftUI
menu commands are addressed by menu-item title (a `Commands`-API constraint — by design,
no identifier needed); windows are matched by title. Add an `AccessibilityID` constant
(extend `Merlin/Support/AccessibilityID.swift` + apply `.accessibilityIdentifier(...)`)
for any window-level control XCUITest cannot reach by title, as setup for this scenario.

## Scoring rubric
- [ ] Every window opens, renders, and closes without crash.
- [ ] Every one of the 16 custom (B1) menu commands produces its documented effect.
- [ ] Every standard macOS menu item (B2) works — `Settings…` opens Settings; `Quit`
      quits cleanly with open sessions + `config.toml` intact on relaunch; the Edit-menu
      items operate in text fields; Hide / Show All / Minimize / Zoom / Close behave.
- [ ] Every keyboard shortcut fires its command.
- [ ] The three task-305 commands work (terminal toggles, side chat toggles, memory
      window opens) — no dead menu items remain.
- [ ] Every slash command is consumed and behaves.

Every check logs the observed effect/value, not just a tick (see SURFACE-INVENTORY →
"Evidence & end-to-end value logging").

**Score:** items passed / total. Any dead command is a finding.

## Runsheet
1. Phases B–D, 301–306 merged; Merlin built.
2. Run the S7 XCUITest suite (windows/menus/shortcuts).
3. Manually press each keyboard shortcut and each slash command; record effects.
4. Score; write `results/S7-<date>.md`. Dead/incorrect commands → findings backlog.
