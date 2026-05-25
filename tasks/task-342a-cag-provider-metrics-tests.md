# Phase 342a — CAG Provider And Metrics Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 341b complete: CAG request policy and deterministic tool ordering are
implemented.

Recommended execution model: GPT-5.3-Codex.

This phase covers explicit provider support and metrics. Anthropic is the only
provider that needs wire-format changes; OpenAI-compatible, DeepSeek, and local
providers rely on stable prefix bytes and should not receive synthetic
provider-specific cache fields.

New surface introduced in phase 342b:
  - `Merlin/CAG/CacheMetrics.swift`
  - `CAGCacheUsage`
  - `CAGCacheMetricsStore`
  - `CompletionChunk.cacheUsage`
  - Anthropic prompt-cache request encoding:
    - `anthropic-beta: prompt-caching-2024-07-31`
    - system text encoded as cache-marked content block
    - last tool definition cache-marked when tools exist
  - Anthropic SSE usage parsing for `cache_read_input_tokens` and
    `cache_creation_input_tokens`

TDD coverage:
  File 1 - `MerlinTests/Unit/AnthropicProviderTests.swift`:
    `testCAGEnabledAddsPromptCachingBetaHeader`
    `testCAGEnabledMarksSystemBlockEphemeral`
    `testCAGEnabledMarksLastToolEphemeral`
    `testCAGDisabledKeepsLegacySystemString`
    `testAnthropicSSEParserParsesCacheUsage`

  File 2 - `MerlinTests/Unit/CAGCacheMetricsTests.swift`:
    `testUsageComputesHitRate`
    `testMetricsStoreAggregatesProviderUsage`
    `testMetricsStoreResetsProviderUsage`

  File 3 - `MerlinTests/Unit/ProviderTests.swift` or a focused
  `OpenAICompatibleCAGTests.swift`:
    `testOpenAICompatibleProviderDoesNotEmitAnthropicCacheControl`

---

## Edit: MerlinTests/Unit/AnthropicProviderTests.swift

Add request-building assertions:

- With `CompletionRequest.cachePolicy = .ephemeral`,
  `urlRequest.value(forHTTPHeaderField: "anthropic-beta")` contains
  `prompt-caching-2024-07-31`.
- The JSON body `system` field is an array with one text block:

```json
{
  "type": "text",
  "text": "...",
  "cache_control": { "type": "ephemeral" }
}
```

- The final encoded tool object has:

```json
"cache_control": { "type": "ephemeral" }
```

- With `.disabled`, the system field remains the current plain string and no
  beta header is sent.

Add SSE parsing assertion for a line like:

```json
data: {"type":"message_delta","usage":{"input_tokens":100,"cache_read_input_tokens":80,"cache_creation_input_tokens":20}}
```

Expected `chunk.cacheUsage?.readTokens == 80`,
`creationTokens == 20`, and `uncachedInputTokens == 100`.

## Write to: MerlinTests/Unit/CAGCacheMetricsTests.swift

Test a small actor or value store that aggregates `CAGCacheUsage` by provider ID.
Hit rate definition:

```swift
readTokens / max(1, readTokens + creationTokens + uncachedInputTokens)
```

The store should support record, snapshot, and reset for a provider.

## Add OpenAI-Compatible Negative Test

Build a request through `encodeRequest` or `OpenAICompatibleProvider` with
`cachePolicy = .ephemeral`. Assert the JSON body does not contain
`cache_control` and no Anthropic beta header exists. Explicit cache markers are
provider-specific; stable bytes are the CAG mechanism for these providers.

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD FAILED with errors naming missing CAG cache metrics, request
encoding, and parser symbols.

## Commit
```bash
git add MerlinTests/Unit/AnthropicProviderTests.swift \
        MerlinTests/Unit/CAGCacheMetricsTests.swift \
        MerlinTests/Unit/ProviderTests.swift \
        tasks/task-342a-cag-provider-metrics-tests.md
git commit -m "Phase 342a — CAG provider and metrics tests (failing)"
```
