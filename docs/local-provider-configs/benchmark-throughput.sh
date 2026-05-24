#!/bin/bash
# Measure raw generation throughput (tokens/sec) per provider.
#
# Not a substitute for `/calibrate` — this only measures speed, not output
# quality. Use `/calibrate` from inside Merlin for quality-scored numbers.
#
# Usage:
#   bash benchmark-throughput.sh <provider-id>
#   bash benchmark-throughput.sh all
#
# Each provider gets the same prompt and max_tokens=200; we time the request
# wall-clock and divide by completion_tokens reported by the server. Three
# warm runs per provider; the first is discarded (cache effects); the median
# of the remaining two is the recorded value.
#
# macOS bash 3.2 compatible. No associative arrays.

set -uo pipefail

if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    G=$(tput setaf 2); R=$(tput setaf 1); Y=$(tput setaf 3); D=$(tput sgr0)
else
    G=""; R=""; Y=""; D=""
fi

base_url_for() {
    case "$1" in
        lmstudio)  echo "http://localhost:1234/v1" ;;
        ollama)    echo "http://localhost:11434/v1" ;;
        jan)       echo "http://localhost:1337/v1" ;;
        localai)   echo "http://localhost:8080/v1" ;;
        mistralrs) echo "http://localhost:1235/v1" ;;
        vllm)      echo "http://localhost:8000/v1" ;;
        llamacpp)  echo "http://localhost:8081/v1" ;;
        *)         echo "" ;;
    esac
}

# A prompt that elicits ~150-200 tokens of code-style output without being
# wildly off-distribution for a coder model.
PROMPT='Write a Python function that computes the nth Fibonacci number iteratively. Include a brief docstring. Just the function body — no commentary.'
MAX_TOKENS=200

bench_one_request() {
    local id="$1" url="$2" model_id="$3"
    local payload
    payload=$(cat <<EOF
{
  "model": "$model_id",
  "messages": [{"role": "user", "content": "$PROMPT"}],
  "max_tokens": $MAX_TOKENS,
  "temperature": 0
}
EOF
)
    local t_start t_end
    t_start=$(python3 -c 'import time; print(time.time())')
    local response
    response=$(curl -sS -m 180 -X POST \
        -H 'Content-Type: application/json' \
        -d "$payload" "$url/chat/completions" 2>/dev/null)
    t_end=$(python3 -c 'import time; print(time.time())')

    # Extract completion_tokens from response.
    local tokens
    tokens=$(echo "$response" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('usage', {}).get('completion_tokens', 0))
except Exception:
    print(0)
" 2>/dev/null)

    if [ -z "$tokens" ] || [ "$tokens" -le 0 ]; then
        echo "FAIL"
        return
    fi

    local elapsed
    elapsed=$(python3 -c "print(round(($t_end - $t_start), 3))")
    local tps
    tps=$(python3 -c "print(round($tokens / max(($t_end - $t_start), 0.001), 1))")
    echo "$tokens tokens in ${elapsed}s = ${tps} tok/s"
}

bench_provider() {
    local id="$1"
    local url
    url=$(base_url_for "$id")
    if [ -z "$url" ]; then
        printf "${R}Unknown provider: %s${D}\n" "$id"
        return
    fi
    printf "${G}== %s ==${D} (%s)\n" "$id" "$url"

    # Get the actual model id reported by /v1/models so we send the right name.
    local models_resp
    models_resp=$(curl -sS -m 5 "$url/models" 2>/dev/null)
    local model_id
    model_id=$(echo "$models_resp" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    data = d.get('data', [])
    print(data[0]['id'] if data else '')
except Exception:
    print('')
" 2>/dev/null)
    if [ -z "$model_id" ]; then
        printf "  ${R}no model from /v1/models — provider likely not running${D}\n\n"
        return
    fi
    printf "  model: %s\n" "$model_id"

    printf "  warm:   "; bench_one_request "$id" "$url" "$model_id"
    printf "  run 1:  "; bench_one_request "$id" "$url" "$model_id"
    printf "  run 2:  "; bench_one_request "$id" "$url" "$model_id"
    echo
}

main() {
    local target="${1:-all}"
    if [ "$target" = "all" ]; then
        # NOTE: each provider holds ~32 GB Metal at idle; on a 128 GB M4 you
        # can't run all five simultaneously. The script doesn't manage that —
        # the caller is responsible for ensuring only the targeted provider's
        # daemon is up before each call.
        for id in lmstudio ollama jan localai mistralrs vllm llamacpp; do
            bench_provider "$id"
        done
    else
        bench_provider "$target"
    fi
}

main "$@"
