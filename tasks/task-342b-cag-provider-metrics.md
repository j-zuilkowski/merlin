# Task 342b — CAG Provider And Metrics Implementation

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 342a complete: CAG provider and metrics tests are failing.

Recommended execution model: GPT-5.3-Codex.

Implement explicit Anthropic prompt caching and cache metrics. Do not add
Anthropic-only keys to OpenAI-compatible providers.

---

## Write to: Merlin/CAG/CacheMetrics.swift

Add:

```swift
struct CAGCacheUsage: Sendable, Equatable, Codable {
    var readTokens: Int
    var creationTokens: Int
    var uncachedInputTokens: Int
    var hitRate: Double { ... }
}
```

Add:

```swift
actor CAGCacheMetricsStore {
    static let shared = CAGCacheMetricsStore()
    func record(_ usage: CAGCacheUsage, providerID: String)
    func snapshot(providerID: String) -> CAGCacheUsage
    func reset(providerID: String)
}
```

Aggregation should sum token counts. Keep the API small; the Budget UI can read
it in a later task.

## Edit: Merlin/Providers/LLMProvider.swift

Add optional cache usage to `CompletionChunk`:

```swift
var cacheUsage: CAGCacheUsage?
```

Preserve existing initializers by defaulting the new property to nil.

## Edit: Merlin/Providers/AnthropicProvider.swift

When `request.cachePolicy.isCacheable`:

- Set `anthropic-beta` to include `prompt-caching-2024-07-31`.
- Encode the system prompt as a content-block array with an ephemeral
  `cache_control` block.
- Encode tools through an Anthropic encoder path that marks the final tool with
  ephemeral `cache_control`.

When CAG is disabled, preserve current request body shape exactly: system as a
plain string and no prompt-caching beta header.

While streaming, if a parsed chunk contains `cacheUsage`, record it:

```swift
await CAGCacheMetricsStore.shared.record(usage, providerID: id)
```

Do this inside the streaming task without blocking normal deltas.

## Edit: AnthropicMessageEncoder in Merlin/Providers/AnthropicProvider.swift

Add an overload or parameter:

```swift
static func encodeTools(_ tools: [ToolDefinition], cachePolicy: CAGCachePolicy = .disabled) -> [[String: Any]]
```

Only the last encoded tool gets `cache_control` when cacheable. Do not mark
every tool; Anthropic permits a small number of cache breakpoints and the final
tool captures the preceding tool array.

## Edit: Merlin/Providers/AnthropicSSEParser.swift

Parse `usage` from any Anthropic event payload. If cache fields are present,
return a `CompletionChunk(delta: nil, finishReason: nil, cacheUsage: usage)`.

Map:

- `cache_read_input_tokens` -> `readTokens`
- `cache_creation_input_tokens` -> `creationTokens`
- `input_tokens` -> `uncachedInputTokens`

If no cache fields are present, preserve existing parsing behavior.

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```
Expected: all tests pass, including the task 342a CAG provider and metrics
tests.

## Commit
```bash
git add Merlin/CAG/CacheMetrics.swift \
        Merlin/Providers/LLMProvider.swift \
        Merlin/Providers/AnthropicProvider.swift \
        Merlin/Providers/AnthropicSSEParser.swift \
        MerlinTests/Unit/AnthropicProviderTests.swift \
        MerlinTests/Unit/CAGCacheMetricsTests.swift \
        MerlinTests/Unit/ProviderTests.swift \
        tasks/task-342b-cag-provider-metrics.md
git commit -m "Task 342b — CAG Anthropic cache control and metrics"
```
