#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
EVIDENCE_ROOT="$ROOT/docs/e2e/2026-05-26-merlin-full-gui"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="${MERLIN_E2E_RUN_DIR:-$EVIDENCE_ROOT/rerun-full-$STAMP}"
CONFIG="$HOME/.merlin/config.toml"
PROVIDERS="$HOME/Library/Application Support/Merlin/providers.json"
BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/merlin-e2e-backups.XXXXXX")"
CONFIG_BAK="$BACKUP_DIR/config.toml.bak"
PROVIDERS_BAK="$BACKUP_DIR/providers.json.bak"

LMSTUDIO_TEXT_MODEL="${LMSTUDIO_TEXT_MODEL:-qwen3-coder-30b-a3b-instruct-mlx}"
LMSTUDIO_VISION_MODEL="${LMSTUDIO_VISION_MODEL:-qwen/qwen3-vl-8b}"
OLLAMA_TEXT_MODEL="${OLLAMA_TEXT_MODEL:-qwen3-coder-30b-a3b-instruct:latest}"
LLAMACPP_TEXT_MODEL="${LLAMACPP_TEXT_MODEL:-qwen3-coder-local}"
LLAMACPP_VISION_MODEL="${LLAMACPP_VISION_MODEL:-qwen3-vl-local}"
LLAMACPP_PRESET="${LLAMACPP_PRESET:-$EVIDENCE_ROOT/llamacpp-router-models.ini}"
JAN_TEXT_MODEL="${JAN_TEXT_MODEL:-Qwen3-Coder-30B-A3B-Instruct-Q8_0}"
JAN_CLI="${JAN_CLI:-/Applications/Jan.app/Contents/MacOS/jan-cli}"
LOCALAI_TEXT_MODEL="${LOCALAI_TEXT_MODEL:-qwen3-coder-30b-a3b-instruct}"
LOCALAI_VISION_MODEL="${LOCALAI_VISION_MODEL:-qwen3-vl-8b-instruct}"
LOCALAI_LAUNCH="${LOCALAI_LAUNCH:-$ROOT/docs/local-provider-configs/localai/launch-native.sh}"
MISTRALRS_TEXT_MODEL="${MISTRALRS_TEXT_MODEL:-Qwen/Qwen3-Coder-30B-A3B-Instruct}"
MISTRALRS_LAUNCH="${MISTRALRS_LAUNCH:-$ROOT/docs/local-provider-configs/mistralrs/launch-qwen3-coder.sh}"
VLLM_TEXT_MODEL="${VLLM_TEXT_MODEL:-qwen3-coder-30b-a3b-instruct}"
VLLM_LAUNCH="${VLLM_LAUNCH:-$ROOT/docs/local-provider-configs/vllm-metal/launch-qwen3-coder.sh}"
VLLM_MAX_MODEL_LEN="${VLLM_MAX_MODEL_LEN:-8192}"
VLLM_MAX_NUM_BATCHED_TOKENS="${VLLM_MAX_NUM_BATCHED_TOKENS:-2048}"
VLLM_METAL_MEMORY_FRACTION="${VLLM_METAL_MEMORY_FRACTION:-0.45}"
GGUF_TEXT_MODEL="${GGUF_TEXT_MODEL:-$HOME/Models/gguf/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf}"
GGUF_VISION_MODEL="${GGUF_VISION_MODEL:-$HOME/Models/gguf/Qwen_Qwen3-VL-8B-Instruct-Q8_0.gguf}"
GGUF_MMPROJ="${GGUF_MMPROJ:-$HOME/Models/gguf/mmproj-Qwen_Qwen3-VL-8B-Instruct-f16.gguf}"
XCODE_DESTINATION="${XCODE_DESTINATION:-platform=macOS,arch=arm64}"
XCODE_PREFLIGHT_TIMEOUT="${XCODE_PREFLIGHT_TIMEOUT:-300}"
XCODE_CORE_TIMEOUT="${XCODE_CORE_TIMEOUT:-1800}"
XCODE_GUI_TIMEOUT="${XCODE_GUI_TIMEOUT:-1200}"
XCODE_LIVE_TIMEOUT="${XCODE_LIVE_TIMEOUT:-1200}"
XCODE_AGENTIC_TIMEOUT="${XCODE_AGENTIC_TIMEOUT:-1800}"
XCODE_CAPABILITY_TIMEOUT="${XCODE_CAPABILITY_TIMEOUT:-2400}"

FULL_BATTERY_GREEN=0
RUNNER_OWNED_PIDS=()
FAILURES=()
SKIPS=()

mkdir -p "$RUN_DIR/logs"

record_owned_pid() {
  RUNNER_OWNED_PIDS+=("$1")
}

port_is_listening() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

wait_http() {
  local url="$1" timeout="$2" log="$3"
  local i
  for ((i = 1; i <= timeout; i++)); do
    if curl -fsS --max-time 2 "$url" > "$log" 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

stop_port_listener() {
  local port="$1"
  local pids pid
  pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  for pid in $pids; do
    kill "$pid" 2>/dev/null || true
  done
  sleep 1
  pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  for pid in $pids; do
    kill -9 "$pid" 2>/dev/null || true
  done
}

stop_owned_pids() {
  local pid
  set +u
  for pid in "${RUNNER_OWNED_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  set -u
}

stop_lmstudio() {
  if command -v lms >/dev/null 2>&1; then
    lms unload --all >/dev/null 2>&1 || true
    lms server stop >/dev/null 2>&1 || true
  fi
}

stop_ollama() {
  osascript -e 'tell application "Ollama" to quit' >/dev/null 2>&1 || true
  pkill -TERM -x ollama >/dev/null 2>&1 || true
  sleep 1
  stop_port_listener 11434
}

stop_test_apps() {
  pkill -TERM -x Merlin >/dev/null 2>&1 || true
  pkill -TERM -x MerlinUITests-Runner >/dev/null 2>&1 || true
  pkill -TERM -x TaskBoard >/dev/null 2>&1 || true
}

remove_red_battery_artifacts() {
  if [[ "$FULL_BATTERY_GREEN" != "1" ]]; then
    rm -rf "$RUN_DIR/screenshots" "$RUN_DIR/xcalibre-work"
    find "$RUN_DIR" -maxdepth 1 \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) -delete 2>/dev/null || true
  fi
}

cleanup() {
  set +e
  trap - EXIT INT TERM
  stop_test_apps
  stop_lmstudio
  stop_owned_pids
  if [[ -f "$CONFIG_BAK" ]]; then cp "$CONFIG_BAK" "$CONFIG"; fi
  if [[ -f "$PROVIDERS_BAK" ]]; then cp "$PROVIDERS_BAK" "$PROVIDERS"; fi
  remove_red_battery_artifacts
  rm -rf "$BACKUP_DIR"
  echo "cleanup summary: stopped ${#RUNNER_OWNED_PIDS[@]} owned process(es); restored config/providers when backups existed; full_green=$FULL_BATTERY_GREEN"
}
trap cleanup EXIT INT TERM

slug() {
  printf "%s" "$1" | tr '[:upper:] /:' '[:lower:]---' | tr -cd '[:alnum:]_.-'
}

run_step() {
  local name="$1"; shift
  local log="$RUN_DIR/logs/$(slug "$name").log"
  echo "== $name =="
  set +e
  "$@" > "$log" 2>&1
  local status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    if [[ "$name" == "gui automation live" ]] && grep -q "Test skipped" "$log"; then
      echo "FAIL $name (tests skipped; log $log)"
      tail -n 80 "$log" || true
      FAILURES+=("$name")
      return 1
    fi
    echo "PASS $name"
    return 0
  else
    echo "FAIL $name (exit $status; log $log)"
    tail -n 80 "$log" || true
    FAILURES+=("$name")
    return "$status"
  fi
}

run_step_timeout() {
  local name="$1" timeout="$2"; shift 2
  local log="$RUN_DIR/logs/$(slug "$name").log"
  local pid status=""
  echo "== $name =="
  set +e
  "$@" > "$log" 2>&1 &
  pid=$!
  local deadline=$((SECONDS + timeout))
  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      capture_timeout_diagnostics "$name" "$pid" "$log"
      pkill -TERM -P "$pid" 2>/dev/null || true
      kill "$pid" 2>/dev/null || true
      sleep 2
      pkill -KILL -P "$pid" 2>/dev/null || true
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null
      status=124
      break
    fi
    sleep 2
  done
  if [[ -z "$status" ]]; then
    wait "$pid"
    status=$?
  fi
  set -e
  if [[ "$status" -eq 0 ]]; then
    if [[ "$name" == "gui automation live" ]] && grep -q "Test skipped" "$log"; then
      echo "FAIL $name (tests skipped; log $log)"
      tail -n 80 "$log" || true
      FAILURES+=("$name")
      return 1
    fi
    echo "PASS $name"
    return 0
  fi
  echo "FAIL $name (exit $status; log $log)"
  tail -n 80 "$log" || true
  FAILURES+=("$name")
  return "$status"
}

capture_timeout_diagnostics() {
  local name="$1" parent_pid="$2" log="$3"
  local diag="$RUN_DIR/logs/$(slug "$name")-timeout-diagnostics.log"
  {
    echo "== timeout diagnostics for $name =="
    date
    echo
    echo "== process tree candidates =="
    ps ax -o pid,ppid,stat,etime,comm,args | grep -E 'xcodebuild|XCTest|xctest|MerlinUITests|Build/Products/Debug/Merlin.app|TaskBoard.app|llama-server|mistralrs|vllm|local-ai|ollama serve|jan' | grep -v grep || true
    echo
    echo "== child processes of $parent_pid =="
    ps -o pid,ppid,stat,etime,comm,args -p "$parent_pid" 2>/dev/null || true
    pgrep -P "$parent_pid" | while read -r child; do
      ps -o pid,ppid,stat,etime,comm,args -p "$child" 2>/dev/null || true
    done
  } >> "$diag" 2>&1

  ps ax -o pid=,args= \
    | grep 'Build/Products/Debug/Merlin.app/Contents/MacOS/Merlin' \
    | grep -v grep \
    | while read -r app_pid _; do
    local sample_file="$RUN_DIR/logs/$(slug "$name")-merlin-$app_pid.sample"
    sample "$app_pid" 3 -file "$sample_file" >/dev/null 2>&1 || true
    {
      echo
      echo "== Merlin host sample $app_pid =="
      grep -n -E 'XCTestDriver|_prepareTestConfigurationAndIDESession|XCTFuture|XCTWaiter|RunTestsFromRunLoop' "$sample_file" | head -n 40 || true
    } >> "$diag" 2>&1
  done

  {
    echo
    echo "Timeout diagnostics: $diag"
  } >> "$log" 2>&1
}

run_shell_step() {
  local name="$1" command="$2"
  run_step "$name" /bin/zsh -lc "cd '$ROOT' && $command"
}

run_shell_step_timeout() {
  local name="$1" timeout="$2" command="$3"
  run_step_timeout "$name" "$timeout" /bin/zsh -lc "cd '$ROOT' && $command"
}

run_xcode_step_timeout() {
  local name="$1" timeout="$2" command="$3"
  stop_test_apps
  run_shell_step_timeout "$name" "$timeout" "$command"
}

run_shell_step_allow_unsupported() {
  local name="$1" command="$2"
  local log="$RUN_DIR/logs/$(slug "$name").log"
  echo "== $name =="
  set +e
  /bin/zsh -lc "cd '$ROOT' && $command" > "$log" 2>&1
  local status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "PASS $name"
    return 0
  fi
  if [[ "$status" -eq 77 ]]; then
    echo "SKIP $name - provider/model unsupported (log $log)"
    tail -n 80 "$log" || true
    SKIPS+=("$name: provider/model unsupported")
    return 0
  fi
  echo "FAIL $name (exit $status; log $log)"
  tail -n 80 "$log" || true
  FAILURES+=("$name")
  return "$status"
}

skip_step() {
  local name="$1" reason="$2"
  echo "SKIP $name - $reason"
  SKIPS+=("$name: $reason")
}

backup_user_config() {
  [[ -f "$CONFIG" ]] && cp "$CONFIG" "$CONFIG_BAK"
  [[ -f "$PROVIDERS" ]] && cp "$PROVIDERS" "$PROVIDERS_BAK"
}

restore_user_config() {
  [[ -f "$CONFIG_BAK" ]] && cp "$CONFIG_BAK" "$CONFIG"
  [[ -f "$PROVIDERS_BAK" ]] && cp "$PROVIDERS_BAK" "$PROVIDERS"
}

write_lmstudio_config() {
  local kag_enabled="${1:-false}"
  local kag_url="${2:-}"
  cat > "$CONFIG" <<EOF
auto_compact = false
max_tokens = 32768
keep_awake = false
provider_name = "lmstudio"
model_id = "$LMSTUDIO_TEXT_MODEL"
default_permission_mode = "autoAccept"
notifications_enabled = true
message_density = "comfortable"
max_subagent_threads = 4
max_subagent_depth = 2
xcalibre_token = ""

[memory]
backend_id = "local-vector"

[kag]
enabled = $kag_enabled
EOF
  if [[ -n "$kag_url" ]]; then
    printf 'xcalibre_url = "%s"\n' "$kag_url" >> "$CONFIG"
  fi
  cat >> "$CONFIG" <<EOF

[slots]
execute = "lmstudio:$LMSTUDIO_TEXT_MODEL"
reason = "deepseek"
orchestrate = "lmstudio:$LMSTUDIO_TEXT_MODEL"
vision = "lmstudio:$LMSTUDIO_VISION_MODEL"
EOF
  mkdir -p "$(dirname "$PROVIDERS")"
  cat > "$PROVIDERS" <<EOF
{
  "providers": [
    {
      "id": "deepseek",
      "displayName": "DeepSeek V4 Pro",
      "baseURL": "https://api.deepseek.com/v1",
      "model": "deepseek-v4-pro",
      "isEnabled": true,
      "isLocal": false,
      "supportsThinking": true,
      "supportsVision": false,
      "kind": "openAICompatible"
    },
    {
      "id": "deepseek-flash",
      "displayName": "DeepSeek V4 Flash",
      "baseURL": "https://api.deepseek.com/v1",
      "model": "deepseek-v4-flash",
      "isEnabled": true,
      "isLocal": false,
      "supportsThinking": false,
      "supportsVision": false,
      "kind": "openAICompatible"
    },
    {
      "id": "lmstudio",
      "displayName": "LM Studio",
      "baseURL": "http://127.0.0.1:1234/v1",
      "model": "$LMSTUDIO_TEXT_MODEL",
      "isEnabled": true,
      "isLocal": true,
      "supportsThinking": false,
      "supportsVision": true,
      "kind": "openAICompatible",
      "budget": { "maxInputTokens": 32768, "reservedOutputTokens": 4096 }
    }
  ],
  "activeProviderID": "lmstudio",
  "firstLaunchSetupCompleted": true
}
EOF
}

start_lmstudio_pair() {
  if ! command -v lms >/dev/null 2>&1; then
    return 127
  fi
  lms server start >/dev/null 2>&1 || return 1
  wait_http "http://127.0.0.1:1234/v1/models" 60 "$RUN_DIR/logs/lmstudio-models-start.json" || return 1
  lms unload --all >/dev/null 2>&1 || true
  lms load "$LMSTUDIO_TEXT_MODEL" -y -c 32768 --parallel 1 >/dev/null 2>&1 || return 1
  lms load "$LMSTUDIO_VISION_MODEL" -y -c 32768 --parallel 1 >/dev/null 2>&1 || return 1
  wait_http "http://127.0.0.1:1234/v1/models" 30 "$RUN_DIR/logs/lmstudio-models-loaded.json"
}

start_ollama() {
  if ! command -v ollama >/dev/null 2>&1; then
    return 127
  fi
  if port_is_listening 11434; then
    echo "stopping pre-existing Ollama listener before runner-owned start"
    stop_ollama
  fi
  if port_is_listening 11434; then
    echo "port 11434 still in use before runner-owned Ollama start"
    return 2
  fi
  ollama serve > "$RUN_DIR/logs/ollama-serve.log" 2>&1 &
  record_owned_pid "$!"
  wait_http "http://127.0.0.1:11434/v1/models" 60 "$RUN_DIR/logs/ollama-models.json"
}

start_jan_text() {
  if [[ ! -x "$JAN_CLI" ]]; then
    echo "Jan CLI not found or not executable at $JAN_CLI"
    return 127
  fi
  if [[ ! -x /opt/homebrew/bin/llama-server ]]; then
    echo "llama-server not found or not executable at /opt/homebrew/bin/llama-server"
    return 127
  fi
  if [[ ! -f "$GGUF_TEXT_MODEL" ]]; then
    echo "text GGUF model missing at $GGUF_TEXT_MODEL"
    return 66
  fi
  if port_is_listening 1337; then
    echo "port 1337 already in use before runner-owned Jan start"
    return 2
  fi
  "$JAN_CLI" serve \
    --model-path "$GGUF_TEXT_MODEL" \
    --bin /opt/homebrew/bin/llama-server \
    --port 1337 \
    --n-gpu-layers=-1 \
    --ctx-size 32768 \
    --verbose \
    > "$RUN_DIR/logs/jan-text.log" 2>&1 &
  record_owned_pid "$!"
  wait_http "http://127.0.0.1:1337/v1/models" 120 "$RUN_DIR/logs/jan-models-text.json"
}

start_jan_vision() {
  if [[ ! -x "$JAN_CLI" ]]; then
    echo "Jan CLI not found or not executable at $JAN_CLI"
    return 127
  fi
  if [[ ! -x /opt/homebrew/bin/llama-server ]]; then
    echo "llama-server not found or not executable at /opt/homebrew/bin/llama-server"
    return 127
  fi
  if [[ ! -f "$GGUF_VISION_MODEL" ]]; then
    echo "vision GGUF model missing at $GGUF_VISION_MODEL"
    return 66
  fi
  if [[ ! -f "$GGUF_MMPROJ" ]]; then
    echo "vision mmproj missing at $GGUF_MMPROJ"
    return 66
  fi
  if port_is_listening 1337; then
    echo "port 1337 already in use before runner-owned Jan vision start"
    return 2
  fi
  "$JAN_CLI" serve \
    --model-path "$GGUF_VISION_MODEL" \
    --mmproj "$GGUF_MMPROJ" \
    --bin /opt/homebrew/bin/llama-server \
    --port 1337 \
    --n-gpu-layers=-1 \
    --ctx-size 32768 \
    --verbose \
    > "$RUN_DIR/logs/jan-vision.log" 2>&1 &
  record_owned_pid "$!"
  wait_http "http://127.0.0.1:1337/v1/models" 120 "$RUN_DIR/logs/jan-models-vision.json"
}

start_localai() {
  if [[ ! -x "$LOCALAI_LAUNCH" ]]; then
    echo "LocalAI launch script not found or not executable at $LOCALAI_LAUNCH"
    return 127
  fi
  if port_is_listening 8080; then
    echo "port 8080 already in use before runner-owned LocalAI start"
    return 2
  fi
  PORT=8080 "$LOCALAI_LAUNCH" > "$RUN_DIR/logs/localai.log" 2>&1 &
  record_owned_pid "$!"
  wait_http "http://127.0.0.1:8080/v1/models" 120 "$RUN_DIR/logs/localai-models.json"
}

start_mistralrs() {
  if [[ ! -x "$MISTRALRS_LAUNCH" ]]; then
    echo "mistral.rs launch script not found or not executable at $MISTRALRS_LAUNCH"
    return 127
  fi
  if port_is_listening 1235; then
    echo "port 1235 already in use before runner-owned mistral.rs start"
    return 2
  fi
  PORT=1235 "$MISTRALRS_LAUNCH" > "$RUN_DIR/logs/mistralrs.log" 2>&1 &
  record_owned_pid "$!"
  wait_http "http://127.0.0.1:1235/v1/models" 120 "$RUN_DIR/logs/mistralrs-models.json"
}

start_vllm() {
  if [[ ! -x "$VLLM_LAUNCH" ]]; then
    echo "vLLM-Metal launch script not found or not executable at $VLLM_LAUNCH"
    return 127
  fi
  if port_is_listening 8000; then
    echo "port 8000 already in use before runner-owned vLLM start"
    return 2
  fi
  PORT=8000 \
    MAX_MODEL_LEN="$VLLM_MAX_MODEL_LEN" \
    MAX_NUM_BATCHED_TOKENS="$VLLM_MAX_NUM_BATCHED_TOKENS" \
    VLLM_METAL_MEMORY_FRACTION="$VLLM_METAL_MEMORY_FRACTION" \
    "$VLLM_LAUNCH" > "$RUN_DIR/logs/vllm.log" 2>&1 &
  record_owned_pid "$!"
  wait_http "http://127.0.0.1:8000/v1/models" 180 "$RUN_DIR/logs/vllm-models.json"
}

start_llamacpp_router() {
  if [[ ! -x /opt/homebrew/bin/llama-server ]]; then
    return 127
  fi
  if [[ ! -f "$LLAMACPP_PRESET" ]]; then
    return 66
  fi
  if port_is_listening 8081; then
    echo "port 8081 already in use before runner-owned llama.cpp start"
    return 2
  fi
  /opt/homebrew/bin/llama-server \
    --host 127.0.0.1 \
    --port 8081 \
    --jinja \
    --metrics \
    --models-preset "$LLAMACPP_PRESET" \
    > "$RUN_DIR/logs/llamacpp-router.log" 2>&1 &
  record_owned_pid "$!"
  wait_http "http://127.0.0.1:8081/v1/models" 90 "$RUN_DIR/logs/llamacpp-models.json"
}

run_local_provider_smokes() {
  if run_step "local provider lmstudio startup" start_lmstudio_pair; then :; fi
  if port_is_listening 1234; then
    run_shell_step "local provider lmstudio smoke" "LMSTUDIO_TEXT_MODEL='$LMSTUDIO_TEXT_MODEL' bash docs/local-provider-configs/smoke-test.sh lmstudio" || true
  fi
  stop_lmstudio

  if run_step "local provider ollama startup" start_ollama; then
    run_shell_step "local provider ollama smoke" "OLLAMA_TEXT_MODEL='$OLLAMA_TEXT_MODEL' bash docs/local-provider-configs/smoke-test.sh ollama" || true
  fi
  stop_owned_pids
  stop_ollama
  RUNNER_OWNED_PIDS=()

  if run_step "local provider llamacpp startup" start_llamacpp_router; then
    run_shell_step "local provider llamacpp smoke" "LLAMACPP_TEXT_MODEL='$LLAMACPP_TEXT_MODEL' LLAMACPP_VISION_MODEL='$LLAMACPP_VISION_MODEL' bash docs/local-provider-configs/smoke-test.sh llamacpp" || true
  fi
  stop_owned_pids
  RUNNER_OWNED_PIDS=()

  if run_step "local provider jan text startup" start_jan_text; then
    run_shell_step "local provider jan text smoke" "JAN_TEXT_MODEL='$JAN_TEXT_MODEL' bash docs/local-provider-configs/smoke-test.sh jan" || true
  fi
  stop_owned_pids
  stop_port_listener 1337
  RUNNER_OWNED_PIDS=()
  if run_step "local provider jan vision startup" start_jan_vision; then
    run_shell_step "local provider jan vision smoke" "SMOKE_ONLY_VISION=1 SMOKE_REQUIRE_VISION=1 bash docs/local-provider-configs/smoke-test.sh jan" || true
  fi
  stop_owned_pids
  stop_port_listener 1337
  RUNNER_OWNED_PIDS=()

  if run_step "local provider localai startup" start_localai; then
    run_shell_step "local provider localai smoke" "SMOKE_REQUIRE_VISION=1 LOCALAI_TEXT_MODEL='$LOCALAI_TEXT_MODEL' LOCALAI_VISION_MODEL='$LOCALAI_VISION_MODEL' bash docs/local-provider-configs/smoke-test.sh localai" || true
  fi
  stop_owned_pids
  RUNNER_OWNED_PIDS=()

  if run_step "local provider mistralrs startup" start_mistralrs; then
    run_shell_step_allow_unsupported "local provider mistralrs smoke" "SMOKE_ALLOW_PROVIDER_MODEL_GAP=1 MISTRALRS_TEXT_MODEL='$MISTRALRS_TEXT_MODEL' bash docs/local-provider-configs/smoke-test.sh mistralrs" || true
  fi
  stop_owned_pids
  RUNNER_OWNED_PIDS=()

  if run_step "local provider vllm startup" start_vllm; then
    run_shell_step "local provider vllm smoke" "VLLM_TEXT_MODEL='$VLLM_TEXT_MODEL' bash docs/local-provider-configs/smoke-test.sh vllm" || true
  fi
  stop_owned_pids
  RUNNER_OWNED_PIDS=()
}

if [[ "${1:-}" == "--dry-run-cleanup" ]]; then
  backup_user_config
  cleanup
  exit 0
fi

if [[ "${1:-}" == "--self-test-failure-aggregation" ]]; then
  run_step "self test pass" /usr/bin/true
  run_step "self test fail" /usr/bin/false || true
  echo "== Self-test summary =="
  printf "Failures: %d\n" "${#FAILURES[@]}"
  for item in "${FAILURES[@]}"; do printf "  FAIL %s\n" "$item"; done
  if [[ "${#FAILURES[@]}" -eq 0 ]]; then
    exit 0
  fi
  exit 1
fi

backup_user_config

stop_test_apps

XCODE_AVAILABLE=0
if run_xcode_step_timeout "xcode test preflight" "$XCODE_PREFLIGHT_TIMEOUT" "xcodebuild -scheme MerlinTests -destination '$XCODE_DESTINATION' -only-testing:MerlinTests/CapabilityConvergenceTests test"; then
  XCODE_AVAILABLE=1
else
  echo "Xcode/XCTest preflight failed; skipping xcodebuild-backed stages and continuing shell/provider smokes."
fi

if [[ "$XCODE_AVAILABLE" == "1" ]]; then
  run_xcode_step_timeout "core unit suite" "$XCODE_CORE_TIMEOUT" "xcodebuild -scheme MerlinTests -destination '$XCODE_DESTINATION' test" || true
  run_xcode_step_timeout "full gui suite" "$XCODE_GUI_TIMEOUT" "xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinUITests test" || true
  run_xcode_step_timeout "focused visual gui suite" "$XCODE_GUI_TIMEOUT" "xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinUITests/VisualLayoutTests test" || true
  run_xcode_step_timeout "deepseek provider live" "$XCODE_LIVE_TIMEOUT" "RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinLiveTests/DeepSeekProviderLiveTests test" || true
  run_xcode_step_timeout "deepseek agentic loop live" "$XCODE_AGENTIC_TIMEOUT" "RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinE2ETests/AgenticLoopE2ETests/testFullLoopWithRealDeepSeek test" || true

  if start_lmstudio_pair; then
    write_lmstudio_config false
    run_xcode_step_timeout "capability S1 swift gui" "$XCODE_CAPABILITY_TIMEOUT" "RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS1SwiftGUIDebugCycle test" || true
    run_xcode_step_timeout "capability S2 rust" "$XCODE_CAPABILITY_TIMEOUT" "RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS2RustDebugCycle test" || true
  else
    FAILURES+=("lmstudio pair startup for S1/S2 live scenarios")
  fi
else
  skip_step "core unit suite" "xcode test preflight failed"
  skip_step "full gui suite" "xcode test preflight failed"
  skip_step "focused visual gui suite" "xcode test preflight failed"
  skip_step "deepseek provider live" "xcode test preflight failed"
  skip_step "deepseek agentic loop live" "xcode test preflight failed"
  skip_step "capability S1 swift gui" "xcode test preflight failed"
  skip_step "capability S2 rust" "xcode test preflight failed"
fi
stop_lmstudio
restore_user_config

run_local_provider_smokes

if [[ "$XCODE_AVAILABLE" == "1" ]] && start_lmstudio_pair; then
  write_lmstudio_config false
  run_xcode_step_timeout "calibration local pair" "$XCODE_LIVE_TIMEOUT" "RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinE2ETests/CalibrationLiveTests/testCalibrateExecuteSlotModel test" || true
  run_xcode_step_timeout "eval harness smoke" "$XCODE_LIVE_TIMEOUT" "RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinE2ETests/EvalHarnessSmokeTests test" || true
  run_xcode_step_timeout "capability S4 rag" "$XCODE_CAPABILITY_TIMEOUT" "RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS4RAGGrounding test" || true
  write_lmstudio_config false
  run_xcode_step_timeout "capability S5 lora" "$XCODE_LIVE_TIMEOUT" "RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS5LoRAPipeline test" || true
  run_xcode_step_timeout "capability S6 electronics" "$XCODE_LIVE_TIMEOUT" "RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS6Electronics test" || true
  run_xcode_step_timeout "capability S6 schematic ocr" "$XCODE_LIVE_TIMEOUT" "RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS6SchematicOCR test" || true
  run_xcode_step_timeout "gui automation live" "$XCODE_GUI_TIMEOUT" "RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live -destination '$XCODE_DESTINATION' -only-testing:MerlinE2ETests/GUIAutomationE2ETests test" || true
else
  if [[ "$XCODE_AVAILABLE" == "1" ]]; then
    FAILURES+=("lmstudio pair startup for local live scenarios")
  else
    skip_step "calibration local pair" "xcode test preflight failed"
    skip_step "eval harness smoke" "xcode test preflight failed"
    skip_step "capability S4 rag" "xcode test preflight failed"
    skip_step "capability S5 lora" "xcode test preflight failed"
    skip_step "capability S6 electronics" "xcode test preflight failed"
    skip_step "capability S6 schematic ocr" "xcode test preflight failed"
    skip_step "gui automation live" "xcode test preflight failed"
  fi
fi

restore_user_config

echo "== Full battery summary =="
printf "Failures: %d\n" "${#FAILURES[@]}"
for item in "${FAILURES[@]}"; do printf "  FAIL %s\n" "$item"; done
printf "Skips: %d\n" "${#SKIPS[@]}"
for item in "${SKIPS[@]}"; do printf "  SKIP %s\n" "$item"; done

if [[ "${#FAILURES[@]}" -eq 0 ]]; then
  FULL_BATTERY_GREEN=1
  exit 0
fi
exit 1
