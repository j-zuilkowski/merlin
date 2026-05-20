# Local Provider Testing Matrix — Results

Compare each local provider's calibration output against the LM Studio MLX-8bit
baseline. All five serve the same `Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf` (or
the equivalent MLX-8bit in LM Studio's case) so engine overhead is the only
variable.

Run order per provider:

1. Launch the provider (see provider-specific instructions in `README.md`)
2. `bash smoke-test.sh <provider-id>` — fills in the smoke columns below
3. In Merlin: Settings → Providers → enable provider + Refresh Models → pick model
4. Run `/calibrate` in Merlin against DeepSeek as the reference remote
5. Locate the report at `merlin-eval/results/CALIBRATION-harness-<timestamp>.md`
6. Record `overallLocalScore` and the per-category breakdown below

## Smoke matrix — 2026-05-20 first pass

| Provider | Reachable | Completion | Streaming | Tool call | Notes |
|---|---|---|---|---|---|
| **lmstudio** (baseline) | ✓ | ✓ | ✓ (8 chunks) | ✓ | MLX-8bit; `:1234`; 2 models reported by `/v1/models` |
| **ollama** | ⚠ blocked | — | — | — | App running but daemon not bound — first-launch flow needs interactive click on the menubar icon (license accept). Re-run smoke once daemon is bound. |
| **jan** | ⚠ blocked | — | — | — | Daemon needs Jan UI → Settings → Local Server → Start. GUI step. |
| **localai** (native) | ✓ | ✓ ("pong") | ✓ (12 chunks) | ✓ | Homebrew install + Metal + `metal-llama-cpp` backend. Docker version retired. |
| **mistralrs** | ✓ | ✗ HTTP 500 | ⚠ 0 chunks | ✗ HTTP 500 | Server binds and `/v1/models` returns, but inference panics: `indexed_moe_forward is not implemented in this platform!` — Mistral.rs's `candle-core 0.10.2` does not yet implement MoE forward pass on Metal. **Qwen3-Coder-A3B is MoE; cannot serve from this provider on Apple Silicon today.** |
| **vllm** (vLLM-Metal) | ✗ never bound | — | — | — | Engine init fails with `HFValidationError: Repo id must be in the form 'repo_name' or 'namespace/repo_name'` when fed a local GGUF path. vLLM 0.21.0's GGUF loader passes the path through HF validation. **FP8 safetensors fallback (~30 GB, `Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8`) is the documented next step but not yet attempted.** |

Mark each cell: ✓ pass / ⚠ warn / ✗ fail. Add details under Notes.

## Calibration matrix

DeepSeek (`deepseek-v4-flash`) is the reference remote — it's the only enabled
remote provider in `~/.merlin/config.toml`. Each row records the local provider's
overall score and the per-category breakdown (Reasoning / Coding / Instruction-
Following / Summarization) from its CalibrationReport.

| Provider | Overall | Reasoning | Coding | Instr-Follow | Summarize | tok/s observed | Report file |
|---|---|---|---|---|---|---|---|
| **lmstudio** (baseline) | | | | | | | |
| **ollama** | | | | | | | |
| **jan** | | | | | | | |
| **localai** (native) | | | | | | | |
| **mistralrs** | | | | | | | |
| **vllm** (vLLM-Metal) | | | | | | | |

`Overall`: `overallLocalScore` from the report (mean of all 18 prompt scores).
`tok/s observed`: approximate generation rate during the run — useful for
distinguishing engine overhead between providers serving the same model.

## Provider-specific outcomes

For each provider that surfaces something interesting (failure, surprising
score, performance anomaly, format quirk), drop a one-paragraph note here:

### lmstudio
_baseline_ — passes all four axes. Two models exposed via `/v1/models`
(`qwen3-coder-30b-a3b-instruct-mlx`, `qwen3-vl-8b-instruct-mlx`).

### ollama
2026-05-20: app installed at `/Applications/Ollama.app`. `open -a Ollama` launches
the GUI process but the daemon never binds to `:11434` — Ollama on macOS requires
the user to click through a first-launch dialog (terms / "Start" prompt) in the
menubar before the daemon initializes. `~/.ollama/` never gets created without
that interaction. **Unblocked by user action**: open Ollama from Spotlight, click
through the welcome screen, then `ollama create qwen3-coder-30b-a3b-instruct -f
docs/local-provider-configs/ollama/Modelfile-qwen3-coder`, then re-run smoke.

### jan
Same pattern — app installed, daemon needs Jan UI → Settings → Local Server →
Start. GUI step. Unblocked by user action.

### localai (native)
✓ Passes all four axes. Native install via `brew install localai` + the
`metal-llama-cpp` backend resolves the Docker-on-macOS Metal problem (Docker
Desktop's Linux VM has no GPU access). Single completion returns "pong";
streaming yields 12 SSE chunks; tool_calls present in the response.

### mistralrs
✗ Inference panics on Metal. Server binds; `/v1/models` returns; but every chat
completion request hits:
```
thread '<unnamed>' panicked at candle-core-0.10.2/src/quantized/mod.rs:680:17:
indexed_moe_forward is not implemented in this platform!
```
This is a `candle-core` Metal backend limitation, not a configuration issue.
Qwen3-Coder-A3B is a Mixture-of-Experts model; the MoE forward pass for Metal
isn't yet implemented in candle 0.10.2.

**Options to revisit:** wait for upstream Mistral.rs / candle-core to ship the
Metal MoE op, OR switch to a non-MoE model for this provider only, OR retire
Mistral.rs from the active testing matrix until the upstream lands.

### vllm (vLLM-Metal)
✗ Engine init fails before the server binds:
```
huggingface_hub.errors.HFValidationError: Repo id must be in the form
'repo_name' or 'namespace/repo_name': '/Users/.../Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf'.
```
vLLM 0.21.0 (the venv `+cpu` build per `local-llm-provider-tested` memory) passes
the local GGUF path through HF repo-id validation at `model_lifecycle.py:126`,
which rejects file paths. This is the documented MoE-GGUF fragility flagged in
the original launch script comment.

**FP8 safetensors fallback is the documented next step.** Requires:
```bash
huggingface-cli download Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8 \
    --local-dir ~/Models/hf/Qwen3-Coder-30B-A3B-Instruct-FP8
```
(~30 GB download). Then uncomment the FP8 block in
`docs/local-provider-configs/vllm-metal/launch-qwen3-coder.sh`.
Not started in this pass — pending user approval given the disk + bandwidth cost.


## Takeaways — 2026-05-20 first pass

**Passing smoke today (2/6):** LM Studio (MLX-8bit baseline), LocalAI native (Q8 GGUF + Metal).

**Blocked on user action (2/6):** Ollama and Jan.ai — both have GUI-only first-launch flows that can't be driven from the shell. Once each is brought up by hand once, both should work end-to-end with the existing Modelfile / model.json artifacts.

**Failed on Metal compatibility (2/6):**
- **Mistral.rs** — `candle-core 0.10.2` doesn't implement MoE forward on Metal. Qwen3-MoE can't serve from this provider today regardless of how the loader is configured. Blocked upstream until candle lands the kernel.
- **vLLM-Metal** — vLLM 0.21.0's GGUF loader treats local file paths as HF repo IDs. Same Qwen3-MoE-via-GGUF combo is fragile here too. The documented workaround is FP8 safetensors (~30 GB download, not attempted yet).

**Implication for the calibration matrix:** the planned "calibrate all 5" comparison cannot complete today. The realistic data set is:
- LM Studio (baseline) — runnable now
- LocalAI native — runnable now
- Ollama — runnable after one menubar click
- Jan.ai — runnable after Jan UI toggle
- Mistral.rs — **out** until upstream MoE-on-Metal lands
- vLLM-Metal — **out** unless FP8 fallback is pursued (separate decision)

**Recommendation:** complete calibration on the four providers that can run (LM Studio, LocalAI, Ollama, Jan) — that already gives a meaningful llama.cpp-family-vs-MLX comparison. Defer Mistral.rs until upstream catches up. Defer vLLM-Metal until you decide whether the FP8 download is worth it.
