# S5 — LoRA Training

Proves Merlin's LoRA self-training pipeline runs end-to-end: it consumes DPO preference
pairs, invokes `mlx_lm` training, produces an adapter, and the adapter is loadable and
routable through the execute slot.

**This is a pipeline-integrity test, not a model-quality test.** Use a minimal iteration
count — the goal is "the pipeline runs and produces a valid adapter", not a good adapter.

---

## Setup

Confirmed available: Python 3.9.13, `mlx_lm`, `mlx`, Apple Silicon (M4 Max), and an
MLX-format base model in LM Studio (`qwopus3.5-27b…-mlx`). If a smaller MLX model is
available, prefer it — training even a few iterations on 27B is heavy.

## Fixture: `merlin-eval/fixtures/lora-dpo/`

Seed ~30–50 DPO preference pairs in the format `Merlin/Engine/DPOQueue.swift` expects
(`~/.merlin/lora/pending/<uuid>.json` — confirm the schema from that file). Each pair:
a prompt, a `chosen` response, a `rejected` response. Keep the content trivial and
consistent (e.g. "always answer in one sentence" preference) — content quality does not
matter, schema validity does.

A `train-config.json` (or the equivalent the trainer reads) pinning a **tiny** run:
`iters: 20`, small batch, small `lora_layers` — see `Merlin/Engine/LoRATrainer.swift`.

---

## Scenario

LoRA training is triggered through Merlin's LoRA settings UI (`LoRASettingsSection`), not
a chat prompt. The scenario is therefore harness-assisted + manual:

1. Place the seed DPO pairs so Merlin's DPO queue sees them.
2. In Merlin → Settings → LoRA, select the base model, set the tiny iteration count,
   start training.
3. Observe the training run to completion.
4. Confirm the adapter is produced and offer to route the execute slot through
   `mlx_lm.server` + the adapter.

---

## Scoring rubric

**Deterministic / observable:**
- [ ] The DPO pairs are picked up — the queue/UI shows the seeded count.
- [ ] Training launches `mlx_lm` (a `python -m mlx_lm.lora` process) and runs without
      error to the configured iteration count.
- [ ] An adapter artifact is produced under `~/.merlin/lora/` (adapter weights file).
- [ ] The adapter loads — `mlx_lm.server` (or the trainer's verify step) accepts it.
- [ ] The execute slot can be pointed at the adapter-backed endpoint and a smoke
      generation returns text.

**Judgment:**
- [ ] Merlin surfaced training progress/errors honestly (no silent failure — recall the
      audit theme; a training run that "succeeds" but produced no adapter is a finding).

**Score:** pipeline stages passed / 5.

---

## Runsheet

1. Batches B–D merged; Merlin built; `python3 -c "import mlx_lm"` succeeds.
2. Seed the DPO pairs into `~/.merlin/lora/pending/`.
3. Open Merlin → Settings → LoRA; select the base model; set `iters` low (~20).
4. Start training; watch the process and Merlin's progress UI.
5. On completion: check `~/.merlin/lora/` for the adapter; attempt to load it; run one
   generation through the adapter-backed execute slot.
6. Score against the rubric; write `merlin-eval/results/S5-<date>.md`.
7. If `mlx_lm` errors, no adapter appears, or the UI reports success with no artifact —
   that is a finding; record it (and add to `BLOCKED.md` if it is an environment gap).
