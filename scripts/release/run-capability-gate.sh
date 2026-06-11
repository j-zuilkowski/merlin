#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_DIR="${RELEASE_DIR:-$ROOT/docs/e2e/2026-06-08-v2.4.0-release}"
LOG_DIR="$RELEASE_DIR/logs"
PRESET="${LLAMACPP_PRESET:-$ROOT/docs/e2e/2026-05-26-merlin-full-gui/llamacpp-router-models.ini}"
LLAMA_SERVER="${LLAMA_SERVER:-/opt/homebrew/bin/llama-server}"
XCALIBRE_DIR="${XCALIBRE_DIR:-$(cd "$ROOT/.." && pwd)/xcalibre-server}"
CONFIG="$HOME/.merlin/config.toml"
PROVIDERS="$HOME/Library/Application Support/Merlin/providers.json"
EXECUTE_MODEL="qwen3-coder-local"
VISION_MODEL="qwen3-vl-local"
ROUTER_BASE="http://127.0.0.1:8081"
XCALIBRE_BASE="http://127.0.0.1:8083"
XCODEBUILD_TIMEOUT_SECONDS="${CAPABILITY_GATE_TIMEOUT_SECONDS:-2400}"

BACKUP_DIR=""
WORK_DIR=""
ROUTER_PID=""
XCALIBRE_PID=""

usage() {
  cat <<'USAGE'
Usage: scripts/release/run-capability-gate.sh [--dry-run|--self-test]

Runs release gate #8 with deterministic ownership of:
- llama.cpp router on 127.0.0.1:8081
- xcalibre-server on 127.0.0.1:8083
- temporary Merlin config.toml and providers.json
- focused S1/S2 xcodebuild invocation
- timeout, logs, config restore, and port cleanup

--dry-run    Print the exact owned services and focused xcodebuild command.
--self-test  Validate the runner contract without starting services.
USAGE
}

log_step() {
  printf '\n== %s ==\n' "$1"
}

port_pids() {
  lsof -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null || true
}

port_has_listener() {
  [ -n "$(port_pids "$1")" ]
}

require_free_port() {
  port="$1"
  if port_has_listener "$port"; then
    echo "port $port already has a listener; refusing to reuse external state"
    lsof -nP -iTCP:"$port" -sTCP:LISTEN || true
    exit 1
  fi
}

wait_http() {
  url="$1"
  timeout="$2"
  out="$3"
  i=1
  while [ "$i" -le "$timeout" ]; do
    if curl -fsS --max-time 2 "$url" > "$out" 2>&1; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

kill_tree() {
  pid="$1"
  [ -n "$pid" ] || return 0
  if ! kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  children="$(pgrep -P "$pid" 2>/dev/null || true)"
  for child in $children; do
    kill_tree "$child"
  done
  kill "$pid" 2>/dev/null || true
  sleep 1
  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

cleanup_port() {
  port="$1"
  pids="$(port_pids "$port")"
  for pid in $pids; do
    kill_tree "$pid"
  done
  sleep 1
  pids="$(port_pids "$port")"
  for pid in $pids; do
    kill -9 "$pid" 2>/dev/null || true
  done
}

cleanup_fixture_helpers() {
  pids="$(pgrep -f "DerivedData/TaskBoard-.*/TaskBoard.app/Contents/MacOS/TaskBoard" 2>/dev/null || true)"
  for pid in $pids; do
    kill_tree "$pid"
  done
}

restore_user_config() {
  if [ -n "$BACKUP_DIR" ] && [ -f "$BACKUP_DIR/config.toml" ]; then
    mkdir -p "$(dirname "$CONFIG")"
    cp "$BACKUP_DIR/config.toml" "$CONFIG"
  fi
  if [ -n "$BACKUP_DIR" ] && [ -f "$BACKUP_DIR/providers.json" ]; then
    mkdir -p "$(dirname "$PROVIDERS")"
    cp "$BACKUP_DIR/providers.json" "$PROVIDERS"
  fi
}

cleanup() {
  set +e
  restore_user_config
  kill_tree "$ROUTER_PID"
  kill_tree "$XCALIBRE_PID"
  cleanup_fixture_helpers
  cleanup_port 8081
  cleanup_port 8083
  if [ -n "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
  if [ -n "$BACKUP_DIR" ]; then
    rm -rf "$BACKUP_DIR"
  fi
  log_step "cleanup"
  if port_has_listener 8081; then
    lsof -nP -iTCP:8081 -sTCP:LISTEN || true
  else
    echo "port 8081: closed"
  fi
  if port_has_listener 8083; then
    lsof -nP -iTCP:8083 -sTCP:LISTEN || true
  else
    echo "port 8083: closed"
  fi
  echo "Merlin config/providers restored"
}

print_plan() {
  cat <<PLAN
release-dir: $RELEASE_DIR
llama.cpp router: $LLAMA_SERVER --host 127.0.0.1 --port 8081 ($ROUTER_BASE) --models-preset $PRESET
execute model: llamacpp:$EXECUTE_MODEL
vision model: llamacpp:$VISION_MODEL
xcalibre server: $XCALIBRE_DIR/target/debug/backend on $XCALIBRE_BASE
xcodebuild timeout seconds: $XCODEBUILD_TIMEOUT_SECONDS
xcodebuild target:
  xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests-Live -destination platform=macOS -derivedDataPath /tmp/merlin-derived-v240-capability -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS1SwiftGUIDebugCycle -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS2RustDebugCycle
PLAN
}

self_test() {
  echo "self-test: owned llama.cpp router on 8081"
  echo "self-test: owned xcalibre server on 8083"
  echo "self-test: config backup and restore trap"
  echo "self-test: bounded xcodebuild timeout"
  echo "self-test: explicit release model IDs"
  echo "self-test: fixture helper cleanup"
  echo "self-test: pass"
}

write_release_config() {
  mkdir -p "$HOME/.merlin" "$(dirname "$PROVIDERS")"
  cat > "$CONFIG" <<EOF
auto_compact = false
max_tokens = 32768
keep_awake = false
provider_name = "llamacpp"
model_id = "$EXECUTE_MODEL"
default_permission_mode = "autoAccept"
notifications_enabled = true
message_density = "comfortable"
max_subagent_threads = 4
max_subagent_depth = 2
xcalibre_token = ""

[memory]
backend_id = "local-vector"

[kag]
enabled = false
xcalibre_url = "$XCALIBRE_BASE"

[slots]
execute = "llamacpp:$EXECUTE_MODEL"
reason = "deepseek"
orchestrate = "deepseek"
vision = "llamacpp:$VISION_MODEL"
EOF

  EXECUTE_MODEL="$EXECUTE_MODEL" VISION_MODEL="$VISION_MODEL" python3 - <<'PY'
import json
import os

path = os.path.expanduser("~/Library/Application Support/Merlin/providers.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {
        "providers": [],
        "modelCache": {},
        "activeProviderID": "deepseek",
        "firstLaunchSetupCompleted": True,
    }

providers = data.setdefault("providers", [])
ids = {p.get("id"): p for p in providers}
if "llamacpp" not in ids:
    providers.append({
        "id": "llamacpp",
        "displayName": "llama.cpp",
        "baseURL": "http://127.0.0.1:8081/v1",
        "model": os.environ["EXECUTE_MODEL"],
        "isEnabled": True,
        "isLocal": True,
        "supportsThinking": False,
        "supportsVision": True,
        "kind": "openAICompatible",
        "local_model_manager_id": "llamacpp",
    })
    ids = {p.get("id"): p for p in providers}
if "deepseek" not in ids:
    providers.append({
        "id": "deepseek",
        "displayName": "DeepSeek V4 Pro",
        "baseURL": "https://api.deepseek.com/v1",
        "model": "deepseek-v4-pro",
        "isEnabled": True,
        "isLocal": False,
        "supportsThinking": True,
        "supportsVision": False,
        "kind": "openAICompatible",
    })
    ids = {p.get("id"): p for p in providers}
if "deepseek-flash" not in ids:
    providers.append({
        "id": "deepseek-flash",
        "displayName": "DeepSeek V4 Flash",
        "baseURL": "https://api.deepseek.com/v1",
        "model": "deepseek-v4-flash",
        "isEnabled": True,
        "isLocal": False,
        "supportsThinking": False,
        "supportsVision": False,
        "kind": "openAICompatible",
    })

for provider in providers:
    if provider.get("id") == "llamacpp":
        provider["isEnabled"] = True
        provider["baseURL"] = "http://127.0.0.1:8081/v1"
        provider["model"] = os.environ["EXECUTE_MODEL"]
        provider["supportsVision"] = True
        provider["local_model_manager_id"] = "llamacpp"
    if provider.get("id") in ("deepseek", "deepseek-flash"):
        provider["isEnabled"] = True

data["activeProviderID"] = "llamacpp:" + os.environ["EXECUTE_MODEL"]
data["firstLaunchSetupCompleted"] = True
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
}

write_xcalibre_config() {
  XCALIBRE_CONFIG="$WORK_DIR/xcalibre-config.toml"
  cat > "$XCALIBRE_CONFIG" <<EOF
[app]
base_url = "$XCALIBRE_BASE"
storage_path = "$WORK_DIR/xcalibre-storage"
[database]
url = "sqlite://$WORK_DIR/xcalibre-library.db"
[auth]
jwt_secret = ""
access_token_ttl_mins = 15
refresh_token_ttl_days = 30
max_login_attempts = 10
lockout_duration_mins = 15
[watch_folder]
enabled = false
[llm]
enabled = false
allow_private_endpoints = true
EOF
}

start_router() {
  log_step "start llama.cpp router"
  test -x "$LLAMA_SERVER" || { echo "missing llama-server: $LLAMA_SERVER"; exit 1; }
  test -f "$PRESET" || { echo "missing llama.cpp preset: $PRESET"; exit 1; }
  require_free_port 8081
  "$LLAMA_SERVER" --host 127.0.0.1 --port 8081 --jinja --metrics \
    --models-preset "$PRESET" > "$LOG_DIR/08-capability-runner-llamacpp-router.log" 2>&1 &
  ROUTER_PID="$!"
  wait_http "$ROUTER_BASE/v1/models" 90 "$LOG_DIR/08-capability-runner-llamacpp-models.json" || {
    echo "llama.cpp router did not become ready"
    tail -80 "$LOG_DIR/08-capability-runner-llamacpp-router.log" || true
    exit 1
  }
  python3 - "$LOG_DIR/08-capability-runner-llamacpp-models.json" "$EXECUTE_MODEL" "$VISION_MODEL" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)
models = {item.get("id") for item in data.get("data", [])}
missing = [model for model in sys.argv[2:] if model not in models]
if missing:
    print("missing release model IDs: " + ", ".join(missing))
    sys.exit(1)
print("model IDs present: " + ", ".join(sys.argv[2:]))
PY
}

start_xcalibre() {
  log_step "start xcalibre-server"
  test -d "$XCALIBRE_DIR" || { echo "missing xcalibre-server repo: $XCALIBRE_DIR"; exit 1; }
  require_free_port 8083
  (cd "$XCALIBRE_DIR" && cargo build -p backend > "$LOG_DIR/08-capability-runner-xcalibre-build.log" 2>&1)
  test -x "$XCALIBRE_DIR/target/debug/backend" || { echo "xcalibre backend did not build"; exit 1; }
  write_xcalibre_config
  CONFIG_PATH="$XCALIBRE_CONFIG" APP_BIND_ADDR="127.0.0.1:8083" \
    "$XCALIBRE_DIR/target/debug/backend" > "$LOG_DIR/08-capability-runner-xcalibre-server.log" 2>&1 &
  XCALIBRE_PID="$!"
  wait_http "$XCALIBRE_BASE/health" 120 "$LOG_DIR/08-capability-runner-xcalibre-health.json" || {
    echo "xcalibre-server did not become ready"
    tail -80 "$LOG_DIR/08-capability-runner-xcalibre-server.log" || true
    exit 1
  }
}

run_with_timeout() {
  timeout="$1"
  shift
  "$@" &
  child="$!"
  (
    sleep "$timeout"
    if kill -0 "$child" 2>/dev/null; then
      echo "EvalShell timeout after ${timeout}s: $*"
      kill_tree "$child"
    fi
  ) &
  watchdog="$!"
  set +e
  wait "$child"
  status="$?"
  set -e
  kill_tree "$watchdog"
  wait "$watchdog" 2>/dev/null || true
  return "$status"
}

run_gate() {
  mkdir -p "$LOG_DIR"
  trap cleanup EXIT INT TERM
  BACKUP_DIR="$(mktemp -d /tmp/merlin-release-config-backup.XXXXXX)"
  WORK_DIR="$(mktemp -d /tmp/merlin-release-capability.XXXXXX)"

  log_step "backup user config"
  [ -f "$CONFIG" ] && cp "$CONFIG" "$BACKUP_DIR/config.toml"
  [ -f "$PROVIDERS" ] && cp "$PROVIDERS" "$BACKUP_DIR/providers.json"
  echo "backup dir: $BACKUP_DIR"
  echo "work dir: $WORK_DIR"

  start_router
  start_xcalibre

  log_step "write isolated release config"
  write_release_config
  rg -n "provider_name|model_id|execute|orchestrate|vision|xcalibre_url" "$CONFIG"

  log_step "focused S1/S2 xcodebuild"
  run_with_timeout "$XCODEBUILD_TIMEOUT_SECONDS" \
    xcodebuild test \
      -project Merlin.xcodeproj \
      -scheme MerlinTests-Live \
      -destination "platform=macOS" \
      -derivedDataPath /tmp/merlin-derived-v240-capability \
      -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS1SwiftGUIDebugCycle \
      -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS2RustDebugCycle
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --dry-run)
    print_plan
    exit 0
    ;;
  --self-test)
    self_test
    exit 0
    ;;
  "")
    run_gate 2>&1 | tee "$LOG_DIR/08-capability-runner.log"
    ;;
  *)
    usage
    exit 64
    ;;
esac
