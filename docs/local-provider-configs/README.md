# Local Provider Configs — testing matrix + per-provider reference

Per-provider artifacts and configuration notes for the five local providers
Merlin can route to (LM Studio is the always-on baseline; the other five are
exercised via this directory). Each provider serves the same model class —
`Qwen3-Coder-30B-A3B-Instruct` — but the runtime, format, and feature set vary.

Shared on-disk assets:
- GGUF (Q8_0, 32 GB): `~/Models/gguf/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf` — used by Ollama, Jan.ai, LocalAI
- MLX-8bit dir (already in LM Studio's cache): `~/.lmstudio/models/lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-8bit/` — used by LM Studio AND vLLM-Metal
- VL pair (Q8_0 GGUF + mmproj): `~/Models/gguf/Qwen_Qwen3-VL-8B-Instruct-Q8_0.gguf` + `mmproj-Qwen_Qwen3-VL-8B-Instruct-f16.gguf` — text-only smoke first; mmproj wiring per provider is a follow-up.

Each provider registers its model under whatever name the user chooses. Merlin
discovers the live model list from each `/v1/models` endpoint at runtime via
`ProviderRegistry.fetchAllModels()`, so **Settings → Providers → Refresh Models**
populates the per-provider picker with whatever each one reports. **No model
name is hardcoded in `ProviderConfig`.**

---

## Per-provider reference

Each entry lists: launch / install, supported model formats, LoRA serving path,
configuration tips, known limitations.

### LM Studio (baseline)

- **Endpoint:** `http://localhost:1234/v1`
- **Install:** `/Applications/LM Studio.app` from the lmstudio.ai DMG
- **Launch:** open the app; it auto-binds `:1234` once the local server is enabled in the UI
- **Formats:** MLX (Apple's native quantization). LM Studio's catalog ships MLX-4bit, MLX-6bit, MLX-8bit, MLX-bf16 variants.
- **Architectures:** anything MLX supports — Llama, Qwen (dense + MoE), Mistral, Phi, Gemma, etc. Qwen3-Coder-MoE works out of the box.
- **LoRA serving:** **direct** — LM Studio loads adapter via its UI on top of the base. No fuse step required.
- **Tool calling:** OpenAI-compatible; works out of the box for tool-capable models.
- **Vision:** supported (the MLX-VL models load with their projector bundled in the directory).
- **Notes:** the live baseline against which other providers are calibrated. Multiple models can be loaded in parallel within the server.

### Ollama

- **Endpoint:** `http://localhost:11434/v1`
- **Install:** `/Applications/Ollama.app` from ollama.com
- **Launch:** `OLLAMA_HOST=127.0.0.1:11434 /Applications/Ollama.app/Contents/Resources/ollama serve` (after one-time `mkdir -p ~/.ollama/`)
- **Model register:** `ollama create qwen3-coder-30b-a3b-instruct -f ollama/Modelfile-qwen3-coder` (copies the GGUF into Ollama's blob store — ~32 GB duplicate)
- **Formats:** GGUF (preferred). Modern Ollama also imports safetensors via `ollama create` Modelfiles, though GGUF is the typical path.
- **Architectures:** anything llama.cpp supports — Llama 1/2/3/3.1/3.3, Qwen 1.5/2/2.5/3 (dense and MoE), Mistral, Mixtral, Phi, Gemma, DeepSeek, etc. Qwen3-Coder-MoE works.
- **LoRA serving:** **fuse + convert** — `mlx_lm.fuse` the adapter into the base, then `llama.cpp/convert_hf_to_gguf.py` to GGUF, then a fresh `ollama create` to register the fine-tuned model.
- **Tool calling:** requires a tool-aware Modelfile `TEMPLATE` that renders `.Tools` and `.ToolCalls` blocks. The canonical Qwen3 tool template is in `ollama/Modelfile-qwen3-coder`. **Without this template Ollama returns HTTP 400 "model does not support tools"** — even if the underlying model is tool-capable.
- **Vision:** native multimodal support since 0.4; Modelfile needs separate `FROM` lines for the main GGUF and the mmproj projector.
- **Notes:** Ollama's blob store doesn't symlink — `ollama create` always copies the GGUF in. Plan for 2× disk on the same model.

### Jan.ai

- **Endpoint:** `http://localhost:1337/v1` (Merlin's default; Jan-CLI defaults to 6767, rebind via `--port 1337`)
- **Install:** `/Applications/Jan.app` from jan.ai + `brew install llama.cpp` (Jan ships the CLI wrapper but not the inference backend)
- **Launch:** `/Applications/Jan.app/Contents/MacOS/jan-cli serve --model-path <gguf> --bin $(which llama-server) --port 1337 --n-gpu-layers=-1 --ctx-size 32768 --detach`
- **Formats:** GGUF (via the bundled llama.cpp backend). Also supports MLX via Jan's MLX backend if installed separately, but llama-server is the standard path.
- **Architectures:** anything llama.cpp supports — same surface as Ollama. Qwen3-Coder-MoE works.
- **LoRA serving:** **fuse + convert** — same path as Ollama (MLX fuse → GGUF convert → register in Jan).
- **Tool calling:** works out of the box via llama-server's OpenAI compat.
- **Vision:** llama.cpp's mmproj path; pass `--mmproj <path>` at server launch.
- **Notes:** `jan-cli` is the headless launch path; the Jan.app GUI is optional. `/v1/models` returns a hybrid response that contains both `models` and `data` keys — clients reading only `data` work fine.

### LocalAI (native — Docker version retired)

- **Endpoint:** `http://localhost:8080/v1`
- **Install:** `brew install localai` (Homebrew bottle, native arm64 binary; ~138 MB) + a backend install
- **One-time backend install:** `LOCALAI_BACKENDS_PATH=~/.localai/backends local-ai backends install localai@metal-llama-cpp`
- **Launch:** `bash localai/launch-native.sh` (wraps the right `local-ai run` invocation)
- **Formats:** GGUF (via the metal-llama-cpp backend). LocalAI's broader gallery also covers diffusion / TTS / ASR / embedding via separately-installed backends; the llama.cpp backend is the LLM path.
- **Architectures:** anything llama.cpp supports.
- **LoRA serving:** fuse + convert (same as Ollama / Jan).
- **Tool calling:** OpenAI-compatible via llama-cpp backend.
- **Vision:** llama.cpp mmproj path; configured in the model YAML.
- **Notes:** **Docker version retired 2026-05-20** — Docker Desktop's Linux VM on macOS has no Metal access, so the Docker build ran CPU-only at ~1–3 tok/s. The native Homebrew binary uses Metal directly and runs at full Apple-Silicon speed. The 4 Docker-managed volumes from the prior install are removed; backends live at `~/.localai/backends/`, models at `~/.localai/models/`. The model YAML (`localai/qwen3-coder-30b-a3b-instruct.yaml`) is dropped alongside the GGUF symlink at `~/.localai/models/`.

### Mistral.rs

- **Endpoint:** `http://localhost:1235/v1` — **rebound off the default `:1234`** to avoid the LM Studio port collision (Merlin's `ProviderConfig` default updated to match).
- **Install:** `cargo install mistralrs-server --features metal` (already at `~/.cargo/bin/mistralrs`)
- **Launch:** `bash mistralrs/launch-qwen3-coder.sh`
- **Formats:** GGUF, safetensors, ISQ (in-situ quantization). The CLI's `serve` subcommand auto-detects format via `--format gguf|plain|ggml`.
- **Architectures:** dense models — Llama, Mistral, Qwen2.5 (dense), Phi, etc. **MoE: NOT supported on Metal.** `candle-core 0.10.2` panics on `indexed_moe_forward is not implemented in this platform!` for any MoE architecture (Qwen3-Coder-A3B, Mixtral, etc.). **No further testing of MoE models on Mistral.rs has been done** — the panic is upstream and consistent.
- **LoRA serving:** fuse + convert (same as Ollama / Jan / LocalAI).
- **Tool calling:** OpenAI-compatible for supported model architectures.
- **Vision:** multimodal support in newer versions; check release notes for the active build.
- **Notes:** **Use Mistral.rs only with non-MoE models** for now. It's a viable serving target for Mistral-style and dense Qwen models, but Qwen3-Coder-A3B is out of scope. If the candle-core Metal backend lands `indexed_moe_forward`, revisit.

### vLLM-Metal

- **Endpoint:** `http://localhost:8000/v1`
- **Install:** `~/.venv-vllm-metal/` Python venv (community port; `pip install vllm-metal` or a manual build)
- **Launch:** `bash vllm-metal/launch-qwen3-coder.sh`
- **Formats:** **MLX only** — vLLM-Metal's loader is `mlx_lm.load`, which reads MLX-format model directories (HF layout: `config.json` + `model-*.safetensors` + tokenizer). It does NOT load GGUF files (rejected at HF-validation stage) and does NOT load FP8-MoE safetensors (MLX can't consume the `weight_scale_inv` per-tensor scale params).
- **Architectures:** anything `mlx_lm` supports — Llama, Qwen 2/3 (dense + MoE), Mistral, Phi, etc. Qwen3-Coder-A3B works.
- **LoRA serving:** **direct (after one fuse step)** — vLLM-Metal serves the same MLX format `mlx_lm.lora` produces. Run `mlx_lm.fuse --model <base> --adapter-path <adapter> --save-path <merged>`, then `vllm serve <merged>`. **No GGUF conversion required.** This puts vLLM-Metal in the same MLX-native serving family as LM Studio and `mlx_lm.server`. `mlx_lm.load()` natively supports `adapter_path` for direct base+adapter loading; vLLM-Metal doesn't yet expose this on its CLI, so the fuse step is required for now.
- **Tool calling:** requires `--enable-auto-tool-choice --tool-call-parser qwen3_coder`. The `qwen3_coder` parser ships with vllm-metal at `vllm/tool_parsers/qwen3coder_tool_parser.py`.
- **Vision:** the `mlx_vlm` path handles VL models; vLLM-Metal's model_lifecycle detects VLM at load time.
- **Notes:** shares the LM Studio MLX directory directly — no extra download. **Memory: ~32 GB Metal allocation at startup.** Running concurrently with Ollama + Jan + LocalAI (each ~32 GB Metal) OOMs a 128 GB M4 Max. **Run vLLM-Metal alongside at most one other heavy provider, or alone.**

---

## Cross-provider summary

| Provider | Native format | Q8 MoE OK? | LoRA serving path | Tool-call setup |
|---|---|---|---|---|
| LM Studio | MLX | ✓ | Direct (UI) | Built-in |
| vLLM-Metal | MLX | ✓ | Fuse → serve merged dir | `--tool-call-parser qwen3_coder` |
| Ollama | GGUF | ✓ | Fuse → convert → register | Tool-aware Modelfile TEMPLATE |
| Jan.ai | GGUF | ✓ | Fuse → convert → register | Built-in (via llama-server) |
| LocalAI | GGUF | ✓ | Fuse → convert → register | Built-in (via llama.cpp) |
| **Mistral.rs** | **GGUF / safetensors / ISQ** | **✗ — candle MoE-on-Metal unsupported** | **N/A for MoE bases** | Built-in for supported archs |

LoRA-trained adapter from `mlx_lm.lora` deploys cleanest to LM Studio and
`mlx_lm.server` (direct), then to vLLM-Metal (one fuse step), then to the GGUF
family (fuse + convert). **Mistral.rs is in the matrix for non-MoE base models
only.**

## Memory model

Each provider loading the Q8_0 / MLX-8bit model takes ~32 GB of Metal-shared
memory on Apple Silicon. The full 5-provider sweep is borderline-OOM on a 128 GB
M4 Max — saw `kIOGPUCommandBufferCallbackErrorOutOfMemory` when all five tried to
coexist. **For calibration: enable one provider at a time in Merlin Settings,
run `/calibrate`, disable, switch.** The smoke-test script
(`bash smoke-test.sh <id>`) is fine for sequential per-provider probing.

## After launching a provider

1. Each provider serves a model that responds to `model = "<your-chosen-id>"` via `/v1/chat/completions`.
2. In Merlin, enable the provider in **Settings → Providers** (or set `isEnabled = true` in `~/.merlin/config.toml`) and click **Refresh Models** to populate the per-provider picker with whatever `/v1/models` reports.
3. Run `/calibrate` against the provider with DeepSeek as the reference remote. The CalibrationReport lands in `merlin-eval/results/CALIBRATION-harness-<timestamp>.md`.

## VL serving (deferred)

The VL model (`Qwen3-VL-8B-Instruct`) needs the mmproj projector wired
per-provider:

- **LM Studio**: native — the MLX-VL directory packages the projector inside.
- **vLLM-Metal**: `mlx_vlm` path handles the projector automatically when the MLX-VL directory is present.
- **Ollama (≥ 0.4)**: native multimodal; Modelfile needs `FROM` lines for both the main GGUF and the mmproj projector.
- **Jan / LocalAI**: pass `--mmproj <path>` at server launch.
- **Mistral.rs**: multimodal in newer versions; check release notes for the active build (the MoE limitation applies to VL-MoE as well).

Wire each provider's VL serving in a separate pass once text-only smoke is green.
