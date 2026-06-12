# Web Search Plugin

Tier-2 out-of-process Merlin plugin for native web search and static page extraction.

This plugin is governed by `DEVELOPMENT.md`. The first vertical slice implements the five default free providers, bus-routed MCP tools, dynamic settings manifest, workspace TTL cache behavior, provider diagnostics, and bounded static HTML extraction.

Current completion status is tracked in `TODO.md`. The electronics evidence-consumer proposal is documented separately and remains unwired.

## Local Merlin Loading

The repository root `.mcp.json` loads this plugin through Merlin's normal MCP config path:

```json
{
  "mcpServers": {
    "web-search": {
      "command": "/usr/bin/swift",
      "args": [
        "run",
        "--quiet",
        "--package-path",
        "${MERLIN_PROJECT_ROOT}/plugins/web-search",
        "web-search-plugin"
      ],
      "transport": "stdio"
    }
  }
}
```

Merlin resolves `${MERLIN_PROJECT_ROOT}` when it merges project MCP config, then launches the plugin as a stdio MCP server. This keeps development packaging source-based and avoids a separate binary build step.

## Manual Smoke

1. Open the Merlin workspace at this repository root.
2. Confirm the `web-search` MCP server is present from `.mcp.json`.
3. Start or reopen the workspace session so MCP servers are loaded.
4. Confirm settings include the dynamic `plugin.web_search` section.
5. Call `web_provider_status` and confirm the five free providers are reported.
6. Call `web_search` with a small query such as `merlin`.
7. Call `web_extract_page` with an ordinary static HTML URL.
8. Call `web_search_and_extract` with a small query.
9. Call `web_clear_cache`.
10. Remove or disable the `web-search` MCP server, reopen the session, and confirm the web-search settings and tools disappear.

## Focused Tests

```bash
swift test
MERLIN_WEB_SEARCH_LIVE_SMOKE=1 swift test --filter LiveHTTPWiringTests/testOptInLiveFreeProvidersReturnResultsOrDiagnostics
```

Run the live smoke only when network access is acceptable. Fixture tests remain the primary gate.

Managed-provider live smoke is deferred until `BRAVE_API_KEY`, `TAVILY_API_KEY`, and `FIRECRAWL_API_KEY` are available. Without those keys, the managed-provider tests validate fixture parsing and structured disabled diagnostics.
