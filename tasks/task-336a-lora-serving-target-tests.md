# Task 336a — LoRA Serving Target Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 335b complete: ProviderConfigCalibrationDefaultsTests + Mistral.rs port rebind.

vLLM-Metal smoke testing (2026-05-20) confirmed it serves MLX format directly
via `mlx_lm.load`, putting it in the same MLX-native runtime family as
`mlx_lm.server` and LM Studio. All three can serve a LoRA-trained adapter:
mlx_lm.server / LM Studio load adapters directly; vLLM-Metal requires one
`mlx_lm.fuse` step first. Today Merlin hard-codes the routing target to
`mlx_lm.server` via the `loraServerURL` field.

New surface in task 336b:
  - `AppSettings.loraServingTarget: String` — selects which MLX-native runtime
    serves the trained adapter. Default `"mlx_lm_server"` (historic behaviour).
    Other values: `"vllm_metal"`, `"lm_studio"`, `"custom"`.
  - `AppSettings.knownLoRAServingTargets: [String]` — static, pins the canonical
    set so the UI picker stays in sync with the AppSettings codec.
  - TOML serialisation: writes `lora_serving_target = "<value>"` when not
    default; omits when default.

TDD coverage:
  File 1 — `MerlinTests/Unit/LoRAServingTargetSettingsTests.swift`:
    `testDefaultIsMLXLMServer` — fresh AppSettings reports `"mlx_lm_server"`
    `testTOMLRoundTripForNonDefault` — set → serialise → parse → restored value matches
    `testTOMLOmittedWhenDefault` — default value never appears in serialised TOML
    `testSupportedTargetSet` — `knownLoRAServingTargets` equals canonical set

---

## Write to: MerlinTests/Unit/LoRAServingTargetSettingsTests.swift
(see committed file)

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    -only-testing:MerlinTests/LoRAServingTargetSettingsTests 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10
```
Expected: BUILD FAILED with errors naming `loraServingTarget` and `knownLoRAServingTargets` as missing on `AppSettings`.

## Commit
```bash
git add MerlinTests/Unit/LoRAServingTargetSettingsTests.swift \
        tasks/task-336a-lora-serving-target-tests.md
git commit -m "Task 336a — LoRAServingTargetSettingsTests (failing)"
```
