# Local Provider Testing Matrix — Results

Validated against live runs on **May 22, 2026**, with llama.cpp router validation refreshed on **May 25, 2026** and the reliable provider set refreshed on **May 27, 2026**.

Prefer llama.cpp router mode for Merlin's local general+vision workflow. Compare
other local providers against the same Qwen model class so engine overhead and
runtime behavior are the only variables; LM Studio uses the equivalent MLX-8bit
model, while the GGUF providers use `Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf`.

Run order per provider:

1. Launch the provider (see provider-specific instructions in `README.md`)
2. `bash smoke-test.sh <provider-id>` — fills in the smoke columns below
3. In Merlin: Settings → Providers → enable provider + Refresh Models → pick model
4. Run `/calibrate` in Merlin against DeepSeek as the reference remote
5. Locate the report at `merlin-eval/results/CALIBRATION-harness-<timestamp>.md`
6. Record `overallLocalScore` and the per-category breakdown below

## Current reliable set — 2026-05-27

| Provider | Current status | Reason |
|---|---|---|
| **llamacpp** | Preferred reliable in router mode | One router-mode `llama-server` served explicit text and vision model IDs successfully. |
| **lmstudio** | Reliable alternative | Text, streaming, tool calls, and vision passed. |
| **jan** | Reliable alternative | Text, streaming, tool calls, and vision passed through the Jan CLI / llama-server path. |
| **localai** | Non-working for Merlin full surface | Text, streaming, and vision responded, but tool-call requests returned plain content without OpenAI `tool_calls`. |
| **ollama** | Non-working for Merlin full surface | Text works, but the tested Qwen3-VL path crashes the runner on real image requests; skip unless upstream issue tracking shows a fix. |
| **vllm** (vLLM-Metal) | Non-working / avoid | Text and auto tool calls can work, but forced tool choice is unreliable and vision is not implemented on Metal. |
| **mistralrs** | Non-working for tested model | The tested Qwen3 MoE GGUF path fails on first inference on Apple Metal. |

## Historical support matrix — 2026-05-22

| Provider | General model | Vision model | Timed calibration | Status | Notes |
|---|---|---|---|---|---|
| **lmstudio** | ✓ | ✓ | ✓ | Reliable alternative | Historical complete local pair |
| **jan** | ✓ | ✓ | ✓ | Reliable | Pair passed after correcting first vision-path launch mistake |
| **localai** | ✓ | ✓ | ✓ | Superseded: non-working for Merlin full surface | Historical pair run passed, but the May 27 full-surface smoke found tool calls do not return OpenAI `tool_calls` |
| **ollama** | ✓ | ✗ | general only | Non-working for Merlin full surface | Vision requests crashed the runner with `EOF` / `exit status 2` |
| **vllm** (vLLM-Metal) | ✓ | ✗ | general only | Non-working / avoid | Vision failed upstream with `NotImplementedError` on Metal; forced tool choice is unreliable |
| **mistralrs** | ✗ | not pursued | — | Non-working for tested model | Tested Qwen3 MoE GGUF loads, then fails on first inference on Metal |
| **llamacpp** | ✓ | ✓ | smoke | Reliable in router mode | One router-mode `llama-server` served the local Qwen3 Coder + Qwen3-VL GGUF pair with `mmproj`; `/health`, `/v1/models`, `/models/load`, text completion, streaming, tool-call request shape, and image request returned HTTP 200 |

## Timed calibration matrix — 2026-05-22

| Provider | Wall clock seconds | Local score | Reference score | Report file |
|---|---|---|---|---|
| **lmstudio** | `600.442` | `0.8056` | `0.8333` | `codex-calibration-logs/lmstudio/calibration-report.json` |
| **jan** | `501.843` | `0.8056` | `0.8056` | `codex-calibration-logs/jan/calibration-report.json` |
| **localai** | `494.966` | `0.8056` | `0.8611` | `codex-calibration-logs/localai/calibration-report.json` |
| **ollama** | `520.890` | `0.8611` | `0.8056` | `codex-calibration-logs/ollama/calibration-report.json` |
| **vllm** (vLLM-Metal) | `592.440` | `0.8889` | `0.7778` | `codex-calibration-logs/vllm/calibration-report.json` |
| **mistralrs** | — | — | — | No successful calibration run |
| **llamacpp** | smoke run | pass | pass | `/tmp/merlin-llamacpp-smoke.txt` |

## Provider-specific outcomes

For each provider that surfaces something interesting (failure, surprising
score, performance anomaly, format quirk), drop a one-paragraph note here:

### lmstudio
Reliable. General + vision pair passed live testing and the uncapped
timed calibration run.

### ollama
Non-working for Merlin's full local-provider surface. General calibration succeeded, but the tested vision model
failed on both `/v1/chat/completions` and `/api/chat` with the runner exiting
`EOF` / `exit status 2`. This is a runtime failure under real image load, not a
Merlin wiring problem.

### jan
Reliable. General + vision pair passed live testing and timed
calibration. A first vision launch used the wrong GGUF filename, then passed
cleanly after correction.

### localai (native)
Non-working for Merlin's full local-provider surface. Historical general +
vision calibration passed from one LocalAI instance, but the May 27 full-surface
smoke found tool-call requests return plain content without OpenAI `tool_calls`.

### mistralrs
Non-working for the tested Qwen3-Coder-A3B GGUF model on Apple Metal.
Server binds and `/v1/models` returns, but the first real completion fails
because the MoE path reaches CUDA-only `indexed_moe_forward`. Upstream bug
filed: `EricLBuehler/mistral.rs#2160`.

### vllm (vLLM-Metal)
Non-working / avoid. The general MLX model calibrated successfully, but the tested
vision runtime failed on the first real image request with:
`NotImplementedError: Multimodal encoder execution is not wired on Metal yet`.
Forced required tool choice is also unreliable. Avoid this provider for the
foreseeable future.

### llamacpp
Reliable in router mode. Merlin ships a first-class `llamacpp`
provider and `LlamaCppModelManager` targeting one router-mode `llama-server`
process on `http://localhost:8081/v1`. Runtime load/unload is available through
`POST /models/load` and `POST /models/unload` when `/models` router endpoints
are present; single-model servers fall back to restart guidance. The refreshed
validation used `/opt/homebrew/bin/llama-server` 9290 with
`Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf`,
`Qwen_Qwen3-VL-8B-Instruct-Q8_0.gguf`, and
`mmproj-Qwen_Qwen3-VL-8B-Instruct-f16.gguf`. Text, streaming, tool-call shape,
and a data-URI image request all returned HTTP 200.

## Upstream issue tracking — 2026-05-22

### Ollama
- [ollama/ollama#16264](https://github.com/ollama/ollama/issues/16264) — imported `Qwen3-VL-8B` GGUF + `mmproj` registers as vision-capable on Apple Silicon, then crashes on the first real image request with `EOF` / `exit status 2`
- [ollama/ollama#13150](https://github.com/ollama/ollama/issues/13150) — Qwen3-VL crashes with a nil-pointer dereference in the vision path and returns `500` / `EOF`
- [ollama/ollama#13113](https://github.com/ollama/ollama/issues/13113) — Qwen3-VL crashes on small images before inference
- [ollama/ollama#13187](https://github.com/ollama/ollama/issues/13187) — custom Qwen3-VL-MoE models fail even when they validate and run in other runtimes
- [ollama/ollama#15898](https://github.com/ollama/ollama/issues/15898) — dual-`FROM` GGUF + `mmproj` loading fails for a related Qwen vision/MoE path because Ollama's vendored `llama.cpp` lacks the architecture support

### vllm-metal
- [vllm-project/vllm-metal#319](https://github.com/vllm-project/vllm-metal/issues/319) — RFC to add end-to-end vision-language model support
- [vllm-project/vllm-metal#333](https://github.com/vllm-project/vllm-metal/issues/333) — RFC to add the missing non-causal encoder-attention primitive needed for vision towers on Metal

### Mistral.rs
- [EricLBuehler/mistral.rs#2160](https://github.com/EricLBuehler/mistral.rs/issues/2160) — tested GGUF Qwen3 MoE model loads on Metal, then fails on the first real inference via CUDA-only `indexed_moe_forward`
- [EricLBuehler/mistral.rs#2032](https://github.com/EricLBuehler/mistral.rs/issues/2032) — related Qwen3.5 MoE Metal path still has shader and `indexed_moe_forward` gaps


## Takeaways — 2026-05-22

**Preferred local provider:**
- **llama.cpp** for router-mode validation of the GGUF general+vision pair

**Reliable local alternatives:**
- **LM Studio**
- **Jan.ai**

llama.cpp passed the router-mode smoke, tool-call, and image validation against
the same local GGUF pair. LM Studio and Jan.ai passed both model roles and
completed a timed calibration run.

**Non-working local providers:**
- **LocalAI** — text, streaming, and vision work, but tool calls do not return OpenAI `tool_calls`
- **Ollama** — general works, vision runner crashes on real image requests
- **vLLM-Metal** — general works, but forced tool choice is unreliable and vision is upstream-blocked on Metal
- **Mistral.rs** — the tested Qwen3 MoE GGUF path fails on first inference on
  Apple Metal

**Memory rule remains strict:** run one provider at a time, then shut it down.
Concurrent local daemons caused avoidable failures earlier in the sweep.
