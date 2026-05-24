#!/bin/bash
# Smoke-test a local provider's OpenAI-compatible endpoint along four axes:
#   1. Reachability — /v1/models returns 200 with at least one entry
#   2. Single completion — /v1/chat/completions returns a text response
#   3. Streaming     — /v1/chat/completions with stream=true emits SSE chunks
#   4. Tool call    — /v1/chat/completions with a tool defined emits tool_calls
#
# Usage:
#   bash smoke-test.sh <provider-id>
#   bash smoke-test.sh all
#
# provider-id ∈ {lmstudio, ollama, jan, localai, mistralrs, vllm, llamacpp}
#
# Each provider is probed against the baseURL that matches ProviderConfig's
# defaults — keep in sync with Merlin/Providers/ProviderConfig.swift.
#
# macOS bash 3.2 compatible — no associative arrays.

set -uo pipefail

# ---- color helpers ----
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
        mistralrs) echo "http://localhost:1235/v1" ;;   # rebound off :1234 to avoid LM Studio
        vllm)      echo "http://localhost:8000/v1" ;;
        llamacpp)  echo "http://localhost:8081/v1" ;;
        *)         echo "" ;;
    esac
}

# Parallel arrays for the summary so we don't need bash-4 maps.
SUMMARY_IDS=()
SUMMARY_RESULTS=()

probe_reachable() {
    local id="$1" url="$2"
    local status
    status=$(curl -sS -m 5 -o /tmp/smoke-models-"$id".json -w "%{http_code}" "$url/models" 2>/dev/null || echo "000")

    if [ "$status" != "200" ]; then
        printf "  reachable      ${R}FAIL${D} (HTTP %s)\n" "$status"
        return 1
    fi
    local count
    count=$(python3 -c "import json,sys; print(len(json.load(open('/tmp/smoke-models-$id.json')).get('data', [])))" 2>/dev/null || echo 0)
    if [ "$count" -eq 0 ]; then
        printf "  reachable      ${Y}WARN${D} (200 but 0 models loaded)\n"
        return 2
    fi
    local first_model
    first_model=$(python3 -c "import json; print(json.load(open('/tmp/smoke-models-$id.json'))['data'][0]['id'])")
    printf "  reachable      ${G}OK${D}   (models: %d; first: %s)\n" "$count" "$first_model"
    echo "$first_model" > /tmp/smoke-model-id-"$id"
    return 0
}

probe_completion() {
    local id="$1" url="$2"
    local model_id
    model_id=$(cat /tmp/smoke-model-id-"$id" 2>/dev/null || echo "")
    if [ -z "$model_id" ]; then
        printf "  completion     ${R}SKIP${D} (no model id from /models)\n"
        return 1
    fi
    local payload
    payload=$(cat <<EOF
{
  "model": "$model_id",
  "messages": [{"role": "user", "content": "Reply with the single word: pong"}],
  "max_tokens": 32,
  "temperature": 0
}
EOF
)
    local status
    status=$(curl -sS -m 90 -o /tmp/smoke-comp-"$id".json -w "%{http_code}" \
        -H 'Content-Type: application/json' \
        -d "$payload" "$url/chat/completions" 2>/dev/null || echo "000")

    if [ "$status" != "200" ]; then
        printf "  completion     ${R}FAIL${D} (HTTP %s)\n" "$status"
        return 1
    fi
    local content
    content=$(python3 -c "import json; d=json.load(open('/tmp/smoke-comp-$id.json')); print(d['choices'][0]['message']['content'][:60])" 2>/dev/null || echo "PARSE_ERROR")
    if [ "$content" = "PARSE_ERROR" ]; then
        printf "  completion     ${R}FAIL${D} (200 but response shape unexpected)\n"
        return 1
    fi
    printf "  completion     ${G}OK${D}   (\"%s\")\n" "$content"
    return 0
}

probe_streaming() {
    local id="$1" url="$2"
    local model_id
    model_id=$(cat /tmp/smoke-model-id-"$id" 2>/dev/null || echo "")
    if [ -z "$model_id" ]; then
        printf "  streaming      ${R}SKIP${D} (no model id)\n"
        return 1
    fi
    local payload
    payload=$(cat <<EOF
{
  "model": "$model_id",
  "messages": [{"role": "user", "content": "Count from 1 to 3."}],
  "max_tokens": 40,
  "temperature": 0,
  "stream": true
}
EOF
)
    local chunks
    chunks=$(curl -sS -m 60 -N \
        -H 'Content-Type: application/json' \
        -d "$payload" "$url/chat/completions" 2>/dev/null \
        | grep -c '^data: ' || echo 0)
    if [ "$chunks" -lt 2 ]; then
        printf "  streaming      ${R}FAIL${D} (%d SSE chunks; expected >= 2)\n" "$chunks"
        return 1
    fi
    printf "  streaming      ${G}OK${D}   (%d SSE chunks)\n" "$chunks"
    return 0
}

probe_tools() {
    local id="$1" url="$2"
    local model_id
    model_id=$(cat /tmp/smoke-model-id-"$id" 2>/dev/null || echo "")
    if [ -z "$model_id" ]; then
        printf "  tool call      ${R}SKIP${D} (no model id)\n"
        return 1
    fi
    # Forces a tool call by asking for current weather with a single tool defined.
    local payload
    payload=$(cat <<EOF
{
  "model": "$model_id",
  "messages": [{"role": "user", "content": "What is the weather in Tokyo right now? Use the tool."}],
  "tools": [{
    "type": "function",
    "function": {
      "name": "get_weather",
      "description": "Get current weather for a city",
      "parameters": {
        "type": "object",
        "properties": {"city": {"type": "string"}},
        "required": ["city"]
      }
    }
  }],
  "tool_choice": "auto",
  "max_tokens": 128,
  "temperature": 0
}
EOF
)
    local status
    status=$(curl -sS -m 90 -o /tmp/smoke-tool-"$id".json -w "%{http_code}" \
        -H 'Content-Type: application/json' \
        -d "$payload" "$url/chat/completions" 2>/dev/null || echo "000")
    if [ "$status" != "200" ]; then
        printf "  tool call      ${R}FAIL${D} (HTTP %s — does the provider support 'tools' parameter?)\n" "$status"
        return 1
    fi
    local has_tool_calls
    has_tool_calls=$(python3 -c "
import json
d = json.load(open('/tmp/smoke-tool-$id.json'))
choice = d['choices'][0]
msg = choice.get('message', {})
print('YES' if msg.get('tool_calls') else 'NO')
" 2>/dev/null || echo "PARSE_ERROR")
    case "$has_tool_calls" in
        YES) printf "  tool call      ${G}OK${D}   (tool_calls present in response)\n"; return 0 ;;
        NO)  printf "  tool call      ${Y}WARN${D} (200 but no tool_calls — model didn't call the tool; format may still work)\n"; return 2 ;;
        *)   printf "  tool call      ${R}FAIL${D} (response shape unexpected)\n"; return 1 ;;
    esac
}

run_provider() {
    local id="$1"
    local url
    url=$(base_url_for "$id")
    if [ -z "$url" ]; then
        printf "${R}Unknown provider: %s${D}\n" "$id"
        SUMMARY_IDS+=("$id")
        SUMMARY_RESULTS+=("UNKNOWN")
        return 1
    fi
    printf "${G}== %s ==${D} (%s)\n" "$id" "$url"
    local fails=0
    probe_reachable "$id" "$url" || fails=$((fails + 1))
    if [ "$fails" -eq 0 ]; then
        probe_completion "$id" "$url" || fails=$((fails + 1))
        probe_streaming  "$id" "$url" || fails=$((fails + 1))
        probe_tools      "$id" "$url" || fails=$((fails + 1))
    fi
    SUMMARY_IDS+=("$id")
    if [ "$fails" -eq 0 ]; then
        SUMMARY_RESULTS+=("PASS")
    else
        SUMMARY_RESULTS+=("FAIL ($fails)")
    fi
    echo
}

main() {
    local target="${1:-all}"
    if [ "$target" = "all" ]; then
        # localai is the Homebrew-native install (`brew install localai`), which uses
        # Metal directly. The previous Docker-on-Mac version was CPU-only and skipped
        # here; the native swap restored it to first-class status.
        for id in lmstudio ollama jan localai mistralrs vllm llamacpp; do
            run_provider "$id"
        done
    else
        run_provider "$target"
    fi

    printf "${G}== Summary ==${D}\n"
    local i=0
    while [ "$i" -lt "${#SUMMARY_IDS[@]}" ]; do
        printf "  %-12s %s\n" "${SUMMARY_IDS[$i]}" "${SUMMARY_RESULTS[$i]}"
        i=$((i + 1))
    done
}

main "$@"
