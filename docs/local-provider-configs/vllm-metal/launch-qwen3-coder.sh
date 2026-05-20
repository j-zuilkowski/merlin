#!/bin/bash
# vLLM-Metal launch — Qwen3-Coder-30B-A3B-Instruct Q8_0
#
# This script tries the GGUF path first. vLLM-Metal's GGUF support is the weakest
# of the five untested providers — Qwen3 MoE under GGUF on the +cpu/Metal build
# (0.21.0+) may not be supported. If `vllm serve` fails to load, fall back to the
# FP8 safetensors download path (commented out below).
#
# Per local-llm-provider-tested memory: vllm lives in ~/.venv-vllm-metal, not on
# the system PATH. Activate or call the venv binary directly.

set -euo pipefail

VLLM="${VLLM:-$HOME/.venv-vllm-metal/bin/vllm}"
GGUF="$HOME/Models/gguf/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf"
PORT=8000

if [ ! -x "$VLLM" ]; then
    echo "error: vllm binary not found at $VLLM"
    exit 1
fi

if [ ! -f "$GGUF" ]; then
    echo "error: model file not found: $GGUF"
    exit 1
fi

# Attempt 1 — GGUF path (cheapest if it works).
echo "[vllm-metal] attempting GGUF load..."
exec "$VLLM" serve "$GGUF" \
    --quantization gguf \
    --served-model-name qwen3-coder-30b-a3b-instruct \
    --port "$PORT" \
    --max-model-len 32768 \
    --gpu-memory-utilization 0.85 \
    --enforce-eager

# Attempt 2 — FP8 safetensors fallback. Comment out attempt 1 (the `exec`) and
# uncomment the block below if attempt 1 errors with "architecture not supported"
# or "tensor mismatch". Requires a separate ~30 GB download first:
#   huggingface-cli download Qwen/Qwen3-Coder-30B-A3B-Instruct-FP8 \
#       --local-dir ~/Models/hf/Qwen3-Coder-30B-A3B-Instruct-FP8
#
# exec "$VLLM" serve ~/Models/hf/Qwen3-Coder-30B-A3B-Instruct-FP8 \
#     --quantization fp8 \
#     --served-model-name qwen3-coder-30b-a3b-instruct \
#     --port "$PORT" \
#     --max-model-len 32768 \
#     --gpu-memory-utilization 0.85 \
#     --enforce-eager

# Verify after launch:
#   curl -s http://localhost:8000/v1/models | jq '.data[].id'
