# Task 387b - llama.cpp explicit smoke

## Traceability

- Vision reference: vision.md#local-model-management
- Spec reference: spec.md#full-green-e2e-battery-v24
- Related spec reference: spec.md#llamacpp-first-class-local-provider-v23
- Test task: tasks/task-387a-llamacpp-explicit-smoke-tests.md

## Behavior

WHEN `smoke-test.sh llamacpp` runs THE script SHALL require or derive non-default explicit text and vision model IDs before sending smoke requests.
WHEN `LLAMACPP_TEXT_MODEL` or `LLAMACPP_VISION_MODEL` is set THE script SHALL use those values exactly and fail if the router catalog does not expose them.
WHEN no explicit environment override is set THE script SHALL prefer documented Qwen text/vision model IDs over `default` and SHALL fail if no non-default capable model is available.

## Implementation

- Add explicit model resolution helpers to `docs/local-provider-configs/smoke-test.sh`.
- Support `LLAMACPP_TEXT_MODEL` and `LLAMACPP_VISION_MODEL` overrides for local hardware/model differences.
- Prefer configured/documented Qwen model IDs when present in `/v1/models`; never use `default` for llama.cpp router completion, streaming, tool-call, or vision checks.
- Include the resolved text and vision model IDs in the smoke output and results artifact.
- Preserve the one-local-provider-pair-at-a-time workflow and shut down instructions.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/LocalProviderSmokeScriptTests test
LLAMACPP_TEXT_MODEL=qwen3-coder-local LLAMACPP_VISION_MODEL=qwen3-vl-local \
  bash docs/local-provider-configs/smoke-test.sh llamacpp
```

Expected green state: script tests pass and the live llama.cpp smoke reports explicit text and vision model IDs without selecting `default`.
