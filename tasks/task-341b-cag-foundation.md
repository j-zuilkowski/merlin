# Phase 341b — CAG Foundation Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 341a complete: CAG foundation tests are failing.

Recommended execution model: GPT-5.3-Codex.

Implement the non-provider foundation for Cache-Augmented Generation. This phase
does not add Anthropic `cache_control` wire markers yet; that lands in phase
342b. The output of this phase is a stable request policy and deterministic
prompt/tool surface that providers can consume.

---

## Write to: Merlin/CAG/CachePolicy.swift

Add:

```swift
enum CAGCachePolicy: String, Codable, Sendable, Equatable {
    case disabled
    case ephemeral
    var isCacheable: Bool { self != .disabled }
}
```

Add a stable tool-ordering helper:

```swift
enum CAGToolOrdering {
    static func stable(_ tools: [ToolDefinition]) -> [ToolDefinition]
}
```

Behavior:

- Sort by `function.name`.
- Deduplicate by `function.name`.
- When duplicate names exist, keep the first definition from the original input.

Keep this helper pure and independent from `ToolRegistry` so tests can cover it
without mutating global registry state.

## Edit: Merlin/Providers/LLMProvider.swift

Add `var cachePolicy: CAGCachePolicy = .disabled` to `CompletionRequest`.

This is request metadata; providers that do not support explicit cache markers
may ignore it. Do not change the OpenAI-compatible request JSON in this phase.

## Edit: Merlin/Config/AppSettings.swift

Add published settings:

```swift
@Published var cagEnabled: Bool = false
@Published var cagPinConstitution: Bool = true
@Published var cagPinnedTaskDocs: [String] = []
```

Persist them under `[cag]`:

- `enabled`
- `pin_constitution`
- `pinned_task_docs`

Preserve existing `[kag]` behavior. Do not merge KAG and CAG settings.

## Edit: Merlin/Engine/AgenticEngine.swift

When building a `CompletionRequest`, set:

```swift
request.cachePolicy = AppSettings.shared.cagEnabled ? .ephemeral : .disabled
```

Apply deterministic tool ordering before assigning tools:

```swift
request.tools = CAGToolOrdering.stable(offeredTools())
```

Also make `offeredTools()` itself return stable ordering if that is cleaner, but
ensure the request array is sorted even when MCP tools register in different
orders.

Do not move RAG/KAG enrichment into the system prompt. `effectiveMessage` is the
hot suffix and must remain a user-message augmentation.

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```
Expected: all tests pass, including the phase 341a CAG foundation tests.

## Commit
```bash
git add Merlin/CAG/CachePolicy.swift \
        Merlin/Providers/LLMProvider.swift \
        Merlin/Config/AppSettings.swift \
        Merlin/Engine/AgenticEngine.swift \
        MerlinTests/Unit/CAGCachePolicyTests.swift \
        MerlinTests/Unit/AppSettingsCAGTests.swift \
        MerlinTests/Unit/AgenticEngineCAGTests.swift \
        tasks/task-341b-cag-foundation.md
git commit -m "Phase 341b — CAG foundation and stable request policy"
```
