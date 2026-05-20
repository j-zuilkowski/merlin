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

## Smoke matrix

| Provider | Reachable | Completion | Streaming | Tool call | Notes |
|---|---|---|---|---|---|
| **lmstudio** (baseline) | ⬜ | ⬜ | ⬜ | ⬜ | MLX-8bit; running on `:1234` |
| **ollama** | ⬜ | ⬜ | ⬜ | ⬜ | Q8_0 GGUF via Modelfile |
| **jan** | ⬜ | ⬜ | ⬜ | ⬜ | Q8_0 GGUF via Jan hub |
| **localai** (native) | ⬜ | ⬜ | ⬜ | ⬜ | Homebrew install + Metal; Docker version retired |
| **mistralrs** | ⬜ | ⬜ | ⬜ | ⬜ | `:1235` (rebound off LM Studio's `:1234`) |
| **vllm** (vLLM-Metal) | ⬜ | ⬜ | ⬜ | ⬜ | Q8_0 GGUF attempt; FP8 safetensors fallback if MoE-GGUF fails |

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
_baseline_

### ollama


### jan


### localai (native)


### mistralrs


### vllm (vLLM-Metal)


## Takeaways

After the matrix is filled in, summarise:
- Which providers passed smoke
- Calibration variance across the four llama.cpp-family providers (Ollama, Jan,
  LocalAI, Mistral.rs) — they share the same kernel so should converge within
  ~1–2% if everything is wired correctly. Larger gaps suggest a tokenizer or
  parameter-default mismatch worth investigating.
- vLLM-Metal vs the rest — different inference path, so a genuinely different
  number is expected.
- Decision on whether to retire any local providers from the configured list,
  or surface specific calibration parameter advisories.
