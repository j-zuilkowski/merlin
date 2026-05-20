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
MODEL="$HOME/Models/gguf/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf"
PORT=1235

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
exec "$MISTRALRS" serve \
    -p "$PORT" \
    --model-id Qwen/Qwen3-Coder-30B-A3B-Instruct \
    --format gguf \
    --quantized-file "$MODEL"

# Verify after launch (in another shell):
#   curl -s http://localhost:1235/v1/models | jq '.data[].id'
#   curl -s http://localhost:1235/v1/chat/completions \
#     -H 'Content-Type: application/json' \
#     -d '{"model":"qwen3-coder-30b-a3b-instruct","messages":[{"role":"user","content":"ping"}]}'
