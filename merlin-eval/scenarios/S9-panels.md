# S9 — Workspace Panels

Proves every workspace panel opens, displays real data, and behaves. Covers
`SURFACE-INVENTORY.md` section D.

## Mechanism
M3 (host-render smoke test per panel) + M2 (toolbar toggle + XCUITest) + drive the
underlying state and assert the panel reflects it. Visual correctness via M5 screenshot
judge.

## What is exercised

For each panel: toggle it on (toolbar button or menu), assert it renders, drive its data
source, assert the panel shows the data, toggle it off.

- **SessionSidebar** — projects + live/prior/archived sessions; context menus
  (close/resume/archive/delete); project-header popover (new session / close project).
- **ToolLogView** (tool log) — run a tool; assert lines appear, colour-coded by source;
  Clear button empties it; text is selectable.
- **TerminalPane** — enter a shell command, Run; assert streamed stdout/stderr rows and
  the exit-status badge; Stop cancels.
- **ScreenPreviewView** — after a screen capture, assert the image + timestamp + source
  bundle ID; expand/collapse.
- **DiffPane** — with staged changes present, assert the file list, +/- stats, hunk
  expansion, per-line comment input, Accept/Reject, Accept-All-Commit.
- **FilePane** — open a text file and an image file; assert correct rendering; close.
- **PreviewPane** — open an HTML file; assert the WKWebView renders it.
- **SideChatPane** — open it; assert it is an independent chat session (regression for
  the SideChatPane crash fixed earlier this effort).
- **ProviderHUD** — assert provider name, context-usage bar colour thresholds, the
  popover provider list + status dots.
- **PendingAttentionChip / Panel** — with findings queued, assert the chip shows the
  true count (regression for phase 304) and the panel lists + dismisses findings.

## Accessibility-ID coverage
Phase 306b's `AccessibilityID` pass ran without this catalogue and was driven from
source — substantial (~110 identifiers), but not verified-exhaustive. Before the M2
portion, cross-check every panel control against `Merlin/Support/AccessibilityID.swift`.
**Known-suspect gaps:** the six `WorkspaceView` toolbar toggles (Staged Changes, File
Viewer, Terminal, Preview, Side Chat, Memories) and the `ScreenPreviewView` /
`PreviewPane` controls have no constants. Add identifiers (extend `AccessibilityID.swift`
+ apply `.accessibilityIdentifier(...)`) for any uncovered control as setup for this
scenario.

## Scoring rubric
- [ ] Every panel renders without crash (host-render smoke for each).
- [ ] Every toolbar toggle and the View-menu toggles show/hide the right panel.
- [ ] Each panel reflects its real data when that data is driven.
- [ ] SideChatPane opens without crashing; the attention chip shows the true count.
- [ ] Visual layout of each panel is correct (screenshot judge).

**Score:** panels verified / 10, plus the two regressions.

## Runsheet
1. Phases B–D, 301–306 merged; Merlin built.
2. Run the S9 host-render + XCUITest suite.
3. Drive each panel's data (run a tool, run a shell command, stage a change, capture a
   screen, queue findings) and eyeball each panel.
4. Score; write `results/S9-<date>.md`.
