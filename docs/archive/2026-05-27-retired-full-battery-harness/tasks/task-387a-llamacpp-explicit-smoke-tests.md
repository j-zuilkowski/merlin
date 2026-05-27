# Task 387a - llama.cpp explicit smoke tests

## Traceability

- Vision reference: vision.md#local-model-management
- Spec reference: spec.md#full-green-e2e-battery-v24
- Related spec reference: spec.md#llamacpp-first-class-local-provider-v23
- Prior failure: `docs/local-provider-configs/smoke-test.sh llamacpp` selected the router's `default` model and returned HTTP 000000 for completion/tool-call smoke checks.

## Behavior

WHEN the llama.cpp smoke script runs against a router catalog THE script SHALL select explicit configured text and vision model IDs instead of the catalog's `default` entry.
WHEN an explicit smoke model is unavailable THE script SHALL fail with the missing model ID and catalog response instead of silently falling back to `default`.
WHEN the text and vision model smokes complete THE script SHALL record the exact model ID used for completion, streaming, tool-call shape, and image request checks.

## Red Tests

- Add script-level tests for `docs/local-provider-configs/smoke-test.sh` using fixture `/v1/models` responses where `default` is first and the real text/vision models appear later.
- Assert `llamacpp` text smoke uses the configured text model ID for completion, streaming, and tool-call checks.
- Assert `llamacpp` vision smoke uses the configured vision model ID and reports the paired `mmproj`/vision route when available.
- Assert a missing explicit model produces a deterministic failure that includes the requested model ID and the catalog body.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/LocalProviderSmokeScriptTests test
```

Expected red state: the new smoke-script tests fail because the current script can choose the first catalog model, including `default`.
