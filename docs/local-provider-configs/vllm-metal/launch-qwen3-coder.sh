#!/bin/bash
# vLLM-Metal launch — Qwen3-Coder-30B-A3B-Instruct
#
# IMPORTANT — format choice:
# vLLM-Metal's loader is built on `mlx_lm.load`. It expects an MLX-format model
# directory (HuggingFace-style layout with config.json + model-*.safetensors +
# tokenizer files). It does NOT load single .gguf files: earlier attempts hit
# `HFValidationError` (the loader runs the input through HF repo-id validation
# at one stage). It also does NOT handle FP8-MoE safetensors: FP8 ships
# `weight_scale_inv` per-tensor scale params that MLX doesn't consume for MoE
# layers.
#
# The MLX-8bit model already in LM Studio's cache works out of the box.
# Same on-disk file, two providers — no duplicate download.

set -euo pipefail

VLLM="${VLLM:-$HOME/.venv-vllm-metal/bin/vllm}"
MODEL_DIR="$HOME/.lmstudio/models/lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-8bit"
PORT=8000

if [ ! -x "$VLLM" ]; then
    echo "error: vllm binary not found at $VLLM"
    exit 1
fi

if [ ! -d "$MODEL_DIR" ]; then
    echo "error: MLX model dir not found: $MODEL_DIR"
    echo "       (re-download via LM Studio or:"
    echo "        huggingface-cli download lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-8bit"
    echo "         --local-dir $MODEL_DIR)"
    exit 1
fi

# --tool-call-parser qwen3_coder enables Qwen3-Coder's native tool-call format;
# without it, vLLM returns HTTP 400 on any request with `tools` set.
# --enable-auto-tool-choice lets the model decide whether to call a tool.
# --enforce-eager disables torch.compile / CUDAGraphs (irrelevant on Metal but
# harmless; avoids a noisy warning).
#
# Memory note: vLLM-Metal loads the model into Metal-shared memory. Running it
# concurrently with the other GGUF-using providers (Ollama + Jan + LocalAI each
# at ~32 GB Metal) can OOM the GPU. Single-provider use is fine; in the
# smoke-test sweep, shut down the others before launching vLLM-Metal.
exec "$VLLM" serve "$MODEL_DIR" \
    --served-model-name qwen3-coder-30b-a3b-instruct \
    --port "$PORT" \
    --max-model-len 32768 \
    --enforce-eager \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder

# Verify after launch:
#   curl -s http://localhost:8000/v1/models | jq '.data[].id'
#   bash ../smoke-test.sh vllm
