#!/bin/bash
# LocalAI (native macOS) launch — Qwen3-Coder-30B-A3B-Instruct Q8_0
#
# This launches the Homebrew-installed `local-ai` binary with Metal acceleration.
# Docker is NOT used — Docker Desktop's Linux VM on macOS cannot reach the GPU,
# which made the original Docker LocalAI run CPU-only at ~1-3 tok/s. The native
# binary uses llama.cpp's Metal backend directly.
#
# Prereqs:
#   1. brew install localai             (installs to /opt/homebrew/bin/local-ai)
#   2. mkdir -p ~/.localai/{models,backends}
#   3. ln -sf ~/Models/gguf/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf \
#            ~/.localai/models/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf
#   4. cp ./qwen3-coder-30b-a3b-instruct.yaml ~/.localai/models/
#   5. LOCALAI_BACKENDS_PATH=~/.localai/backends \
#         local-ai backends install localai@metal-llama-cpp
#
# Verify with smoke-test.sh after launch:
#   bash ../smoke-test.sh localai

set -euo pipefail

LOCALAI_BIN="${LOCALAI_BIN:-/opt/homebrew/bin/local-ai}"
MODELS_DIR="${LOCALAI_MODELS_PATH:-$HOME/.localai/models}"
BACKENDS_DIR="${LOCALAI_BACKENDS_PATH:-$HOME/.localai/backends}"
PORT=8080

if [ ! -x "$LOCALAI_BIN" ]; then
    echo "error: local-ai binary not found at $LOCALAI_BIN"
    echo "       install: brew install localai"
    exit 1
fi

if [ ! -d "$MODELS_DIR" ]; then
    echo "error: models dir missing: $MODELS_DIR (see prereqs in this script)"
    exit 1
fi

if [ ! -d "$BACKENDS_DIR/metal-llama-cpp" ]; then
    echo "error: metal-llama-cpp backend missing at $BACKENDS_DIR/metal-llama-cpp"
    echo "       install: LOCALAI_BACKENDS_PATH=$BACKENDS_DIR local-ai backends install localai@metal-llama-cpp"
    exit 1
fi

LOCALAI_BACKENDS_PATH="$BACKENDS_DIR" \
LOCALAI_MODELS_PATH="$MODELS_DIR" \
exec "$LOCALAI_BIN" run \
    --backends-path "$BACKENDS_DIR" \
    --models-path "$MODELS_DIR" \
    --address ":$PORT" \
    --context-size 32768 \
    --f16
