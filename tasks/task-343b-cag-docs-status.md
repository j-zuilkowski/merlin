# Phase 343b — CAG Documentation And Status Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 343a complete: architecture/documentation status tests are failing.

Recommended execution model: GPT-5.3-Codex.

Reconcile architecture and release-current documentation after CAG ships.

---

## Edit: spec.md

Update stale status labels:

- Change the top `v2.3 planned` release note to `v2.3`.
- Change `## llama.cpp First-Class Local Provider [v2.3 planned]` to `[v2.3]`.
- Keep historical task file references historical; do not rewrite old phase
  descriptions.

Update CAG:

- Change `## CAG — Cache-Augmented Generation [v11, planned]` to `[v11]`.
- Remove the "Status: not implemented" block.
- Replace planned file-layout/settings text with shipped surface:
  - `Merlin/CAG/CachePolicy.swift`
  - `Merlin/CAG/CacheMetrics.swift`
  - `CompletionRequest.cachePolicy`
  - `AppSettings.cagEnabled`
  - `AppSettings.cagPinConstitution`
  - `AppSettings.cagPinnedTaskDocs`
  - `AnthropicProvider` explicit `cache_control`
  - stable-byte behavior for DeepSeek/OpenAI-compatible/local providers
- State that RAG/KAG injections remain hot suffix content and must not be folded
  into the cacheable system prefix.

## Edit: FEATURES.md

Add a concise CAG feature section near RAG/KAG or Local Model Management:

- CAG caches the cold prefix: system prompt, project instructions, domain
  addenda, and stable tool schemas.
- RAG/KAG, tool results, and user turns remain hot.
- Anthropic uses explicit `cache_control`; other providers benefit from stable
  prefix bytes when their servers support automatic cache/KV reuse.
- Cache metrics track read/create/uncached input tokens.

## Edit: Merlin/Docs/UserGuide.md

Add a user-facing CAG section:

- What it does.
- How to enable it in config/settings (`[cag] enabled = true`).
- What not to expect: it does not replace RAG/KAG and does not train/fine-tune
  a model.

## Edit: Merlin/Docs/DeveloperManual.md

Document:

- `CAGCachePolicy`
- `CAGToolOrdering`
- `CAGCacheUsage`
- `CAGCacheMetricsStore`
- `CompletionRequest.cachePolicy`
- Anthropic request encoding and cache usage parsing
- The invariant that RAG/KAG enrichment stays out of the stable prefix.

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```
Expected: all tests pass, including `ArchitectureStatusLabelTests` and
`DocumentationSweepTests`.

```bash
rg -n "v2\\.3 planned|CAG.*planned|Status: not implemented|phase work is deferred" \
    spec.md FEATURES.md Merlin/Docs/UserGuide.md Merlin/Docs/DeveloperManual.md
```
Expected: no hits in release-current docs.

## Commit
```bash
git add spec.md \
        FEATURES.md \
        Merlin/Docs/UserGuide.md \
        Merlin/Docs/DeveloperManual.md \
        MerlinTests/Unit/ArchitectureStatusLabelTests.swift \
        MerlinTests/Unit/DocumentationSweepTests.swift \
        tasks/task-343b-cag-docs-status.md
git commit -m "Phase 343b — document CAG and refresh architecture status"
```
