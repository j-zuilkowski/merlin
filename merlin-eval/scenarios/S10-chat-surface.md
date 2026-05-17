# S10 — Chat Input Surfaces & Rendering

Proves every way of getting input into the chat works, and every kind of chat output
renders correctly. Covers `SURFACE-INVENTORY.md` sections F and G — and answers the
question "how is chat output observed and scored".

## Mechanism
- **Input (F):** M2 (XCUITest) + M1 (`EvalHarness`).
- **Rendering (G):** M3 — `ConversationHTMLRenderer` is a pure `[ChatEntry] -> String`
  function, so its output is asserted directly in unit tests; visual correctness of the
  rendered WKWebView via M5 screenshot judge.

## How chat output is observed and scored
Three layers:
1. **Content** — `EvalHarness.EvalRun` captures the `AgentEvent` stream (assistant text,
   tool calls, system notes, errors). Scoring of "did Merlin answer correctly / call the
   right tools" runs off `EvalRun`.
2. **Rendering** — `ConversationHTMLRenderer.messageHTML(for:)` is called directly with a
   crafted `ChatEntry` of each kind; the returned HTML is asserted (correct structure,
   classes, escaping). No app run needed.
3. **Visual** — a screenshot of the live WKWebView, judged by a human or Merlin's vision
   model, for layout/colour/legibility.

## What is exercised

**Input surfaces (F):** type a message and send; send via Return; Stop mid-stream;
attach a file (paperclip → NSOpenPanel); drag-and-drop a file; paste a file and an image;
`@`-mention picker (type `@`, pick a file); skills/`/` picker (type `/`, pick a skill);
voice dictation button (covered by S3 — confirm the button is present and toggles); the
BTW overlay (`/btw`); the toolbar actions bar (run an offered action); the scroll-lock
banner (scroll up → banner → Resume); the permission-mode cycle button.

**Rendering kinds (G):** assert `ConversationHTMLRenderer` output for a `ChatEntry` of
each kind — user, assistant, system, error; thinking block (collapsible); tool-call rows
(running / done / error states); grounding report (each status); RAG sources block
(phase 294); subagent block (phase 295). Assert the JS-bridge interactive elements
(thinking toggle, tool-row toggle, scroll-lock signal).

## Accessibility-ID coverage
Phase 306b's `AccessibilityID` pass ran without this catalogue and was driven from
source — substantial (~110 identifiers), but not verified-exhaustive. The chat input
surfaces appear well-covered (`chat-input`, send/stop, attachment, voice, @-mention,
skills picker, toolbar-action prefix, resume-scroll, permission-mode). Before the M2
portion, confirm each input surface this scenario drives resolves to a real
`AccessibilityID` constant; add any missing one (extend `AccessibilityID.swift` + apply
`.accessibilityIdentifier(...)`) as setup.

## Scoring rubric
- [ ] Every input surface delivers text/files into the draft or sends correctly.
- [ ] Empty-draft send is disabled.
- [ ] `ConversationHTMLRenderer` produces correct HTML for all 8 entry kinds + thinking
      + tool rows + grounding + RAG sources + subagent block.
- [ ] HTML escaping is correct (no injection via message content).
- [ ] Interactive chat elements (toggles, scroll-lock) work.
- [ ] Visual: the rendered chat is legible and correctly laid out (screenshot judge).

**Score:** input surfaces / N + rendering kinds / M, plus the visual pass.

## Runsheet
1. Phases B–D, 301–306 merged; Merlin built.
2. Run the S10 renderer unit tests (M3) and the XCUITest input suite (M2).
3. Manually exercise drag/drop, paste, @-mention, skills picker, BTW, scroll-lock.
4. Screenshot the chat with every entry kind present; judge visually.
5. Score; write `results/S10-<date>.md`.
