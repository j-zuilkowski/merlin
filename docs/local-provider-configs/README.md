# Local Provider Configs — Q8_0 GGUF testing matrix

Per-provider artifacts to serve `Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf` across the
five untested local providers so `/calibrate` can compare them against the LM Studio
MLX-8bit baseline.

GGUF lives at `~/Models/gguf/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf` (32 GB). The
vision-language pair (`Qwen_Qwen3-VL-8B-Instruct-Q8_0.gguf` + `mmproj-Qwen_Qwen3-VL-8B-Instruct-f16.gguf`)
ships alongside it but VL serving needs the mmproj wired per-provider — covered as a
follow-up after the text-only smoke tests pass.

Each provider registers its own model under whatever name the user chooses; the
example artifacts here use `qwen3-coder-30b-a3b-instruct` as a convenient shared
name, but you can pick any string. Merlin discovers the live model list from each
provider's `/v1/models` endpoint at runtime (via `ProviderRegistry.fetchAllModels()`),
so **Settings → Providers → Refresh Models** populates the per-provider picker
with whatever each one actually reports. No model name is hardcoded in `ProviderConfig`.

## Per-provider setup

### Ollama
- File: `ollama/Modelfile-qwen3-coder`
- Register: `ollama create qwen3-coder-30b-a3b-instruct -f ollama/Modelfile-qwen3-coder`
- Endpoint: `http://localhost:11434/v1`

### Jan.ai
- File: `jan/qwen3-coder-30b-a3b-instruct/model.json`
- Install: copy `jan/qwen3-coder-30b-a3b-instruct/` into `~/Library/Application Support/Jan/data/models/`
- Enable: Jan UI → Settings → Local Server → Start
- Endpoint: `http://localhost:1337/v1`

### LocalAI
- File: `localai/qwen3-coder-30b-a3b-instruct.yaml`
- Install: copy YAML into the container's `/models/` volume (or mount `~/Models/` and the YAML directly)
- Endpoint: `http://localhost:8080/v1`

### Mistral.rs
- File: `mistralrs/launch-qwen3-coder.sh`
- Launch: `bash mistralrs/launch-qwen3-coder.sh`
- Endpoint: `http://localhost:1235/v1` (**not** 1234 — that collides with LM Studio)
- Merlin's `ProviderConfig` default has been updated to `:1235` to match.

### vLLM-Metal
- File: `vllm-metal/launch-qwen3-coder.sh`
- Launch: `bash vllm-metal/launch-qwen3-coder.sh`
- Endpoint: `http://localhost:8000/v1`
- The script tries the GGUF path first via `vllm serve --quantization gguf`. If the
  MoE architecture isn't supported under GGUF on the installed vLLM version, fall
  back to the FP8 safetensors download (`Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8`).

## After launching all five

1. Each provider should serve a model that responds to `model = "qwen3-coder-30b-a3b-instruct"`.
2. In Merlin, enable each provider in **Settings → Providers** (or set `isEnabled = true` in `~/.merlin/config.toml`).
3. Run `/calibrate` against each, comparing to the LM Studio MLX-8bit baseline. Same
   Q8_0-equivalent precision across all five = apples-to-apples engine-overhead
   comparison.

## VL serving (deferred)

Once the text-only smoke tests pass, each provider's VL story diverges:

- **Ollama (≥ 0.4):** native multimodal; Modelfile needs a `FROM` for both the main
  GGUF and the mmproj projector — see Ollama vision docs.
- **Jan / LocalAI (llama.cpp backend):** pass `--mmproj <path>` at server launch.
- **Mistral.rs:** multimodal in newer versions; check release notes for the active build.
- **vLLM-Metal:** VL in GGUF is the weakest support area; HF safetensors is the
  reliable VL path for vLLM.

Wire each in a separate pass once the Coder smoke tests are green.
