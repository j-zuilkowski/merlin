# Phase 341a — CAG Foundation Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 340b complete: llama.cpp and slot-status documentation sweep landed.

Recommended execution model: GPT-5.3-Codex.

Architecture currently reserves CAG as "Cache-Augmented Generation" but the
runtime only has an older stable-prefix helper. This phase turns CAG into a
first-class implementation surface without changing provider wire formats yet.

New surface introduced in phase 341b:
  - `Merlin/CAG/CachePolicy.swift`
  - `CAGCachePolicy` request policy (`disabled` or `ephemeral`)
  - deterministic tool ordering/deduplication helper for cache-stable prefixes
  - AppSettings CAG keys:
    - `[cag].enabled`
    - `[cag].pin_constitution`
    - `[cag].pinned_task_docs`
  - `CompletionRequest.cachePolicy`
  - AgenticEngine request wiring so CAG-enabled sessions mark requests as
    cacheable while leaving RAG/KAG injections in the hot user-message suffix.

TDD coverage:
  File 1 - `MerlinTests/Unit/CAGCachePolicyTests.swift`:
    `testDefaultPolicyIsDisabled`
    `testEphemeralPolicyIsCacheable`
    `testStableToolOrderingSortsByName`
    `testStableToolOrderingDeduplicatesByName`
    `testStableToolOrderingKeepsFirstDefinitionForDuplicateName`
    `testHotRAGAndKAGTextIsNotPartOfStablePrefix`

  File 2 - `MerlinTests/Unit/AppSettingsCAGTests.swift`:
    `testCAGSettingsDefaults`
    `testCAGSettingsRoundTrip`
    `testCAGSettingsLoadFromTomlSection`

  File 3 - `MerlinTests/Unit/AgenticEngineCAGTests.swift`:
    `testEngineMarksRequestsEphemeralWhenCAGEnabled`
    `testEngineLeavesRequestsUncachedWhenCAGDisabled`
    `testOfferedToolsAreSortedBeforeProviderRequest`

---

## Write to: MerlinTests/Unit/CAGCachePolicyTests.swift

Create tests for a small pure CAG policy layer. Use hand-built `ToolDefinition`
values with intentionally shuffled names and duplicate names.

Expected behavior:

- `CAGCachePolicy.disabled.isCacheable == false`
- `CAGCachePolicy.ephemeral.isCacheable == true`
- `CAGToolOrdering.stable(_:)` returns definitions sorted by
  `function.name`.
- Duplicate tool names are deduplicated after sorting by name, preserving the
  first definition seen for that name in the original input.
- Existing `AgenticEngine.buildStablePrefix()` remains cold-only: RAG/KAG
  injection strings such as `[Relevant passages from your library]` and
  `## Knowledge Graph` must not appear in it.

## Write to: MerlinTests/Unit/AppSettingsCAGTests.swift

Use the same temp-config pattern as `AppSettingsKAGTests`.

Defaults:

- `cagEnabled == false`
- `cagPinConstitution == true`
- `cagPinnedTaskDocs == []`

Round-trip TOML should produce and reload:

```toml
[cag]
enabled = true
pin_constitution = false
pinned_task_docs = ["tasks/task-341a-cag-foundation-tests.md"]
```

## Write to: MerlinTests/Unit/AgenticEngineCAGTests.swift

Use a capturing `LLMProvider` that records the final `CompletionRequest` passed
to `complete(request:)`.

Tests must prove:

- When `AppSettings.shared.cagEnabled = true`, the request sent by
  `AgenticEngine.send(userMessage:)` has `cachePolicy == .ephemeral`.
- When CAG is disabled, the request remains `.disabled`.
- The request tool array is sorted by `function.name` before it reaches the
  provider. Register/reset tool definitions as needed, and restore global
  state in `tearDown`.

Keep these tests local and deterministic. Do not call real providers.

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD FAILED with errors naming missing CAG policy/settings/request
symbols.

## Commit
```bash
git add MerlinTests/Unit/CAGCachePolicyTests.swift \
        MerlinTests/Unit/AppSettingsCAGTests.swift \
        MerlinTests/Unit/AgenticEngineCAGTests.swift \
        tasks/task-341a-cag-foundation-tests.md
git commit -m "Phase 341a — CAG foundation tests (failing)"
```
