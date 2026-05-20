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
| **vllm** (vLLM-Metal) | ✗ both paths | — | — | — | GGUF path fails with `HFValidationError` (vLLM 0.21.0's loader rejects local file paths). FP8 safetensors fallback **also fails**: `ValueError: Received 18624 parameters not in model: ...weight_scale_inv` — MLX doesn't handle FP8 per-tensor scale params for MoE models. Both upstream-blocked for Qwen3-MoE on Apple Silicon. |

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
**Both load paths fail upstream.**

GGUF (Q8_0):
```
huggingface_hub.errors.HFValidationError: Repo id must be in the form
'repo_name' or 'namespace/repo_name': '/Users/.../Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf'.
```
vLLM 0.21.0's loader passes the local GGUF path through HF repo-id validation
at `model_lifecycle.py:126`.

FP8 safetensors (downloaded 2026-05-20, ~29 GB at `~/Models/hf/Qwen3-Coder-30B-A3B-Instruct-FP8/`):
```
ValueError: Received 18624 parameters not in model:
  model.layers.0.mlp.experts.0.down_proj.weight_scale_inv, ...
```
MLX (the Apple Silicon ML framework that vLLM-Metal uses) doesn't handle the
FP8 per-tensor scale params (`weight_scale_inv`) that accompany FP8-quantized
MoE models.

Both paths blocked upstream. **Recommendation: drop vLLM-Metal from the active
testing matrix** for the same reason Mistral.rs was dropped — Qwen3-MoE on
Apple Silicon is the common failure surface. The FP8 download stays on disk as
documentation of the attempt; revisit if vLLM-Metal's MLX integration improves.


## Takeaways — 2026-05-20 final

**Passing smoke (4/6):** LM Studio (MLX-8bit baseline), Ollama (Q8 GGUF), Jan.ai (Q8 GGUF), LocalAI native (Q8 GGUF). All four pass all four wire-format axes (reachable, completion, streaming, tool_calls).

**Out of the matrix (2/6):**
- **Mistral.rs** — dropped per user direction. `candle-core 0.10.2` lacks `indexed_moe_forward` for Metal; can't serve Qwen3-MoE.
- **vLLM-Metal** — both GGUF and FP8 load paths fail upstream on Qwen3-MoE + MLX (HFValidationError on GGUF; `weight_scale_inv` mismatch on FP8). FP8 safetensors stay on disk in case vLLM-Metal's MLX integration improves.

**Calibration matrix is 4 providers** — meaningful llama.cpp-vs-MLX comparison even without Mistral.rs and vLLM-Metal:
- LM Studio = MLX-8bit (different inference path)
- Ollama / Jan / LocalAI = llama.cpp family on Q8_0 GGUF (same kernel; provides a 3-way convergence sanity check)

Calibration outcomes should show:
- Ollama / Jan / LocalAI converging within ~1–2% of each other (same kernel; differences are wrapper overhead and parameter defaults)
- LM Studio differing more because it's a different precision (MLX-8bit vs Q8_0 GGUF) and a different runtime (MLX vs llama.cpp)
- Larger gaps on the llama.cpp trio than ~2% would suggest a tokenizer or parameter-default mismatch worth investigating.

**Daemons running at end of pass:**
- LM Studio (`:1234`) — yours, leave alone
- LocalAI native (`:8080`) — restart with `bash docs/local-provider-configs/localai/launch-native.sh`
- Ollama (`:11434`) — restart with `OLLAMA_HOST=127.0.0.1:11434 /Applications/Ollama.app/Contents/Resources/ollama serve`
- Jan (`:1337`, via `jan-cli` + Homebrew `llama-server`) — restart with the `jan-cli serve` command in this file's Jan section

All four are ready for `/calibrate` runs from Merlin against DeepSeek as the reference remote.
