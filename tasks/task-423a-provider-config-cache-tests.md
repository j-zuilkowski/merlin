# Task 423a - Provider Config Cache Tests

Date: 2026-05-30

## Goal

Add failing tests proving component provider fixture paths and provider-cache
settings can come from plugin configuration instead of every tool call.

## Test Scope

1. Read `electronics_provider_config_path` JSON for provider fixture paths.
2. Use configured cache directory and TTL.
3. Cache mapped provider candidates after a fixture-backed run.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected before Task 423b: config-backed provider selection tests fail.
