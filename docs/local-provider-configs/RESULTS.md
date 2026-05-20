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

## Smoke matrix — 2026-05-20 final

| Provider | Reachable | Completion | Streaming | Tool call | Notes |
|---|---|---|---|---|---|
| **lmstudio** (baseline) | ✓ | ✓ | ✓ (8 chunks) | ✓ | MLX-8bit; `:1234`; 2 models reported by `/v1/models` |
| **ollama** | ✓ | ✓ | ✓ (9 chunks) | ✓ | Unblocked: `mkdir -p ~/.ollama/{models,logs}` + `ollama serve` bypassed the GUI first-launch flow. Tool-aware Modelfile template needed for tool_calls — see commit |
| **jan** | ✓ | ✓ | ✓ (10 chunks) | ✓ | Unblocked: `jan-cli serve --model-path <gguf> --bin $(which llama-server)`. Required `brew install llama.cpp` (Jan ships the CLI but not the backend binary). Port rebound to 1337 to match Merlin's `ProviderConfig.swift` default. |
| **localai** (native) | ✓ | ✓ ("pong") | ✓ (12 chunks) | ✓ | Homebrew install + Metal + `metal-llama-cpp` backend. Docker version retired. |
| **mistralrs** | — DROPPED — | | | | Per user direction (2026-05-20): retired from the testing matrix. `candle-core 0.10.2` doesn't implement MoE forward on Metal; Qwen3-Coder-A3B can't serve from this provider on Apple Silicon today. Revisit when upstream lands the kernel. |
| **vllm** (vLLM-Metal) | ✓ | ✓ | ✓ (10 chunks) | ✓ | **Resolved 2026-05-20**: vLLM-Metal uses `mlx_lm.load`, not the standard vLLM weight loaders. Wants an MLX-format model directory (HF layout: `config.json` + `model-*.safetensors` + tokenizer). Pointing it at LM Studio's `~/.lmstudio/models/.../Qwen3-Coder-30B-A3B-Instruct-MLX-8bit/` directly works — no extra download. Requires `--enable-auto-tool-choice --tool-call-parser qwen3_coder` for tool_calls. GGUF and FP8 paths are dead ends for this provider; **MLX is its native format**. |

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
**Resolved 2026-05-20.** Initially looked blocked — `open -a Ollama` launched the
GUI process but the daemon never bound. The unblocker: pre-create `~/.ollama/`
manually, then run `ollama serve` directly from `/Applications/Ollama.app/Contents/Resources/ollama`.
That bypasses the menubar first-launch flow entirely. Once the daemon is up:
`ollama create qwen3-coder-30b-a3b-instruct -f docs/local-provider-configs/ollama/Modelfile-qwen3-coder`
imports the GGUF into Ollama's blob store (32 GB copy, not symlinked — Ollama's
blob store is opaque).

The first Modelfile version used a plain ChatML template, which Ollama
**rejected as not tool-capable** (HTTP 400: "model does not support tools").
Ollama gates tool support on the template rendering `.Tools` and `.ToolCalls`
blocks. The Modelfile now uses the canonical Qwen3 tool-aware template — fixed
the tool-call axis without re-importing the GGUF.

### jan
**Resolved 2026-05-20.** Jan ships `/Applications/Jan.app/Contents/MacOS/jan-cli`
which bypasses the GUI entirely: `jan-cli serve --model-path <gguf> --port 1337
--n-gpu-layers=-1 --ctx-size 32768 --detach`. The catch: `jan-cli` doesn't ship
the inference backend, only the CLI wrapper. Needed `brew install llama.cpp` to
provide `llama-server`, then `--bin $(which llama-server)` in the `jan-cli serve`
invocation. Default port is 6767, rebound to 1337 to match Merlin's
`ProviderConfig.swift`. Hybrid `/v1/models` response (both `models` and `data`
keys) confused the smoke test on first read but the OpenAI-compat surface works
correctly.

### localai (native)
✓ Passes all four axes. Native install via `brew install localai` + the
`metal-llama-cpp` backend resolves the Docker-on-macOS Metal problem (Docker
Desktop's Linux VM has no GPU access). Single completion returns "pong";
streaming yields 12 SSE chunks; tool_calls present in the response.

### mistralrs
**Dropped from matrix per user direction (2026-05-20).** Inference panics on
Metal: `indexed_moe_forward is not implemented in this platform!`
`candle-core 0.10.2` doesn't implement MoE forward pass for Metal. Server
binds and `/v1/models` returns, but every chat completion errors. Cannot serve
Qwen3-Coder-A3B from this provider on Apple Silicon today. Revisit when
upstream candle lands the Metal MoE op.

### vllm (vLLM-Metal)
**Resolved 2026-05-20.** The earlier failures were format-choice errors, not
upstream limitations:

- GGUF path failed because vLLM-Metal's loader is `mlx_lm.load`, not vLLM's
  standard GGUF loader. `mlx_lm` doesn't read `.gguf` files — it reads HF-layout
  model directories. The `HFValidationError` at
  `vllm_metal/v1/model_lifecycle.py:126` came from `mlx_lm` running my path
  through HF repo-id validation, which rejects single files.
- FP8 path failed because MLX's MoE backend doesn't consume the FP8 per-tensor
  scale params (`weight_scale_inv`).

The **correct input is an MLX-format model directory** — which is exactly what
LM Studio already has at
`~/.lmstudio/models/lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-8bit/`.
Pointing `vllm serve` at that directory works out of the box. **No additional
download required** — vLLM-Metal and LM Studio share the same on-disk MLX file.

Tool calls require `--enable-auto-tool-choice --tool-call-parser qwen3_coder`;
without them, vLLM returns HTTP 400 on any request with `tools` set.

**Memory caveat**: vLLM-Metal allocates the model into Metal-shared memory at
startup. Running it concurrently with the three GGUF-using providers (Ollama,
Jan, LocalAI, each carrying ~32 GB of Metal allocation for the same model) OOMs
the GPU on a 128 GB M4 Max. The earlier smoke sweep hit
`kIOGPUCommandBufferCallbackErrorOutOfMemory`. In practice this is fine — only
one provider serves the active Merlin request at a time. For the smoke-test
sweep, shut down the other GGUF daemons before launching vLLM-Metal.

The 29 GB FP8 download stays on disk for now; can be deleted (vLLM-Metal won't
use it).


## Takeaways — 2026-05-20 final

**Passing smoke (5/6):** LM Studio (MLX-8bit baseline), Ollama (Q8 GGUF), Jan.ai (Q8 GGUF), LocalAI native (Q8 GGUF), vLLM-Metal (MLX-8bit, sharing LM Studio's on-disk dir). All five pass all four wire-format axes when run in isolation.

**Out of the matrix (1/6):**
- **Mistral.rs** — dropped per user direction. `candle-core 0.10.2` lacks `indexed_moe_forward` for Metal; can't serve Qwen3-MoE.

**Calibration matrix is 5 providers** — covers both inference paths:
- **MLX family**: LM Studio (LM Studio's own MLX runtime), vLLM-Metal (uses `mlx_lm` against the same on-disk model directory).
- **llama.cpp family**: Ollama, Jan, LocalAI — same kernel, same Q8_0 GGUF.

Calibration outcomes should show:
- LM Studio ≈ vLLM-Metal — same MLX file, near-identical outputs. Any gap is server-side scheduling overhead.
- Ollama / Jan / LocalAI converging within ~1–2% of each other (same llama.cpp kernel; differences are wrapper overhead + parameter defaults).
- MLX family vs llama.cpp family — different precision (MLX-8bit vs Q8_0 GGUF) and different runtime; meaningful gap is the interesting signal.

**Memory note**: vLLM-Metal and LM Studio share Metal allocation when both load
the same MLX model — running both simultaneously is borderline on a 128 GB M4.
The other GGUF providers each carry their own ~32 GB Metal allocation. **For
calibration: run one provider at a time** (enable in Merlin, run `/calibrate`,
disable, switch). The smoke sweep saw `kIOGPUCommandBufferCallbackErrorOutOfMemory`
when all five tried to coexist.

**Daemons running at end of pass:**
- LM Studio (`:1234`) — yours, leave alone
- vLLM-Metal (`:8000`, PID 62965, MLX-8bit from LM Studio dir)
- The other three (Ollama / Jan / LocalAI) were stopped to free Metal memory for vLLM-Metal. Restart commands in this file's per-provider sections.

All five are ready for `/calibrate` runs from Merlin against DeepSeek as the reference remote, one at a time.
