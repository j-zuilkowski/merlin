# Task 336b — LoRA Serving Target Implementation

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 336a complete: failing `LoRAServingTargetSettingsTests` (4 tests) in place.

---

## Edit: Merlin/Config/AppSettings.swift

Add `loraServingTarget: String` after `loraServerURL`. Default `"mlx_lm_server"`.
Static `knownLoRAServingTargets: [String]` lists the canonical 4. TOML key:
`lora_serving_target` inside `[lora]`. Mirror the pattern of every other lora-
prefixed field: declaration, `LoraConfig` outer + inner structs, both
`CodingKeys` enums, `serializedTOML()` writer (omit when default), Codable
applier, line-based parser fallback.

## Edit: Merlin/Views/Settings/LoRASettingsSection.swift

Inference section now shows a Picker (Serving runtime) with 4 options and a
TextField (Server URL). Both disabled when `loraAutoLoad == false`. Three
helpers (`loraServingTargetHelp`, `loraServingTargetURLPlaceholder`,
`loraServingTargetURLHelp`) emit per-target guidance — the launch command,
expected port, and adapter-load strategy (direct vs fuse-then-serve).

## Routing impact

`AppState.loraProvider` still constructs an `OpenAICompatibleProvider`
pointing at `loraServerURL`. No change to engine wiring — all four target
options speak OpenAI-compat, so the same provider type works. `loraServingTarget`
is a UI-side choice that drives helper text + future per-target defaults.
Wiring per-target launch automation (e.g. spinning up vLLM-Metal in-process)
is intentionally out of scope.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    -only-testing:MerlinTests/LoRAServingTargetSettingsTests 2>&1 \
    | grep -E 'Test Case|Executed|BUILD' | tail
```
Expected: 4 tests pass. Full suite: 1845 tests, 0 failures.

```bash
xcodebuild -scheme MerlinTests-Live build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head
```
Expected: `** TEST BUILD SUCCEEDED **`.

## Commit
```bash
git add Merlin/Config/AppSettings.swift \
        Merlin/Views/Settings/LoRASettingsSection.swift \
        tasks/task-336b-lora-serving-target.md
git commit -m "Task 336b — LoRA serving-target picker (mlx_lm.server / vLLM-Metal / LM Studio / custom)"
```
