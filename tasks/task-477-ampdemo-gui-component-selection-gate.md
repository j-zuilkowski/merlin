# Task 477 - AmpDemo GUI Component Selection Gate

## Objective

Run a fresh app-only AmpDemo workflow attempt through Merlin's GUI path, without
manually designing the sample project, and identify the next generic electronics
workflow gate needed for honest completion.

## Scope

This task records a workflow evidence run only. It does not hand-select AmpDemo
components and does not add product code. The purpose is to find the next generic
Merlin behavior needed before another full AmpDemo attempt can advance.

## Fresh Run Setup

Built and installed the current app:

```bash
xcodebuild build -project Merlin.xcodeproj -scheme Merlin -destination 'platform=macOS'
rm -rf /Applications/Merlin.app
/usr/bin/ditto /Users/jonzuilkowski/Library/Developer/Xcode/DerivedData/Merlin-ehaeyubkoothsygklrellvqjerch/Build/Products/Debug/Merlin.app /Applications/Merlin.app
codesign --verify --deep --strict /Applications/Merlin.app
```

Result: build succeeded and `/Applications/Merlin.app` passed codesign
verification.

Verified configured local execution providers before launch:

- `execute = llamacpp:qwen3-coder-next-local`
- `orchestrate = llamacpp:qwen3-coder-next-local`
- `vision = llamacpp:qwen3-vl-local`
- `reason = deepseek`
- `curl http://127.0.0.1:8081/health` returned `{"status":"ok"}`
- `/v1/models` reported `qwen3-coder-next-local` and `qwen3-vl-local`
- a direct chat completion to `qwen3-coder-next-local` returned `OK`

Cleaned the AmpDemo generated state before the run:

```bash
AMP=/Users/jonzuilkowski/Documents/localProject/AmpDemo
SESSION_DIR="$HOME/Library/Application Support/Merlin/sessions/_Users_jonzuilkowski_Documents_localProject_AmpDemo"
pkill -x Merlin || true
find "$AMP" -mindepth 1 -maxdepth 1 ! -name spec.md -exec rm -rf {} +
for d in artifacts vendor-feeds kicad gerbers drill simulation bom screenshots reports libraries; do mkdir -p "$AMP/$d"; done
rm -rf "$AMP/.merlin"
rm -rf "$SESSION_DIR"
rm -f "$HOME/.merlin/inject.txt"
: > "$HOME/.merlin/telemetry.jsonl"
open -na /Applications/Merlin.app --args --open-project "$AMP" --active-domain electronics
```

## GUI Execution Evidence

Direct keyboard/cliclick focus and an exploratory XCUITest route were not usable
in this desktop environment. XCUITest failed before test execution while enabling
automation mode:

```text
Failed to initialize for UI testing: ... Timed out while enabling automation mode.
```

The successful run used Merlin's own live-session GUI injection path,
`~/.merlin/inject.txt`, while `/Applications/Merlin.app` was open on the AmpDemo
project. This routes through `LiveSession.submitInjectedMessage` and the active
`ChatViewModel`, not through direct tool calls or hand-authored artifacts.

Captured app-only screenshots:

- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/01_clean_session_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/02_request_injected_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_1_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_2_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_3_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_4_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_5_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_6_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_7_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_8_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_9_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_10_app_only.png`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/04_component_selection_blocked_app_only.png`

## Workflow Artifacts

Merlin generated these artifacts during the GUI-driven run:

- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/98B2DDB2-7433-4C01-B03C-C4156BFD3184-design_intent.json`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/53FEDAD1-FEDF-4A53-9F2A-D721428B9614-design_intent.json`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/19397343-C00B-46CD-90C0-C93DA986AC6D-circuit_ir.json`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/03ECE826-D739-446D-A057-FEDDA41B16FB-component_matrix.json`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-kicad-root-cache/kicad-library-roots.json`
- `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-kicad-catalog-cache/kicad-library-catalog.json`

Telemetry evidence:

- `kicad_build_intent_model` completed and emitted DesignIntent evidence.
- `kicad_approve_design_intent` completed and emitted approved DesignIntent
  evidence.
- `kicad_generate_circuit_ir` completed and emitted Circuit IR evidence.
- `kicad_select_components` completed after about 134 seconds and emitted a
  component matrix.

## Observed Gate

The run stopped truthfully at component selection:

```text
status: BLOCKED_INPUT_QUALITY
COMPONENT_SELECTION_BLOCKED: Component selection has unresolved decisions that
require catalog evidence, a concrete part choice, or revised constraints.
```

The component matrix contains 21 components and all 21 have
`selection_status = requires_vendor_resolution`. No footprint, schematic, PCB,
ERC, DRC, SPICE, BOM, or fabrication step was allowed to advance from unresolved
component decisions.

## Next Generic Work

The next gate Merlin needs is not an AmpDemo-specific manual parts list. It is a
generic component-selection revision path that can take a blocked component
matrix, perform catalog-backed resolution or constraint refinement, and either:

- emit a concrete selected component matrix with manufacturer, MPN, vendor
  evidence, datasheet evidence, symbol, footprint, and pin compatibility for
  every required component; or
- stop with structured missing-evidence questions that are specific enough for a
  user or provider-backed tool to resolve.

Do not rerun the full AmpDemo workflow past this point until that generic
component-selection resolution gate exists.

## Verification

Focused artifact checks:

```bash
find /Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin -maxdepth 5 -type f -print | sort
jq -r '.components | length' /Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/03ECE826-D739-446D-A057-FEDDA41B16FB-component_matrix.json
jq -r '.components | group_by(.selection_status)[] | "\(.[0].selection_status) \(length)"' /Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/03ECE826-D739-446D-A057-FEDDA41B16FB-component_matrix.json
tail -n 160 "$HOME/.merlin/telemetry.jsonl"
```

Results:

- Artifact paths listed above exist.
- Component matrix count: `21`.
- Selection status summary: `requires_vendor_resolution 21`.
- Telemetry shows the tool sequence and the component-selection stop.

No full AmpDemo completion is claimed.
