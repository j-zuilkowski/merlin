#!/usr/bin/env bash
set -euo pipefail
ROOT="/Users/jonzuilkowski/Documents/localProject/merlin"
XCAL="/Users/jonzuilkowski/Documents/localProject/xcalibre-server"
RUN_DIR="$1"
CONFIG="$HOME/.merlin/config.toml"
PROVIDERS="$HOME/Library/Application Support/Merlin/providers.json"
CONFIG_BAK="$RUN_DIR/config.toml.bak"
PROVIDERS_BAK="$RUN_DIR/providers.json.bak"
LLAMA_PID=""
XCAL_PID=""
cleanup() {
  set +e
  if [[ -n "$LLAMA_PID" ]]; then kill "$LLAMA_PID" 2>/dev/null || true; wait "$LLAMA_PID" 2>/dev/null || true; fi
  if [[ -n "$XCAL_PID" ]]; then kill "$XCAL_PID" 2>/dev/null || true; wait "$XCAL_PID" 2>/dev/null || true; fi
  if [[ -f "$CONFIG_BAK" ]]; then cp "$CONFIG_BAK" "$CONFIG"; fi
  if [[ -f "$PROVIDERS_BAK" ]]; then cp "$PROVIDERS_BAK" "$PROVIDERS"; fi
}
trap cleanup EXIT
cp "$CONFIG" "$CONFIG_BAK"
cp "$PROVIDERS" "$PROVIDERS_BAK"

# Start the single local provider pair through one router-mode llama-server.
/opt/homebrew/bin/llama-server \
  --host 127.0.0.1 \
  --port 8081 \
  --jinja \
  --metrics \
  --models-preset "$ROOT/docs/e2e/2026-05-26-merlin-full-gui/llamacpp-router-models.ini" \
  > "$RUN_DIR/logs/llamacpp-router.log" 2>&1 &
LLAMA_PID=$!
for i in {1..90}; do
  if curl -fsS --max-time 2 http://127.0.0.1:8081/v1/models > "$RUN_DIR/logs/llamacpp-models-start.json"; then break; fi
  sleep 1
  if [[ "$i" == 90 ]]; then echo "llama.cpp router did not become ready"; exit 1; fi
done

# Build and smoke-start the real sibling xcalibre-server backend.
(cd "$XCAL" && cargo build -p backend > "$RUN_DIR/logs/xcalibre-build.log" 2>&1)
XCAL_WORK="$RUN_DIR/xcalibre-work"
mkdir -p "$XCAL_WORK/storage"
cat > "$XCAL_WORK/config.toml" <<EOF
[app]
base_url = "http://127.0.0.1:8083"
storage_path = "$XCAL_WORK/storage"
[database]
url = "sqlite://$XCAL_WORK/library.db"
[watch_folder]
enabled = false
path = "$XCAL_WORK/watch"
interval_seconds = 2
[llm]
enabled = false
allow_private_endpoints = true
EOF
mkdir -p "$XCAL_WORK/watch"
CONFIG_PATH="$XCAL_WORK/config.toml" APP_BIND_ADDR="127.0.0.1:8083" "$XCAL/target/debug/backend" \
  > "$RUN_DIR/logs/xcalibre-server.log" 2>&1 &
XCAL_PID=$!
for i in {1..120}; do
  if curl -fsS --max-time 2 http://127.0.0.1:8083/api/docs/openapi.json > "$RUN_DIR/logs/xcalibre-openapi.json"; then break; fi
  sleep 1
  if [[ "$i" == 120 ]]; then echo "xcalibre-server did not become ready"; exit 1; fi
done

# Temporary Merlin config: one local provider pair, DeepSeek critic/reason.
cat > "$CONFIG" <<EOF
auto_compact = false
max_tokens = 32768
keep_awake = false
provider_name = "llamacpp"
model_id = "qwen3-coder-local"
default_permission_mode = "autoAccept"
notifications_enabled = true
message_density = "comfortable"
max_subagent_threads = 4
max_subagent_depth = 2
xcalibre_token = ""

[memory]
backend_id = "local-vector"

[kag]
enabled = true
xcalibre_url = "http://127.0.0.1:8083"

[slots]
execute = "llamacpp:qwen3-coder-local"
reason = "deepseek"
orchestrate = "deepseek"
vision = "llamacpp:qwen3-vl-local"
EOF
node <<'EOF'
const fs = require('fs');
const path = process.env.HOME + '/Library/Application Support/Merlin/providers.json';
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
for (const p of data.providers) {
  if (p.id === 'llamacpp') {
    p.isEnabled = true;
    p.baseURL = 'http://127.0.0.1:8081/v1';
    p.model = '';
    p.supportsVision = true;
    p.local_model_manager_id = 'llamacpp';
  }
  if (p.id === 'deepseek' || p.id === 'deepseek-flash') p.isEnabled = true;
}
data.activeProviderID = 'llamacpp:qwen3-coder-local';
fs.writeFileSync(path, JSON.stringify(data, null, 2));
EOF

curl -fsS --max-time 2 http://127.0.0.1:8081/v1/models > "$RUN_DIR/logs/llamacpp-models-before-s2.json"
(
  cd "$ROOT"
  rm -rf /tmp/merlin-e2e-derived
  XCALIBRE_BASE_URL="http://127.0.0.1:8083" \
  xcodebuild -scheme MerlinTests-Live test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-e2e-derived \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
    -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS2RustDebugCycle
) > "$RUN_DIR/logs/xcodebuild-S2-local-deepseek.log" 2>&1
