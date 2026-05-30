# Merlin Full GUI E2E Matrix — 2026-05-26

## Scope

This run validates Merlin as a human-operated macOS app, with local models for
execute/vision and DeepSeek constrained to critic/reason/reference use. The run
must keep evidence artifacts in this directory so they can be tracked in git.

## Constraints

- Run one local provider pair at a time.
- Use DeepSeek only as critic/reason/reference.
- Launch xcalibre-server and validate RAG against a live HTTP server.
- Record screenshots across major functions.
- Report any unreachable, hidden, debug-only, or dead UI surfaces.
- Include non-happy-path cases: unconfigured slots, missing provider, blocked
  tools, failed/invalid input, empty states, cancellation/dismissal, and recovery.

## Automated Coverage

| Area | Command or action | Expected |
|---|---|---|
| Unit + integration suite | `xcodebuild -scheme MerlinTests test` | Pass |
| UI suite | `xcodebuild -scheme MerlinUITests test` | Pass or actionable issue list |
| E2E suite | `xcodebuild -scheme MerlinE2ETests test` | Pass where live prerequisites exist; skip only documented environment gaps |
| Local provider smoke | `docs/local-provider-configs/smoke-test.sh <provider>` | `/models`, completion, streaming, tools, vision where supported |
| RAG live server | xcalibre-server `/health`, `/api/v1/search/chunks`, Merlin `rag_search` | Live service reachable and Merlin reports sources or expected empty/unauthorized diagnostics |

## Manual Human-Style GUI Coverage

| Surface | Cases |
|---|---|
| Workspace launch | empty workspace, open test project, new session, session switching |
| Sidebar | projects, sessions, archive toggle, slot status rows, new project workspace |
| Slot status | all four slots unconfigured, configured local execute/vision, DeepSeek reason, busy, red failure if reachable |
| Chat | type/send, cancel/stop, attachments dismissal, slash commands, at/skills picker, side question overlay |
| Toolbar panels | diff, file browser, terminal, preview, side chat, memories, CAG metrics, electronics jobs |
| Settings | every settings section opens and scrolls; providers refresh/models/key modal; role slots; agents; hooks; scheduler; memories; library; MCP; skills; web search; permissions; connectors; advanced; LoRA; performance/model controls |
| Modal/sheet flows | auth popup deny/allow paths, first-launch skip/continue if reachable, project picker cancel/open-folder, scheduler add/cancel, calibration picker cancel/start when prerequisites exist |
| RAG | xcalibre unavailable, xcalibre available, empty search, populated search if fixture data exists |
| Local model path | local text prompt, local vision prompt with screenshot/image, `/calibrate` against DeepSeek reference if runtime capacity permits |
| Error paths | local provider down, invalid model/400 prevention, missing tooling sheets, blocked electronics/KiCad actions |
| Layout | desktop window sizes, scrolling, no clipped text/buttons, no top provider HUD artifacts |

## Screenshot Set

Minimum screenshot evidence:

1. Workspace start / sidebar slot panel.
2. Settings Providers.
3. Settings Role Slots.
4. CAG metrics panel.
5. Electronics jobs panel.
6. File browser panel.
7. Terminal panel.
8. Memory / library surface.
9. Calibration surface.
10. Chat after local-provider prompt.
11. RAG search/source evidence or expected diagnostic.
12. Any defect state.

## Hidden / Unreachable UI Audit

Audit method:

- Enumerate `AccessibilityID` constants.
- Map each to a reachable surface, gated surface, dynamic-only surface, or stale/unreachable surface.
- Compare UI tests and manual screenshots against the map.
- Search source for debug/test-only launch flags and controls.
- Report any element that should be removed, exposed, or documented.

## Result Legend

- `PASS`: exercised and behavior matched expectation.
- `BLOCKED`: environment prerequisite missing; command/screenshot/log attached.
- `FAIL`: app defect or regression.
- `SKIP`: explicitly out of scope or destructive/risky action not performed.

