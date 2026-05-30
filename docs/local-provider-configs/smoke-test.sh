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
UNSUPPORTED_PROVIDER_MODEL_GAP=0

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
    if [ "$id" = "llamacpp" ]; then
        select_llamacpp_models "$id" || return 1
        return 0
    fi
    select_text_model "$id" || return 1
    return 0
}

select_text_model() {
    local id="$1"
    local model_id=""
    local env_name
    env_name=$(text_model_env_var_for "$id")
    if [ -n "$env_name" ]; then
        eval "model_id=\${$env_name:-}"
    fi

    if [ -z "$model_id" ]; then
        model_id=$(python3 -c "
import json
import sys

provider = sys.argv[1]
data = json.load(open('/tmp/smoke-models-' + provider + '.json')).get('data', [])
ids = [str(item.get('id', '')) for item in data if str(item.get('id', ''))]
preferred_by_provider = {
    'lmstudio': ['qwen3-coder-local', 'qwen3-coder-30b-a3b-instruct-mlx'],
    'ollama': ['qwen3-coder-30b-a3b-instruct:latest', 'qwen3-coder:latest'],
    'jan': ['Qwen3-Coder-30B-A3B-Instruct-Q8_0', 'qwen3-coder-local', 'qwen3-coder-30b-a3b-instruct-q8_0'],
    'localai': ['qwen3-coder-local', 'qwen3-coder-30b-a3b-instruct'],
    'mistralrs': ['Qwen/Qwen3-Coder-30B-A3B-Instruct', 'qwen3-coder-local', 'qwen3-coder-30b-a3b-instruct'],
    'vllm': ['qwen3-coder-local', 'qwen3-coder-30b-a3b-instruct'],
}
for candidate in preferred_by_provider.get(provider, []):
    if candidate in ids:
        print(candidate)
        raise SystemExit
for candidate in ids:
    low = candidate.lower()
    if candidate != 'default' and 'coder' in low and 'vl' not in low and 'vision' not in low:
        print(candidate)
        raise SystemExit
for candidate in ids:
    low = candidate.lower()
    if candidate != 'default' and 'vl' not in low and 'vision' not in low:
        print(candidate)
        raise SystemExit
for candidate in ids:
    if candidate != 'default':
        print(candidate)
        raise SystemExit
" "$id" 2>/dev/null)
    fi

    validate_catalog_model "$id" "$model_id" "text" || return 1
    echo "$model_id" > /tmp/smoke-model-id-"$id"
    printf "  text model:    ${G}%s${D}\n" "$model_id"
    return 0
}

text_model_env_var_for() {
    case "$1" in
        lmstudio)  echo "LMSTUDIO_TEXT_MODEL" ;;
        ollama)    echo "OLLAMA_TEXT_MODEL" ;;
        jan)       echo "JAN_TEXT_MODEL" ;;
        localai)   echo "LOCALAI_TEXT_MODEL" ;;
        mistralrs) echo "MISTRALRS_TEXT_MODEL" ;;
        vllm)      echo "VLLM_TEXT_MODEL" ;;
        *)         echo "" ;;
    esac
}

vision_model_env_var_for() {
    case "$1" in
        jan)      echo "JAN_VISION_MODEL" ;;
        localai)  echo "LOCALAI_VISION_MODEL" ;;
        llamacpp) echo "LLAMACPP_VISION_MODEL" ;;
        *)        echo "" ;;
    esac
}

select_vision_model() {
    local id="$1"
    local model_id=""
    local env_name
    env_name=$(vision_model_env_var_for "$id")
    if [ -n "$env_name" ]; then
        eval "model_id=\${$env_name:-}"
    fi

    if [ -z "$model_id" ]; then
        model_id=$(python3 -c "
import json
import sys

provider = sys.argv[1]
data = json.load(open('/tmp/smoke-models-' + provider + '.json')).get('data', [])
ids = [str(item.get('id', '')) for item in data if str(item.get('id', ''))]
preferred_by_provider = {
    'jan': ['qwen3-vl-8b-instruct', 'qwen_qwen3-vl-8b-instruct-q8_0', 'Qwen_Qwen3-VL-8B-Instruct-Q8_0'],
    'localai': ['qwen3-vl-8b-instruct', 'qwen_qwen3-vl-8b-instruct-q8_0', 'Qwen_Qwen3-VL-8B-Instruct-Q8_0'],
    'llamacpp': ['qwen3-vl-local', 'qwen_qwen3-vl-8b-instruct-q8_0', 'Qwen_Qwen3-VL-8B-Instruct-Q8_0'],
}
for candidate in preferred_by_provider.get(provider, []):
    if candidate in ids:
        print(candidate)
        raise SystemExit
for candidate in ids:
    low = candidate.lower()
    if candidate != 'default' and ('vl' in low or 'vision' in low):
        print(candidate)
        raise SystemExit
" "$id" 2>/dev/null)
    fi

    validate_catalog_model "$id" "$model_id" "vision" || return 1
    echo "$model_id" > /tmp/smoke-vision-model-id-"$id"
    printf "  vision model:  ${G}%s${D}\n" "$model_id"
    return 0
}

select_llamacpp_models() {
    local id="$1"
    local text_model="${LLAMACPP_TEXT_MODEL:-}"
    local vision_model="${LLAMACPP_VISION_MODEL:-}"

    if [ -z "$text_model" ]; then
        text_model=$(python3 -c "
import json
data = json.load(open('/tmp/smoke-models-$id.json')).get('data', [])
ids = [str(item.get('id', '')) for item in data]
preferred = [
    'qwen3-coder-local',
    'qwen3-coder-30b-a3b-instruct-q8_0',
    'Qwen3-Coder-30B-A3B-Instruct-Q8_0',
]
for model_id in preferred:
    if model_id in ids:
        print(model_id)
        raise SystemExit
for model_id in ids:
    low = model_id.lower()
    if model_id != 'default' and 'coder' in low:
        print(model_id)
        raise SystemExit
for model_id in ids:
    model_id = str(model_id)
    low = model_id.lower()
    if model_id != 'default' and 'vl' not in low and 'vision' not in low:
        print(model_id)
        raise SystemExit
" 2>/dev/null)
    fi

    if [ -z "$vision_model" ]; then
        vision_model=$(python3 -c "
import json
data = json.load(open('/tmp/smoke-models-$id.json')).get('data', [])
ids = [str(item.get('id', '')) for item in data]
preferred = [
    'qwen3-vl-local',
    'qwen_qwen3-vl-8b-instruct-q8_0',
    'Qwen_Qwen3-VL-8B-Instruct-Q8_0',
]
for model_id in preferred:
    if model_id in ids:
        print(model_id)
        raise SystemExit
for model_id in ids:
    low = model_id.lower()
    if model_id != 'default' and ('vl' in low or 'vision' in low):
        print(model_id)
        raise SystemExit
" 2>/dev/null)
    fi

    validate_catalog_model "$id" "$text_model" "text" || return 1
    validate_catalog_model "$id" "$vision_model" "vision" || return 1

    echo "$text_model" > /tmp/smoke-model-id-"$id"
    echo "$vision_model" > /tmp/smoke-vision-model-id-"$id"
    printf "  text model:    ${G}%s${D}\n" "$text_model"
    printf "  vision model:  ${G}%s${D}\n" "$vision_model"
    return 0
}

validate_catalog_model() {
    local id="$1" model_id="$2" kind="$3"
    if [ -z "$model_id" ]; then
        if [ "$id" = "llamacpp" ]; then
            printf "  %s model:    ${R}FAIL${D} (llama.cpp router catalog exposed only default or no %s-capable model)\n" "$kind" "$kind"
        else
            printf "  %s model:    ${R}FAIL${D} (no non-default model found in provider catalog)\n" "$kind"
        fi
        cat /tmp/smoke-models-"$id".json
        printf "\n"
        return 1
    fi
    if [ "$model_id" = "default" ]; then
        printf "  %s model:    ${R}FAIL${D} (model_id = 'default' is not valid for llama.cpp router smoke)\n" "$kind"
        return 1
    fi
    if ! python3 -c "
import json, sys
model = sys.argv[1]
data = json.load(open('/tmp/smoke-models-$id.json')).get('data', [])
raise SystemExit(0 if any(str(item.get('id', '')) == model for item in data) else 1)
" "$model_id" 2>/dev/null; then
        printf "  %s model:    ${R}FAIL${D} (%s not present in provider catalog)\n" "$kind" "$model_id"
        cat /tmp/smoke-models-"$id".json
        printf "\n"
        return 1
    fi
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
        if [ "${SMOKE_ALLOW_PROVIDER_MODEL_GAP:-0}" = "1" ] && [ "$id" = "mistralrs" ] && [ "$status" = "500" ]; then
            UNSUPPORTED_PROVIDER_MODEL_GAP=1
            printf "  completion     ${Y}UNSUPPORTED${D} (HTTP 500 from provider/model combination)\n"
            return 2
        fi
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
    local stream_file="/tmp/smoke-stream-$id.txt"
    if ! curl -sS -m 60 -N \
        -H 'Content-Type: application/json' \
        -d "$payload" "$url/chat/completions" > "$stream_file" 2>/dev/null; then
        printf "  streaming      ${R}FAIL${D} (request failed)\n"
        return 1
    fi
    local chunks
    chunks=$(grep -c '^data: ' "$stream_file" 2>/dev/null || true)
    case "$chunks" in
        ''|*[!0-9]*) chunks=0 ;;
    esac
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

probe_vision() {
    local id="$1" url="$2"
    case "$id" in
        jan|localai|llamacpp) ;;
        *) return 0 ;;
    esac
    local model_id
    model_id=$(cat /tmp/smoke-vision-model-id-"$id" 2>/dev/null || echo "")
    if [ -z "$model_id" ]; then
        if [ "${SMOKE_REQUIRE_VISION:-0}" != "1" ] && [ "$id" = "jan" ]; then
            printf "  vision         ${Y}SKIP${D} (Jan text smoke uses a separate vision server lifecycle)\n"
            return 0
        fi
        if select_vision_model "$id"; then
            model_id=$(cat /tmp/smoke-vision-model-id-"$id" 2>/dev/null || echo "")
        else
            if [ "${SMOKE_REQUIRE_VISION:-0}" = "1" ] || [ "$id" = "llamacpp" ]; then
                printf "  vision         ${R}SKIP${D} (no vision model id)\n"
                return 1
            fi
            printf "  vision         ${Y}SKIP${D} (no vision model id)\n"
            return 0
        fi
    fi
    local payload
    payload=$(cat <<EOF
{
  "model": "$model_id",
  "messages": [{
    "role": "user",
    "content": [
      {"type": "text", "text": "Reply with the single word: vision"},
      {"type": "image_url", "image_url": {"url": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="}}
    ]
  }],
  "max_tokens": 32,
  "temperature": 0
}
EOF
)
    local status
    status=$(curl -sS -m 120 -o /tmp/smoke-vision-"$id".json -w "%{http_code}" \
        -H 'Content-Type: application/json' \
        -d "$payload" "$url/chat/completions" 2>/dev/null || echo "000")
    if [ "$status" != "200" ]; then
        printf "  vision         ${R}FAIL${D} (HTTP %s; model %s)\n" "$status" "$model_id"
        return 1
    fi
    printf "  vision         ${G}OK${D}   (model %s)\n" "$model_id"
    return 0
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
    rm -f /tmp/smoke-model-id-"$id" /tmp/smoke-vision-model-id-"$id"
    printf "${G}== %s ==${D} (%s)\n" "$id" "$url"
    local fails=0
    local unsupported=0
    probe_reachable "$id" "$url" || fails=$((fails + 1))
    if [ "$fails" -eq 0 ]; then
        if [ "${SMOKE_ONLY_VISION:-0}" = "1" ]; then
            select_vision_model "$id" || fails=$((fails + 1))
            if [ "$fails" -eq 0 ]; then
                probe_vision "$id" "$url" || fails=$((fails + 1))
            fi
        else
            probe_completion "$id" "$url"
            local completion_status=$?
            if [ "$completion_status" -eq 2 ] && [ "$UNSUPPORTED_PROVIDER_MODEL_GAP" -eq 1 ]; then
                unsupported=1
            elif [ "$completion_status" -ne 0 ]; then
                fails=$((fails + 1))
            fi
            if [ "$unsupported" -eq 0 ]; then
                probe_streaming  "$id" "$url" || fails=$((fails + 1))
                probe_tools      "$id" "$url" || fails=$((fails + 1))
                probe_vision     "$id" "$url" || fails=$((fails + 1))
            else
                printf "  streaming      ${Y}SKIP${D} (provider/model unsupported)\n"
                printf "  tool call      ${Y}SKIP${D} (provider/model unsupported)\n"
                printf "  vision         ${Y}SKIP${D} (provider/model unsupported)\n"
            fi
        fi
    fi
    SUMMARY_IDS+=("$id")
    if [ "$unsupported" -eq 1 ]; then
        SUMMARY_RESULTS+=("UNSUPPORTED")
        echo
        return 77
    elif [ "$fails" -eq 0 ]; then
        SUMMARY_RESULTS+=("PASS")
        echo
        return 0
    else
        SUMMARY_RESULTS+=("FAIL ($fails)")
        echo
        return 1
    fi
}

main() {
    local target="${1:-all}"
    local failed=0
    local unsupported=0
    if [ "$target" = "all" ]; then
        # localai is the Homebrew-native install (`brew install localai`), which uses
        # Metal directly. The previous Docker-on-Mac version was CPU-only and skipped
        # here; the native swap restored it to first-class status.
        for id in lmstudio ollama jan localai mistralrs vllm llamacpp; do
            run_provider "$id"
            local provider_status=$?
            if [ "$provider_status" -eq 77 ]; then
                unsupported=1
            elif [ "$provider_status" -ne 0 ]; then
                failed=1
            fi
        done
    else
        run_provider "$target"
        local provider_status=$?
        if [ "$provider_status" -eq 77 ]; then
            unsupported=1
        elif [ "$provider_status" -ne 0 ]; then
            failed=1
        fi
    fi

    printf "${G}== Summary ==${D}\n"
    local i=0
    while [ "$i" -lt "${#SUMMARY_IDS[@]}" ]; do
        printf "  %-12s %s\n" "${SUMMARY_IDS[$i]}" "${SUMMARY_RESULTS[$i]}"
        i=$((i + 1))
    done
    if [ "$failed" -ne 0 ]; then
        return 1
    fi
    if [ "$unsupported" -ne 0 ]; then
        return 77
    fi
    return 0
}

main "$@"
