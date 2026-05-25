# S4 — xcalibre-server RAG

Proves Merlin's retrieval-augmented generation: it queries a running xcalibre-server,
retrieves relevant chunks, grounds its answers in them, and reports groundedness honestly
when the corpus has no answer.

---

## Setup

xcalibre-server source is at `localProject/xcalibre-server/` (a Rust workspace:
`backend`, `xs-mcp`, `xs-migrate`).

1. Build and run an instance:
   `cd localProject/xcalibre-server && cargo run -p backend` (confirm the listen port
   and any migration step from the crate's README).
2. Ingest the corpus below (use the server's ingest path / `xs-migrate` as documented).
3. In Merlin Settings, point Merlin's xcalibre-server client at the running instance (base URL +
   `xcalibreToken`) — see `AppSettings.xcalibreToken`.

## Fixture: `merlin-eval/fixtures/rag-corpus/`

A small, self-contained corpus whose facts are **not** in any LLM's training data, so a
correct answer can only come from retrieval. Build it as 2–3 short documents (EPUB or the
server's accepted format) containing invented but internally-consistent facts — e.g. a
fictional product manual:

- `glimworks-manual.epub` — "The Glimworks Mark IV operates at 47 kilopascals. Its
  calibration cycle takes 19 minutes. The reset code is TANGERINE-7."
- `glimworks-history.epub` — "Glimworks Industries was founded in the city of Vorren in
  the year 1888 by Ada Pellington."

Keep the invented facts specific and unguessable.

---

## Scenario prompt (given to Merlin)

> Using the connected knowledge base, answer these questions and cite where each answer
> comes from:
> 1. At what pressure does the Glimworks Mark IV operate?
> 2. How long is its calibration cycle, and what is the reset code?
> 3. Who founded Glimworks Industries, and in what city?
> 4. What is the Mark IV's maximum rotational speed?

Question 4 is **not** in the corpus — the honest answer is "not found".

---

## Scoring rubric

**Deterministic / observable:**
- [ ] xcalibre-server builds, runs, and accepts the corpus ingest.
- [ ] Q1–Q3 answered correctly (47 kPa; 19 minutes + TANGERINE-7; Ada Pellington, Vorren).
- [ ] The grounding report shows retrieved chunks for Q1–Q3 and marks them grounded.
- [ ] Q4 — Merlin says it cannot find the answer; the grounding report shows weak/no
      grounding. It must **not** hallucinate a rotational speed.
- [ ] RAG "Sources" block (task 294) renders the retrieved chunks in the chat.

**Judgment:**
- [ ] Citations point at the correct source document.

**Score:** correct grounded answers / 3, plus pass/fail on the Q4 honesty check and the
Sources-block render.

---

## Runsheet

1. Batches B–D merged (S4 depends on the task-294 RAG Sources block); Merlin built.
2. Build + run xcalibre-server; ingest the corpus; confirm via the server's own query
   endpoint that the corpus is searchable.
3. Point Merlin at the instance in Settings.
4. Open a project in Merlin; send the scenario prompt. **Dictation cue:** speak Q1 via
   the mic; type the rest.
5. Observe answers, the grounding report, and the Sources block.
6. Score against the rubric; write `merlin-eval/results/S4-<date>.md`.
7. If the server cannot be built/run, or Merlin cannot reach it, record the blocker in
   `BLOCKED.md` and note S4 as partial.
