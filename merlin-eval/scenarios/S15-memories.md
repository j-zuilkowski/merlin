# S15 — Memories

Proves the memory subsystem: generation, secret redaction, the pending-review workflow,
the library, and backend selection. Covers `SURFACE-INVENTORY.md` section P.

## Mechanism
M1 (`EvalHarness` — run a session, trigger generation) + M2 (the review UI / Library
pane) + M4 (inspect `~/.merlin/memories/`).

## What is exercised

**Generation:** run a session with memory-worthy content (preferences, conventions,
pitfalls), trigger generation (idle timer, or the manual path); assert memory entries
are produced into `~/.merlin/memories/pending/` as `.md` bullet files.

**Redaction (critical):** seed a session whose content contains an API key, a Bearer
token, a GitHub PAT, a Slack token, and absolute file paths. After generation, assert
the pending memory files contain **no** secrets (`[REDACTED]`) and **no** raw paths
(`[PATH]`). A leaked secret here is a hard fail.

**Content rules:** assert generated memories are only `- ` bullet lines, contain no
verbatim file contents, no raw tool output, no tool-call syntax.

**Review workflow:** in the memory-review UI, select a pending memory; **Approve** →
assert it moves to `~/.merlin/memories/` and is written to the backend; **Reject** →
assert the pending file is deleted.

**Library / search:** in the Library settings pane (`MemoryBrowserView`), search for an
approved memory; assert it is found; delete a chunk; assert removal.

**Backend selection:** switch `memory.backend_id` between `local-vector` and `null`;
assert writes go to the selected backend.

## Scoring rubric
- [ ] Generation produces well-formed bullet memories from a session.
- [ ] **Zero secrets and zero raw paths** in any generated memory — redaction holds.
- [ ] Content rules enforced (bullets only, no verbatim content / tool output).
- [ ] Approve moves + persists; Reject deletes.
- [ ] Library search finds approved memories; delete works.
- [ ] Backend selection routes writes correctly.

**Score:** checks passed / N — the redaction check is pass/fail and gating.

## Runsheet
1. Tasks B–D, 301–306 merged; Merlin built. Back up real `~/.merlin/memories/`.
2. Run a seeded session (include planted fake secrets) via `EvalHarness`; trigger
   generation.
3. Inspect every pending memory file for leaks; walk the review + library UI.
4. Score; write `results/S15-<date>.md`. Any leak → immediate finding, top priority.
