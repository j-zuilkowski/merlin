#!/bin/bash
# Merlin — Phase 00: Environment Preflight
# Run manually before starting any Codex phases:
#   bash phases/phase-00-preflight.sh
#
# Exits 0 if all required deps are satisfied (warnings are non-fatal).
# Installs missing brew tools automatically where safe to do so.

set -uo pipefail

PASS="✓"
WARN="⚠"
FAIL="✗"
errors=0
warnings=0

# ── Helpers ────────────────────────────────────────────────────────────

ok()   { echo "  $PASS $1"; }
warn() { echo "  $WARN $1"; ((warnings++)) || true; }
fail() { echo "  $FAIL $1"; ((errors++)) || true; }

brew_install() {
    local pkg="$1"
    echo "    → Installing $pkg via Homebrew..."
    if brew install "$pkg" &>/dev/null; then
        ok "$pkg installed"
    else
        fail "$pkg — brew install $pkg failed. Install manually."
    fi
}

section() { echo ""; echo "── $1 ──────────────────────────────────────"; }

# ── macOS ──────────────────────────────────────────────────────────────

section "System"

macmajor=$(sw_vers -productVersion | cut -d. -f1)
macfull=$(sw_vers -productVersion)
if [ "${macmajor:-0}" -ge 14 ]; then
    ok "macOS $macfull (≥14 required)"
else
    fail "macOS $macfull — Merlin requires macOS 14+. Upgrade before proceeding."
fi

# RAM
ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
if [ "$ram_gb" -ge 64 ]; then
    ok "RAM: ${ram_gb}GB"
else
    warn "RAM: ${ram_gb}GB — 128GB recommended for Qwen2.5-VL-72B at Q4_K_M"
fi

# Disk space — need ~60GB free (43GB model + DerivedData + project)
avail_gb=$(df -g . | awk 'NR==2{print $4}')
if [ "${avail_gb:-0}" -ge 60 ]; then
    ok "Disk: ${avail_gb}GB available"
else
    warn "Disk: ${avail_gb}GB available — 60GB+ recommended (model + DerivedData)"
fi

# ── Xcode ──────────────────────────────────────────────────────────────

section "Xcode"

if ! command -v xcodebuild &>/dev/null; then
    fail "Xcode — not found. Install Xcode 15+ from the App Store."
else
    xc_full=$(xcodebuild -version 2>/dev/null | head -1)
    xc_major=$(echo "$xc_full" | awk '{print $2}' | cut -d. -f1)
    if [ "${xc_major:-0}" -ge 15 ]; then
        ok "$xc_full (≥15 required for performAccessibilityAudit)"
    else
        fail "$xc_full — Merlin requires Xcode 15+. Update from the App Store."
    fi
fi

# Xcode CLT
if xcode-select -p &>/dev/null; then
    ok "Xcode Command Line Tools ($(xcode-select -p))"
else
    fail "Xcode Command Line Tools — run: xcode-select --install"
fi

# Swift version — try xcrun first, fall back to direct call
# Use 2>&1 because some Swift versions write --version output to stderr
swift_ver=$(xcrun swift --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
swift_ver="${swift_ver:-$(swift --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)}"
if [ -n "$swift_ver" ]; then
    ok "Swift $swift_ver"
else
    fail "Swift — not found via xcrun or PATH. Try: sudo xcode-select -s /Applications/Xcode.app"
fi

# Simulator runtime (needed for phase-08b, phase-23)
if xcrun simctl list runtimes 2>/dev/null | grep -q "iOS\|macOS"; then
    ok "Simulator runtimes available"
else
    warn "No simulator runtimes found — xcode_simulator_* tools will fail. Install via Xcode → Platforms."
fi

# xcresulttool (needed for phase-08b xcresult parsing)
if xcrun xcresulttool version &>/dev/null; then
    ok "xcresulttool available"
else
    fail "xcresulttool not found — required by XcodeTools.parseXcresult"
fi

# ── Homebrew ───────────────────────────────────────────────────────────

section "Homebrew & CLI Tools"

if ! command -v brew &>/dev/null; then
    fail "Homebrew — install from https://brew.sh before continuing"
    echo ""
    echo "  *** Cannot auto-install remaining tools without Homebrew. ***"
    echo "  *** Install Homebrew and re-run this script.              ***"
    echo ""
    # Skip brew-dependent checks
else
    ok "Homebrew $(brew --version | head -1)"

    # xcodegen — required for phase-01
    if command -v xcodegen &>/dev/null; then
        ok "xcodegen $(xcodegen --version 2>/dev/null | head -1)"
    else
        brew_install xcodegen
    fi

    # python3 — used in LM Studio model check below
    if command -v python3 &>/dev/null; then
        ok "python3 $(python3 --version 2>/dev/null)"
    else
        warn "python3 — not found. LM Studio model-name check will be skipped."
    fi
fi

# Codex CLI
if command -v codex &>/dev/null; then
    ok "Codex CLI ($(codex --version 2>/dev/null | head -1))"
else
    warn "Codex CLI — not found on PATH. Install the Codex app and ensure 'codex' is on PATH."
    warn "  Alternatively use the Codex GUI and paste phase file contents manually."
fi

# ── LM Studio ──────────────────────────────────────────────────────────

section "LM Studio (local vision model)"

if curl -s --connect-timeout 2 http://localhost:1234/v1/models &>/dev/null; then
    ok "LM Studio server running on :1234"
    # Check vision model is loaded
    if command -v python3 &>/dev/null; then
        loaded=$(curl -s http://localhost:1234/v1/models \
            | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ids = [m['id'] for m in d.get('data', [])]
    print('\n'.join(ids))
except:
    pass
" 2>/dev/null)
        if echo "$loaded" | grep -qi "qwen2.5-vl"; then
            ok "Qwen2.5-VL model detected: $(echo "$loaded" | grep -i qwen2.5-vl | head -1)"
        else
            warn "Qwen2.5-VL model not detected in LM Studio."
            warn "  Load: lmstudio-community/Qwen2.5-VL-72B-Instruct-GGUF → Q4_K_M (~47.4GB) before running live/E2E tests."
            warn "  Loaded models: ${loaded:-none}"
        fi
    else
        warn "python3 unavailable — cannot verify which model is loaded in LM Studio."
    fi
else
    warn "LM Studio not running on :1234."
    warn "  Required for: phase-09b (screen capture), phase-10 (vision query), phase-23/24 (E2E)."
    warn "  Unit + integration tests (MerlinTests scheme) work without LM Studio."
fi

# ── DeepSeek API Key ───────────────────────────────────────────────────

section "DeepSeek API Key"

key_found=false
if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    ok "DEEPSEEK_API_KEY found in environment"
    key_found=true
fi

if security find-generic-password -s "com.merlin.deepseek" -a "api-key" &>/dev/null 2>&1; then
    ok "DeepSeek API key found in macOS Keychain (service: com.merlin.deepseek)"
    key_found=true
fi

if [ "$key_found" = false ]; then
    warn "DeepSeek API key not found in environment or Keychain."
    warn "  The app will prompt for it on first launch (stored to Keychain)."
    warn "  To pre-load: security add-generic-password -s com.merlin.deepseek -a api-key -w <your-key>"
fi

# ── macOS Permissions ──────────────────────────────────────────────────

section "macOS Permissions (manual verification required)"

echo "  The following permissions must be granted in System Settings before"
echo "  GUI automation and screen capture tests will pass."
echo "  They cannot be verified programmatically."
echo ""

# Accessibility — check if Terminal/Codex is in the list (heuristic only)
echo "  □ Accessibility (System Settings → Privacy & Security → Accessibility)"
echo "    Required by: AXInspectorTool, CGEventTool"
echo "    Grant to: Merlin.app (after first build)"
echo ""
echo "  □ Screen Recording (System Settings → Privacy & Security → Screen Recording)"
echo "    Required by: ScreenCaptureTool"
echo "    Grant to: Merlin.app (after first build)"
echo ""
echo "  □ Apple Events / Automation"
echo "    Required by: XcodeTools.openFile (AppleScript to Xcode)"
echo "    Grant when: first time agent opens a file in Xcode"

# ── Project Directory ──────────────────────────────────────────────────

section "Project Directory"

proj_dir="$(cd "$(dirname "$0")/.." && pwd)"
ok "Project root: $proj_dir"

if [ -f "$proj_dir/phases/HANDOFF.md" ]; then
    phase_count=$(ls "$proj_dir/phases/phase-"*.md 2>/dev/null | wc -l | tr -d ' ')
    ok "$phase_count phase files found in phases/"
else
    fail "phases/HANDOFF.md not found — run this script from the project root."
fi

if [ -f "$proj_dir/architecture.md" ]; then
    ok "architecture.md present"
else
    warn "architecture.md missing — Codex context will be incomplete."
fi

if [ -f "$proj_dir/llm.md" ]; then
    ok "llm.md present"
else
    warn "llm.md missing."
fi

# ── Summary ────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════"

if [ "$errors" -eq 0 ] && [ "$warnings" -eq 0 ]; then
    echo "  $PASS All checks passed. Ready to begin Phase 01."
elif [ "$errors" -eq 0 ]; then
    echo "  $PASS Required deps OK. $warnings warning(s) — review above."
    echo "     Warnings affect live/E2E tests only. Unit tests will run."
    echo "     Safe to begin Phase 01."
else
    echo "  $FAIL $errors error(s) must be fixed before proceeding."
    [ "$warnings" -gt 0 ] && echo "  $WARN $warnings warning(s) also noted."
    echo ""
    echo "  Fix all errors, then re-run: bash phases/phase-00-preflight.sh"
fi

echo "══════════════════════════════════════════════"
echo ""

exit "$errors"
