# Web Search Plugin Development Charter

## Goal

Build a usable Tier-2 Web Search Plugin for Merlin with all five default free providers, dynamic settings, provider diagnostics, workspace cache policy, bus-routed tools, and static HTML page extraction.

## Architecture Freeze

The completed plugin shape is:

```text
plugins/web-search/
  Package.swift
  README.md
  DEVELOPMENT.md
  TODO.md
  Sources/WebSearchPlugin/
    main.swift
    MCP/
      WebSearchMCPServer.swift
      MCPRequest.swift
      MCPResponse.swift
      ToolDefinitions.swift
      PluginManifest.swift
    Core/
      SearchRequest.swift
      SearchResult.swift
      SearchProvider.swift
      PageExtractionProvider.swift
      SearchCoordinator.swift
      ProviderDiagnostics.swift
      WebSearchSettings.swift
      WebSearchCache.swift
      URLCanonicalizer.swift
      ResultRanker.swift
    Providers/
      DuckDuckGoLiteProvider.swift
      WikipediaProvider.swift
      GitHubSearchProvider.swift
      StackExchangeProvider.swift
      HackerNewsProvider.swift
      OptionalManagedProviders.swift
    Extraction/
      URLSessionPageExtractor.swift
      HTMLTextExtractor.swift
      BotPolicy.swift
    Support/
      JSON.swift
      HTTPClient.swift
      Clock.swift
  Tests/WebSearchPluginTests/
    ManifestTests.swift
    MCPServerTests.swift
    ProviderFixtureTests.swift
    SearchCoordinatorTests.swift
    ExtractionTests.swift
    CacheTests.swift
    Fixtures/
```

Ownership rules:

1. `MCP/` owns transport, manifest, tool definitions, and MCP request/response plumbing.
2. `Core/` owns contracts, settings, diagnostics, cache policy, canonicalization, ranking, dedupe, and coordination.
3. `Providers/` only fetch, parse, normalize, and return diagnostics for one source each.
4. `Extraction/` only fetches pages, enforces bounds, detects blocked/degraded pages, and extracts readable text or Markdown.
5. Merlin core owns plugin discovery, dynamic settings rendering, authorization, and bus routing.
6. This plugin revision does not change electronics-domain behavior, schemas, gates, or part-selection rules.

No new top-level abstraction is allowed unless it is required by a stage gate or removes duplication already present in the plugin code.

## Stage Gates

### 1. Scaffold And Manifest

Pass criteria:

1. Swift package exists and builds.
2. MCP server answers `initialize`, `tools/list`, `tools/call`, and `resources/read`.
3. `merlin://plugin/manifest` returns the Tier-2 plugin manifest.
4. Manifest declares `plugin.web_search` settings and tool routes.
5. `web_provider_status` returns structured diagnostics.
6. `web_search` returns a structured unavailable/degraded diagnostic if providers are not wired yet.

Out of scope:

1. No provider HTTP.
2. No extraction.
3. No optional managed providers.

### 2. Contracts, Settings, Diagnostics, And Cache

Pass criteria:

1. Core request/result/settings/diagnostics models exist.
2. Settings schema matches `spec.md`.
3. Diagnostics include explicit states: `ok`, `empty`, `blocked`, `bot_policy_blocked`, `rate_limited`, `captcha`, `parse_failed`, `timeout`, `disabled`.
4. Cache policy is workspace-scoped and TTL-aware.
5. Contract tests pass without live network.

Out of scope:

1. No global shared cache.
2. No provider-specific optimization.

### 3. Provider Fixtures And Parsers

Pass criteria:

1. Fixture parser tests exist for DuckDuckGo Lite/HTML, Wikipedia API, GitHub Search API, Stack Exchange API, and Hacker News Algolia API.
2. Each provider normalizes to the same `SearchResult` shape.
3. Each provider returns provider diagnostics on empty, malformed, blocked, or rate-limited fixture data.

Out of scope:

1. No live HTTP until fixture parsing is green.
2. No ranking tuning beyond fields required by the coordinator.

### 4. Search Coordinator

Pass criteria:

1. Coordinator reads settings.
2. Enabled providers fan out concurrently.
3. Results are canonicalized, deduped, ranked, capped, and returned with cited provider metadata.
4. Partial success is valid only when failed providers are reported honestly.
5. `web_search` and `web_search_and_extract` return stable JSON envelopes.

Out of scope:

1. No LLM reranking.
2. No provider-specific search workflow outside the shared provider interface.

### 5. Live HTTP Wiring

Pass criteria:

1. All five default free providers use bounded HTTP requests.
2. Live smoke tests are separate from fixture tests.
3. Timeouts, rate-limit backoff, and disabled provider settings are enforced.
4. Live failures degrade through diagnostics, not silent skips.

Out of scope:

1. No repeated live debugging loop before fixture tests pass.
2. No paid-provider implementation.

### 6. Static HTML Extraction

Pass criteria:

1. `web_extract_page` fetches ordinary static HTML with `URLSession`.
2. Content type and byte limits are enforced.
3. Basic HTML cleanup produces readable text or Markdown.
4. Login pages, CAPTCHA/bot challenges, unsupported content, and unusable pages block with diagnostics.
5. `bot_policy_mode` supports `respect` and `ignore_advisory` as defined in `spec.md`.

Out of scope:

1. No WebKit extractor.
2. No unrestricted crawling.

### 7. Merlin Integration Smoke

Pass criteria:

1. Merlin launches/registers the local plugin through MCP config.
2. Settings appear dynamically while loaded.
3. `web_provider_status`, `web_search`, and `web_extract_page` route through Merlin to the plugin.
4. Unload removes settings and tools.

Out of scope:

1. No app-wide UI redesign.
2. No electronics integration.

## Deferred Ledger

Every deferred item must also appear as a code TODO at the omission site when a stub or placeholder exists.

No remaining deferred implementation items for the generic Web Search Plugin.

Electronics evidence consumption remains proposal-only in `ELECTRONICS_CONSUMER_PROPOSAL.md`; no electronics-domain behavior is wired.

## TODO Format

All intentional omissions use this exact prefix:

```swift
// TODO(web-search:<topic>): <specific deferred work and condition for revisiting>.
```

Rules:

1. No bare TODOs.
2. No undocumented stubs.
3. A TODO must name whether it is deferred, blocked, or staged.
4. A TODO must not hide a failing stage-gate requirement.

## Stop Conditions

Stop instead of improvising when:

1. The Tier-2 host manifest bridge fails to load or route the plugin.
2. A provider blocks unauthenticated access or requires behavior outside the configured bot policy.
3. Fixture parsing cannot normalize a provider reliably.
4. The plugin manifest schema conflicts with Merlin core contracts.
5. Live network behavior is unstable in a way fixture tests cannot reproduce.
6. A requested change crosses into electronics-domain behavior, schemas, gates, or part-selection rules.
7. A stage requires a new architecture not present in the architecture freeze.

When a stop condition occurs, record the blocker and the narrowest next decision needed.

## Testing Policy

1. Contract tests precede implementation tests.
2. Fixture tests precede live HTTP.
3. Focused plugin tests precede Merlin integration smoke tests.
4. Do not run full app or broad test suites until the focused slice is green.
5. Live smoke tests are allowed only after fixture and coordinator tests pass.

## Token Conservation Policy

1. No broad scans after the plugin file layout is established.
2. Read exact files only.
3. Use focused test commands only until the vertical slice is green.
4. Progress updates are limited to stage transitions: scaffolded, manifest/tools load, providers normalized, coordinator working, extraction working, focused tests passed, or blocker.
5. Final answers summarize changed files, tests run, and the next stage in a few lines.
