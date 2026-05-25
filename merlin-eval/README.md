# Merlin End-to-End Proving Suite

Acceptance scenarios that exercise every major Merlin capability end-to-end and produce
concrete evidence the app actually works. Built because a prior audit found Merlin had
shipped multiple silently-dead features.

## What this is — and is not

Merlin is LLM-driven and therefore **non-deterministic**. A scenario "Merlin fixes the
planted bug" may pass 8/10 runs. This is an **acceptance/eval suite**, not a pass/fail
unit-test suite. Each run produces **scored evidence**, not a boolean proof.

**Everything is tested, and values are logged end to end.** A control, setting, command,
or capability is "tested" only when its value is captured at every stage of its pipeline
— initial value → value set → in-app effect observed → value on disk → value after
reload/relaunch. Each `results/SN-<date>.md` records the concrete observed values per
check, not a bare ✓/✗. See `SURFACE-INVENTORY.md` → "Evidence & end-to-end value
logging".

## Layout

```
merlin-eval/
  README.md             — this file
  SURFACE-INVENTORY.md  — the complete catalogue of every user/operator surface +
                          the coverage map (which scenario tests what)
  BLOCKED.md            — capabilities that cannot be tested with what is installed
  scenarios/            — one file per scenario: manifest + prompt + rubric + runsheet
    S1-swift-gui.md   S2-rust.md     S3-dictation.md   S4-rag.md
    S5-lora.md        S6-electronics.md
    S7..S18           — surface-coverage scenarios (windows, menus, settings, panels,
                        chat surface, dialogs, operator config, connectors, skills,
                        memories, intents, notifications, agent tools) — coverage map
                        in SURFACE-CENSUS.md
  fixtures/             — fixture artifacts built by Codex per the task docs
  results/              — per-run proving-pass result logs
```

S1–S6 are **capability** scenarios (Merlin doing real work). S7–S18 are **surface**
scenarios that exhaustively exercise Merlin's own UI, operator, and agent-tool surface —
every window, menu, settings pane, panel, dialog, config mechanism, and all ~67 agent
tools. **`SURFACE-CENSUS.md`** — mechanically derived by grep from all 258 source files —
is the authoritative coverage map; an uncovered row there is untested surface. (The
older `SURFACE-INVENTORY.md` is superseded — it was a hand-curated subset.)

## How a scenario is structured

Each `scenarios/SN-*.md` contains:
- **Planted-defect manifest** — every deliberate defect: id, kind (logic/visual), exact
  location, expected fix, and the cue by which it should be detected.
- **Scenario prompt** — the exact task text given to Merlin.
- **Scoring rubric** — deterministic checks (builds clean, tests pass, netlist correct,
  adapter produced) plus judgment checks (debugged sensibly, visuals correct).
- **Runsheet** — ordered manual steps for the human-in-the-loop parts.

## Two test layers

1. **Automated harness** — the `MerlinE2ETests` target in the merlin repo drives a
   `LiveSession` programmatically, sends a scenario prompt, awaits loop completion, and
   asserts the deterministic outcomes.
2. **Runsheets** — for the parts that cannot be automated: voice dictation (a human must
   speak), visual confirmation, and KiCad GUI work.

## Running a proving pass

Run **after** Merlin Batches B–D (task docs 294–301) are executed — the suite targets a
complete Merlin. For each scenario: follow the runsheet / run the harness test, score
against the rubric, and write a dated result file to `results/`.

## Capability baseline (probed 2026-05-16)

All six scenario areas are testable on this machine: Rust 1.94, Python 3.9.13 +
mlx_lm/mlx, ngspice, vale, KiCad 10.0.3, FreeRouting (bundled JRE), merlin-kicad-mcp,
xcalibre-server source, LM Studio. See `BLOCKED.md` for any exceptions found later.
