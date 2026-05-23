#!/bin/bash
# Mistral.rs launch — Qwen3-Coder-30B-A3B-Instruct Q8_0
#
# IMPORTANT: this uses --port 1235, not the default 1234. LM Studio also defaults
# to 1234 — running both on 1234 produces a silent port collision where whichever
# started second fails to bind. Merlin's ProviderConfig has been updated to expect
# mistralrs on 1235; if you change the port here, change it there too.
#
# Cargo-installed location is ~/.cargo/bin/mistralrs (per local-llm-provider-tested
# memory). Confirm with: `which mistralrs`.

set -euo pipefail

MISTRALRS="${MISTRALRS:-$HOME/.cargo/bin/mistralrs}"
MODEL="${GGUF_PATH:-$HOME/Models/gguf/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf}"
HF_MODEL_ID="${HF_MODEL_ID:-Qwen/Qwen3-Coder-30B-A3B-Instruct}"
PORT="${PORT:-1235}"
CONTEXT_LENGTH="${CONTEXT_LENGTH:-}"
GPU_LAYERS="${GPU_LAYERS:-}"
CPU_THREADS="${CPU_THREADS:-}"
ROPE_FREQUENCY_BASE="${ROPE_FREQUENCY_BASE:-}"
FLASH_ATTENTION="${FLASH_ATTENTION:-}"
BATCH_SIZE="${BATCH_SIZE:-}"

if [ ! -x "$MISTRALRS" ]; then
    echo "error: mistralrs binary not found at $MISTRALRS"
    echo "       set MISTRALRS=<path> or install: cargo install mistralrs-server --features metal"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "error: model file not found: $MODEL"
    exit 1
fi

# mistralrs CLI uses the new `serve` subcommand (≥ 0.6).
# --model-id Qwen/Qwen3-Coder-30B-A3B-Instruct: HF ID used to fetch the tokenizer
#   (small download, < 5 MB). The GGUF on disk carries the weights; only the
#   tokenizer.json comes from HF cache.
# --format gguf: explicit quantized format.
# --quantized-file: local GGUF path.
ARGS=(
    serve
    -p "$PORT"
    --model-id "$HF_MODEL_ID"
    --format gguf
    --quantized-file "$MODEL"
)

if [ -n "$CONTEXT_LENGTH" ]; then
    ARGS+=(--max-seq-len "$CONTEXT_LENGTH")
fi
if [ -n "$GPU_LAYERS" ]; then
    ARGS+=(--gpu-layers "$GPU_LAYERS")
fi
if [ -n "$CPU_THREADS" ]; then
    ARGS+=(--cpu-threads "$CPU_THREADS")
fi
if [ -n "$ROPE_FREQUENCY_BASE" ]; then
    ARGS+=(--rope-frequency-base "$ROPE_FREQUENCY_BASE")
fi
if [ "$FLASH_ATTENTION" = "1" ] || [ "$FLASH_ATTENTION" = "true" ]; then
    ARGS+=(--flash-attn)
fi
if [ -n "$BATCH_SIZE" ]; then
    ARGS+=(--batch-size "$BATCH_SIZE")
fi

exec "$MISTRALRS" "${ARGS[@]}"

# Verify after launch (in another shell):
#   curl -s http://localhost:1235/v1/models | jq '.data[].id'
#   curl -s http://localhost:1235/v1/chat/completions \
#     -H 'Content-Type: application/json' \
#     -d '{"model":"qwen3-coder-30b-a3b-instruct","messages":[{"role":"user","content":"ping"}]}'
